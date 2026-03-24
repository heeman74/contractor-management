---
phase: 23-real-time-chat
plan: "02"
subsystem: mobile-data-layer
tags: [drift, websocket, offline-sync, riverpod, chat]
dependency_graph:
  requires:
    - "23-01 (backend WebSocket endpoint)"
    - "Phase 22 task execution data layer (schema v10)"
  provides:
    - "Drift schema v11 with ChatThreads, ChatMessages, ChatReadReceipts"
    - "ChatDao reactive streams (watchMessages, watchThreadsByProject)"
    - "ChatWsClient with exponential backoff and heartbeat"
    - "ChatSyncService offline queue drain"
    - "ChatRepository REST bridge"
    - "Riverpod providers for chat data"
  affects:
    - "app_database.dart (schema version bump)"
    - "AI providers (ChatMessage name conflict resolved)"
tech_stack:
  added:
    - "web_socket_channel: ^3.0.3 (explicit dependency)"
  patterns:
    - "Drift insertAllOnConflictUpdate for batch operations"
    - "IOWebSocketChannel.connect with JWT query param"
    - "SyncQueue outbox for offline chat messages"
    - "StreamProvider.autoDispose.family for reactive Drift streams"
key_files:
  created:
    - mobile/lib/core/database/tables/chat_threads.dart
    - mobile/lib/core/database/tables/chat_messages.dart
    - mobile/lib/core/database/tables/chat_read_receipts.dart
    - mobile/lib/features/chat/data/chat_dao.dart
    - mobile/lib/features/chat/data/chat_ws_client.dart
    - mobile/lib/features/chat/data/chat_sync_service.dart
    - mobile/lib/features/chat/data/chat_repository.dart
    - mobile/lib/features/chat/domain/chat_providers.dart
  modified:
    - mobile/lib/core/database/app_database.dart (schema v10→v11, ChatDao registered)
    - mobile/pubspec.yaml (web_socket_channel explicit)
    - mobile/lib/features/ai/presentation/providers/intake_chat_provider.dart (hide ChatMessage)
    - mobile/lib/features/ai/presentation/providers/interview_chat_provider.dart (hide ChatMessage)
decisions:
  - "ChatMessage Drift data class conflicts with ai_models.dart ChatMessage; resolved with `hide ChatMessage` in AI provider imports (same pattern as UserRole)"
  - "BASE_WS_URL as dart-define constant defaulting to ws://localhost:8000 for dev"
  - "ChatWsClient per-thread (Provider.autoDispose.family) so WS closes when screen leaves tree"
  - "ChatSyncService uses SyncQueue outbox (entityType=chat_message) — consistent with existing offline sync pattern"
  - "batch batchInsertMessages uses insertAllOnConflictUpdate (Batch API); NOT insertOnConflictUpdate (not on Batch)"
metrics:
  duration: "1600s"
  completed: "2026-03-24"
  tasks: 2
  files: 12
---

# Phase 23 Plan 02: Mobile Chat Data Layer Summary

**One-liner:** Drift schema v11 with ChatThreads/ChatMessages/ChatReadReceipts tables, ChatDao reactive streams, IOWebSocketChannel client with 1-64s exponential backoff, SyncQueue outbox drain, REST bridge, and Riverpod StreamProvider.family providers.

## Tasks Completed

| Task | Description | Commit | Files |
|------|-------------|--------|-------|
| 1 | Drift chat tables + schema v11 | e6da0a6 | chat_threads.dart, chat_messages.dart, chat_read_receipts.dart, app_database.dart, pubspec.yaml, chat_dao.dart |
| 2 | ChatWsClient, ChatSyncService, ChatRepository, providers | 31782aa | chat_ws_client.dart, chat_sync_service.dart, chat_repository.dart, chat_providers.dart |
| Bug fix | ChatMessage name conflict in AI providers | 504240f | intake_chat_provider.dart, interview_chat_provider.dart |

## Verification

- `dart analyze lib/core/database/tables/chat_threads.dart chat_messages.dart chat_read_receipts.dart` — No issues
- `dart analyze lib/features/chat/` — No issues
- `dart run build_runner build` — 682 outputs, no errors
- `schemaVersion => 11` in app_database.dart
- `web_socket_channel: ^3.0.3` in pubspec.yaml
- `chatMessagesProvider` and `chatThreadsProvider` are StreamProvider.autoDispose.family
- `flutter test` — 794 passing, 13 pre-existing failures (unrelated to chat)

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 1 - Bug] Fixed ChatMessage Dart namespace conflict**
- **Found during:** Task 2 verification (flutter test run)
- **Issue:** Drift generates a `ChatMessage` data class from the `ChatMessages` table. This conflicts with the existing `ChatMessage` class in `ai_models.dart` which is imported by the AI chat providers.
- **Fix:** Added `hide ChatMessage` to the `app_database.dart` import in `intake_chat_provider.dart` and `interview_chat_provider.dart` — same pattern documented in MEMORY.md for `UserRole`.
- **Files modified:** mobile/lib/features/ai/presentation/providers/intake_chat_provider.dart, interview_chat_provider.dart
- **Commit:** 504240f

**2. [Rule 1 - Bug] Fixed Drift Batch API call**
- **Found during:** Task 2 dart analyze
- **Issue:** `batchInsertMessages` used `b.insertOnConflictUpdate(table, row)` but Drift's `Batch` class only exposes `insertAllOnConflictUpdate(table, rows)` for bulk upserts.
- **Fix:** Changed to `b.insertAllOnConflictUpdate(chatMessages, messages)` (single call for all rows).
- **Files modified:** mobile/lib/features/chat/data/chat_dao.dart
- **Commit:** 31782aa

## Self-Check: PASSED

All 8 key files exist on disk. All 3 commits (e6da0a6, 31782aa, 504240f) confirmed in git log.
