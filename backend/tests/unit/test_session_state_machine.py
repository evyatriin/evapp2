import pytest
from utils.session_state_machine import (
    InvalidStateTransition,
    can_transition,
    transition_state,
    is_terminal,
)
from models.beckn_models import SessionStateEnum


class TestSessionStateTransitions:
    """Test valid state transitions."""

    def test_initiated_to_authorizing(self):
        """Session can transition from INITIATED to AUTHORIZING."""
        assert can_transition(SessionStateEnum.INITIATED, SessionStateEnum.AUTHORIZING)

    def test_authorizing_to_authorized(self):
        """Session can transition from AUTHORIZING to AUTHORIZED."""
        assert can_transition(SessionStateEnum.AUTHORIZING, SessionStateEnum.AUTHORIZED)

    def test_authorized_to_starting(self):
        """Session can transition from AUTHORIZED to STARTING."""
        assert can_transition(SessionStateEnum.AUTHORIZED, SessionStateEnum.STARTING)

    def test_starting_to_charging(self):
        """Session can transition from STARTING to CHARGING."""
        assert can_transition(SessionStateEnum.STARTING, SessionStateEnum.CHARGING)

    def test_charging_to_stopping(self):
        """Session can transition from CHARGING to STOPPING."""
        assert can_transition(SessionStateEnum.CHARGING, SessionStateEnum.STOPPING)

    def test_stopping_to_metering_final(self):
        """Session can transition from STOPPING to METERING_FINAL."""
        assert can_transition(SessionStateEnum.STOPPING, SessionStateEnum.METERING_FINAL)

    def test_metering_to_awaiting_payment(self):
        """Session can transition from METERING_FINAL to AWAITING_PAYMENT."""
        assert can_transition(SessionStateEnum.METERING_FINAL, SessionStateEnum.AWAITING_PAYMENT)

    def test_awaiting_payment_to_payment_confirmed(self):
        """Session can transition from AWAITING_PAYMENT to PAYMENT_CONFIRMED."""
        assert can_transition(SessionStateEnum.AWAITING_PAYMENT, SessionStateEnum.PAYMENT_CONFIRMED)

    def test_charging_to_failed_on_error(self):
        """Session can transition from CHARGING to FAILED on error."""
        assert can_transition(SessionStateEnum.CHARGING, SessionStateEnum.FAILED)

    def test_initiated_to_failed(self):
        """Most states can transition to FAILED."""
        for state in [
            SessionStateEnum.INITIATED,
            SessionStateEnum.AUTHORIZING,
            SessionStateEnum.CHARGING,
        ]:
            assert can_transition(state, SessionStateEnum.FAILED)


class TestInvalidTransitions:
    """Test invalid state transitions."""

    def test_initiated_cannot_go_directly_to_charging(self):
        """Cannot skip states and go directly to CHARGING."""
        assert not can_transition(SessionStateEnum.INITIATED, SessionStateEnum.CHARGING)
        with pytest.raises(InvalidStateTransition):
            transition_state(SessionStateEnum.INITIATED, SessionStateEnum.CHARGING)

    def test_completed_cannot_transition(self):
        """Completed sessions cannot transition to other states."""
        assert not can_transition(SessionStateEnum.COMPLETED, SessionStateEnum.CHARGING)
        with pytest.raises(InvalidStateTransition):
            transition_state(SessionStateEnum.COMPLETED, SessionStateEnum.CHARGING)

    def test_authorized_cannot_go_backward(self):
        """Cannot go backward from AUTHORIZED to INITIATED."""
        assert not can_transition(SessionStateEnum.AUTHORIZED, SessionStateEnum.INITIATED)
        with pytest.raises(InvalidStateTransition):
            transition_state(SessionStateEnum.AUTHORIZED, SessionStateEnum.INITIATED)

    def test_invalid_state_transition_message(self):
        """InvalidStateTransition exception includes helpful message."""
        try:
            transition_state(SessionStateEnum.COMPLETED, SessionStateEnum.CHARGING)
        except InvalidStateTransition as e:
            assert "COMPLETED" in str(e)
            assert "CHARGING" in str(e)


class TestTerminalStates:
    """Test terminal state detection."""

    def test_completed_is_terminal(self):
        """COMPLETED is a terminal state."""
        assert is_terminal(SessionStateEnum.COMPLETED)

    def test_disputed_is_terminal(self):
        """DISPUTED is a terminal state."""
        assert is_terminal(SessionStateEnum.DISPUTED)

    def test_charging_is_not_terminal(self):
        """CHARGING is not a terminal state."""
        assert not is_terminal(SessionStateEnum.CHARGING)

    def test_initiated_is_not_terminal(self):
        """INITIATED is not a terminal state."""
        assert not is_terminal(SessionStateEnum.INITIATED)


class TestAllValidTransitions:
    """Test the complete transition matrix."""

    def test_valid_transitions_dict_exists(self):
        """VALID_TRANSITIONS is defined."""
        from utils.session_state_machine import VALID_TRANSITIONS

        assert isinstance(VALID_TRANSITIONS, dict)
        assert len(VALID_TRANSITIONS) > 0

    def test_all_states_represented(self):
        """All states have transitions defined."""
        from utils.session_state_machine import VALID_TRANSITIONS

        for state in SessionStateEnum:
            # All states should be in VALID_TRANSITIONS (even if with empty set for terminal states)
            assert state in VALID_TRANSITIONS
