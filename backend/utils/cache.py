"""Redis-backed cache with in-memory dict fallback."""
from __future__ import annotations

import functools
import json
import logging
import time
from typing import Any, Callable, Dict, Optional

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
            logger.info("REDIS_URL not set — cache falling back to in-memory store")
            return None
        _redis_client = redis.from_url(redis_url, decode_responses=True, socket_timeout=2)
        _redis_client.ping()
        logger.info("Redis cache store connected")
        return _redis_client
    except Exception as exc:
        _redis_unavailable = True
        logger.warning("Redis unavailable (%s) — cache falling back to in-memory store", exc)
        return None


# ---------------------------------------------------------------------------
# In-memory fallback
# ---------------------------------------------------------------------------

_memory_cache: Dict[str, Dict[str, Any]] = {}


def _mem_get(key: str) -> Optional[Any]:
    entry = _memory_cache.get(key)
    if entry is None:
        return None
    if entry["ttl"] and time.time() > entry["expires_at"]:
        del _memory_cache[key]
        return None
    return entry["value"]


def _mem_set(key: str, value: Any, ttl_seconds: int) -> None:
    _memory_cache[key] = {
        "value": value,
        "ttl": ttl_seconds,
        "expires_at": time.time() + ttl_seconds if ttl_seconds else float("inf"),
    }


def _mem_delete(key: str) -> None:
    _memory_cache.pop(key, None)


def _mem_delete_pattern(pattern: str) -> None:
    prefix = pattern.rstrip("*")
    keys_to_delete = [k for k in list(_memory_cache.keys()) if k.startswith(prefix)]
    for k in keys_to_delete:
        del _memory_cache[k]


# ---------------------------------------------------------------------------
# CacheManager
# ---------------------------------------------------------------------------

class CacheManager:
    """Async cache manager backed by Redis with in-memory fallback."""

    async def get(self, key: str) -> Optional[Any]:
        try:
            r = _get_redis()
            if r is not None:
                raw = r.get(key)
                return json.loads(raw) if raw is not None else None
            return _mem_get(key)
        except Exception as exc:
            logger.error("Cache get failed for key=%s: %s", key, exc)
            return None

    async def set(self, key: str, value: Any, ttl_seconds: int = 300) -> None:
        try:
            serialized = json.dumps(value, default=str)
            r = _get_redis()
            if r is not None:
                r.setex(key, ttl_seconds, serialized)
            else:
                _mem_set(key, value, ttl_seconds)
        except Exception as exc:
            logger.error("Cache set failed for key=%s: %s", key, exc)

    async def invalidate(self, key: str) -> None:
        try:
            r = _get_redis()
            if r is not None:
                r.delete(key)
            else:
                _mem_delete(key)
        except Exception as exc:
            logger.error("Cache invalidate failed for key=%s: %s", key, exc)

    async def invalidate_pattern(self, pattern: str) -> None:
        """Delete all keys matching *pattern* (e.g. 'charger:abc123:*')."""
        try:
            r = _get_redis()
            if r is not None:
                cursor = 0
                while True:
                    cursor, keys = r.scan(cursor, match=pattern, count=100)
                    if keys:
                        r.delete(*keys)
                    if cursor == 0:
                        break
            else:
                _mem_delete_pattern(pattern)
        except Exception as exc:
            logger.error("Cache invalidate_pattern failed for pattern=%s: %s", pattern, exc)


# Singleton
cache = CacheManager()


# ---------------------------------------------------------------------------
# @cached decorator
# ---------------------------------------------------------------------------

def cached(key_prefix: str, ttl_seconds: int = 300) -> Callable:
    """Decorator that caches the return value of an async function.

    The cache key is ``<key_prefix>:<arg0>:<arg1>:…``.  Works only for
    positional arguments and JSON-serialisable return values.

    Example::

        @cached("charger", ttl_seconds=60)
        async def get_charger(charger_id: str) -> dict:
            ...
    """

    def decorator(func: Callable) -> Callable:
        @functools.wraps(func)
        async def wrapper(*args: Any, **kwargs: Any) -> Any:
            arg_part = ":".join(str(a) for a in args)
            kwarg_part = ":".join(f"{k}={v}" for k, v in sorted(kwargs.items()))
            parts = [key_prefix, arg_part, kwarg_part]
            cache_key = ":".join(p for p in parts if p)

            cached_value = await cache.get(cache_key)
            if cached_value is not None:
                logger.debug("Cache HIT: %s", cache_key)
                return cached_value

            logger.debug("Cache MISS: %s", cache_key)
            result = await func(*args, **kwargs)
            if result is not None:
                await cache.set(cache_key, result, ttl_seconds)
            return result

        return wrapper

    return decorator
