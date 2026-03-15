---
phase: 12-client-profile-sync-fix
plan: 01
subsystem: sync
tags: [drift, dio, sync-handler, offline-first, client-profile, e2e-tests]

requires:
  - phase: 09-sync-engine-gap-closure
    provides: SyncHandler interface, SyncEngine drainQueue, MockDioClient E2E test pattern

provides:
  - ClientProfileSyncHandler.push() correctly routes to POST /clients/{userId}/profile for both CREATE and UPDATE
  - E2E tests covering all three sync push scenarios (CREATE, UPDATE, full offline flow)

affects:
  - sync-engine
  - client-portal
  - crm

tech-stack:
  added: []
  patterns:
    - "Sync handler upsert pattern: when backend has single upsert endpoint, remove operation switch and route all mutations to POST"
    - "Payload key extraction: extract user FK from payload['userId'] (camelCase), not item.entityId (which is the entity's own PK)"

key-files:
  created:
    - mobile/test/e2e/phase_12_client_profile_sync_fix_e2e_test.dart
  modified:
    - mobile/lib/features/jobs/data/client_profile_sync_handler.dart

key-decisions:
  - "Phase 12: ClientProfileSyncHandler uses single POST /clients/{userId}/profile for both CREATE and UPDATE — no operation switch needed when backend has upsert semantics"
  - "Phase 12: userId extracted from payload['userId'] (camelCase) not item.entityId — entityId holds profile UUID, userId holds user FK"

patterns-established:
  - "Sync handler simplification: if backend endpoint has upsert semantics, collapse CREATE/UPDATE switch to single POST call"

requirements-completed: [CLNT-01]

duration: 3min
completed: 2026-03-15
---

# Phase 12 Plan 01: Client Profile Sync Fix Summary

**Surgical two-line fix to ClientProfileSyncHandler.push() closing INT-04: offline client profile edits now sync to POST /clients/{userId}/profile instead of parking on 404**

## Performance

- **Duration:** 3 min
- **Started:** 2026-03-15T05:41:33Z
- **Completed:** 2026-03-15T05:44:30Z
- **Tasks:** 2
- **Files modified:** 2

## Accomplishments

- Removed broken switch statement routing CREATE to `POST /clients/profiles` and UPDATE to `PATCH /clients/profiles/{id}` (both 404 endpoints)
- Both CREATE and UPDATE now route to `POST /clients/{userId}/profile` matching the backend's single upsert endpoint
- userId correctly extracted from `payload['userId']` (not `item.entityId` which holds the profile UUID)
- 6 E2E tests pass covering CREATE, UPDATE, full offline flow with real Drift DB, and StateError on unknown operation
- Phase 9 regression suite (13 tests) still green — no regressions
- dart analyze clean on modified handler

## Task Commits

Each task was committed atomically:

1. **Task 1 (TDD RED): Failing E2E tests** - `b390c3c` (test)
2. **Task 1 (TDD GREEN): Handler fix** - `be93652` (feat)
3. **Task 2: dart analyze cleanup** - `c82e735` (fix — unused import removed)

_Note: TDD task has RED + GREEN commits per TDD execution protocol_

## Files Created/Modified

- `mobile/lib/features/jobs/data/client_profile_sync_handler.dart` - Removed broken switch; unified CREATE+UPDATE to single POST upsert; userId extracted from payload
- `mobile/test/e2e/phase_12_client_profile_sync_fix_e2e_test.dart` - 6 E2E tests: CREATE route, UPDATE route, negative URL checks, full offline flow with real Drift DB

## Decisions Made

- Eliminated switch on operation — the backend's `create_or_update_profile` upsert handles both; a switch adds complexity with no benefit
- Removed unused `sync_queue_dao.dart` import (auto-fix, Rule 1) found by dart analyze after handler simplification

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 1 - Bug] Removed unused import causing dart analyze warning**
- **Found during:** Task 2 (dart analyze verification)
- **Issue:** `sync_queue_dao.dart` import was unused after handler simplification (SyncQueueData is re-exported via app_database.dart)
- **Fix:** Removed the unused import directive
- **Files modified:** mobile/lib/features/jobs/data/client_profile_sync_handler.dart
- **Verification:** `dart analyze` reports "No issues found"
- **Committed in:** c82e735 (separate fix commit)

---

**Total deviations:** 1 auto-fixed (Rule 1 — unused import)
**Impact on plan:** Cleanup only. No scope creep.

## Issues Encountered

- E2E stub for `pushWithIdempotency` needed to cover both the 3-arg form (POST default) and the 4-arg form (named `method:` param) because the original broken code used `method: 'PATCH'` for UPDATE. Added a second `when()` stub to make the RED phase correctly capture the broken PATCH call.

## User Setup Required

None — no external service configuration required.

## Next Phase Readiness

- INT-04 gap closed: offline client profile edits fully sync end-to-end
- Phase 12 is the final gap-closure phase; no blocking concerns for v1.0 milestone
- All sync handlers now route to correct backend endpoints

---
*Phase: 12-client-profile-sync-fix*
*Completed: 2026-03-15*
