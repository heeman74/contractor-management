"""WebSocket ConnectionManager with Redis pub/sub for cross-worker broadcast.

Design:
  - Each FastAPI worker maintains its own in-process dict of open WebSocket
    connections, keyed by thread_id -> user_id -> WebSocket.
  - When a message is sent, it is published to a Redis channel: chat:thread:{thread_id}.
  - Each worker with connections to that thread has a background relay task
    subscribed to the same Redis channel. The relay task forwards received
    payloads to all local connections for that thread.
  - This ensures messages reach all connected clients regardless of which
    worker handled the HTTP POST that created the message.

Redis connection:
  - Lazy-initialized on first use from settings.redis_url.
  - Separate Redis client per pubsub subscription (redis-py requirement:
    a PubSub connection blocks its underlying connection).

Relay task lifecycle:
  - Started when the first connection to a thread is registered.
  - Cancelled and cleaned up when the last connection to a thread disconnects.
  - Individual send errors (dead connections) are caught and logged — one bad
    connection should never prevent others from receiving messages.

Module-level singleton `manager` is imported by the WebSocket endpoint.
"""

from __future__ import annotations

import asyncio
import json
import logging
from typing import Any

from fastapi import WebSocket

logger = logging.getLogger(__name__)


class ConnectionManager:
    """Manages WebSocket connections and Redis pub/sub relay per thread."""

    def __init__(self) -> None:
        # thread_id (str) -> user_id (str) -> WebSocket
        self._connections: dict[str, dict[str, WebSocket]] = {}
        # Lazy-initialized Redis client for publishing
        self._redis: Any | None = None
        # thread_id -> asyncio relay task
        self._relay_tasks: dict[str, asyncio.Task] = {}  # type: ignore[type-arg]

    async def _get_redis(self) -> Any:
        """Lazy-initialize the Redis client from application settings.

        Returns a connected redis.asyncio.Redis instance. Reuses the existing
        instance if already created (connection pooling handled by redis-py).
        """
        if self._redis is None:
            import redis.asyncio as aioredis

            from app.core.config import settings

            self._redis = aioredis.from_url(settings.redis_url, decode_responses=True)
        return self._redis

    async def connect(self, websocket: WebSocket, thread_id: str, user_id: str) -> None:
        """Accept a WebSocket connection and register it for the given thread.

        If this is the first connection to a thread, starts a Redis relay
        task that subscribes to chat:thread:{thread_id} and forwards
        published messages to all local connections.

        Args:
            websocket: The FastAPI WebSocket to register.
            thread_id: UUID string of the thread to subscribe to.
            user_id: UUID string of the connecting user.
        """
        await websocket.accept()

        if thread_id not in self._connections:
            self._connections[thread_id] = {}

        self._connections[thread_id][user_id] = websocket
        logger.info("WebSocket connected: thread=%s user=%s", thread_id, user_id)

        # Start relay task if this is the first connection for this thread
        if thread_id not in self._relay_tasks:
            task = asyncio.create_task(
                self._relay_from_redis(thread_id),
                name=f"chat-relay-{thread_id}",
            )
            self._relay_tasks[thread_id] = task

    async def disconnect(self, websocket: WebSocket, thread_id: str, user_id: str) -> None:
        """Remove a WebSocket connection and clean up the relay task if empty.

        If this was the last connection for a thread, cancels the Redis relay
        task to free resources.

        Args:
            websocket: The disconnecting WebSocket (used for identity, not called).
            thread_id: UUID string of the thread.
            user_id: UUID string of the disconnecting user.
        """
        thread_connections = self._connections.get(thread_id, {})
        thread_connections.pop(user_id, None)

        if not thread_connections:
            # No more local connections for this thread — clean up relay task
            self._connections.pop(thread_id, None)

            task = self._relay_tasks.pop(thread_id, None)
            if task is not None and not task.done():
                task.cancel()
                import contextlib

                async with contextlib.suppress(asyncio.CancelledError):
                    await task

        logger.info("WebSocket disconnected: thread=%s user=%s", thread_id, user_id)

    async def broadcast_to_thread(self, thread_id: str, payload: dict[str, Any]) -> None:
        """Publish a message payload to the Redis channel for a thread.

        All workers subscribed to chat:thread:{thread_id} will receive and
        relay this to their local connections. The payload is serialized to JSON.

        Args:
            thread_id: UUID string of the target thread.
            payload: Dictionary to publish (will be JSON-encoded).
        """
        try:
            redis = await self._get_redis()
            channel = f"chat:thread:{thread_id}"
            await redis.publish(channel, json.dumps(payload))
        except Exception:
            logger.exception("Failed to publish to Redis channel for thread %s", thread_id)

    async def _relay_from_redis(self, thread_id: str) -> None:
        """Subscribe to Redis channel and relay messages to local WebSocket connections.

        This coroutine runs as a background task for as long as there is at least
        one local connection to the thread. It uses a separate Redis PubSub
        connection (redis-py requirement — PubSub blocks its connection).

        Each individual send error is caught and logged so one dead connection
        does not prevent others from receiving messages.

        Args:
            thread_id: UUID string of the thread to relay for.
        """
        import redis.asyncio as aioredis

        from app.core.config import settings

        pubsub_redis = aioredis.from_url(settings.redis_url, decode_responses=True)
        pubsub = pubsub_redis.pubsub()
        channel = f"chat:thread:{thread_id}"

        try:
            await pubsub.subscribe(channel)
            logger.info("Redis relay started: thread=%s channel=%s", thread_id, channel)

            async for raw_message in pubsub.listen():
                if raw_message["type"] != "message":
                    continue

                data = raw_message["data"]
                try:
                    payload = json.loads(data) if isinstance(data, str) else data
                except json.JSONDecodeError:
                    logger.warning("Invalid JSON from Redis channel %s: %r", channel, data)
                    continue

                # Relay to all local connections for this thread
                connections = self._connections.get(thread_id, {})
                dead_users: list[str] = []

                for uid, ws in connections.items():
                    try:
                        await ws.send_json(payload)
                    except Exception:
                        # Individual connection failure — log and mark for cleanup
                        logger.debug(
                            "Failed to send to WebSocket user=%s thread=%s — marking dead",
                            uid,
                            thread_id,
                        )
                        dead_users.append(uid)

                # Clean up dead connections (avoid dict mutation during iteration)
                for uid in dead_users:
                    connections.pop(uid, None)

        except asyncio.CancelledError:
            logger.info("Redis relay cancelled: thread=%s", thread_id)
        except Exception:
            logger.exception("Redis relay error: thread=%s", thread_id)
        finally:
            try:
                await pubsub.unsubscribe(channel)
                await pubsub_redis.aclose()
            except Exception:
                logger.debug("Error closing Redis pubsub for thread %s", thread_id)

    async def send_to_user(self, thread_id: str, user_id: str, payload: dict[str, Any]) -> bool:
        """Send a payload directly to a specific user's local WebSocket connection.

        Used for targeted messages (e.g. delivery confirmations, error messages)
        that do not need to be broadcast to all thread members.

        Returns True if the message was sent successfully, False if the user
        is not connected on this worker.
        """
        connection = self._connections.get(thread_id, {}).get(user_id)
        if connection is None:
            return False
        try:
            await connection.send_json(payload)
            return True
        except Exception:
            logger.debug("Failed to send direct message to user=%s thread=%s", user_id, thread_id)
            return False


# Module-level singleton — imported by the WebSocket endpoint router
manager = ConnectionManager()
