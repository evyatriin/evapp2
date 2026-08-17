"""WebSocket manager with Redis pub/sub and in-memory fallback."""
from __future__ import annotations

import asyncio
import json
import logging
from collections import defaultdict
from typing import Any, Dict, List, Set

from fastapi import WebSocket

logger = logging.getLogger(__name__)

# ---------------------------------------------------------------------------
# Redis pub/sub (optional)
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
            logger.info("REDIS_URL not set — WebSocket manager using in-memory broadcast only")
            return None
        _redis_client = redis.from_url(redis_url, decode_responses=True, socket_timeout=2)
        _redis_client.ping()
        logger.info("Redis pub/sub for WebSocket manager connected")
        return _redis_client
    except Exception as exc:
        _redis_unavailable = True
        logger.warning(
            "Redis unavailable (%s) — WebSocket manager using in-memory broadcast only", exc
        )
        return None


# ---------------------------------------------------------------------------
# WebSocketManager
# ---------------------------------------------------------------------------

class WebSocketManager:
    """Manages WebSocket connections per session with optional Redis pub/sub.

    Multiple WebSocket clients can subscribe to the same session_id.
    Messages are broadcast to all connected clients for that session.

    When Redis is available, published messages are also pushed to the
    ``ws:session:<session_id>`` channel so that a multi-instance deployment
    can fan-out correctly.  Each instance subscribes to relevant channels
    on connect and unsubscribes on disconnect.
    """

    def __init__(self) -> None:
        # session_id -> set of (websocket, user_id) tuples
        self._connections: Dict[str, List[Dict[str, Any]]] = defaultdict(list)
        self._lock = asyncio.Lock()

    async def connect(self, session_id: str, websocket: WebSocket, user_id: str) -> None:
        """Register a new WebSocket connection for *session_id*."""
        await websocket.accept()
        async with self._lock:
            self._connections[session_id].append(
                {"ws": websocket, "user_id": user_id}
            )
        logger.info(
            "WebSocket connected: session=%s user=%s (total=%d)",
            session_id,
            user_id,
            len(self._connections[session_id]),
        )

        # Optionally subscribe to Redis channel for this session
        r = _get_redis()
        if r is not None:
            channel = f"ws:session:{session_id}"
            # Fire-and-forget: start a listener task for this connection
            asyncio.create_task(
                self._redis_listener(session_id, channel, websocket),
                name=f"redis_listener:{session_id}:{id(websocket)}",
            )

    def disconnect(self, session_id: str, websocket: WebSocket) -> None:
        """Remove a WebSocket connection."""
        conns = self._connections.get(session_id, [])
        self._connections[session_id] = [c for c in conns if c["ws"] is not websocket]
        logger.info(
            "WebSocket disconnected: session=%s (remaining=%d)",
            session_id,
            len(self._connections[session_id]),
        )

    async def broadcast_meter_update(
        self, session_id: str, meter_data: Dict[str, Any]
    ) -> None:
        """Push a live meter update to all subscribers of *session_id*."""
        payload = json.dumps({"type": "meter_update", "data": meter_data}, default=str)
        await self._broadcast(session_id, payload)

        # Publish to Redis so other app instances can relay
        r = _get_redis()
        if r is not None:
            try:
                r.publish(f"ws:session:{session_id}", payload)
            except Exception as exc:
                logger.error("Redis publish meter_update failed: session=%s %s", session_id, exc)

    async def broadcast_session_end(
        self, session_id: str, final_data: Dict[str, Any]
    ) -> None:
        """Push a session-end event to all subscribers and clean up."""
        payload = json.dumps({"type": "session_end", "data": final_data}, default=str)
        await self._broadcast(session_id, payload)

        # Publish to Redis
        r = _get_redis()
        if r is not None:
            try:
                r.publish(f"ws:session:{session_id}", payload)
            except Exception as exc:
                logger.error("Redis publish session_end failed: session=%s %s", session_id, exc)

        # Close all connections for this session
        async with self._lock:
            conns = self._connections.pop(session_id, [])
        for conn in conns:
            try:
                await conn["ws"].close()
            except Exception:
                pass

    async def _broadcast(self, session_id: str, payload: str) -> None:
        """Send *payload* to every WebSocket subscribed to *session_id*."""
        async with self._lock:
            conns = list(self._connections.get(session_id, []))

        dead: List[Dict[str, Any]] = []
        for conn in conns:
            try:
                await conn["ws"].send_text(payload)
            except Exception as exc:
                logger.warning(
                    "WebSocket send failed: session=%s user=%s error=%s",
                    session_id,
                    conn.get("user_id"),
                    exc,
                )
                dead.append(conn)

        # Remove dead connections
        if dead:
            async with self._lock:
                for d in dead:
                    try:
                        self._connections[session_id].remove(d)
                    except ValueError:
                        pass

    async def _redis_listener(
        self, session_id: str, channel: str, websocket: WebSocket
    ) -> None:
        """Subscribe to a Redis channel and forward messages to *websocket*."""
        try:
            import redis  # type: ignore
            import os

            redis_url = os.getenv("REDIS_URL", "")
            if not redis_url:
                return

            # Each listener needs its own connection for blocking subscribe
            sub_client = redis.from_url(redis_url, decode_responses=True)
            pubsub = sub_client.pubsub()
            pubsub.subscribe(channel)
            logger.debug("Redis subscribe: channel=%s", channel)

            for message in pubsub.listen():
                # Check if websocket is still connected
                found = any(
                    c["ws"] is websocket
                    for c in self._connections.get(session_id, [])
                )
                if not found:
                    break
                if message["type"] == "message":
                    try:
                        await websocket.send_text(message["data"])
                    except Exception:
                        break
        except Exception as exc:
            logger.debug("Redis listener ended: channel=%s reason=%s", channel, exc)
        finally:
            try:
                pubsub.unsubscribe(channel)
                sub_client.close()
            except Exception:
                pass


# Singleton
ws_manager = WebSocketManager()
