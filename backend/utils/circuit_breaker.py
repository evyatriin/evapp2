"""Circuit breaker for protecting external service calls (OCPP, payment, etc.)."""
from __future__ import annotations

import asyncio
import logging
import time
from enum import Enum
from typing import Any, Callable, Dict

logger = logging.getLogger(__name__)


# ---------------------------------------------------------------------------
# States
# ---------------------------------------------------------------------------

class CircuitState(str, Enum):
    CLOSED = "CLOSED"        # Normal operation — requests flow through
    OPEN = "OPEN"            # Tripped — requests fail fast
    HALF_OPEN = "HALF_OPEN"  # Probing — limited requests allowed


# ---------------------------------------------------------------------------
# Exception
# ---------------------------------------------------------------------------

class CircuitOpenError(Exception):
    """Raised when a call is rejected because the circuit is OPEN."""

    def __init__(self, charger_id: str = ""):
        self.charger_id = charger_id
        super().__init__(
            f"Circuit breaker is OPEN for charger={charger_id!r} — service may be unavailable"
        )


# ---------------------------------------------------------------------------
# CircuitBreaker
# ---------------------------------------------------------------------------

class CircuitBreaker:
    """Per-resource circuit breaker.

    State machine:
        CLOSED  --[failures >= threshold]--> OPEN
        OPEN    --[recovery_timeout elapsed]--> HALF_OPEN
        HALF_OPEN --[success >= success_threshold]--> CLOSED
        HALF_OPEN --[failure]--> OPEN
    """

    def __init__(
        self,
        name: str = "",
        failure_threshold: int = 5,
        recovery_timeout: float = 30.0,
        success_threshold: int = 2,
    ) -> None:
        self.name = name
        self.failure_threshold = failure_threshold
        self.recovery_timeout = recovery_timeout
        self.success_threshold = success_threshold

        self._state = CircuitState.CLOSED
        self._failure_count = 0
        self._success_count = 0
        self._last_failure_time: float = 0.0
        self._lock = asyncio.Lock()

    @property
    def state(self) -> CircuitState:
        return self._state

    def _record_success(self) -> None:
        if self._state == CircuitState.HALF_OPEN:
            self._success_count += 1
            if self._success_count >= self.success_threshold:
                logger.info("Circuit breaker CLOSED (recovered): %s", self.name)
                self._state = CircuitState.CLOSED
                self._failure_count = 0
                self._success_count = 0
        elif self._state == CircuitState.CLOSED:
            # Reset failure count on any success
            self._failure_count = 0

    def _record_failure(self) -> None:
        self._failure_count += 1
        self._last_failure_time = time.monotonic()
        self._success_count = 0

        if self._state == CircuitState.HALF_OPEN:
            logger.warning("Circuit breaker OPEN (half-open probe failed): %s", self.name)
            self._state = CircuitState.OPEN
        elif self._state == CircuitState.CLOSED:
            if self._failure_count >= self.failure_threshold:
                logger.error(
                    "Circuit breaker OPEN (failures=%d threshold=%d): %s",
                    self._failure_count,
                    self.failure_threshold,
                    self.name,
                )
                self._state = CircuitState.OPEN

    def _check_state(self) -> None:
        """Transition OPEN -> HALF_OPEN when the recovery timeout has elapsed."""
        if self._state == CircuitState.OPEN:
            elapsed = time.monotonic() - self._last_failure_time
            if elapsed >= self.recovery_timeout:
                logger.info(
                    "Circuit breaker HALF_OPEN (recovery probe): %s (elapsed=%.1fs)",
                    self.name,
                    elapsed,
                )
                self._state = CircuitState.HALF_OPEN
                self._success_count = 0

    async def call(self, func: Callable, *args: Any, **kwargs: Any) -> Any:
        """Call *func* through the circuit breaker.

        Raises:
            CircuitOpenError: if the circuit is open and not yet probing.
            Exception: whatever *func* raises on failure.
        """
        async with self._lock:
            self._check_state()
            if self._state == CircuitState.OPEN:
                raise CircuitOpenError(self.name)

        try:
            if asyncio.iscoroutinefunction(func):
                result = await func(*args, **kwargs)
            else:
                result = await asyncio.to_thread(func, *args, **kwargs)
            async with self._lock:
                self._record_success()
            return result
        except CircuitOpenError:
            raise
        except Exception as exc:
            async with self._lock:
                self._record_failure()
            logger.error("Circuit breaker recorded failure for %s: %s", self.name, exc)
            raise


# ---------------------------------------------------------------------------
# Per-charger registry
# ---------------------------------------------------------------------------

_breaker_registry: Dict[str, CircuitBreaker] = {}
_registry_lock = asyncio.Lock()


async def get_charger_breaker(charger_id: str) -> CircuitBreaker:
    """Return (creating if needed) a CircuitBreaker dedicated to *charger_id*."""
    if charger_id in _breaker_registry:
        return _breaker_registry[charger_id]
    async with _registry_lock:
        # Double-check after acquiring lock
        if charger_id not in _breaker_registry:
            _breaker_registry[charger_id] = CircuitBreaker(
                name=f"charger:{charger_id}",
                failure_threshold=5,
                recovery_timeout=30.0,
                success_threshold=2,
            )
        return _breaker_registry[charger_id]
