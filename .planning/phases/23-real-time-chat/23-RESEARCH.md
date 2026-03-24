# Phase 23: Real-Time Chat - Research

**Researched:** 2026-03-24
**Domain:** WebSocket real-time messaging, Redis pub/sub, offline message queue, FCM push
**Confidence:** HIGH

## Summary

Phase 23 adds real-time chat to ContractorHub: two thread types (per-trade-scope and project-wide), WebSocket transport via FastAPI/Starlette's native support, offline queuing via the existing Drift SyncQueue outbox pattern, and FCM push for offline delivery. The stack is already 90% present — FastAPI has WebSocket support built in, Redis is already in Settings (redis_url), firebase_admin is installed, and web_socket_channel 3.0.3 is already a transitive Flutter dependency.

The key architectural challenge is chat-per-thread connection management with Redis pub/sub for broadcasting (one WebSocket connection per user, subscribed to relevant thread channels). FastAPI's single-process in-memory ConnectionManager does not scale across uvicorn workers; Redis pub/sub solves this and is already configured as `settings.redis_url`. The `redis` package (v5.2.1) with `redis.asyncio` is the modern async approach — `aioredis` is deprecated/abandoned.

The offline-first pattern mirrors the existing SyncQueue outbox: messages typed offline write a Drift row, the sync engine drains on reconnect in FIFO order, and the server deduplicates by UUID. This is the key differentiator vs Connecteam (no offline mode). Last 100 messages cached in Drift on login; older history paginated from server on scroll-up.

**Primary recommendation:** Use FastAPI native WebSockets + `redis.asyncio` pub/sub per thread channel + existing SyncQueue outbox pattern for offline queuing. Add `redis==5.2.1` to requirements.txt and `web_socket_channel: ^3.0.3` explicitly to pubspec.yaml. One migration (0020) covers all new chat tables.

<user_constraints>
## User Constraints (from CONTEXT.md)

### Locked Decisions
- **D-01:** WebSocket transport — FastAPI/Starlette native WebSocket, `ws://api/v1/chat`, JWT auth
- **D-02:** Typing indicator only — no online/offline presence status
- **D-03:** Same WebSocket endpoint for mobile and web
- **D-04:** Two thread types — trade scope thread (auto-created on contractor assignment) + project-wide group chat
- **D-05:** Read receipts — show who read each message with timestamp
- **D-06:** @mentions with forced push — override mute settings for `@user` or `@all`
- **D-07:** Announcement channels deferred to future phase
- **D-08:** Server timestamp ordering — server assigns monotonic sequence per thread; dedup by message UUID
- **D-09:** Project-wide chat auto-includes all contractors on any trade scope + GC
- **D-10:** Photos + PDFs + annotated photos shareable in chat. No video or GIF
- **D-11:** Share annotated photos from task execution into trade scope chat
- **D-12:** Offline queue messages in Drift, sync on reconnect; consistent with SyncQueue pattern
- **D-13:** Last 100 messages per thread cached in Drift on login; paginate older from server
- **D-14:** FCM preview "John D. (Plumbing): Can you check the valve clearance?" — sender + trade scope + preview; @mention overrides mute

### Claude's Discretion
- WebSocket connection lifecycle (heartbeat interval, reconnect backoff strategy)
- Chat message DB schema design (tables, indexes, RLS policies)
- Message pagination strategy (cursor-based vs offset)
- Chat UI layout and styling (follows Phase 22 UI-SPEC design patterns)
- File upload endpoint for chat attachments (reuse or separate from task attachments)
- Mute/notification settings per thread
- Message search implementation (full-text or client-side filter)
- WebSocket authentication flow (JWT in query param vs first-message auth)

### Deferred Ideas (OUT OF SCOPE)
- One-way announcement channels (Connecteam Channels)
- Message reactions/emoji
- Message threading (Slack-style reply-to)
- Message search
- Message pinning
</user_constraints>

<phase_requirements>
## Phase Requirements

| ID | Description | Research Support |
|----|-------------|-----------------|
| CHAT-01 | GC can send text messages to any trade contractor on a project | Trade scope thread model; WebSocket broadcast per thread channel; FastAPI WS router |
| CHAT-02 | Contractor can reply to GC messages in real-time | Same WebSocket endpoint; bidirectional; ConnectionManager + Redis pub/sub |
| CHAT-03 | Chat supports photo and file sharing (annotated photos, PDFs) | Reuse task attachment upload pattern; ChatAttachment model; inline preview in message bubble |
| CHAT-04 | Chat threads are organized per trade scope within a project | ChatThread model with thread_type enum; auto-creation hook on trade scope assignment |
| CHAT-05 | New chat messages trigger push notifications via FCM | Extend NotificationService.send_chat_notification; FCM data payload with thread_id for deep-link; @mention forced push |
</phase_requirements>

---

## Standard Stack

### Core
| Library | Version | Purpose | Why Standard |
|---------|---------|---------|--------------|
| fastapi (built-in) | 0.115.12 | WebSocket endpoint via `websocket.accept()` | Starlette native; no extra install |
| redis[asyncio] | 5.2.1 | Pub/sub channel per thread; broadcast across workers | `redis.asyncio` replaces deprecated `aioredis`; already in Settings |
| web_socket_channel | 3.0.3 | Flutter WebSocket client | Already transitive dep; IOWebSocketChannel for mobile |
| firebase_admin | 6.6.0 | FCM push dispatch | Already installed; existing NotificationService pattern |
| drift | 2.32.0 | Local message cache + outbox | Already installed; SyncQueue pattern directly reusable |

### Supporting
| Library | Version | Purpose | When to Use |
|---------|---------|---------|-------------|
| connectivity_plus | 7.0.0 | Detect online/offline to gate WS connect | Already installed |
| uuid | 4.0.0 (Dart) | Client-generated message UUID for dedup | Already installed |
| aiofiles | 24.1.0 | File upload for chat attachments | Already installed |

### Alternatives Considered
| Instead of | Could Use | Tradeoff |
|------------|-----------|----------|
| `redis.asyncio` pub/sub | In-memory ConnectionManager | In-memory doesn't scale across uvicorn workers; Redis already configured |
| `redis.asyncio` | `aioredis` | `aioredis` is abandoned (aio-libs-abandoned on GitHub); redis-py 5.x has native asyncio |
| Native WS + custom heartbeat | `broadcaster` library | `broadcaster` adds abstraction; native is simpler given single backend |
| Cursor-based pagination | Offset pagination | Cursor (by sequence number) avoids drift when new messages arrive; correct for chat |

**Installation — backend:**
```bash
# Add to requirements.txt:
redis==5.2.1
```

**Installation — mobile (make explicit in pubspec.yaml):**
```yaml
web_socket_channel: ^3.0.3
```

**Version verification (confirmed 2026-03-24):**
- `redis` Python: 5.2.1 (PyPI)
- `web_socket_channel` Flutter: 3.0.3 (already in transitive dep tree)
- FastAPI: 0.115.12 (already installed, WebSocket support confirmed)

---

## Architecture Patterns

### Recommended Project Structure

**Backend:**
```
backend/app/features/chat/
├── __init__.py
├── models.py          # ChatThread, ChatMessage, ChatMembership, ChatReadReceipt, ThreadMute
├── repository.py      # ChatThreadRepository, ChatMessageRepository
├── service.py         # ChatService (TenantScopedService)
├── router.py          # WebSocket endpoint + REST endpoints (history, threads, read receipt)
├── schemas.py         # ChatThreadResponse, ChatMessageResponse, etc.
└── ws_manager.py      # ConnectionManager + Redis pub/sub broadcaster

backend/migrations/versions/0020_chat.py  # All chat tables in one migration
```

**Mobile:**
```
mobile/lib/features/chat/
├── data/
│   ├── chat_ws_client.dart        # WebSocket client with reconnect backoff
│   ├── chat_repository.dart       # Drift DAO + API calls
│   └── chat_sync_service.dart     # Drain outbox queue on reconnect
├── domain/
│   ├── chat_message.dart          # Domain models
│   └── chat_thread.dart
└── presentation/
    ├── chat_screen.dart           # Thread list
    ├── chat_thread_screen.dart    # Message list + input
    └── widgets/
        ├── message_bubble.dart    # Text/image/PDF/annotated-photo bubbles
        ├── typing_indicator.dart  # "..." animation
        └── read_receipt_row.dart  # "Read by John, 2:14 PM"
```

**Drift tables (add to existing app_database.dart):**
```
mobile/lib/core/database/tables/
├── chat_threads.dart
├── chat_messages.dart
└── chat_read_receipts.dart
```

**Web:**
```
web/src/features/chat/
├── components/
│   ├── ChatPanel.tsx              # Sidebar panel for project chat
│   ├── MessageList.tsx
│   ├── MessageInput.tsx
│   └── MessageBubble.tsx
├── hooks/
│   ├── useChatWebSocket.ts        # useRef WebSocket + reconnect
│   └── useChatMessages.ts        # TanStack Query + WS merge
└── types.ts
```

### Pattern 1: Database Schema (Claude's Discretion)

**What:** Four tables — `chat_threads`, `chat_messages`, `chat_memberships`, `chat_read_receipts`. All tenant-scoped. Soft deletes. Monotonic `seq` per thread assigned by DB sequence or trigger.

**Tables:**
```sql
-- migration 0020_chat.py

CREATE TABLE chat_threads (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    company_id UUID NOT NULL REFERENCES companies(id),
    project_id UUID NOT NULL REFERENCES projects(id),
    thread_type TEXT NOT NULL CHECK (thread_type IN ('scope', 'project_wide')),
    trade_scope_id UUID REFERENCES trade_scopes(id),  -- NULL for project_wide
    name TEXT NOT NULL,  -- e.g. "Plumbing" or "Project-Wide"
    muted_by JSONB NOT NULL DEFAULT '[]'::jsonb,  -- array of user_ids who muted
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    deleted_at TIMESTAMPTZ
);

CREATE TABLE chat_messages (
    id UUID PRIMARY KEY,        -- client-generated UUID (idempotency key)
    company_id UUID NOT NULL REFERENCES companies(id),
    thread_id UUID NOT NULL REFERENCES chat_threads(id),
    sender_id UUID NOT NULL REFERENCES users(id),
    content TEXT,               -- NULL for attachment-only messages
    seq BIGINT NOT NULL,        -- server-assigned monotonic sequence per thread
    attachment_id UUID,         -- FK to task_attachments reuse pattern
    attachment_type TEXT CHECK (attachment_type IN ('photo', 'pdf', 'annotated_photo')),
    annotation_data TEXT,       -- JSON overlay for annotated photos (Phase 22 AnnotationLayer)
    mentions JSONB NOT NULL DEFAULT '[]'::jsonb,  -- array of mentioned user_ids
    mention_all BOOLEAN NOT NULL DEFAULT false,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    deleted_at TIMESTAMPTZ
);

-- Sequence per thread for monotonic ordering
CREATE SEQUENCE chat_thread_seq;

-- Index for efficient thread message fetch by sequence cursor
CREATE INDEX idx_chat_messages_thread_seq ON chat_messages (thread_id, seq);
CREATE INDEX idx_chat_messages_company ON chat_messages (company_id);

CREATE TABLE chat_memberships (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    company_id UUID NOT NULL REFERENCES companies(id),
    thread_id UUID NOT NULL REFERENCES chat_threads(id),
    user_id UUID NOT NULL REFERENCES users(id),
    joined_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    UNIQUE (thread_id, user_id)
);

CREATE TABLE chat_read_receipts (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    company_id UUID NOT NULL REFERENCES companies(id),
    thread_id UUID NOT NULL REFERENCES chat_threads(id),
    user_id UUID NOT NULL REFERENCES users(id),
    last_read_seq BIGINT NOT NULL,
    read_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    UNIQUE (thread_id, user_id)  -- upsert on each read
);

-- RLS: all tables gated by company_id
ALTER TABLE chat_threads ENABLE ROW LEVEL SECURITY;
ALTER TABLE chat_messages ENABLE ROW LEVEL SECURITY;
ALTER TABLE chat_memberships ENABLE ROW LEVEL SECURITY;
ALTER TABLE chat_read_receipts ENABLE ROW LEVEL SECURITY;

CREATE POLICY chat_threads_isolation ON chat_threads
    USING (company_id = current_setting('app.current_company_id')::uuid);
-- (repeat for all chat tables)
```

**Sequence assignment:** Use a DB-level counter per thread. Options:
- Option A: Single global `chat_thread_seq` sequence, accept gaps per thread (simpler)
- Option B: Use `nextval()` in a trigger per `thread_id` (complex, avoids cross-thread gaps)
- **Recommendation:** Option A — single global sequence. Monotonic per thread is guaranteed since seq only increases; gaps don't matter for ordering.

### Pattern 2: WebSocket Connection Manager + Redis Pub/Sub

**What:** ConnectionManager holds per-process WebSocket connections keyed by `user_id`. Redis pub/sub channel per thread (`chat:thread:{thread_id}`). All workers subscribe to channels for their connected users.

**Example:**
```python
# Source: redis.readthedocs.io/en/stable/examples/asyncio_examples.html
# + websocket.org/guides/frameworks/fastapi/ pattern

import asyncio
import json
import uuid
from typing import Any

import redis.asyncio as aioredis
from fastapi import WebSocket

from app.core.config import settings


class ConnectionManager:
    """In-process WebSocket registry + Redis pub/sub broadcaster."""

    def __init__(self) -> None:
        # keyed by thread_id -> set of WebSocket objects for this worker
        self._connections: dict[str, set[WebSocket]] = {}
        self._redis: aioredis.Redis | None = None

    async def get_redis(self) -> aioredis.Redis:
        if self._redis is None:
            self._redis = aioredis.from_url(
                settings.redis_url,
                encoding="utf-8",
                decode_responses=True,
            )
        return self._redis

    async def connect(self, websocket: WebSocket, thread_id: str) -> None:
        await websocket.accept()
        self._connections.setdefault(thread_id, set()).add(websocket)

    def disconnect(self, websocket: WebSocket, thread_id: str) -> None:
        connections = self._connections.get(thread_id, set())
        connections.discard(websocket)

    async def broadcast_to_thread(self, thread_id: str, payload: dict[str, Any]) -> None:
        """Publish message to Redis channel — all workers relay to their local connections."""
        redis = await self.get_redis()
        await redis.publish(f"chat:thread:{thread_id}", json.dumps(payload))

    async def relay_from_redis(self, thread_id: str) -> None:
        """Subscribe to Redis channel and relay messages to local WebSocket connections."""
        redis = aioredis.from_url(
            settings.redis_url, encoding="utf-8", decode_responses=True
        )
        async with redis.pubsub() as pubsub:
            await pubsub.subscribe(f"chat:thread:{thread_id}")
            async for message in pubsub.listen():
                if message["type"] != "message":
                    continue
                payload = json.loads(message["data"])
                dead: set[WebSocket] = set()
                for ws in self._connections.get(thread_id, set()):
                    try:
                        await ws.send_json(payload)
                    except Exception:
                        dead.add(ws)
                for ws in dead:
                    self._connections[thread_id].discard(ws)


manager = ConnectionManager()
```

### Pattern 3: WebSocket Router Endpoint

**What:** `GET /ws/chat/{thread_id}?token=...` — JWT in query param (browser WebSocket API does not support Authorization headers). Validate before `accept()`. Re-validate every 5 minutes (D-v3.0 in STATE.md: "WebSocket JWT re-validated server-side every 5 minutes; close with 4401 on expiry").

```python
# Source: fastapi.tiangolo.com/advanced/websockets/

from fastapi import APIRouter, WebSocket, WebSocketDisconnect, Query
from app.core.security import decode_token  # existing utility

router = APIRouter()

@router.websocket("/ws/chat/{thread_id}")
async def chat_websocket(
    websocket: WebSocket,
    thread_id: str,
    token: str = Query(...),
):
    # 1. Validate JWT BEFORE accept() — reject unauthorized early
    try:
        payload = decode_token(token)
    except Exception:
        await websocket.close(code=4401)
        return

    user_id = payload["sub"]
    company_id = payload["company_id"]

    # 2. Verify user is member of this thread (RLS via company_id)
    # ... membership check ...

    # 3. Accept and register
    await manager.connect(websocket, thread_id)

    # 4. Start Redis relay as background task
    relay_task = asyncio.create_task(manager.relay_from_redis(thread_id))

    try:
        last_validated = asyncio.get_event_loop().time()
        while True:
            # Re-validate token every 5 minutes (STATE.md D: close with 4401 on expiry)
            now = asyncio.get_event_loop().time()
            if now - last_validated > 300:
                try:
                    decode_token(token)  # raises if expired
                    last_validated = now
                except Exception:
                    await websocket.close(code=4401)
                    break

            data = await asyncio.wait_for(websocket.receive_json(), timeout=30.0)
            await handle_incoming_message(data, user_id, company_id, thread_id)

    except WebSocketDisconnect:
        pass
    except asyncio.TimeoutError:
        # Heartbeat timeout — send ping or close
        pass
    finally:
        manager.disconnect(websocket, thread_id)
        relay_task.cancel()
```

### Pattern 4: Flutter WebSocket Client with Reconnect Backoff

**What:** Custom `ChatWsClient` using `web_socket_channel` + exponential backoff reconnect. Heartbeat ping every 30s. On reconnect, fetch missed messages since `lastSeq` from REST API.

```dart
// Source: docs.flutter.dev/cookbook/networking/web-sockets
// + exponential backoff pattern from community (verified multiple sources)

import 'dart:async';
import 'package:web_socket_channel/io.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

class ChatWsClient {
  ChatWsClient({required this.baseWsUrl, required this.tokenProvider});

  final String baseWsUrl;
  final Future<String> Function() tokenProvider;

  WebSocketChannel? _channel;
  StreamSubscription? _subscription;
  int _retrySeconds = 1;
  bool _disposed = false;
  final _controller = StreamController<Map<String, dynamic>>.broadcast();

  Stream<Map<String, dynamic>> get messages => _controller.stream;

  Future<void> connect(String threadId) async {
    _disposed = false;
    await _connectWithRetry(threadId);
  }

  Future<void> _connectWithRetry(String threadId) async {
    while (!_disposed) {
      try {
        final token = await tokenProvider();
        final uri = Uri.parse('$baseWsUrl/ws/chat/$threadId?token=$token');
        _channel = IOWebSocketChannel.connect(uri);

        await _channel!.ready;  // throws if connection fails
        _retrySeconds = 1;      // reset on successful connect

        _subscription = _channel!.stream.listen(
          (data) => _onMessage(data),
          onDone: () => _scheduleReconnect(threadId),
          onError: (_) => _scheduleReconnect(threadId),
        );
        return;  // connected successfully
      } catch (_) {
        await Future.delayed(Duration(seconds: _retrySeconds));
        _retrySeconds = (_retrySeconds * 2).clamp(1, 64);
      }
    }
  }

  void _scheduleReconnect(String threadId) {
    if (_disposed) return;
    Future.delayed(Duration(seconds: _retrySeconds), () {
      _retrySeconds = (_retrySeconds * 2).clamp(1, 64);
      _connectWithRetry(threadId);
    });
  }

  void send(Map<String, dynamic> payload) {
    _channel?.sink.add(jsonEncode(payload));
  }

  void dispose() {
    _disposed = true;
    _subscription?.cancel();
    _channel?.sink.close();
    _controller.close();
  }
}
```

**Heartbeat:** Send `{"type": "ping"}` every 30 seconds from client; server responds `{"type": "pong"}`. If no pong within 10s, close and reconnect.

**Re-validate on reconnect:** After reconnecting, call `GET /chat/threads/{thread_id}/messages?since_seq={lastSeq}` to fetch missed messages before resuming WebSocket delivery.

### Pattern 5: Offline Outbox (Drift SyncQueue Extension)

**What:** Use SyncQueue outbox exactly as in Phase 2 offline sync. When offline, write `entityType: 'chat_message'`, `operation: 'CREATE'`, `payload: JSON` to SyncQueue. On reconnect, sync engine drains in FIFO order via WebSocket `send()` — no REST endpoint needed for message send.

**Key insight:** Messages queue in SyncQueue (already exists at `mobile/lib/core/database/tables/sync_queue.dart`). The ChatSyncService listens to `connectivityProvider` and drains pending chat messages via WebSocket on reconnect. Server deduplicates by message `id` (UUID, per D-08).

### Pattern 6: FCM Chat Notification (extend NotificationService)

**What:** Add `send_chat_notification()` method to existing `NotificationService`. Follow existing fire-and-forget pattern. For @mention, bypass mute check.

```python
# Extends backend/app/features/notifications/service.py pattern
async def send_chat_notification(
    self,
    thread_id: uuid.UUID,
    sender_name: str,
    trade_scope_name: str | None,
    message_preview: str,
    recipient_user_ids: list[uuid.UUID],
    mention_all: bool,
    mentioned_user_ids: list[uuid.UUID],
    muted_by: list[uuid.UUID],
) -> None:
    """FCM push for new chat message. @mention overrides mute."""
    # D-14: "John D. (Plumbing): Can you check the valve clearance?"
    scope_label = f" ({trade_scope_name})" if trade_scope_name else ""
    body = f"{sender_name}{scope_label}: {message_preview[:100]}"

    for user_id in recipient_user_ids:
        is_mentioned = mention_all or (user_id in mentioned_user_ids)
        is_muted = user_id in muted_by
        if is_muted and not is_mentioned:
            continue  # @mention overrides mute; otherwise skip
        # ... send FCM with data payload: thread_id, type='chat_message'
```

### Pattern 7: Drift Local Cache Tables

**What:** Three new Drift tables — `ChatThreads`, `ChatMessages`, `ChatReadReceipts`. ChatMessages stores last 100 per thread (D-13). Older messages fetched from server on scroll-up (cursor pagination by `seq`).

```dart
// mobile/lib/core/database/tables/chat_messages.dart
class ChatMessages extends Table {
  TextColumn get id => text()();  // client-generated UUID
  TextColumn get companyId => text()();
  TextColumn get threadId => text()();
  TextColumn get senderId => text()();
  TextColumn get senderName => text()();
  TextColumn get content => text().nullable()();
  IntColumn get seq => integer()();
  TextColumn get attachmentId => text().nullable()();
  TextColumn get attachmentType => text().nullable()();
  TextColumn get annotationData => text().nullable()();
  TextColumn get mentions => text().withDefault(const Constant('[]'))();
  BoolColumn get mentionAll => boolean().withDefault(const Constant(false))();
  DateTimeColumn get createdAt => dateTime()();
  DateTimeColumn get deletedAt => dateTime().nullable()();

  @override
  Set<Column> get primaryKey => {id};
}
```

**Trim policy:** After inserting new messages, delete rows for this thread where `seq < (max_seq - 100)` to keep local cache at 100.

### Anti-Patterns to Avoid

- **In-memory ConnectionManager only:** Works for single-process dev; fails silently with `uvicorn --workers 4`. Always back with Redis pub/sub.
- **`async void` in WebSocket loops:** Use `await` everywhere; async void breaks exception propagation.
- **`aioredis` import:** Package is abandoned. Use `import redis.asyncio as aioredis`.
- **Storing JWT in WebSocket URL path (not query param):** Browser WebSocket API cannot set custom headers. JWT must go in query param or first message. Use short-lived token (existing 15-min access token is sufficient).
- **Offset pagination for chat history:** Message counts change while user is scrolling. Use cursor (sequence number): `GET /chat/{thread_id}/messages?before_seq=450&limit=50`.
- **Calling `db.commit()` inside ChatService methods:** CLAUDE.md prohibits this; `get_db` handles commit/rollback.
- **Blocking broadcast on dead connections:** Catch send failures individually; don't let one dead connection block others.
- **`pumpAndSettle()` in Flutter tests with Drift stream providers:** CLAUDE.md/MEMORY.md: Drift streams never settle. Use `pump()` instead.

---

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| Cross-worker broadcast | Custom shared memory | `redis.asyncio` pub/sub | Workers don't share memory; Redis already in settings |
| JWT decode for WS | Custom parser | Existing `decode_token()` from `app.core.security` | Already handles jose + expiry |
| File upload for chat | New upload service | Reuse `POST /tasks/{id}/attachments` pattern with aiofiles | Same S3/local file storage; already tested |
| FCM dispatch | Custom FCM client | Extend existing `NotificationService` | Fire-and-forget pattern, token cleanup, credential management all done |
| Offline message queue | Custom outbox table | Reuse existing `SyncQueue` Drift table | Already handles FIFO, idempotency keys, status lifecycle |
| Message dedup | Custom dedup table | Client UUID + `ON CONFLICT DO NOTHING` on INSERT | Standard pattern; SQLAlchemy `insert().on_conflict_do_nothing()` |
| Annotated photo rendering | New renderer | Reuse Phase 22 `AnnotationLayer` JSON + existing canvas widget | Schema documented at `mobile/lib/features/projects/domain/annotation_schema.dart` |

**Key insight:** This phase is mostly wiring — the hard infrastructure (auth, FCM, file upload, offline sync, Drift tables, annotation rendering) is already built. Chat is a new feature domain built on proven foundations.

---

## Common Pitfalls

### Pitfall 1: WebSocket Auth — Token in URL Logged by Reverse Proxy
**What goes wrong:** JWT token in query param `?token=xyz` gets logged in nginx/load balancer access logs.
**Why it happens:** HTTP upgrade request includes query string in access logs.
**How to avoid:** Keep access tokens short-lived (15 min existing default). Optionally issue a single-use WS handshake token (60s TTL) via `POST /chat/ws-token` — mobile exchanges access token for short-lived WS token. Log masking at nginx level.
**Warning signs:** Long-lived tokens in query params are a security concern at scale; for this phase, the 15-min access token is acceptable.

### Pitfall 2: Redis Pub/Sub Subscriber Task Leak
**What goes wrong:** `relay_from_redis()` asyncio task not cancelled on disconnect — goroutine leak per connection.
**Why it happens:** Task started via `asyncio.create_task()` but not tracked or cancelled in `finally` block.
**How to avoid:** Always `relay_task.cancel()` in the `finally` block of the WebSocket handler. Track relay tasks in ConnectionManager.
**Warning signs:** Redis PUBSUB NUMSUB shows increasing subscriber count without corresponding client growth.

### Pitfall 3: Message Ordering — Clock Skew
**What goes wrong:** Client displays messages out of order when two devices send simultaneously.
**Why it happens:** Relying on `created_at` client timestamp; clock skew between devices.
**How to avoid:** D-08 is locked: server assigns `seq` (monotonic). Client always sorts by `seq`. Client timestamps are for display only ("2:14 PM"), never for ordering.
**Warning signs:** Messages jump around or appear before earlier messages.

### Pitfall 4: Drift Stream Provider with `pumpAndSettle()`
**What goes wrong:** Widget test hangs forever.
**Why it happens:** Drift watch streams never complete, so `pumpAndSettle()` waits forever.
**How to avoid:** MEMORY.md and CLAUDE.md: use `pump()` with explicit frame count for all widget tests using Drift StreamProvider.
**Warning signs:** Test timeout at 60s with no error message.

### Pitfall 5: Project-Wide Chat Auto-Membership Drift
**What goes wrong:** New contractor assigned to trade scope is not added to project-wide chat.
**Why it happens:** Auto-join logic in `ChatService` not triggered on trade scope update.
**How to avoid:** Hook `ChatService.ensure_project_wide_membership()` into `TradeScopeService.assign_contractor()`. Call it whenever `contractor_id` is set or updated on a TradeScope. Write an integration test that assigns a contractor and asserts membership.
**Warning signs:** New contractors see no project-wide chat; GC messages don't reach them.

### Pitfall 6: Offline Queue Drain Race Condition
**What goes wrong:** Same queued message sent twice if connectivity flickers during drain.
**Why it happens:** Queue item marked 'synced' after server ACK, but network drops before ACK arrives.
**How to avoid:** Server uses `ON CONFLICT DO NOTHING` on `chat_messages(id)` — idempotent insert. Client UUID as idempotency key (existing SyncQueue pattern). Worst case: duplicate send delivers one message (server deduplicates by UUID).
**Warning signs:** Duplicate messages appearing in chat.

### Pitfall 7: Redis Not in requirements.txt
**What goes wrong:** `ImportError: No module named 'redis'` at runtime.
**Why it happens:** `redis_url` is in Settings but `redis` package was never added to requirements.txt.
**How to avoid:** Add `redis==5.2.1` to requirements.txt in Wave 0. `settings.redis_url` already defaults to `redis://localhost:6379/0`.
**Warning signs:** App starts (settings loads fine) but crashes on first WebSocket connection attempt.

---

## Code Examples

### FastAPI WebSocket endpoint skeleton
```python
# Source: fastapi.tiangolo.com/advanced/websockets/ + redis.readthedocs.io async examples
from fastapi import APIRouter, WebSocket, WebSocketDisconnect, Query, status
import asyncio

router = APIRouter(tags=["chat"])

@router.websocket("/ws/chat/{thread_id}")
async def chat_ws_endpoint(
    websocket: WebSocket,
    thread_id: str,
    token: str = Query(...),
):
    # Validate before accept — close 4401 if invalid
    try:
        claims = decode_token(token)
    except Exception:
        await websocket.close(code=4401)
        return

    await manager.connect(websocket, thread_id)
    relay = asyncio.create_task(manager.relay_from_redis(thread_id))
    try:
        while True:
            msg = await websocket.receive_json()
            await process_message(msg, claims, thread_id)
    except WebSocketDisconnect:
        pass
    finally:
        manager.disconnect(websocket, thread_id)
        relay.cancel()
```

### Redis async pub/sub (redis-py 5.x)
```python
# Source: redis.readthedocs.io/en/stable/examples/asyncio_examples.html
import redis.asyncio as aioredis

redis_client = aioredis.from_url(
    settings.redis_url,
    encoding="utf-8",
    decode_responses=True,
)

# Publish
await redis_client.publish("chat:thread:abc123", json.dumps(payload))

# Subscribe (in relay task)
async with redis_client.pubsub() as pubsub:
    await pubsub.subscribe("chat:thread:abc123")
    async for message in pubsub.listen():
        if message["type"] == "message":
            await websocket.send_text(message["data"])
```

### SQLAlchemy upsert for read receipts
```python
# Source: SQLAlchemy 2.x docs — insert().on_conflict_do_update()
from sqlalchemy.dialects.postgresql import insert

stmt = insert(ChatReadReceipt).values(
    company_id=company_id,
    thread_id=thread_id,
    user_id=user_id,
    last_read_seq=seq,
    read_at=func.now(),
).on_conflict_do_update(
    index_elements=["thread_id", "user_id"],
    set_={"last_read_seq": seq, "read_at": func.now()},
    where=ChatReadReceipt.last_read_seq < seq,  # only update if newer
)
await db.execute(stmt)
```

### Flutter: Riverpod stream provider for chat messages
```dart
// Source: Riverpod 3 docs — StreamProvider.autoDispose.family
final chatMessagesProvider = StreamProvider.autoDispose.family<
    List<ChatMessage>, String>((ref, threadId) {
  final dao = ref.read(chatDaoProvider);
  return dao.watchMessages(threadId);  // Drift watch stream
});
```

### Drift message DAO (watch pattern)
```dart
// Source: drift.simonbinder.eu/docs/dart-api/streams/
Stream<List<ChatMessage>> watchMessages(String threadId) {
  return (select(chatMessages)
    ..where((m) => m.threadId.equals(threadId))
    ..where((m) => m.deletedAt.isNull())
    ..orderBy([(m) => OrderingTerm.asc(m.seq)]))
    .watch();
}
```

---

## State of the Art

| Old Approach | Current Approach | When Changed | Impact |
|--------------|------------------|--------------|--------|
| `aioredis` for async Redis | `redis.asyncio` (redis-py 5.x) | 2022 — aioredis abandoned | Import `redis.asyncio`, not `aioredis` |
| `EventSourceResponse` (sse_starlette) | `StreamingResponse(text/event-stream)` | Phase 21 discovery | Same applies; FastAPI 0.115 has no `fastapi.sse` module |
| `FamilyAsyncNotifier` (Riverpod 2) | `AsyncNotifier.family` with factory | Riverpod 3 | STATE.md: `(arg) => Notifier(arg)` factory pattern |
| Offset pagination for chat | Cursor-based by sequence | Standard for real-time feeds | Avoids page drift when new messages arrive |

**Deprecated/outdated:**
- `aioredis`: Do NOT use. Package is at `aio-libs-abandoned/aioredis-py`. Use `redis.asyncio`.
- `Interceptor` with `async void` in Flutter: CLAUDE.md: use `QueuedInterceptor` for async operations.

---

## Open Questions

1. **WebSocket auth: query param vs first-message**
   - What we know: Browser WebSocket API cannot send custom headers. Query param is standard.
   - What's unclear: Security team preference; short-lived WS token vs reuse 15-min access token.
   - Recommendation: Use existing 15-min access token in query param for Phase 23. WS-specific token is a hardening improvement for a later phase.

2. **File upload endpoint for chat attachments**
   - What we know: Task attachment upload pattern exists at `POST /tasks/{id}/attachments`. Chat messages also need file attachments.
   - What's unclear: Separate `POST /chat/attachments` or reuse task endpoint.
   - Recommendation: Create `POST /chat/messages/{message_id}/attachment` following exact same `aiofiles` + `StaticFiles` pattern. Don't repurpose task attachments — chat attachments have different lifecycle (message deletion cascades to file).

3. **Redis PUBSUB availability in test environment**
   - What we know: `settings.redis_url = "redis://localhost:6379/0"` in config. Redis is not in requirements.txt yet.
   - What's unclear: Is Redis running in CI/test environment? Backend conftest.py uses PostgreSQL test DB.
   - Recommendation: Add Redis mock/fakeredis for unit tests; add a note in Wave 0 to confirm Redis is available in CI.

4. **Sequence numbering: global vs per-thread**
   - What we know: D-08 says "monotonic sequence number per thread." A global PostgreSQL sequence produces monotonic values across all threads (no per-thread gaps, but gaps within a thread are possible if another thread uses a sequence number).
   - What's unclear: Whether clients care about dense sequences or just monotonic ordering.
   - Recommendation: Global sequence is simpler and still guarantees monotonic ordering within a thread (since seq only increases). Use `nextval('chat_seq')` in the INSERT trigger. Document in migration.

---

## Validation Architecture

### Test Framework
| Property | Value |
|----------|-------|
| Framework | pytest 8.3.4 (backend) + flutter_test (mobile) |
| Config file | `backend/pytest.ini` (or pyproject.toml) |
| Quick run command | `cd backend && uv run python -m pytest tests/test_phase_23_e2e.py -x` |
| Full suite command | `cd backend && uv run python -m pytest && cd mobile && flutter test` |

### Phase Requirements → Test Map
| Req ID | Behavior | Test Type | Automated Command | File Exists? |
|--------|----------|-----------|-------------------|-------------|
| CHAT-01 | GC sends text message to contractor via WebSocket | integration | `pytest tests/test_phase_23_e2e.py::test_gc_sends_message -x` | ❌ Wave 0 |
| CHAT-02 | Contractor reply delivered in real-time via WebSocket | integration | `pytest tests/test_phase_23_e2e.py::test_contractor_reply -x` | ❌ Wave 0 |
| CHAT-03 | Photo + PDF + annotated photo shareable in chat | integration | `pytest tests/test_phase_23_e2e.py::test_chat_file_attachment -x` | ❌ Wave 0 |
| CHAT-04 | Chat threads per trade scope; auto-created on assignment | integration | `pytest tests/test_phase_23_e2e.py::test_thread_auto_create -x` | ❌ Wave 0 |
| CHAT-05 | FCM push on new message; @mention overrides mute | unit | `pytest tests/test_phase_23_e2e.py::test_fcm_push -x` | ❌ Wave 0 |
| CHAT-01..05 | Flutter E2E: full offline→queue→reconnect→sync flow | e2e widget | `cd mobile && flutter test test/e2e/phase_23_real_time_chat_e2e_test.dart` | ❌ Wave 0 |

### Sampling Rate
- **Per task commit:** `cd backend && uv run python -m pytest tests/test_phase_23_e2e.py -x`
- **Per wave merge:** `cd backend && uv run python -m pytest && cd mobile && flutter test`
- **Phase gate:** Full suite green before `/gsd:verify-work`

### Wave 0 Gaps
- [ ] `backend/tests/test_phase_23_e2e.py` — integration tests for CHAT-01 through CHAT-05
- [ ] `mobile/test/e2e/phase_23_real_time_chat_e2e_test.dart` — Flutter E2E covering full message flow
- [ ] `redis==5.2.1` added to `backend/requirements.txt`
- [ ] `web_socket_channel: ^3.0.3` added explicitly to `mobile/pubspec.yaml` (currently transitive only)
- [ ] Migration `0020_chat.py` created (new Alembic migration)
- [ ] `mobile/lib/core/database/tables/chat_threads.dart` — Drift table
- [ ] `mobile/lib/core/database/tables/chat_messages.dart` — Drift table
- [ ] `mobile/lib/core/database/tables/chat_read_receipts.dart` — Drift table

---

## Sources

### Primary (HIGH confidence)
- FastAPI official docs — WebSocket support: https://fastapi.tiangolo.com/advanced/websockets/
- redis-py asyncio docs — async pub/sub API: https://redis.readthedocs.io/en/stable/examples/asyncio_examples.html
- Flutter official WebSocket cookbook: https://docs.flutter.dev/cookbook/networking/web-sockets
- Project codebase: `backend/app/core/config.py` — `redis_url` already in Settings
- Project codebase: `backend/app/features/notifications/service.py` — FCM pattern to extend
- Project codebase: `mobile/lib/core/database/tables/sync_queue.dart` — outbox pattern to reuse
- Project codebase: `.planning/STATE.md` — "WebSocket JWT re-validated server-side every 5 minutes; close with 4401 on expiry" (confirmed locked decision)

### Secondary (MEDIUM confidence)
- WebSocket.org FastAPI guide — connection manager + Redis pub/sub scaling: https://websocket.org/guides/frameworks/fastapi/
- Nanda Gopal Pattanayak (Medium) — scaling WebSockets with pub/sub: https://medium.com/@nandagopal05/scaling-websockets-with-pub-sub-using-python-redis-fastapi-b16392ffe291
- DEV Community — WebSocket authentication in FastAPI: https://dev.to/hamurda/how-i-solved-websocket-authentication-in-fastapi-and-why-depends-wasnt-enough-1b68
- Ably — WebSockets + Flutter client considerations: https://ably.com/topic/websockets-flutter

### Tertiary (LOW confidence)
- Exponential backoff pattern from community articles (verified against multiple sources, consistent): `_retrySeconds = (_retrySeconds * 2).clamp(1, 64)` pattern

---

## Metadata

**Confidence breakdown:**
- Standard stack: HIGH — packages verified via pip/npm/flutter pub; FastAPI WS confirmed at runtime
- Architecture: HIGH — patterns verified against official docs + existing codebase patterns
- Pitfalls: HIGH — drawn from existing STATE.md decisions, CLAUDE.md rules, and MEMORY.md
- Open questions: MEDIUM — need confirmation on Redis CI availability and WS token strategy

**Research date:** 2026-03-24
**Valid until:** 2026-04-24 (30 days; redis-py and web_socket_channel are stable)
