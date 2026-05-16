"""Saga pattern for distributed, compensatable multi-step operations."""
from __future__ import annotations

import logging
from dataclasses import dataclass, field
from typing import Any, Callable, Dict, List, Optional

logger = logging.getLogger(__name__)


@dataclass
class SagaStep:
    """A single step in a saga with a forward action and a compensating action."""

    name: str
    action: Callable[[Dict[str, Any]], Any]        # async callable(context) -> Any
    compensate: Callable[[Dict[str, Any]], Any]     # async callable(context) -> Any


class Saga:
    """Orchestrate a sequence of steps where each step can be compensated on failure.

    Usage::

        saga = Saga()
        saga.add_step(SagaStep("acquire_lock", action_fn, compensate_fn))
        saga.add_step(SagaStep("create_session", action_fn, compensate_fn))
        saga.add_step(SagaStep("start_ocpp", action_fn, compensate_fn))
        result_context = await saga.execute({"charger_id": "..."})
    """

    def __init__(self) -> None:
        self._steps: List[SagaStep] = []

    def add_step(self, step: SagaStep) -> "Saga":
        """Append a step to the saga. Returns self for chaining."""
        self._steps.append(step)
        return self

    async def execute(self, context: Dict[str, Any]) -> Dict[str, Any]:
        """Execute all steps in order.

        On failure at step N, compensations for steps 0..N-1 are executed in
        reverse order.

        Args:
            context: Shared mutable dict passed to every action and compensation.
                     Steps may add keys to communicate results to later steps.

        Returns:
            The final *context* dict after all steps succeed.

        Raises:
            Exception: The original exception from the failing step, after all
                       compensations have been attempted.
        """
        completed_steps: List[SagaStep] = []

        for step in self._steps:
            logger.info("Saga: executing step '%s'", step.name)
            try:
                result = await step.action(context)
                if result is not None:
                    context[f"_result_{step.name}"] = result
                completed_steps.append(step)
            except Exception as exc:
                logger.error("Saga: step '%s' failed: %s — starting compensation", step.name, exc)
                await self._compensate(completed_steps, context)
                raise

        logger.info("Saga: all %d steps completed successfully", len(self._steps))
        return context

    async def _compensate(
        self, completed_steps: List[SagaStep], context: Dict[str, Any]
    ) -> None:
        """Run compensations in reverse order, swallowing errors so all run."""
        for step in reversed(completed_steps):
            logger.info("Saga: compensating step '%s'", step.name)
            try:
                await step.compensate(context)
            except Exception as exc:
                # Log but do not raise — we want all compensations to run
                logger.error("Saga: compensation for '%s' failed: %s", step.name, exc)
