---
phase: 02-offline-sync-engine
plan: "03"
subsystem: flutter-sync-engine
tags: [sync-engine, connectivity, drift, registry-pattern, exponential-backoff, offline-first, idempotency]
dependency_graph:
  requires: [02-01, 02-02]
  provides: [sync-engine, sync-registry, connectivity-service, sync-handlers, dio-retry]
  affects: [sync_queue, sync_cursor, companies, users, user_roles, service_locator, dio_client]
tech_stack:
  added:
    - connectivity_plus: ^7.0.0 (connectivity stream, v7 returns List<ConnectivityResult>)
    - internet_connection_checker_plus: ^2.9.1 (verifies real internet vs captive portal)
    - dio_smart_retry: ^7.0.1 (RetryInterceptor for exponential backoff)
    - workmanager: ^0.9.0 (dependency added for Plan 04 to avoid pubspec conflicts)
  patterns:
    - Registry pattern (SyncRegistry) for zero-refactor entity type addition
    - _isSyncing guard for re-entrant drain prevention
    - Exponential backoff 1/2/4/8/16s with max 5 attempts then reset to 0
    - Drift insertOnConflictUpdate for idempotent pull-side upserts
    - broadcast StreamController for SyncStatus UI updates
    - Two-phase connectivity check: interface detection then hasInternetAccess
key_files:
  created:
    - mobile/lib/core/sync/sync_handler.dart
    - mobile/lib/core/sync/sync_registry.dart
    - mobile/lib/core/sync/sync_engine.dart
    - mobile/lib/core/sync/connectivity_service.dart
    - mobile/lib/core/sync/handlers/company_sync_handler.dart
    - mobile/lib/core/sync/handlers/user_sync_handler.dart
    - mobile/lib/core/sync/handlers/user_role_sync_handler.dart
    - mobile/android/app/src/main/AndroidManifest.xml
  modified:
    - mobile/lib/core/network/dio_client.dart
    - mobile/lib/core/di/service_locator.dart
    - mobile/pubspec.yaml
decisions:
  - "connectivity_plus v7 returns List<ConnectivityResult> — checked with .any((r) => r != ConnectivityResult.none)"
  - "Two-phase connectivity check: interface up AND hasInternetAccess — avoids captive portal false positives"
  - "After max retries (5), resetAttemptCount=0 and leave as pending — retry on next connectivity cycle (not abandoned)"
  - "pullDelta catches DioException silently — cursor not advanced on failure, next pull covers same range"
  - "Unexpected handler errors (StateError for unregistered type) park the item to prevent infinite loop"
metrics:
  duration: "5 min"
  completed_date: "2026-03-05"
  tasks_completed: 2
  files_created: 8
  files_modified: 3
---

# Phase 02 Plan 03: Core Sync Engine Service Layer Summary

**One-liner:** SyncEngine with FIFO queue drain (4xx park / 5xx exponential backoff), cursor-based delta pull, registry-pattern handler routing, and ConnectivityService with real internet verification using connectivity_plus v7 + internet_connection_checker_plus.

## What Was Built

### Task 1: SyncHandler, SyncRegistry, ConnectivityService, DioClient + pubspec (commit: d870c57)

Created `mobile/lib/core/sync/sync_handler.dart`:
- Abstract `SyncHandler` class with `entityType`, `push(SyncQueueData)`, and `applyPulled(Map<String, dynamic>)` interface
- Defines the contract that all entity-specific handlers implement

Created `mobile/lib/core/sync/sync_registry.dart`:
- `SyncRegistry` with `register(handler)`, `getHandler(entityType)`, and `registeredTypes`
- `getHandler` throws `StateError` for unregistered types — programming error detection
- `registeredTypes` is unmodifiable list for safe enumeration

Created `mobile/lib/core/sync/connectivity_service.dart`:
- Wraps `connectivity_plus` v7 (`List<ConnectivityResult>` stream — not single value)
- On non-none result: verifies actual internet via `InternetConnection().hasInternetAccess`
- Exposes `startListening(VoidCallback onConnected)` and `isOnlineStream` for UI
- Avoids false positives from captive portals and broken routers

Created three entity handlers:
- `company_sync_handler.dart`: POST `/companies` with Idempotency-Key, upserts via `CompaniesCompanion`
- `user_sync_handler.dart`: POST `/users` with Idempotency-Key, upserts via `UsersCompanion`
- `user_role_sync_handler.dart`: POST `/users/{userId}/roles` with Idempotency-Key, upserts via `UserRolesCompanion`
- All handlers handle tombstones: non-null `deleted_at` in response propagates locally

Updated `mobile/lib/core/network/dio_client.dart`:
- Added `RetryInterceptor` (BEFORE `LogInterceptor` so retries are logged)
- `retries: 5`, `retryDelays: [1s, 2s, 4s, 8s, 16s]`, evaluator: false for 4xx, true for 5xx/timeout
- Added `pushWithIdempotency(path, data, idempotencyKey)` method for outbox push

Added to `mobile/pubspec.yaml`:
- `connectivity_plus: ^7.0.0`, `internet_connection_checker_plus: ^2.9.1`, `dio_smart_retry: ^7.0.1`, `workmanager: ^0.9.0`

Created `mobile/android/app/src/main/AndroidManifest.xml`:
- `INTERNET` and `ACCESS_NETWORK_STATE` permissions

### Task 2: SyncEngine + Service Locator Registration (commit: bfe7d6e)

Created `mobile/lib/core/sync/sync_engine.dart`:

**`SyncStatus` / `SyncState`:**
- `enum SyncState { offline, allSynced, pending, syncing }`
- `SyncStatus(state, pendingCount, {syncingOf})` with `subtitle` switch expression
- Subtitles: `'Offline'`, `'All synced'`, `'N item(s) pending'`, `'Syncing M of N...'`

**`drainQueue()`:**
- `_isSyncing` guard prevents re-entrant concurrent drain
- FIFO order via `SyncQueueDao.getPendingItems()` (`createdAt` ASC)
- Per-item: `handler.push(item)` → `markSynced(id)` on success
- 4xx catch: `markParked(id, error:)` — permanent, no retry
- 5xx/timeout catch: increment `attemptCount`, apply `_backoffDelays[newCount-1]`
- At max attempts (5): reset `attemptCount = 0`, leave as pending for next cycle
- Unexpected errors: park item to prevent infinite loop
- Emits `SyncStatus.syncing` per-item progress and final `allSynced`/`pending` state

**`pullDelta()`:**
- Reads cursor from `SyncCursorDao.getCursor()` (null = first launch, omits param)
- GET `/api/v1/sync?cursor=<isoTimestamp>` via `DioClient.instance`
- Applies companies, users, user_roles via registry handlers
- Updates cursor with `server_timestamp` from response
- DioException caught silently — cursor not advanced, next pull covers same range

**`initialize()`:** Wires `ConnectivityService` → `_onConnectivityRestored` (drain + pull)

**`syncNow()`:** Public drain+pull for pull-to-refresh and foreground triggers

Updated `mobile/lib/core/di/service_locator.dart`:
- Registers `ConnectivityService`, `SyncRegistry` (+3 handlers), `SyncEngine` singletons
- Calls `syncEngine.initialize()` after registration to start connectivity listening

## Decisions Made

| Decision | Rationale |
|----------|-----------|
| `connectivity_plus` v7 returns `List<ConnectivityResult>` | Breaking change in v7 — `.any((r) => r != ConnectivityResult.none)` for non-none check |
| Two-phase connectivity check (interface + `hasInternetAccess`) | Captive portals report connected but HTTP fails — verify before triggering sync |
| Reset `attemptCount = 0` after max retries (not abandon/park) | Abandoned items accumulate; reset lets next connectivity cycle retry them |
| Park on unexpected `StateError` | Unregistered entity type in queue is unrecoverable in current session; park prevents infinite loop |
| `pullDelta` swallows `DioException` silently | Cursor not advanced on failure — next call covers same range; crash would block all future syncs |

## Deviations from Plan

None — plan executed exactly as written.

## Self-Check

Files created:
- [x] `mobile/lib/core/sync/sync_handler.dart`
- [x] `mobile/lib/core/sync/sync_registry.dart`
- [x] `mobile/lib/core/sync/sync_engine.dart`
- [x] `mobile/lib/core/sync/connectivity_service.dart`
- [x] `mobile/lib/core/sync/handlers/company_sync_handler.dart`
- [x] `mobile/lib/core/sync/handlers/user_sync_handler.dart`
- [x] `mobile/lib/core/sync/handlers/user_role_sync_handler.dart`
- [x] `mobile/android/app/src/main/AndroidManifest.xml`

Files modified:
- [x] `mobile/lib/core/network/dio_client.dart`
- [x] `mobile/lib/core/di/service_locator.dart`
- [x] `mobile/pubspec.yaml`

Commits:
- [x] d870c57 — Task 1: SyncHandler, SyncRegistry, handlers, ConnectivityService, DioClient, pubspec
- [x] bfe7d6e — Task 2: SyncEngine, service locator registration

## Self-Check: PASSED
