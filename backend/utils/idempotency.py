"""Idempotency helper with Redis primary store and in-memory fallback."""
from __future__ import annotations

import hashlib
import json
import logging
import time
from typing import Any, Dict, Optional

logger = logging.getLogger(__name__)

TTL_SECONDS = 86400  # 24 hours

# ---------------------------------------------------------------------------
# Redis client (optional)
# ---------------------------------------------------------------------------

_redis_client = None
_redis_unavailable = False


def _get_redis():
    """Lazily acquire a Redis client; return None if unavailable."""
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
            logger.info("REDIS_URL not set — idempotency falling back to in-memory store")
            return None
        _redis_client = redis.from_url(redis_url, decode_responses=True, socket_timeout=2)
        _redis_client.ping()
        logger.info("Redis idempotency store connected")
        return _redis_client
    except Exception as exc:
        _redis_unavailable = True
        logger.warning("Redis unavailable (%s) — idempotency falling back to in-memory store", exc)
        return None


# ---------------------------------------------------------------------------
# In-memory fallback
# ---------------------------------------------------------------------------

_memory_store: Dict[str, Dict[str, Any]] = {}


def _memory_get(key: str) -> Optional[Dict[str, Any]]:
    entry = _memory_store.get(key)
    if entry is None:
        return None
    if time.time() > entry["expires_at"]:
        del _memory_store[key]
        return None
    return entry["data"]


def _memory_set(key: str, data: Dict[str, Any]) -> None:
    _memory_store[key] = {
        "data": data,
        "expires_at": time.time() + TTL_SECONDS,
    }


# ---------------------------------------------------------------------------
# Public API
# ---------------------------------------------------------------------------

def make_idempotency_key(user_id: str, request_key: str, body: Any) -> str:
    """Derive a deterministic cache key from the user, request key, and body hash."""
    body_str = json.dumps(body, sort_keys=True, default=str) if body else ""
    combined = f"{user_id}:{request_key}:{body_str}"
    digest = hashlib.sha256(combined.encode()).hexdigest()[:16]
    return f"idempotency:{user_id}:{request_key}:{digest}"


def check_idempotency(key: str, user_id: str, body: Any) -> Optional[Dict[str, Any]]:
    """Return a previously stored response for this key, or None if not found."""
    try:
        r = _get_redis()
        if r is not None:
            raw = r.get(key)
            if raw:
                return json.loads(raw)
            return None
        return _memory_get(key)
    except Exception as exc:
        logger.error("idempotency check failed for key=%s: %s", key, exc)
        return None


def store_idempotency_response(
    key: str,
    user_id: str,
    body: Any,
    response: Dict[str, Any],
) -> None:
    """Persist a response so duplicate requests get the same answer."""
    try:
        r = _get_redis()
        if r is not None:
            r.setex(key, TTL_SECONDS, json.dumps(response, default=str))
        else:
            _memory_set(key, response)
    except Exception as exc:
        logger.error("idempotency store failed for key=%s: %s", key, exc)
