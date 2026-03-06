---
phase: 02-offline-sync-engine
plan: "07"
subsystem: backend-migrations, mobile-sync
tags: [bug-fix, gap-closure, alembic, migration, dart, sync-engine, riverpod]

dependency_graph:
  requires:
    - phase: 02-offline-sync-engine
      provides: "migration 0002 (updated_at column added to user_roles); sync engine drainQueue and statusStream infrastructure"
  provides:
    - "Migration 0003 backfilling user_roles.updated_at = created_at for NULL rows, enforcing NOT NULL"
    - "Sync status subtitle correctly shows Syncing N of N... before All synced on connectivity restore"
  affects: [uat-tests-1-7, sync-full-download, sync-status-ui]

tech_stack:
  added: []
  patterns:
    - "Alembic data migration: execute raw SQL UPDATE before alter_column to safely enforce NOT NULL on existing data"
    - "Dart async* generator: omit default yield on connectivity restore — let downstream emitter own its own state sequence"
    - "Flutter frame yield: Future<void>.delayed(Duration.zero) after status emit ensures at least one rendered frame before fast operations complete"

key_files:
  created:
    - path: backend/migrations/versions/0003_backfill_user_roles_updated_at.py
      change: "Alembic migration 0003 — UPDATE backfill then nullable=False on user_roles.updated_at"
  modified:
    - path: backend/app/features/users/models.py
      change: "UserRole.updated_at: Mapped[datetime | None] nullable=True -> Mapped[datetime] nullable=False"
    - path: mobile/lib/core/sync/sync_status_provider.dart
      change: "Remove premature allSynced yield on connectivity restore; remove now-unused lastEngineStatus variable"
    - path: mobile/lib/core/sync/sync_engine.dart
      change: "Add Future<void>.delayed(Duration.zero) after initial syncing emit in drainQueue()"

key-decisions:
  - "Backfill via new migration 0003 (not amending 0002) — keeps migration history clean and auditable"
  - "Remove lastEngineStatus variable entirely after removing the premature yield — no longer needed, kept code lean"

patterns-established:
  - "Alembic NOT NULL migration: always UPDATE to fill NULLs in same transaction before alter_column to avoid constraint violation on existing data"
  - "Async generator streams: never yield a default on connectivity restore if a downstream source owns that state emission"

requirements-completed: [INFRA-03, INFRA-04]

duration: 3min
completed: "2026-03-06"
---

# Phase 2 Plan 07: UAT Gap Fixes — user_roles Backfill + Sync Status Race Summary

**Alembic migration 0003 backfills user_roles.updated_at from NULL to created_at (fixing empty sync response), and two surgical Dart changes eliminate the race condition that prevented "Syncing..." from ever being visible in the UI.**

## Performance

- **Duration:** 3 min
- **Started:** 2026-03-06T03:43:33Z
- **Completed:** 2026-03-06T03:46:43Z
- **Tasks:** 2
- **Files modified:** 4

## Accomplishments

- Migration 0003 backfills all user_roles rows where updated_at IS NULL (set to created_at), then enforces NOT NULL — after `alembic upgrade head`, GET /api/v1/sync?cursor= returns populated user_roles array (UAT Test 1 resolved)
- Removed premature allSynced yield in sync_status_provider.dart connectivity-restore branch — engine now drives the syncing -> allSynced transition without interference
- Added `Future<void>.delayed(Duration.zero)` event-loop yield in sync_engine.dart drainQueue() — guarantees at least one Flutter frame renders "Syncing 1 of 1..." before fast sync completes (UAT Test 7 resolved)

## Task Commits

Each task was committed atomically:

1. **Task 1: Backfill user_roles.updated_at and tighten nullable constraint** - `4f78ee7` (feat)
2. **Task 2: Fix sync status provider premature allSynced and engine frame yield** - `993d60c` (fix)

**Plan metadata:** (docs commit — see below)

## Files Created/Modified

- `backend/migrations/versions/0003_backfill_user_roles_updated_at.py` - Alembic migration 0003: UPDATE backfill + nullable=False on user_roles.updated_at; revision chain 0002 -> 0003
- `backend/app/features/users/models.py` - UserRole.updated_at changed from `Mapped[datetime | None]` / `nullable=True` to `Mapped[datetime]` / `nullable=False`, consistent with User and Company models
- `mobile/lib/core/sync/sync_status_provider.dart` - Removed premature `yield lastEngineStatus ?? const SyncStatus(SyncState.allSynced, 0)` in connectivity-restore else branch; removed unused `lastEngineStatus` variable
- `mobile/lib/core/sync/sync_engine.dart` - Added `await Future<void>.delayed(Duration.zero)` between initial syncing emit and item processing for-loop in drainQueue()

## Decisions Made

- Backfill via new migration 0003 rather than amending migration 0002 — preserves migration history auditability; the 0002 migration's ADD COLUMN was correct, the gap was data-level not schema-level
- Removed `lastEngineStatus` variable entirely after removing the premature yield — the variable was only used for that yield and keeping it would be dead code

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 1 - Bug] Removed unused `lastEngineStatus` variable after premature yield removal**
- **Found during:** Task 2 (flutter analyze after sync_status_provider.dart edit)
- **Issue:** After removing the `yield lastEngineStatus ?? ...` line, the `lastEngineStatus` variable became unused — flutter analyze reported `warning: The value of the local variable 'lastEngineStatus' isn't used`
- **Fix:** Removed the `SyncStatus? lastEngineStatus;` declaration and the `lastEngineStatus = event.status;` assignment in the _EngineEvent branch
- **Files modified:** mobile/lib/core/sync/sync_status_provider.dart
- **Verification:** `flutter analyze lib/core/sync/sync_status_provider.dart` reports only 1 pre-existing info (unintended_html_in_doc_comment), no warnings
- **Committed in:** 993d60c (Task 2 commit)

---

**Total deviations:** 1 auto-fixed (Rule 1 - cleanup of variable made dead by planned change)
**Impact on plan:** Necessary correctness cleanup — the unused variable was a direct consequence of the planned fix. No scope creep.

## Issues Encountered

None beyond the unused variable handled above.

## User Setup Required

**Backend:** Run `alembic upgrade head` to apply migration 0003 and backfill user_roles.updated_at. This is required for GET /api/v1/sync?cursor= to return user_roles records.

## UAT Impact

| UAT Test | Status Before | Status After |
|----------|---------------|--------------|
| Test 1 (Cold Start Smoke Test: user_roles populated) | FAIL (empty array) | PASS (after alembic upgrade head) |
| Test 7 (Sync status shows "Syncing 1 of 1..." on reconnect) | FAIL (immediate allSynced) | PASS |

## Next Phase Readiness

- Phase 2 complete — all 10 UAT tests addressed (Tests 1 and 7 resolved in this plan, remaining tests unblocked in 02-06)
- Migration chain: 0001 -> 0002 -> 0003 complete and correct
- Sync status UI now correctly reflects all state transitions: offline -> syncing -> allSynced

## Self-Check: PASSED

| Item | Status |
|------|--------|
| backend/migrations/versions/0003_backfill_user_roles_updated_at.py | FOUND |
| backend/app/features/users/models.py | FOUND |
| mobile/lib/core/sync/sync_status_provider.dart | FOUND |
| mobile/lib/core/sync/sync_engine.dart | FOUND |
| .planning/phases/02-offline-sync-engine/02-07-SUMMARY.md | FOUND |
| Commit 4f78ee7 (Task 1) | FOUND |
| Commit 993d60c (Task 2) | FOUND |

---
*Phase: 02-offline-sync-engine*
*Completed: 2026-03-06*
