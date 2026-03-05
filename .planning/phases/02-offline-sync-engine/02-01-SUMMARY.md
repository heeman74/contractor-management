---
phase: 02-offline-sync-engine
plan: 01
subsystem: database
tags: [drift, sqlite, sync-queue, offline-first, outbox-pattern, soft-delete]

# Dependency graph
requires:
  - phase: 01-foundation
    provides: "Drift AppDatabase with Companies/Users/UserRoles tables and UUID PKs"

provides:
  - "SyncQueue Drift table (transactional outbox with UUID idempotency key)"
  - "SyncCursor Drift table (delta sync high-water mark with first-launch detection)"
  - "deleted_at soft-delete column on Companies, Users, UserRoles"
  - "AppDatabase schema v2 with from1To2 migration"
  - "SyncQueueDao: getPendingItems (FIFO), markSynced, markParked, updateAttemptCount, watchPendingCount, insertQueueItem"
  - "SyncCursorDao: getCursor (null on first launch), updateCursor"
  - "CompanyDao: transactional outbox dual-write for insert/update/delete; soft-delete on deleteCompany"
  - "UserDao: transactional outbox dual-write for insertUser and assignRole"

affects:
  - 02-offline-sync-engine
  - 02-02-PLAN (SyncEngine drain queue, delta sync endpoint)
  - 02-03-PLAN (SyncEngine trigger on write)
  - 02-04-PLAN (background sync, WorkManager)
  - 02-05-PLAN (sync status UI — watchPendingCount stream)

# Tech tracking
tech-stack:
  added: []
  patterns:
    - "Transactional outbox: every local mutation writes to entity table + sync_queue in single db.transaction()"
    - "Soft delete: deleteCompany/deleteUser sets deleted_at instead of hard delete for tombstone propagation"
    - "Single-row table pattern: SyncCursor uses key='main' with nullable lastPulledAt for first-launch detection"
    - "FIFO queue: getPendingItems orders by createdAt ASC to preserve causality (CREATE before UPDATE)"
    - "Manual payload serialization: _companyPayload/_userPayload build JSON-safe maps instead of toColumns()"

key-files:
  created:
    - mobile/lib/core/database/tables/sync_queue.dart
    - mobile/lib/core/database/tables/sync_cursor.dart
    - mobile/lib/core/sync/sync_queue_dao.dart
    - mobile/lib/core/sync/sync_cursor_dao.dart
  modified:
    - mobile/lib/core/database/tables/companies.dart
    - mobile/lib/core/database/tables/users.dart
    - mobile/lib/core/database/tables/user_roles.dart
    - mobile/lib/core/database/app_database.dart
    - mobile/lib/features/company/data/company_dao.dart
    - mobile/lib/features/users/data/user_dao.dart

key-decisions:
  - "Payload serialization: manually build Map<String, dynamic> from Companion fields instead of toColumns(false) — toColumns() returns Map<String, Expression> which is not JSON-serializable"
  - "markSynced deletes the row instead of updating status to 'synced' — entity table is source of truth; keeping synced rows grows queue unnecessarily"
  - "SyncCursorDao.updateCursor uses insertOnConflictUpdate — handles both first-time insert and subsequent updates cleanly"
  - "watchPendingCount implemented as select().watch().map(rows.length) — Drift doesn't expose count() as stream natively"
  - "deleteCompany now performs soft delete (sets deletedAt) not hard delete — required for tombstone propagation; deleteCompany behavior change from Phase 1"

patterns-established:
  - "Transactional outbox pattern: db.transaction() wrapping entity write + sync_queue insert in every mutating DAO method"
  - "Soft-delete filter: all read queries (watchAllCompanies, watchUsersByCompany) add .where((tbl) => tbl.deletedAt.isNull())"
  - "_buildQueueEntry helper: consistent SyncQueueCompanion construction across all DAOs"

requirements-completed: [INFRA-03]

# Metrics
duration: 5min
completed: 2026-03-05
---

# Phase 2 Plan 01: Offline Sync Engine Foundation Summary

**Drift transactional outbox with sync_queue/sync_cursor tables, schema v2 migration, and atomic dual-write wiring in CompanyDao and UserDao so every local mutation enqueues to sync_queue in a single SQLite transaction**

## Performance

- **Duration:** ~5 min
- **Started:** 2026-03-05T21:50:42Z
- **Completed:** 2026-03-05T21:55:00Z
- **Tasks:** 3
- **Files modified:** 10

## Accomplishments

- SyncQueue Drift table (9 columns: id as UUID idempotency key, entityType, entityId, operation, payload, status='pending', attemptCount=0, errorMessage nullable, createdAt) enabling the transactional outbox pattern
- SyncCursor Drift table (single-row pattern with nullable lastPulledAt) enabling null-as-first-launch detection for delta vs. full sync
- AppDatabase upgraded to schema v2 with from1To2 migration creating new tables and adding deleted_at to all entity tables
- CompanyDao and UserDao mutating methods wrapped in db.transaction() for atomic entity + sync_queue dual-write — every local mutation now populates sync_queue regardless of connectivity

## Task Commits

Each task was committed atomically:

1. **Task 1: Create sync_queue and sync_cursor Drift tables with deleted_at on existing tables** - `08879ba` (feat)
2. **Task 2: Create SyncQueueDao, SyncCursorDao, and update AppDatabase to schema v2** - `6fb3f3f` (feat)
3. **Task 3: Wire transactional outbox writes into CompanyDao and UserDao** - `25337a0` (feat — included in prior commit with 02-02 backend work)

## Files Created/Modified

- `mobile/lib/core/database/tables/sync_queue.dart` — SyncQueue Drift table: 9-column outbox with UUID idempotency key
- `mobile/lib/core/database/tables/sync_cursor.dart` — SyncCursor Drift table: single-row delta sync high-water mark
- `mobile/lib/core/database/tables/companies.dart` — Added nullable deletedAt column
- `mobile/lib/core/database/tables/users.dart` — Added nullable deletedAt column
- `mobile/lib/core/database/tables/user_roles.dart` — Added nullable deletedAt column
- `mobile/lib/core/database/app_database.dart` — Schema v2, SyncQueue/SyncCursor in tables/daos, from1To2 migration
- `mobile/lib/core/sync/sync_queue_dao.dart` — SyncQueueDao: FIFO getPendingItems, markSynced, markParked, updateAttemptCount, watchPendingCount stream, insertQueueItem
- `mobile/lib/core/sync/sync_cursor_dao.dart` — SyncCursorDao: getCursor (null on first launch), updateCursor (upsert)
- `mobile/lib/features/company/data/company_dao.dart` — Transactional outbox dual-writes; soft-delete for deleteCompany; deletedAt.isNull() filter on watchAllCompanies
- `mobile/lib/features/users/data/user_dao.dart` — Transactional outbox dual-writes for insertUser/assignRole; deletedAt.isNull() filter on watchUsersByCompany

## Decisions Made

- **Payload serialization approach:** Used manually-built `Map<String, dynamic>` per entity (e.g., `_companyPayload()`) rather than `entry.toColumns(false)`. The Drift Companion `toColumns()` returns `Map<String, Expression>` which cannot be JSON-encoded. Manual maps are also more explicit and stable across schema changes.

- **markSynced deletes the row:** After successful sync, the row is deleted rather than marked 'synced'. The entity table is the source of truth — keeping synced rows would grow the queue indefinitely with no benefit.

- **SyncCursorDao.updateCursor uses insertOnConflictUpdate:** This handles both first-time insert (no 'main' row exists) and all subsequent updates with a single upsert call, eliminating the need for a read-then-write pattern.

- **deleteCompany is now soft delete:** Changed from hard delete (`delete(companies)..where(...)`) to soft delete (`update(companies)..write(CompaniesCompanion(deletedAt: Value(DateTime.now())))`). This is a behavioral change from Phase 1 required for tombstone propagation across devices.

## Deviations from Plan

None — plan executed exactly as written. The `_enqueueSync` helper was renamed to `_buildQueueEntry` for clarity but is functionally identical to the plan specification.

## Issues Encountered

- Task 3 files (company_dao.dart, user_dao.dart) had already been committed in a prior session as part of commit `25337a0` (labeled `feat(02-02)`). The write operation produced identical output, so git reported "nothing to commit." This is correct — the content matched the plan exactly.

## User Setup Required

None — no external service configuration required. Schema migration runs automatically on next app launch via Drift's `MigrationStrategy`.

## Next Phase Readiness

- SyncQueueDao.getPendingItems() and SyncCursorDao.getCursor() are ready for SyncEngine to consume (Plan 02-02 and 02-03)
- watchPendingCount() stream is ready for sync status UI provider (Plan 02-05)
- Schema v2 is deployed — Plan 02-02 backend delta sync endpoint can now assume deleted_at on all entity tables
- Concern: build_runner (Drift codegen) has not been run — .g.dart files will need regeneration when Flutter SDK is available. This is a pre-existing blocker noted in STATE.md.

---
*Phase: 02-offline-sync-engine*
*Completed: 2026-03-05*
