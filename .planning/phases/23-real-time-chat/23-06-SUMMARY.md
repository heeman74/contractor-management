---
phase: 23-real-time-chat
plan: "06"
subsystem: testing
tags: [e2e, backend, flutter, chat, pytest, riverpod, drift]
dependency_graph:
  requires: ["23-03", "23-04"]
  provides: ["CHAT-01-tests", "CHAT-02-tests", "CHAT-03-tests", "CHAT-04-tests", "CHAT-05-tests"]
  affects: []
tech_stack:
  added: []
  patterns:
    - "_NoOpWsClient/ChatRepository stubs prevent GetIt lookups in widget tests"
    - "_threadScreenBaseOverrides() helper eliminates ChatThreadScreen test boilerplate"
    - "tester.runAsync() escapes FakeAsync for Drift one-shot select queries"
    - "pump(600ms) flushes ChatInputBar 500ms typing debounce timer"
key_files:
  created:
    - backend/tests/test_phase_23_e2e.py
    - mobile/test/e2e/phase_23_real_time_chat_e2e_test.dart
  modified:
    - backend/app/core/config.py (extra="ignore" for ANTHROPIC_API_KEY)
    - backend/app/main.py (chat router + uploads)
    - backend/tests/conftest.py (chat table truncation)
    - backend/app/features/chat/ (copied from agent-a607cbde worktree)
    - backend/migrations/versions/0020_chat.py (copied migration)
    - backend/app/features/notifications/service.py (send_chat_notification)
decisions:
  - "Used _NoOpChatRepository stub to prevent GetIt/DioClient lookups in ChatScreen tests — chatRepositoryProvider is read in initState post-frame callback"
  - "Replaced watchMessages().first with tester.runAsync + DAO select query to avoid FakeAsync hang in offline queue test"
  - "Used pump(600ms) to flush ChatInputBar's 500ms typing debounce Timer — without this pump, testWidgets hangs on test teardown"
metrics:
  duration_minutes: 540
  tasks_completed: 2
  files_created: 2
  files_modified: 7
  completed_date: "2026-03-24"
---

# Phase 23 Plan 06: E2E Tests for Real-Time Chat Summary

**One-liner:** 19 backend pytest E2E tests + 23 Flutter widget E2E tests covering all CHAT-01 through CHAT-05 requirements with stub infrastructure to prevent GetIt/network calls.

## Tasks Completed

| # | Task | Commit | Files |
|---|------|--------|-------|
| 1 | Backend Phase 23 E2E integration tests | 0639f32 | backend/tests/test_phase_23_e2e.py |
| 2 | Flutter Phase 23 E2E widget tests | 55bf0d4 | mobile/test/e2e/phase_23_real_time_chat_e2e_test.dart |

## What Was Built

### Task 1: Backend E2E Tests (19 tests)

`backend/tests/test_phase_23_e2e.py` — 19 integration tests across 6 test classes:

- **TestChat01GCSendsMessage** (3 tests): text message send, history order, @mention field storage
- **TestChat02ConversationFlow** (3 tests): contractor reply, seq increment, message dedup ON CONFLICT DO NOTHING
- **TestChat03FileSharing** (3 tests): photo upload with attachment_url, PDF attachment_type, annotated_photo annotation_data
- **TestChat04ThreadOrganization** (4 tests): scope thread creation, project_wide thread, cross-project isolation, idempotent creation
- **TestChat05PushNotifications** (3 tests): FCM wiring via send_chat_notification, mention override of mute, muted user skips notification
- **TestChatReadReceiptsAndPagination** (3 tests): read flow, cursor pagination (before_seq), RLS cross-tenant isolation

Helper functions: `_create_project`, `_create_trade_scope`, `_create_scope_thread`, `_create_project_wide_thread`, `_send_message`.

All 19 tests pass against `contractorhub_test` database with Alembic migrations applied.

### Task 2: Flutter E2E Tests (23 tests)

`mobile/test/e2e/phase_23_real_time_chat_e2e_test.dart` — 23 widget tests:

- **CHAT-01 Thread list** (4 tests): shows thread list, unread badge, hidden badge when read, send button visible
- **CHAT-02 Conversation flow** (3 tests): incoming message appears, seq ordering, dedup on echo
- **CHAT-03 File sharing** (4 tests): photo bubble, PDF bubble, annotated-photo chip, attachment picker
- **CHAT-04 Thread organisation** (3 tests): section headers, empty state, sort unread-first
- **CHAT-05 Offline + sync queue** (2 tests): clock icon on pending message, sync queue DAO insert
- **Typing indicator** (2 tests): renders without error, hidden initially
- **Read receipts** (2 tests): done_all icon, single check icon
- **Mute bottom sheet** (1 test): long-press shows "Mute Conversation"
- **ChatThreadTile** (2 tests): renders name + badge, no badge when zero unread

All 23 tests pass with `flutter test --concurrency=1`.

## Infrastructure Required

The main project `backend/` was missing the Phase 23 chat feature (parallel agents committed only docs to master). Required:

1. Copied `backend/app/features/chat/` from `worktree-agent-a607cbde`
2. Copied `backend/migrations/versions/0020_chat.py` for Alembic
3. Copied `backend/app/features/notifications/service.py` (with `send_chat_notification`)
4. Updated `backend/app/main.py` to register chat router + static file mounts
5. Updated `backend/tests/conftest.py` with chat table TRUNCATE entries
6. Added `extra="ignore"` to `Settings.model_config` to handle ANTHROPIC_API_KEY in .env

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 2 - Missing critical setup] Backend missing chat feature entirely**
- **Found during:** Task 1 setup
- **Issue:** Master branch only received planning commits from parallel worktrees — chat feature code was in worktrees not merged
- **Fix:** Copied chat feature files and migration from agent-a607cbde worktree; updated main.py and conftest.py
- **Files modified:** backend/app/features/chat/*, backend/migrations/versions/0020_chat.py, backend/app/main.py, backend/tests/conftest.py, backend/app/features/notifications/service.py
- **Commit:** included in Task 1 commit

**2. [Rule 1 - Bug] Settings validation error for ANTHROPIC_API_KEY**
- **Found during:** Task 1 (test run)
- **Issue:** `.env` file has ANTHROPIC_API_KEY but Pydantic Settings didn't have `extra="ignore"`, causing ValidationError
- **Fix:** Added `"extra": "ignore"` to `Settings.model_config` in `backend/app/core/config.py`
- **Files modified:** backend/app/core/config.py
- **Commit:** included in Task 1 commit

**3. [Rule 1 - Bug] ForeignKeyViolation in project_wide thread test**
- **Found during:** Task 1 (test run)
- **Issue:** Test passed random UUID as contractor member — not in users table
- **Fix:** Changed to use only registered gc_user_id as member
- **Files modified:** backend/tests/test_phase_23_e2e.py
- **Commit:** included in Task 1 commit

**4. [Rule 1 - Bug] chatDaoProvider/chatRepositoryProvider GetIt lookups in widget tests**
- **Found during:** Task 2
- **Issue:** `ChatScreen.initState` reads `chatRepositoryProvider` in post-frame callback; `ChatThreadScreen` reads `chatDaoProvider` for `getLastSeq`. Neither are overridden in basic tests, causing GetIt errors.
- **Fix:** Created `_NoOpChatRepository` stub and `_threadScreenBaseOverrides()` helper; added overrides to all `ChatScreen` and `ChatThreadScreen` tests
- **Files modified:** mobile/test/e2e/phase_23_real_time_chat_e2e_test.dart
- **Commit:** 55bf0d4

**5. [Rule 1 - Bug] ChatThreadScreen hangs due to _NoOpWsClient.connect() creating real WebSocket**
- **Found during:** Task 2
- **Issue:** `_NoOpWsClient` inherited `ChatWsClient.connect()` which attempted real TCP connection to `ws://localhost:9999`, triggering exponential backoff timers
- **Fix:** Overrode `connect()`, `send()`, `sendTyping()`, `sendRead()`, `dispose()` to no-ops
- **Files modified:** mobile/test/e2e/phase_23_real_time_chat_e2e_test.dart
- **Commit:** 55bf0d4

**6. [Rule 1 - Bug] test_offline_message_queued_in_sync_queue timeout (10min)**
- **Found during:** Task 2
- **Issue:** `await dao.watchMessages(_thread1Id).first` inside `testWidgets` FakeAsync context never resolved — Drift watch stream requires real event loop
- **Fix:** Used `tester.runAsync(() => (dao.select(dao.chatMessages)..where(...)).get())` instead of watch query
- **Files modified:** mobile/test/e2e/phase_23_real_time_chat_e2e_test.dart
- **Commit:** 55bf0d4

**7. [Rule 1 - Bug] ChatInputBar typing debounce causes test hang**
- **Found during:** Task 2
- **Issue:** After `tester.enterText(...)`, ChatInputBar creates a 500ms Timer. Test ending with a pending timer causes `testWidgets` to hang on teardown.
- **Fix:** Added `await tester.pump(const Duration(milliseconds: 600))` after text entry to flush the debounce timer
- **Files modified:** mobile/test/e2e/phase_23_real_time_chat_e2e_test.dart
- **Commit:** 55bf0d4

## Self-Check: PASSED

Files exist:
- `/Users/heechung/AndroidStudioProjects/contractormanagement/.claude/worktrees/agent-a6e076e5/backend/tests/test_phase_23_e2e.py` - FOUND
- `/Users/heechung/AndroidStudioProjects/contractormanagement/.claude/worktrees/agent-a6e076e5/mobile/test/e2e/phase_23_real_time_chat_e2e_test.dart` - FOUND

Commits exist:
- `0639f32` (test_phase_23_e2e.py) - FOUND
- `55bf0d4` (phase_23_real_time_chat_e2e_test.dart) - FOUND
