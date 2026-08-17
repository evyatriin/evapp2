import pytest
import json
from unittest.mock import AsyncMock, patch
from utils.idempotency import (
    make_idempotency_key,
    check_idempotency,
    store_idempotency_response,
)


class TestIdempotencyKeyGeneration:
    """Test idempotency key creation."""

    def test_key_generation_format(self):
        """Idempotency key has correct format."""
        key = make_idempotency_key(
            user_id="user-123",
            request_key="start_charge",
            body={"charger_id": "charger-456"},
        )
        assert isinstance(key, str)
        assert key.startswith("idempotency:")
        assert "user-123" in key

    def test_same_inputs_produce_same_key(self):
        """Same inputs always produce the same key."""
        key1 = make_idempotency_key(
            user_id="user-123",
            request_key="start_charge",
            body={"charger_id": "charger-456"},
        )
        key2 = make_idempotency_key(
            user_id="user-123",
            request_key="start_charge",
            body={"charger_id": "charger-456"},
        )
        assert key1 == key2

    def test_different_user_produces_different_key(self):
        """Different users produce different keys."""
        key1 = make_idempotency_key(
            user_id="user-123",
            request_key="start_charge",
            body={"charger_id": "charger-456"},
        )
        key2 = make_idempotency_key(
            user_id="user-789",
            request_key="start_charge",
            body={"charger_id": "charger-456"},
        )
        assert key1 != key2

    def test_different_request_key_produces_different_key(self):
        """Different request keys produce different keys."""
        key1 = make_idempotency_key(
            user_id="user-123",
            request_key="start_charge",
            body={"charger_id": "charger-456"},
        )
        key2 = make_idempotency_key(
            user_id="user-123",
            request_key="stop_charge",
            body={"charger_id": "charger-456"},
        )
        assert key1 != key2

    def test_different_body_produces_different_key(self):
        """Different body produces different keys."""
        key1 = make_idempotency_key(
            user_id="user-123",
            request_key="start_charge",
            body={"charger_id": "charger-456"},
        )
        key2 = make_idempotency_key(
            user_id="user-123",
            request_key="start_charge",
            body={"charger_id": "charger-789"},
        )
        assert key1 != key2

    def test_none_body_produces_key(self):
        """None body is handled gracefully."""
        key = make_idempotency_key(
            user_id="user-123",
            request_key="start_charge",
            body=None,
        )
        assert isinstance(key, str)
        assert key.startswith("idempotency:")


class TestIdempotencyCheck:
    """Test idempotency checking."""

    def test_check_idempotency_no_prior_request(self):
        """check_idempotency returns None if no prior request."""
        with patch("utils.idempotency._get_redis", return_value=None):
            with patch("utils.idempotency._memory_get", return_value=None):
                result = check_idempotency(
                    key="test-key",
                    user_id="user-123",
                    body={"charger_id": "charger-456"},
                )
                assert result is None

    def test_check_idempotency_found_prior_request(self):
        """check_idempotency returns prior response if found."""
        prior_response = {"session_id": "session-123", "status": "created"}
        with patch("utils.idempotency._get_redis", return_value=None):
            with patch(
                "utils.idempotency._memory_get", return_value=prior_response
            ):
                result = check_idempotency(
                    key="test-key",
                    user_id="user-123",
                    body={"charger_id": "charger-456"},
                )
                assert result == prior_response


class TestIdempotencyStorage:
    """Test storing idempotency responses."""

    def test_store_idempotency_response(self):
        """store_idempotency_response stores response."""
        response = {"session_id": "session-123", "status": "created"}

        with patch("utils.idempotency._get_redis", return_value=None):
            with patch("utils.idempotency._memory_set") as mock_set:
                store_idempotency_response(
                    key="test-key",
                    user_id="user-123",
                    body={"charger_id": "charger-456"},
                    response=response,
                )
                # Verify _memory_set was called (since no Redis)
                mock_set.assert_called_once()


class TestIdempotencyFlow:
    """Test complete idempotency flow."""

    def test_idempotency_flow_with_retry(self):
        """Test complete idempotency flow with retried request."""
        key = make_idempotency_key(
            user_id="user-123",
            request_key="start_charge",
            body={"charger_id": "charger-456"},
        )
        response = {"session_id": "session-123", "status": "created"}

        with patch("utils.idempotency._get_redis", return_value=None):
            with patch(
                "utils.idempotency._memory_get", side_effect=[None, response]
            ):
                with patch("utils.idempotency._memory_set"):
                    # First call - no prior response
                    result = check_idempotency(
                        key=key,
                        user_id="user-123",
                        body={"charger_id": "charger-456"},
                    )
                    assert result is None

                    # Store the response
                    store_idempotency_response(
                        key=key,
                        user_id="user-123",
                        body={"charger_id": "charger-456"},
                        response=response,
                    )

                    # Retry - should return cached response
                    result = check_idempotency(
                        key=key,
                        user_id="user-123",
                        body={"charger_id": "charger-456"},
                    )
                    assert result == response
