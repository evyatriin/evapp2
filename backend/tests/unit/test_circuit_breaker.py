import pytest
import asyncio
import time
from utils.circuit_breaker import (
    CircuitBreaker,
    CircuitState,
    CircuitOpenError,
    get_charger_breaker,
)


class TestCircuitBreakerStates:
    """Test circuit breaker state transitions."""

    def test_initial_state_is_closed(self):
        """Circuit breaker starts in CLOSED state."""
        breaker = CircuitBreaker(name="test")
        assert breaker.state == CircuitState.CLOSED

    def test_circuit_opens_after_threshold_failures(self):
        """Circuit opens after reaching failure threshold."""

        async def failing_operation():
            raise Exception("Service error")

        async def test_opens():
            breaker = CircuitBreaker(name="test", failure_threshold=3)
            for _ in range(3):
                try:
                    await breaker.call(failing_operation)
                except Exception:
                    pass
            assert breaker.state == CircuitState.OPEN

        asyncio.run(test_opens())

    def test_rejects_calls_in_open_state(self):
        """Open circuit rejects calls immediately."""

        async def test_rejects():
            breaker = CircuitBreaker(name="test", failure_threshold=2)

            async def failing_op():
                raise Exception("Service error")

            # Trigger failures to open circuit
            for _ in range(2):
                try:
                    await breaker.call(failing_op)
                except Exception:
                    pass

            assert breaker.state == CircuitState.OPEN

            # Next call should immediately raise CircuitOpenError
            with pytest.raises(CircuitOpenError):
                await breaker.call(failing_op)

        asyncio.run(test_rejects())

    def test_allows_calls_in_closed_state(self):
        """Closed circuit allows calls."""

        async def test_allows():
            breaker = CircuitBreaker(name="test")

            async def success_op():
                return "success"

            result = await breaker.call(success_op)
            assert result == "success"
            assert breaker.state == CircuitState.CLOSED

        asyncio.run(test_allows())

    def test_half_open_after_timeout(self):
        """Circuit enters HALF_OPEN state after recovery timeout."""

        async def test_half_open():
            breaker = CircuitBreaker(
                name="test",
                failure_threshold=2,
                recovery_timeout=0.1,  # 100ms for faster testing
            )

            async def failing_op():
                raise Exception("Service error")

            # Open circuit
            for _ in range(2):
                try:
                    await breaker.call(failing_op)
                except Exception:
                    pass

            assert breaker.state == CircuitState.OPEN

            # Wait for recovery timeout
            await asyncio.sleep(0.15)

            # Check state manually (doesn't make a call)
            breaker._check_state()
            assert breaker.state == CircuitState.HALF_OPEN

        asyncio.run(test_half_open())

    def test_closes_on_success_in_half_open(self):
        """Success in HALF_OPEN state returns to CLOSED."""

        async def test_closes():
            breaker = CircuitBreaker(
                name="test",
                failure_threshold=2,
                recovery_timeout=0.1,
                success_threshold=1,
            )

            async def failing_op():
                raise Exception("Service error")

            async def success_op():
                return "success"

            # Open circuit
            for _ in range(2):
                try:
                    await breaker.call(failing_op)
                except Exception:
                    pass

            assert breaker.state == CircuitState.OPEN

            # Wait for HALF_OPEN
            await asyncio.sleep(0.15)
            breaker._check_state()
            assert breaker.state == CircuitState.HALF_OPEN

            # Success should close it
            result = await breaker.call(success_op)
            assert result == "success"
            assert breaker.state == CircuitState.CLOSED

        asyncio.run(test_closes())

    def test_reopens_on_failure_in_half_open(self):
        """Failure in HALF_OPEN state returns to OPEN."""

        async def test_reopens():
            breaker = CircuitBreaker(
                name="test",
                failure_threshold=2,
                recovery_timeout=0.1,
            )

            async def failing_op():
                raise Exception("Service error")

            # Open circuit
            for _ in range(2):
                try:
                    await breaker.call(failing_op)
                except Exception:
                    pass

            assert breaker.state == CircuitState.OPEN

            # Wait for HALF_OPEN
            await asyncio.sleep(0.15)
            breaker._check_state()
            assert breaker.state == CircuitState.HALF_OPEN

            # Failure should reopen it
            with pytest.raises(Exception):
                await breaker.call(failing_op)

            assert breaker.state == CircuitState.OPEN

        asyncio.run(test_reopens())


class TestPerChargerBreaker:
    """Test per-charger circuit breaker management."""

    def test_get_same_breaker_for_charger(self):
        """get_charger_breaker returns same breaker for same charger."""

        async def test_same():
            breaker1 = await get_charger_breaker("charger-123")
            breaker2 = await get_charger_breaker("charger-123")
            assert breaker1 is breaker2

        asyncio.run(test_same())

    def test_different_breakers_for_different_chargers(self):
        """Different chargers get different breakers."""

        async def test_different():
            breaker1 = await get_charger_breaker("charger-123")
            breaker2 = await get_charger_breaker("charger-456")
            assert breaker1 is not breaker2

        asyncio.run(test_different())

    def test_breaker_isolation(self):
        """One charger's failures don't affect another's."""

        async def test_isolation():
            breaker1 = await get_charger_breaker("charger-999")
            breaker2 = await get_charger_breaker("charger-888")

            async def failing_op():
                raise Exception("Service error")

            # Open breaker1
            for _ in range(5):
                try:
                    await breaker1.call(failing_op)
                except Exception:
                    pass

            assert breaker1.state == CircuitState.OPEN
            assert breaker2.state == CircuitState.CLOSED

        asyncio.run(test_isolation())


class TestCircuitBreakerWithSyncAndAsync:
    """Test circuit breaker with both sync and async functions."""

    def test_call_async_function(self):
        """Circuit breaker executes async functions."""

        async def test_async():
            breaker = CircuitBreaker(name="test")

            async def async_op(value):
                await asyncio.sleep(0.01)
                return value * 2

            result = await breaker.call(async_op, 5)
            assert result == 10

        asyncio.run(test_async())

    def test_call_sync_function(self):
        """Circuit breaker executes sync functions via thread pool."""

        async def test_sync():
            breaker = CircuitBreaker(name="test")

            def sync_op(value):
                return value * 2

            result = await breaker.call(sync_op, 5)
            assert result == 10

        asyncio.run(test_sync())
