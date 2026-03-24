---
phase: 23-real-time-chat
plan: 03
subsystem: backend
tags: [chat, websocket, fastapi, redis, fcm, push-notifications, integration-tests, rls]
dependency_graph:
  requires:
    - backend/app/features/chat/models.py
    - backend/app/features/chat/service.py
    - backend/app/features/chat/ws_manager.py
    - backend/app/features/chat/schemas.py
    - backend/app/features/notifications/service.py
  provides:
    - backend/app/features/chat/router.py
    - backend/tests/test_chat.py
  affects:
    - backend/app/main.py
    - backend/app/features/chat/repository.py
    - backend/app/features/notifications/service.py
    - backend/tests/conftest.py
tech_stack:
  added: []
  patterns:
    - WebSocket JWT validation before accept (close 4401 on invalid)
    - JWT re-validation every 5 minutes via asyncio.get_event_loop().time()
    - Fire-and-forget FCM via asyncio.create_task()
    - Cursor pagination with before_seq and since_seq
    - RLS isolation verified via tenant_a/tenant_b cross-tenant tests
key_files:
  created:
    - backend/app/features/chat/router.py
    - backend/tests/test_chat.py
  modified:
    - backend/app/features/chat/repository.py
    - backend/app/features/chat/service.py
    - backend/app/features/notifications/service.py
    - backend/app/main.py
    - backend/tests/conftest.py
decisions:
  - "WebSocket membership check uses direct SELECT on chat_memberships (not list_threads_for_user) — avoids project_id requirement in WS context"
  - "ChatService.create_scope_thread deduplicates member list to prevent UniqueViolationError when contractor == gc user"
  - "mark_read returns 204 (response_model=None) per CLAUDE.md FastAPI DELETE 204 pattern"
  - "since_seq pagination fetches ASC directly; before_seq fetches DESC then reverses — both return ASC to caller"
  - "FCM sender_name resolves to str(user_id) in WebSocket context — full name lookup deferred (no user query in WS handler)"
metrics:
  duration: 400s
  completed: "2026-03-24"
  tasks: 2
  files: 7
---

# Phase 23 Plan 03: Chat Router, REST Endpoints, and Integration Tests Summary

WebSocket endpoint + 8 REST endpoints wiring the Plan 01 data layer into live chat, with FCM push via extended NotificationService and 15 passing integration tests covering all CHAT requirements.

## What Was Built

### Task 1: Chat Router and NotificationService Extension

**router.py** — `APIRouter(tags=["chat"])` with:

**WebSocket endpoint** `WS /ws/chat/{thread_id}?token={jwt}`:
- JWT decoded with `decode_token()` BEFORE `websocket.accept()` — close code 4401 on invalid/expired token
- Tenant context set via `set_current_tenant_id(company_id)` for RLS enforcement
- Membership verified via direct `SELECT chat_memberships WHERE thread_id AND user_id` — close 4403 if not a member
- `manager.connect(websocket, thread_id, user_id)` registers connection (starts Redis relay task per Plan 01 design)
- JWT re-validation every 5 minutes using `asyncio.get_event_loop().time()` counter (STATE.md decision)
- Message types handled: `message` (send + Redis broadcast + FCM fire-and-forget), `typing` (broadcast indicator), `read` (mark_read + broadcast receipt), `ping` (pong response)
- `asyncio.wait_for(receive_json, timeout=30)` — timeout loops back to re-validation check rather than disconnecting
- `finally` block: `manager.disconnect()` cleans up connection and relay task

**REST endpoints**:
- `GET /chat/threads?project_id=X` — list threads for current user via membership join
- `POST /chat/threads` — create scope or project_wide thread (idempotent)
- `GET /chat/threads/{id}/messages?before_seq=N&since_seq=N&limit=50` — cursor pagination
- `POST /chat/threads/{id}/messages` — REST fallback send; broadcasts to Redis; returns existing on dedup
- `POST /chat/threads/{id}/read` — mark read (204)
- `GET /chat/threads/{id}/receipts` — all read positions for "seen by" display
- `POST /chat/messages/{id}/attachment` — save file to `uploads/chat/{message_id}/`, update `attachment_url`
- `PUT /chat/threads/{id}/mute` — toggle muted on membership (204)

**ChatMessageRepository** — added `since_seq` parameter to `list_by_thread()`:
- `before_seq`: fetch DESC + reverse (history load)
- `since_seq`: fetch ASC directly (reconnect catch-up)
- No cursor: fetch DESC + reverse (initial load)

**NotificationService.send_chat_notification**:
- D-14 FCM body: `"{sender_name} ({trade_scope_name}): {message_preview[:100]}"`
- @mention override: muted users receive FCM if `mention_all=True` or their UUID is in `mentioned_user_ids`
- Per-token error handling: UnregisteredError deletes stale token, all other errors logged and swallowed
- Fire-and-forget pattern matches existing job notification design

**main.py** additions:
- `from app.features.chat.router import router as chat_router`
- `app.include_router(chat_router, prefix="/api/v1")` (Phase 23 comment)
- `uploads/chat/` directory created at startup
- `app.mount("/uploads/chat", StaticFiles(directory=...), name="chat-uploads")`

### Task 2: Integration Tests (15 tests, all passing)

**test_chat.py** covers:

| Test | Requirement |
|------|-------------|
| test_create_scope_thread | Thread 201, thread_type='scope', trade_scope_id set |
| test_create_project_wide_thread | Thread 201, thread_type='project_wide', trade_scope_id null |
| test_list_threads_for_project | GET ?project_id returns both threads with correct types |
| test_gc_sends_message | CHAT-01: 201, seq assigned (int > 0), sender_id matches |
| test_message_dedup_by_uuid | ON CONFLICT DO NOTHING — same seq for duplicate UUID |
| test_cursor_pagination | CHAT-02: before_seq returns correct page in ASC order |
| test_since_seq_pagination | CHAT-02: since_seq returns newer messages in ASC order |
| test_mark_read_upsert | seq regression prevented (upsert WHERE guard works) |
| test_get_read_receipts | Receipts returned per user with correct last_read_seq |
| test_chat_file_attachment | CHAT-03: attachment_url set, path contains message_id |
| test_thread_auto_create_idempotent | CHAT-04: same thread.id returned on second create |
| test_toggle_mute | Mute ON/OFF both return 204 |
| test_rls_isolation | Tenant B gets 200+empty or 403/404 for Tenant A's thread |
| test_mentions_stored | CHAT-05: mentions list persisted in DB |
| test_mention_all_stored | mention_all=true persisted |

**conftest.py** — chat tables added to `clean_tables` TRUNCATE in correct FK order:
`chat_read_receipts → chat_messages → chat_memberships → chat_threads`

## Decisions Made

1. **WS membership check via direct SELECT** — `list_threads_for_user` requires `project_id` which is not available in the WS URL (only `thread_id` is). Direct SELECT on `chat_memberships` is simpler and more efficient for this auth check.

2. **Member deduplication in create_scope_thread** — When contractor == gc_user (common in test scenarios or single-person setups), the service was inserting the same user twice causing a UniqueConstraint violation. Added a `seen` set to deduplicate before inserting memberships. [Rule 1 - Bug Fix]

3. **204 endpoints use response_model=None** — FastAPI assertion requires `response_model=None` on 204 routes (per existing CLAUDE.md pattern from Phase 19 P03).

4. **since_seq uses ASC order directly** — `before_seq` fetches DESC + reverses because we want the N most recent messages before a cursor. `since_seq` (catch-up) fetches ASC directly since we want all messages after the cursor up to limit.

5. **FCM sender_name = str(user_id) in WS** — Resolving display names would require a DB query per message in the WebSocket handler. Deferred to a future plan where a user cache can be populated at connect time.

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 1 - Bug] Fixed UniqueViolationError in create_scope_thread when contractor == gc user**
- **Found during:** Task 2 test run
- **Issue:** `create_scope_thread` added `[gc_user_id, contractor_id]` without deduplication. When both are the same UUID (common in test setup), PostgreSQL raised `UniqueViolationError` on `uq_chat_memberships_thread_user`.
- **Fix:** Added `seen: set[uuid.UUID]` guard before adding memberships to `self.db.add()`.
- **Files modified:** `backend/app/features/chat/service.py`
- **Commit:** 8d05a9e

**2. [Rule 2 - Missing Critical Functionality] Added since_seq to ChatMessageRepository**
- **Found during:** Task 1 implementation (plan specified since_seq param for reconnect catch-up)
- **Issue:** Plan 01's `list_by_thread` only had `before_seq`. The router needs `since_seq` for reconnect catch-up messages.
- **Fix:** Added `since_seq: int | None = None` parameter with separate ASC query path.
- **Files modified:** `backend/app/features/chat/repository.py`
- **Commit:** a4c5794

## Self-Check: PASSED

- [x] `backend/app/features/chat/router.py` exists and has `@router.websocket("/ws/chat/{thread_id}")`
- [x] WebSocket validates JWT before accept (close 4401 on invalid)
- [x] Re-validates JWT every 300 seconds (5 minutes)
- [x] REST endpoints: GET /chat/threads, GET+POST /chat/threads/{id}/messages, POST /chat/threads/{id}/read, GET /chat/threads/{id}/receipts, POST /chat/messages/{id}/attachment, PUT /chat/threads/{id}/mute
- [x] Messages endpoint supports both `before_seq` and `since_seq` params
- [x] `NotificationService.send_chat_notification` exists with @mention override logic
- [x] Chat router included in `main.py` with prefix `/api/v1`
- [x] `uploads/chat` static mount added
- [x] `backend/tests/test_chat.py` has 15 test functions (> 12 required)
- [x] All 15 tests pass: `pytest tests/test_chat.py -x` green
- [x] Tests use JWT Bearer token auth (not X-Company-Id headers)
- [x] Chat tables added to `clean_tables` conftest fixture
- [x] Commit a4c5794 (Task 1: router + notifications + main.py)
- [x] Commit 8d05a9e (Task 2: integration tests + service dedup fix)
