"""Retry decorator with exponential back-off and optional jitter."""
from __future__ import annotations

import asyncio
import functools
import logging
import random
from typing import Any, Callable, Sequence, Tuple, Type

logger = logging.getLogger(__name__)


def retry_with_backoff(
    max_retries: int = 3,
    base_delay: float = 0.5,
    max_delay: float = 30.0,
    exceptions: Tuple[Type[Exception], ...] = (Exception,),
    jitter: bool = True,
) -> Callable:
    """Decorator that retries an async function with exponential back-off.

    Args:
        max_retries:  Maximum number of retry attempts (not counting the first call).
        base_delay:   Initial delay in seconds between retries.
        max_delay:    Maximum delay cap in seconds.
        exceptions:   Tuple of exception types that trigger a retry.
        jitter:       If True, add a random fraction of the delay to spread load.

    Example::

        @retry_with_backoff(max_retries=3, base_delay=1.0, exceptions=(httpx.TimeoutException,))
        async def call_ocpp():
            ...
    """

    def decorator(func: Callable) -> Callable:
        @functools.wraps(func)
        async def wrapper(*args: Any, **kwargs: Any) -> Any:
            last_exc: Exception | None = None
            for attempt in range(max_retries + 1):
                try:
                    return await func(*args, **kwargs)
                except exceptions as exc:
                    last_exc = exc
                    if attempt == max_retries:
                        logger.error(
                            "%s failed after %d attempts: %s",
                            func.__qualname__,
                            attempt + 1,
                            exc,
                        )
                        raise

                    delay = min(base_delay * (2 ** attempt), max_delay)
                    if jitter:
                        delay = delay * (0.5 + random.random() * 0.5)

                    logger.warning(
                        "%s attempt %d/%d failed (%s). Retrying in %.2fs…",
                        func.__qualname__,
                        attempt + 1,
                        max_retries + 1,
                        exc,
                        delay,
                    )
                    await asyncio.sleep(delay)
            # Should never reach here
            raise last_exc  # type: ignore[misc]

        return wrapper

    return decorator
