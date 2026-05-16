"""Distributed lock using Redis SETNX with asyncio.Lock fallback."""
from __future__ import annotations

import asyncio
import logging
import time
import uuid
from contextlib import asynccontextmanager
from typing import Optional

logger = logging.getLogger(__name__)

# ---------------------------------------------------------------------------
# Redis client (optional)
# ---------------------------------------------------------------------------

_redis_client = None
_redis_unavailable = False


def _get_redis():
    global _redis_client, _redis_unavailable
    if _redis_unavailable:
        return None
    if _redis_client is not None:
        return _redis_client
    try:
        import redis  # type: ignore
        import os

        redis_url = os.getenv("REDIS_URL", "")
        if not redis_url:
            _redis_unavailable = True
            logger.info("REDIS_URL not set — distributed lock falling back to asyncio.Lock")
            return None
        _redis_client = redis.from_url(redis_url, decode_responses=True, socket_timeout=2)
        _redis_client.ping()
        logger.info("Redis distributed lock store connected")
        return _redis_client
    except Exception as exc:
        _redis_unavailable = True
        logger.warning("Redis unavailable (%s) — distributed lock falling back to asyncio.Lock", exc)
        return None


# ---------------------------------------------------------------------------
# In-process fallback locks
# ---------------------------------------------------------------------------

_local_locks: dict[str, asyncio.Lock] = {}
_local_lock_registry = asyncio.Lock()


async def _get_local_lock(lock_key: str) -> asyncio.Lock:
    async with _local_lock_registry:
        if lock_key not in _local_locks:
            _local_locks[lock_key] = asyncio.Lock()
        return _local_locks[lock_key]


# ---------------------------------------------------------------------------
# Lua script for atomic Redis unlock
# ---------------------------------------------------------------------------

_UNLOCK_SCRIPT = """
if redis.call("GET", KEYS[1]) == ARGV[1] then
    return redis.call("DEL", KEYS[1])
else
    return 0
end
"""


# ---------------------------------------------------------------------------
# Exception
# ---------------------------------------------------------------------------

class LockAcquisitionError(Exception):
    """Raised when a distributed lock cannot be acquired within the timeout."""


# ---------------------------------------------------------------------------
# Public API
# ---------------------------------------------------------------------------

@asynccontextmanager
async def charger_lock(
    charger_id: str,
    connector_id: str,
    timeout_seconds: int = 30,
):
    """Async context manager that acquires an exclusive lock for a charger connector.

    Uses Redis SETNX if available, falls back to asyncio.Lock otherwise.

    Raises:
        LockAcquisitionError: if the lock cannot be acquired within *timeout_seconds*.
    """
    lock_key = f"charger_lock:{charger_id}:{connector_id}"
    lock_value = str(uuid.uuid4())

    r = _get_redis()

    if r is not None:
        # Redis path
        acquired = False
        deadline = time.monotonic() + timeout_seconds
        while time.monotonic() < deadline:
            try:
                ok = r.set(lock_key, lock_value, nx=True, ex=timeout_seconds)
                if ok:
                    acquired = True
                    break
            except Exception as exc:
                logger.error("Redis lock acquisition error for key=%s: %s", lock_key, exc)
                break
            await asyncio.sleep(0.25)

        if not acquired:
            raise LockAcquisitionError(
                f"Could not acquire lock for charger={charger_id} connector={connector_id} "
                f"within {timeout_seconds}s"
            )
        logger.debug("Redis lock acquired: %s", lock_key)
        try:
            yield
        finally:
            try:
                r.eval(_UNLOCK_SCRIPT, 1, lock_key, lock_value)
                logger.debug("Redis lock released: %s", lock_key)
            except Exception as exc:
                logger.error("Failed to release Redis lock %s: %s", lock_key, exc)
    else:
        # asyncio.Lock fallback
        local_lock = await _get_local_lock(lock_key)
        try:
            acquired = await asyncio.wait_for(local_lock.acquire(), timeout=timeout_seconds)
        except asyncio.TimeoutError:
            raise LockAcquisitionError(
                f"Could not acquire local lock for charger={charger_id} connector={connector_id} "
                f"within {timeout_seconds}s"
            )
        logger.debug("Local lock acquired: %s", lock_key)
        try:
            yield
        finally:
            local_lock.release()
            logger.debug("Local lock released: %s", lock_key)
