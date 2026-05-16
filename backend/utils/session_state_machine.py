"""14-state machine for EV charging sessions."""
from __future__ import annotations

import logging
from typing import Dict, Set

from models.beckn_models import SessionStateEnum

logger = logging.getLogger(__name__)


# ---------------------------------------------------------------------------
# Valid transition map
# ---------------------------------------------------------------------------

VALID_TRANSITIONS: Dict[SessionStateEnum, Set[SessionStateEnum]] = {
    SessionStateEnum.INITIATED: {
        SessionStateEnum.AUTHORIZING,
        SessionStateEnum.CANCELLED,
        SessionStateEnum.FAILED,
    },
    SessionStateEnum.AUTHORIZING: {
        SessionStateEnum.AUTHORIZED,
        SessionStateEnum.FAILED,
        SessionStateEnum.CANCELLED,
    },
    SessionStateEnum.AUTHORIZED: {
        SessionStateEnum.STARTING,
        SessionStateEnum.CANCELLED,
        SessionStateEnum.FAILED,
    },
    SessionStateEnum.STARTING: {
        SessionStateEnum.CHARGING,
        SessionStateEnum.FAILED,
        SessionStateEnum.CANCELLED,
    },
    SessionStateEnum.CHARGING: {
        SessionStateEnum.STOPPING,
        SessionStateEnum.FAILED,
    },
    SessionStateEnum.STOPPING: {
        SessionStateEnum.METERING_FINAL,
        SessionStateEnum.FAILED,
    },
    SessionStateEnum.METERING_FINAL: {
        SessionStateEnum.AWAITING_PAYMENT,
        SessionStateEnum.FAILED,
    },
    SessionStateEnum.AWAITING_PAYMENT: {
        SessionStateEnum.PAYMENT_CONFIRMED,
        SessionStateEnum.FAILED,
        SessionStateEnum.DISPUTED,
    },
    SessionStateEnum.PAYMENT_CONFIRMED: {
        SessionStateEnum.UNLOCKING,
    },
    SessionStateEnum.UNLOCKING: {
        SessionStateEnum.COMPLETED,
        SessionStateEnum.FAILED,
    },
    # Terminal states — no outbound transitions
    SessionStateEnum.COMPLETED: set(),
    SessionStateEnum.CANCELLED: set(),
    SessionStateEnum.FAILED: {
        SessionStateEnum.DISPUTED,
    },
    SessionStateEnum.DISPUTED: set(),
}

# States from which no further progression is possible
_TERMINAL_STATES: Set[SessionStateEnum] = {
    SessionStateEnum.COMPLETED,
    SessionStateEnum.CANCELLED,
    SessionStateEnum.DISPUTED,
}

# States where the session is billable (energy was delivered or is being delivered)
_BILLABLE_STATES: Set[SessionStateEnum] = {
    SessionStateEnum.CHARGING,
    SessionStateEnum.STOPPING,
    SessionStateEnum.METERING_FINAL,
    SessionStateEnum.AWAITING_PAYMENT,
    SessionStateEnum.PAYMENT_CONFIRMED,
    SessionStateEnum.UNLOCKING,
    SessionStateEnum.COMPLETED,
    SessionStateEnum.DISPUTED,
}


# ---------------------------------------------------------------------------
# Exception
# ---------------------------------------------------------------------------

class InvalidStateTransition(Exception):
    """Raised when a state transition is not permitted."""

    def __init__(self, current: SessionStateEnum, target: SessionStateEnum, session_id: str = ""):
        self.current = current
        self.target = target
        self.session_id = session_id
        msg = (
            f"Cannot transition session{' ' + session_id if session_id else ''} "
            f"from {current.value} to {target.value}"
        )
        super().__init__(msg)


# ---------------------------------------------------------------------------
# Public API
# ---------------------------------------------------------------------------

def can_transition(current: SessionStateEnum, target: SessionStateEnum) -> bool:
    """Return True if moving from *current* to *target* is a valid transition."""
    allowed = VALID_TRANSITIONS.get(current, set())
    return target in allowed


def transition_state(
    current: SessionStateEnum,
    target: SessionStateEnum,
    session_id: str = "",
) -> SessionStateEnum:
    """Validate and perform the transition, returning the new state.

    Raises:
        InvalidStateTransition: if the transition is not permitted.
    """
    if not can_transition(current, target):
        logger.warning(
            "Invalid state transition: session=%s  %s -> %s",
            session_id,
            current.value,
            target.value,
        )
        raise InvalidStateTransition(current, target, session_id)

    logger.info(
        "State transition: session=%s  %s -> %s",
        session_id,
        current.value,
        target.value,
    )
    return target


def is_terminal(state: SessionStateEnum) -> bool:
    """Return True if *state* is a terminal state with no further transitions."""
    return state in _TERMINAL_STATES


def is_billable(state: SessionStateEnum) -> bool:
    """Return True if *state* indicates energy was delivered and billing applies."""
    return state in _BILLABLE_STATES
