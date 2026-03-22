---
phase: 20-dependency-engine
plan: 04
subsystem: ui
tags: [flutter, riverpod, custom-painter, gantt, dependency-graph, drift, interactive-viewer]

# Dependency graph
requires:
  - phase: 20-02
    provides: TaskDependencyDao, ProjectZoneDao, TaskDependency/ProjectZone Drift tables
  - phase: 20-01
    provides: GanttDataState concept, conflict detection design
provides:
  - GanttPainter CustomPainter rendering trade swim lanes, task bars, today line
  - DependencyArrowPainter CustomPainter with bezier curves and arrowheads
  - GanttChartWidget with InteractiveViewer pinch-to-zoom and drag-to-connect
  - GanttScreen with conflict MaterialBanner and cycle error AlertDialog
  - ganttDataProvider: Riverpod AsyncNotifier.family aggregating all Gantt streams
  - RouteNames.projectGanttPath and GoRouter /projects/:id/gantt route
  - Timeline IconButton in ProjectDetailScreen AppBar
  - 14 E2E tests covering all Gantt features
affects: [phase-21-ai-planning, phase-22-notifications]

# Tech tracking
tech-stack:
  added: []
  patterns:
    - "GanttPainter/DependencyArrowPainter stacked CustomPaint for gantt layers"
    - "AsyncNotifier.family via factory fn (projectId) => GanttDataNotifier(projectId)"
    - "InteractiveViewer(constrained: false) with boundaryMargin for pan/zoom"
    - "ConflictInfo computed locally from (zoneId, dueDate) task groupings"

key-files:
  created:
    - mobile/lib/features/projects/presentation/widgets/gantt_painter.dart
    - mobile/lib/features/projects/presentation/widgets/dependency_arrow_painter.dart
    - mobile/lib/features/projects/presentation/widgets/gantt_chart_widget.dart
    - mobile/lib/features/projects/presentation/screens/gantt_screen.dart
    - mobile/lib/features/projects/presentation/providers/gantt_provider.dart
    - mobile/test/e2e/phase_20_dependency_engine_e2e_test.dart
  modified:
    - mobile/lib/core/routing/route_names.dart
    - mobile/lib/core/routing/app_router.dart
    - mobile/lib/features/projects/presentation/screens/project_detail_screen.dart

key-decisions:
  - "Riverpod 3 AsyncNotifier.family uses factory (arg) => Notifier(arg) pattern — no FamilyAsyncNotifier class"
  - "InteractiveViewer(constrained: false, boundaryMargin: infinity) — allows canvas to extend beyond viewport for Gantt pan"
  - "Full dependency creation (insertWithSyncQueue) deferred to Phase 21 — requires companyId from auth; Phase 20 has local cycle detection only"
  - "SingleChildScrollView removed from GanttScreen body — InteractiveViewer handles its own scrolling to avoid unbounded constraint errors"

patterns-established:
  - "GanttPainter: taskBarRectsOut map filled during paint() for hit testing and arrow positioning"
  - "DependencyArrowPainter: ghost arrow during drag-to-connect via dragStart/dragEnd offsets"
  - "FakeGanttDataNotifier extends GanttDataNotifier for deterministic widget test state"
  - "pump() not pumpAndSettle() in all Gantt widget tests (Drift stream pattern)"

requirements-completed: [PROJ-04, PROJ-05, AI-06]

# Metrics
duration: 15min
completed: 2026-03-22
---

# Phase 20 Plan 04: Dependency Engine Gantt Chart Summary

**Flutter Gantt chart with CustomPainter swim lanes, bezier dependency arrows, pinch-to-zoom, drag-to-connect, conflict banners, and cycle error dialogs — 14 E2E tests pass**

## Performance

- **Duration:** 15 min
- **Started:** 2026-03-22T03:31:51Z
- **Completed:** 2026-03-22T03:46:56Z
- **Tasks:** 2
- **Files modified:** 9 (6 created, 3 modified)

## Accomplishments

- GanttPainter CustomPainter renders trade swim lanes with colored headers, task bars with status-based progress fills (gray/amber/green/red-dashed), and today line indicator
- DependencyArrowPainter renders bezier curves (cubicTo) between connected task bars with arrowheads, lag labels, type labels (SS/FF/SE), and ghost arrow during drag-to-connect
- GanttChartWidget wraps both painters in InteractiveViewer (pinch-to-zoom 0.5x-3.0x), handles long-press drag-to-connect (right-edge 44px handle) and tap hit testing
- GanttScreen with conflict MaterialBanner, cycle error AlertDialog showing tappable chain names, blocked task snackbar feedback
- ganttDataProvider: Riverpod AsyncNotifier.family aggregating TradeScopeDao, TaskDao, TaskDependencyDao, ProjectZoneDao streams with local conflict computation
- Navigation: RouteNames.projectGanttPath + GoRouter route + Timeline button in ProjectDetailScreen AppBar
- 14 E2E tests: swim lanes, task bars, dependency arrows, blocked status, cycle dialog, conflict banner, no-conflict verification, InteractiveViewer, painters presence, DAO stream, state helpers

## Task Commits

Each task was committed atomically:

1. **Task 1: GanttPainter, DependencyArrowPainter, GanttChartWidget, GanttScreen** - `bc8904e` (feat)
2. **Task 2: Flutter E2E tests for dependency engine** - `0f0b51f` (test)

## Files Created/Modified

- `mobile/lib/features/projects/presentation/widgets/gantt_painter.dart` - CustomPainter: swim lanes, task bars, today line, conflict highlights
- `mobile/lib/features/projects/presentation/widgets/dependency_arrow_painter.dart` - CustomPainter: bezier arrows, arrowheads, lag labels, ghost arrow
- `mobile/lib/features/projects/presentation/widgets/gantt_chart_widget.dart` - StatefulWidget: InteractiveViewer, drag-to-connect gestures, hit testing
- `mobile/lib/features/projects/presentation/screens/gantt_screen.dart` - ConsumerStatefulWidget: conflict banner, cycle dialog, blocked snackbar
- `mobile/lib/features/projects/presentation/providers/gantt_provider.dart` - AsyncNotifier.family aggregating all Gantt data streams with conflict detection
- `mobile/lib/core/routing/route_names.dart` - Added projectGantt constant and projectGanttPath helper
- `mobile/lib/core/routing/app_router.dart` - Added /projects/:projectId/gantt GoRouter route
- `mobile/lib/features/projects/presentation/screens/project_detail_screen.dart` - Added Timeline IconButton in AppBar
- `mobile/test/e2e/phase_20_dependency_engine_e2e_test.dart` - 14 E2E tests covering all Gantt features

## Decisions Made

- **Riverpod 3 family pattern**: `AsyncNotifierProvider.autoDispose.family` uses `(arg) => Notifier(arg)` factory — there is no `FamilyAsyncNotifier` class in Riverpod 3; the notifier extends `AsyncNotifier<State>` and receives the arg via constructor
- **InteractiveViewer unbounded constraint**: `constrained: false` with `boundaryMargin: EdgeInsets.all(double.infinity)` allows the Gantt canvas to extend beyond viewport. Test widgets need `SizedBox(width: 800, height: 600)` wrapper to provide bounds
- **Dependency creation deferred**: Full `insertWithSyncQueue` requires `companyId` from auth state. Phase 20 provides local DFS cycle detection; actual DAO write deferred to Phase 21 AI planning integration
- **SingleChildScrollView removed**: GanttScreen body was wrapping `GanttChartWidget` in `SingleChildScrollView` which caused unbounded height constraint with `InteractiveViewer(constrained: false)`. Removed — InteractiveViewer handles its own pan

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 1 - Bug] Removed extra SingleChildScrollView causing unbounded constraints**
- **Found during:** Task 2 (E2E tests)
- **Issue:** `InteractiveViewer(constrained: false)` inside `SingleChildScrollView` received infinite height constraints, crashing layout
- **Fix:** Removed `SingleChildScrollView` wrapper — `InteractiveViewer` handles panning internally
- **Files modified:** `mobile/lib/features/projects/presentation/screens/gantt_screen.dart`
- **Verification:** All 14 E2E tests pass with `pump()`
- **Committed in:** `0f0b51f` (Task 2 commit)

**2. [Rule 1 - Bug] Fixed extra closing paren after SingleChildScrollView removal**
- **Found during:** Task 2 (E2E tests — compilation error)
- **Issue:** After removing `SingleChildScrollView`, its closing `)` remained causing syntax error at line 128
- **Fix:** Removed extra `)` from GanttChartWidget closing
- **Files modified:** `mobile/lib/features/projects/presentation/screens/gantt_screen.dart`
- **Verification:** `dart analyze` passes with no errors
- **Committed in:** `0f0b51f` (Task 2 commit)

**3. [Rule 1 - Bug] Fixed GanttDataNotifier using wrong Riverpod 3 base class**
- **Found during:** Task 1 (dart analyze — `FamilyAsyncNotifier` not found)
- **Issue:** Used `FamilyAsyncNotifier<State, Arg>` which doesn't exist in Riverpod 3; `AutoDisposeFamilyAsyncNotifier` also not found
- **Fix:** Changed to `AsyncNotifier<GanttDataState>` with projectId constructor arg; provider uses `AsyncNotifierProvider.autoDispose.family((arg) => GanttDataNotifier(arg))`
- **Files modified:** `mobile/lib/features/projects/presentation/providers/gantt_provider.dart`
- **Verification:** `dart analyze` passes with no errors
- **Committed in:** `bc8904e` (Task 1 commit)

---

**Total deviations:** 3 auto-fixed (3 Rule 1 bugs)
**Impact on plan:** All fixes necessary for correct layout, compilation, and Riverpod 3 compatibility. No scope creep.

## Issues Encountered

- Riverpod 3 dropped `FamilyAsyncNotifier` class — class-based family notifiers now use regular `AsyncNotifier` with constructor injection and factory `(arg) => Notifier(arg)` in the provider declaration
- `AsyncValue.valueOrNull` renamed to `AsyncValue.value` in Riverpod 3 (returns `T?`)

## User Setup Required

None - no external service configuration required.

## Next Phase Readiness

- All Gantt UI is complete and testable
- Full dependency creation (DAO write) needs companyId from auth in Phase 21
- Phase 21 (AI Planning) can import ganttDataProvider and GanttScreen directly
- Phase 21 should wire up the `createDependency` flow with real auth context

## Self-Check: PASSED

- All 7 created/modified files exist on disk
- Commits bc8904e and 0f0b51f confirmed in git log
- `class GanttPainter extends CustomPainter` found in gantt_painter.dart
- `class DependencyArrowPainter extends CustomPainter` found in dependency_arrow_painter.dart
- `class GanttScreen` found in gantt_screen.dart
- `Dependency creates a loop` found in gantt_screen.dart
- `InteractiveViewer` found in gantt_chart_widget.dart
- 14/14 E2E tests passing

---
*Phase: 20-dependency-engine*
*Completed: 2026-03-22*
