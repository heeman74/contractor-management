---
phase: 20-dependency-engine
plan: "06"
subsystem: mobile
tags: [flutter, riverpod, drift, sync-queue, gantt, dependency-engine]

# Dependency graph
requires:
  - phase: 20-dependency-engine/20-04
    provides: GanttScreen with placeholder _handleDependencyCreated and TaskDependencyDao.insertWithSyncQueue
  - phase: 20-dependency-engine/20-02
    provides: TaskDependencyDao with insertWithSyncQueue and watchByProject
provides:
  - Working mobile dependency persistence via TaskDependencyDao.insertWithSyncQueue
  - CompanyId sourced from AuthAuthenticated state (not hardcoded)
  - Gantt arrows auto-refresh after dependency creation via ref.invalidate
  - E2E test #15 verifying insertWithSyncQueue called with correct companyId
affects:
  - Phase 21 (AI planning integration) - dependency creation now functional; AI can read/write deps
  - Phase 23 (sync) - sync queue entries are now created for mobile-initiated dependencies

# Tech tracking
tech-stack:
  added: []
  patterns:
    - "Read companyId from ref.read(authNotifierProvider) cast as AuthAuthenticated"
    - "ref.read(taskDependencyDaoProvider) for DAO access in ConsumerStatefulWidget"
    - "ref.invalidate(ganttDataProvider(projectId)) to refresh reactive data after mutation"
    - "mocktail registerFallbackValue for TaskDependenciesCompanion in setUpAll"
    - "taskDependencyDaoProvider.overrideWithValue(mockDao) for widget test isolation"

key-files:
  created: []
  modified:
    - mobile/lib/features/projects/presentation/screens/gantt_screen.dart
    - mobile/test/e2e/phase_20_dependency_engine_e2e_test.dart

key-decisions:
  - "TaskDependenciesCompanion imported via app_database.dart show clause (not tables/task_dependencies.dart direct import) — Drift-generated companions only accessible via app_database barrel"
  - "registerFallbackValue required for TaskDependenciesCompanion in mocktail any() matcher — non-nullable custom type needs explicit fallback"

patterns-established:
  - "Drift companion fallback: registerFallbackValue in setUpAll before any() matcher usage"
  - "Auth state read pattern: ref.read(authNotifierProvider) as AuthAuthenticated for companyId"

requirements-completed: ["PROJ-04", "AI-06"]

# Metrics
duration: 8min
completed: 2026-03-22
---

# Phase 20 Plan 06: Mobile Dependency Persistence Gap Closure Summary

**Mobile drag-to-connect now writes TaskDependency rows to Drift with sync queue via insertWithSyncQueue, with companyId from AuthAuthenticated state and arrow refresh via ref.invalidate**

## Performance

- **Duration:** ~8 min
- **Started:** 2026-03-22T04:26:00Z
- **Completed:** 2026-03-22T04:33:48Z
- **Tasks:** 2
- **Files modified:** 2

## Accomplishments
- Replaced placeholder snackbar in `_handleDependencyCreated` with real `TaskDependencyDao.insertWithSyncQueue` call
- CompanyId is sourced from `ref.read(authNotifierProvider)` cast to `AuthAuthenticated` — not hardcoded
- Gantt data is invalidated with `ref.invalidate(ganttDataProvider(projectId))` so dependency arrows refresh immediately
- Unauthenticated guard added — shows error snackbar if companyId is empty
- Error handling wraps the DAO call with a user-facing snackbar on failure
- Added E2E test #15 that verifies `insertWithSyncQueue` is called with correct `companyId`, `predecessorTaskId`, `successorTaskId`
- All 15 E2E tests pass

## Task Commits

Each task was committed atomically:

1. **Task 1: Wire _handleDependencyCreated to persist via DAO** - `c02a5ff` (feat)
2. **Task 2: Add E2E test for mobile dependency persistence** - `d9a6495` (test)

## Files Created/Modified
- `mobile/lib/features/projects/presentation/screens/gantt_screen.dart` - Added imports (drift Value, uuid, auth_provider, auth_state, TaskDependenciesCompanion), replaced placeholder with real DAO write, removed Phase 21 deferral comment
- `mobile/test/e2e/phase_20_dependency_engine_e2e_test.dart` - Added MockTaskDependencyDao, registerFallbackValue for TaskDependenciesCompanion, test #15 verifying persistence with correct companyId

## Decisions Made
- `TaskDependenciesCompanion` must be imported via `app_database.dart` show clause, not from `tables/task_dependencies.dart` directly — Drift generates companions only in the main database barrel
- Mocktail `any()` matcher on `TaskDependenciesCompanion` requires `registerFallbackValue` in `setUpAll` since it's a non-nullable custom type with no default construction

## Deviations from Plan

None - plan executed exactly as written.

The one minor discovery (TaskDependenciesCompanion import path) was handled inline as a Rule 3 fix without blocking the task.

### Auto-fixed Issues

**1. [Rule 3 - Blocking] Fixed TaskDependenciesCompanion import path**
- **Found during:** Task 1 (wire _handleDependencyCreated)
- **Issue:** Plan suggested importing from `tables/task_dependencies.dart` but that file only defines the `TaskDependencies` table class; the companion is generated in `app_database.dart`
- **Fix:** Changed import to `app_database.dart show TaskDependency, TaskDependenciesCompanion`
- **Files modified:** mobile/lib/features/projects/presentation/screens/gantt_screen.dart
- **Verification:** `flutter analyze` reported no issues
- **Committed in:** c02a5ff (Task 1 commit)

**2. [Rule 3 - Blocking] Registered mocktail fallback for TaskDependenciesCompanion**
- **Found during:** Task 2 (E2E test)
- **Issue:** `any()` matcher threw MissingFallbackValueError for TaskDependenciesCompanion — mocktail requires explicit fallback for non-nullable custom types
- **Fix:** Added `registerFallbackValue(TaskDependenciesCompanion(...))` in `setUpAll`
- **Files modified:** mobile/test/e2e/phase_20_dependency_engine_e2e_test.dart
- **Verification:** All 15 tests pass
- **Committed in:** d9a6495 (Task 2 commit)

---

**Total deviations:** 2 auto-fixed (2 blocking)
**Impact on plan:** Both fixes required to compile and test. No scope creep.

## Issues Encountered
None beyond the two blocking import/mock issues above, both resolved inline.

## Next Phase Readiness
- Mobile dependency creation is fully functional end-to-end (create → persist → sync queue → arrow refresh)
- Phase 21 (AI planning) can read existing dependencies from Drift and create new ones via the same DAO
- Sync queue entries are being created and will be processed by the sync engine in Phase 23

---
*Phase: 20-dependency-engine*
*Completed: 2026-03-22*
