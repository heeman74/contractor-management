---
phase: 19-project-data-model
plan: 04
subsystem: ui
tags: [flutter, riverpod, drift, go_router, project-hierarchy, mobile]

# Dependency graph
requires:
  - phase: 19-02
    provides: ProjectDao, TradeScopeDao, TaskDao with watchProjectsByCompany, watchProjectsForContractor, watchScopesByProject, watchTasksByScope streams

provides:
  - ProjectListScreen with role-aware empty states and FAB
  - ProjectDetailScreen with TradeScopeCard ListView
  - TradeScopeDetailScreen with priority-bordered task rows
  - TradeScopeCard widget with trade color bar, contractor name, progress bar
  - ProjectStatusBadge widget for all lifecycle statuses
  - Riverpod providers: projectListProvider (role-aware), tradeScopesProvider, tasksProvider
  - Projects bottom nav tab (admin+contractor only, Branch 8 of StatefulShellRoute)
  - GoRouter routes: /projects, /projects/:projectId, /projects/:projectId/scopes/:scopeId
  - 13 E2E widget tests covering PROJ-03 mobile hierarchy navigation

affects: [phase-20-ai-integration, phase-21, phase-22]

# Tech tracking
tech-stack:
  added: []
  patterns:
    - AsyncNotifier with stream subscription (subscribe in build, cancel in onDispose)
    - StreamProvider.family for parameterized reactive streams
    - Stream.value() in widget tests to avoid pending-timer issues from Drift watch streams
    - TradeScopeCard with IntrinsicHeight + left color accent bar pattern

key-files:
  created:
    - mobile/lib/features/projects/presentation/providers/project_providers.dart
    - mobile/lib/features/projects/presentation/screens/project_list_screen.dart
    - mobile/lib/features/projects/presentation/screens/project_detail_screen.dart
    - mobile/lib/features/projects/presentation/screens/trade_scope_detail_screen.dart
    - mobile/lib/features/projects/presentation/screens/task_list_screen.dart
    - mobile/lib/features/projects/presentation/widgets/trade_scope_card.dart
    - mobile/lib/features/projects/presentation/widgets/project_status_badge.dart
    - mobile/test/e2e/phase_19_project_data_model_e2e_test.dart
  modified:
    - mobile/lib/core/routing/route_names.dart
    - mobile/lib/core/routing/app_router.dart
    - mobile/lib/shared/widgets/app_shell.dart
    - mobile/lib/features/projects/data/project_dao.dart

key-decisions:
  - "watchProjectsForContractor rewritten from selectOnly+JOIN to two-stream approach (select scopes then filter projects) — Drift selectOnly with readTable fails for joined queries; two-stream approach is readable, tested, and correct"
  - "Test 10 split into 3 separate testWidgets — Riverpod 3 forbids changing override counts between pumpWidget calls in same test"
  - "Stream.value() used in widget tests instead of real Drift streams — avoids pending-timer assertion failures from watch streams"
  - "Projects bottom nav tab added as Branch 8 (after Reports Branch 7) — admin and contractor only, not client"

patterns-established:
  - "Hex color utility hexToColor() in trade_scope_card.dart for converting #RRGGBB strings to Flutter Color"
  - "ProjectStatusBadge switch expression maps all lifecycle statuses to (label, bgColor, fgColor) tuples"

requirements-completed: [PROJ-03]

# Metrics
duration: 32min
completed: 2026-03-20
---

# Phase 19 Plan 04: Project Hierarchy Mobile UI Summary

**Flutter project hierarchy: 4 screens with Riverpod providers, Projects bottom nav tab, role-based contractor filtering via watchProjectsForContractor, and 13 passing E2E widget tests**

## Performance

- **Duration:** 32 min
- **Started:** 2026-03-20T11:49:27Z
- **Completed:** 2026-03-20T12:21:53Z
- **Tasks:** 2
- **Files modified:** 12

## Accomplishments

- Four mobile screens: ProjectListScreen, ProjectDetailScreen, TradeScopeDetailScreen, task_list_screen (re-export alias)
- Riverpod providers with role-aware contractor filtering: admin gets all company projects, contractor gets only projects with assigned scope
- TradeScopeCard with left trade-color accent bar, contractor name/"Unassigned", task count, and LinearProgressIndicator progress bar
- Projects tab in bottom navigation (admin + contractor only, Branch 8 in StatefulShellRoute)
- 13 E2E widget tests covering all PROJ-03 acceptance criteria (all passing)
- Bug fix: `watchProjectsForContractor` DAO rewritten to work correctly

## Task Commits

Each task was committed atomically:

1. **Task 1: Create Riverpod providers, routing, bottom nav tab, and all four mobile screens** - `e10f1ef` (feat)
2. **Task 2: Create mobile E2E widget tests for project hierarchy navigation (PROJ-03)** - `e54f439` (feat + Rule 1 bug fix)

## Files Created/Modified

- `mobile/lib/features/projects/presentation/providers/project_providers.dart` - projectListProvider (role-aware), tradeScopesProvider, tasksProvider
- `mobile/lib/features/projects/presentation/screens/project_list_screen.dart` - Project list with FAB, role-specific empty state
- `mobile/lib/features/projects/presentation/screens/project_detail_screen.dart` - TradeScopeCard ListView with "Add Trade Scope" stub
- `mobile/lib/features/projects/presentation/screens/trade_scope_detail_screen.dart` - Task list with priority borders, task detail bottom sheet stub
- `mobile/lib/features/projects/presentation/screens/task_list_screen.dart` - Re-export of TradeScopeDetailScreen (tasks merged per plan note)
- `mobile/lib/features/projects/presentation/widgets/trade_scope_card.dart` - Card with color bar, contractor name, LinearProgressIndicator
- `mobile/lib/features/projects/presentation/widgets/project_status_badge.dart` - Status chip for project/scope/task statuses
- `mobile/lib/core/routing/route_names.dart` - Added projects, projectDetail, tradeScopeDetail constants + path helpers
- `mobile/lib/core/routing/app_router.dart` - Added Branch 8 (Projects) with nested routes
- `mobile/lib/shared/widgets/app_shell.dart` - Added Projects tab, Branch 8 in _allBranchRoutes
- `mobile/lib/features/projects/data/project_dao.dart` - Bug fix: watchProjectsForContractor rewritten
- `mobile/test/e2e/phase_19_project_data_model_e2e_test.dart` - 13 E2E widget tests

## Decisions Made

- `watchProjectsForContractor` was rewritten from a `selectOnly` + JOIN to a two-stream approach (watch TradeScopes for contractor's project IDs, then filter the Projects stream). The original code used `readTable` which fails for `selectOnly` queries in Drift.
- Riverpod 3 requires identical override counts between `pumpWidget` calls in the same test. The drill-down navigation test was split into 3 separate `testWidgets` to comply.
- `Stream.value()` is used in all widget tests instead of real Drift watch streams to avoid the "Timer is still pending" assertion in Flutter test framework.

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 1 - Bug] Fixed watchProjectsForContractor DAO query**
- **Found during:** Task 2 (E2E test for contractor filtering)
- **Issue:** Original `selectOnly` + `innerJoin` + `readTable` combination threw "Invalid table passed to readTable: This row does not contain values for that table" at runtime. The Drift `selectOnly` query produces `TypedResult` rows that don't support `readTable` for joined tables.
- **Fix:** Replaced with a two-stream approach: watch TradeScopes filtered by contractorId to get the set of project IDs, then watch all company Projects and filter by that set. In-memory stream combining via `asyncExpand`.
- **Files modified:** `mobile/lib/features/projects/data/project_dao.dart`
- **Verification:** DAO unit test `watchProjectsForContractor returns only contractor-assigned projects` passes; contractor sees 1 project (project1 with assigned scope), not 2.
- **Committed in:** e54f439 (Task 2 commit)

---

**Total deviations:** 1 auto-fixed (1 bug fix)
**Impact on plan:** Bug fix required for correct contractor role filtering. No scope creep. The two-stream approach is correct and readable, with the trade-off of two separate Drift queries instead of one join query.

## Issues Encountered

- Riverpod 3 does not allow changing the number of `overrides` between `pumpWidget` calls in the same test (throws "Tried to change the number of overrides" assertion). Split test 10 into 3 separate testWidgets — one per hierarchy level — each with a consistent set of 4 overrides.

## User Setup Required

None - no external service configuration required.

## Next Phase Readiness

- PROJ-03 (GC navigates project hierarchy as tree view on mobile) is complete
- Projects tab visible in bottom nav for admin and contractor roles
- Screens wired to GoRouter routes — ready for production data after backend sync (Plan 03 covers sync validation)
- Stub buttons ("Add Trade Scope", "+" FAB) ready for Phase 19 Plan 05 (Create Project wizard)

---
*Phase: 19-project-data-model*
*Completed: 2026-03-20*
