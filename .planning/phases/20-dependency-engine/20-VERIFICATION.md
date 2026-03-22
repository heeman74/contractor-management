---
phase: 20-dependency-engine
verified: 2026-03-22T05:00:00Z
status: passed
score: 18/18 must-haves verified
re_verification: true
  previous_status: gaps_found
  previous_score: 16/18
  gaps_closed:
    - "Web dependency arrows never render (allDependencies = []) — fixed by Plan 05: useProjectDependencies hook added to projects.ts, page.tsx now calls it and passes real data to GanttView"
    - "Mobile drag-to-connect does not persist — fixed by Plan 06: _handleDependencyCreated now calls TaskDependencyDao.insertWithSyncQueue with companyId from AuthAuthenticated; ref.invalidate refreshes arrows"
  gaps_remaining: []
  regressions: []
human_verification:
  - test: "Web Gantt dependency arrow rendering in browser"
    expected: "Arrows connect task bars on the SVAR Gantt when tasks have FS/SS/FF/SE dependencies"
    why_human: "SVG/canvas bezier arrow rendering in SVAR Gantt requires a real browser — cannot verify via grep"
  - test: "Mobile pinch-to-zoom and pan on real device"
    expected: "InteractiveViewer allows smooth pinch-zoom (0.5x-3.0x) and pan on the Gantt canvas"
    why_human: "Gesture simulation in widget tests verifies widget tree presence, not actual touch responsiveness"
  - test: "Conflict badge visual display"
    expected: "Amber MaterialBanner with warning icon, trade names, zone name, and date appears above Gantt when conflicts exist"
    why_human: "Color/styling (amber-100 background, amber-600 icon) cannot be verified programmatically"
---

# Phase 20: Dependency Engine Verification Report

**Phase Goal:** The system enforces cross-trade task dependencies with cycle prevention, and GCs can visualize the full project timeline with all trades and their dependency relationships.
**Verified:** 2026-03-22
**Status:** passed
**Re-verification:** Yes — after gap closure (Plans 05 and 06)

---

## Re-Verification Summary

This is a re-verification after two gap closure plans ran:

- **Plan 05** (commit c216958 + 74957d1): Added `fetchProjectDependencies` and `useProjectDependencies` to `web/src/lib/api/projects.ts`. Updated `gantt/page.tsx` to call `useProjectDependencies(scopes)` and assign the result to `allDependencies`, replacing the prior hard-coded `[]`. Added `queryClient.invalidateQueries({ queryKey: ["project-dependencies"] })` after dependency creation. Two Playwright tests added for fetch verification.
- **Plan 06** (commit c02a5ff + d9a6495): Replaced the placeholder snackbar in `_handleDependencyCreated` with a real `TaskDependencyDao.insertWithSyncQueue` call. CompanyId is sourced from `ref.read(authNotifierProvider) as AuthAuthenticated`. Gantt data invalidated via `ref.invalidate(ganttDataProvider(projectId))` after write. E2E test #15 added to verify `insertWithSyncQueue` is called with correct `companyId`, `predecessorTaskId`, and `successorTaskId`.

Both gaps are now fully closed. All 4 commits verified in git history.

---

## Goal Achievement

### Observable Truths

| # | Truth | Status | Evidence |
|---|-------|--------|----------|
| 1 | Creating a dependency between two tasks returns 201 with edge record | VERIFIED | `DependencyService.create_dependency()` in `service.py`; `test_create_fs_dependency` in `test_phase_20_e2e.py` |
| 2 | Creating a dependency that forms a cycle returns 422 with cycle path | VERIFIED | `DependencyService._find_cycle()` DFS; `test_cycle_rejected_422` passes |
| 3 | A task with an unmet FS predecessor has status=blocked | VERIFIED | `_recompute_blocked_status()` sets task.status='blocked'; `test_task_blocked_by_dependency` |
| 4 | Completing a predecessor task unblocks the successor | VERIFIED | `TaskService.recompute_successor_statuses()`; `test_task_unblocked_on_completion` |
| 5 | Two tasks in same zone on same day detected as conflict | VERIFIED | `ConflictService.detect_conflicts()` self-join query; `test_conflict_detected` |
| 6 | Tasks in different zones are NOT a conflict | VERIFIED | `test_no_conflict_different_zones` passes |
| 7 | Existing depends_on JSONB migrated to task_dependencies rows | VERIFIED | Migration 0016 step 5: INSERT INTO task_dependencies from depends_on JSONB; DROP COLUMN depends_on |
| 8 | TaskDependencies Drift table exists with FS/SS/FF/SE support | VERIFIED | `mobile/lib/core/database/tables/task_dependencies.dart` — `class TaskDependencies extends Table` with dependencyType column |
| 9 | ProjectZones Drift table exists with project FK | VERIFIED | `mobile/lib/core/database/tables/project_zones.dart` — projectId references Projects |
| 10 | Drift schema version upgraded 7→8 with migration | VERIFIED | `app_database.dart:124: int get schemaVersion => 8` + `if (from < 8)` migration block |
| 11 | Sync handlers registered for task_dependency and project_zone | VERIFIED | `service_locator.dart:96-97` — both handlers registered via `registry.register()` |
| 12 | GC can view Gantt page with trade swim lanes | VERIFIED | `web/src/app/(dashboard)/projects/[id]/gantt/page.tsx` + GanttView renders SVAR Gantt with scopes as swim lanes |
| 13 | Dependency arrows visible between task bars on web Gantt | VERIFIED | `useProjectDependencies(scopes)` called in page.tsx:39; result assigned at line 50; passed as `dependencies={allDependencies}` to GanttView at line 184. No empty-array stub remains. |
| 14 | Cycle error dialog shows chain when 422 returned (web) | VERIFIED | `CycleErrorDialog.tsx` with "Dependency creates a loop"; wired in `page.tsx:handleDependencyCreate` |
| 15 | Conflict warnings appear as badges on conflicting task bars | VERIFIED | `ConflictBadge.tsx` with `role="alert"` rendered in page when `conflicts.length > 0` |
| 16 | GC can manage project zones via ZoneManageModal | VERIFIED | `ZoneManageModal.tsx` with add/delete/duplicate validation; wired in page.tsx |
| 17 | Mobile Gantt renders swim lanes and task bars | VERIFIED | `GanttPainter` with `_drawSwimLanes`, `_drawTaskBars`, `_drawTodayLine`; 14 E2E tests pass |
| 18 | Long-press drag-connect creates and persists a new dependency (mobile) | VERIFIED | `_handleDependencyCreated` calls `depDao.insertWithSyncQueue(TaskDependenciesCompanion(...))` at line 197; companyId from `AuthAuthenticated`; `ref.invalidate(ganttDataProvider)` refreshes arrows. E2E test #15 verifies DAO call with captured companion. |

**Score:** 18/18 truths verified

---

## Required Artifacts

### Plan 01 — Backend

| Artifact | Expected | Status | Details |
|----------|----------|--------|---------|
| `backend/app/features/projects/models.py` | TaskDependency + ProjectZone models | VERIFIED | `class TaskDependency(TenantScopedModel)` at line 339, `class ProjectZone` at line 316 |
| `backend/migrations/versions/0016_dependency_engine.py` | Migration 0016 with depends_on migration and drop | VERIFIED | `down_revision = "0015"`, `CREATE TABLE task_dependencies`, `DROP COLUMN depends_on` |
| `backend/app/features/projects/service.py` | DependencyService + ConflictService + ProjectZoneService | VERIFIED | All 3 classes present; `_find_cycle` DFS present |
| `backend/tests/test_phase_20_e2e.py` | 100+ lines, 10+ integration tests | VERIFIED | 636 lines, 24 async test functions |

### Plan 02 — Mobile Data Layer

| Artifact | Expected | Status | Details |
|----------|----------|--------|---------|
| `mobile/lib/core/database/tables/task_dependencies.dart` | TaskDependencies Drift table | VERIFIED | `class TaskDependencies extends Table` with predecessorTaskId, dependencyType |
| `mobile/lib/core/database/tables/project_zones.dart` | ProjectZones Drift table | VERIFIED | `class ProjectZones extends Table` with projectId |
| `mobile/lib/features/projects/data/task_dependency_dao.dart` | TaskDependencyDao with watch/insert/delete | VERIFIED | `watchByProject`, `watchPredecessors`, `insertWithSyncQueue` all present |
| `mobile/lib/core/database/app_database.dart` | schemaVersion 8, if (from < 8) migration | VERIFIED | `int get schemaVersion => 8` at line 124 |

### Plan 03 — Web Gantt

| Artifact | Expected | Status | Details |
|----------|----------|--------|---------|
| `web/src/components/gantt/GanttView.tsx` | SVAR Gantt wrapper with swim lanes | VERIFIED | `"use client"` + dynamic import of `@svar-ui/react-gantt`; trade scopes become swim lane rows |
| `web/src/app/(dashboard)/projects/[id]/gantt/page.tsx` | Gantt page route with GanttView | VERIFIED | Contains GanttView, CycleErrorDialog, ZoneManageModal, conflict banner, `useProjectDependencies` call |
| `web/src/components/gantt/CycleErrorDialog.tsx` | Dialog with cycle chain | VERIFIED | `"Dependency creates a loop"` at line 30; `role="alertdialog"` |
| `web/src/components/gantt/ZoneManageModal.tsx` | Zone list management modal | VERIFIED | `"Project Zones"` at line 78; `aria-label` on delete buttons |
| `web/tests/phase_20_gantt.spec.ts` | 50+ line Playwright E2E tests | VERIFIED | 486+ lines with dependency arrow fetch tests added by Plan 05 |

### Plan 04 — Mobile Gantt UI

| Artifact | Expected | Status | Details |
|----------|----------|--------|---------|
| `mobile/lib/features/projects/presentation/widgets/gantt_painter.dart` | CustomPainter with swim lanes + task bars + today line | VERIFIED | `class GanttPainter extends CustomPainter`; `_drawSwimLanes`, `_drawTaskBars`, `_drawTodayLine` |
| `mobile/lib/features/projects/presentation/widgets/dependency_arrow_painter.dart` | CustomPainter with bezier arrows | VERIFIED | `class DependencyArrowPainter extends CustomPainter`; `cubicTo` at line 67 |
| `mobile/lib/features/projects/presentation/screens/gantt_screen.dart` | GanttScreen with cycle dialog + conflict banner + DAO persistence | VERIFIED | Full DAO write wired; placeholder snackbar removed; all Plan 06 imports present |
| `mobile/test/e2e/phase_20_dependency_engine_e2e_test.dart` | 100+ lines, 15 E2E tests | VERIFIED | 916 lines, 15 testWidgets/test calls; test #15 captures companion and asserts companyId |

### Plan 05 — Web Gap Closure (Dependency Arrow Fetching)

| Artifact | Expected | Status | Details |
|----------|----------|--------|---------|
| `web/src/lib/api/projects.ts` | `fetchProjectDependencies` + `useProjectDependencies` exports | VERIFIED | Lines 215-241: `fetchProjectDependencies` uses `Promise.all` with deduplication; `useProjectDependencies` uses TanStack Query with sorted-taskId cache key |

### Plan 06 — Mobile Gap Closure (Dependency Persistence)

| Artifact | Expected | Status | Details |
|----------|----------|--------|---------|
| `mobile/lib/features/projects/presentation/screens/gantt_screen.dart` | `_handleDependencyCreated` calls `insertWithSyncQueue` | VERIFIED | Lines 192-212: `depDao.insertWithSyncQueue(TaskDependenciesCompanion(...))` called with Value-wrapped fields; companyId from `AuthAuthenticated`; `ref.invalidate` after write |

---

## Key Link Verification

| From | To | Via | Status | Details |
|------|----|-----|--------|---------|
| `backend/app/features/projects/service.py` | `models.py` | `DependencyService` uses `TaskDependency` | WIRED | `class DependencyService(TenantScopedService[TaskDependency])` |
| `backend/app/features/projects/router.py` | `service.py` | Router delegates to DependencyService | WIRED | `create_dependency` calls `DependencyService` |
| `mobile/lib/core/di/service_locator.dart` | `task_dependency_sync_handler.dart` | GetIt registration | WIRED | Lines 96-97: `registry.register(TaskDependencySyncHandler(...))` |
| `web/src/app/(dashboard)/projects/[id]/gantt/page.tsx` | `GET /api/v1/tasks/{id}/dependencies` | `useProjectDependencies(scopes)` TanStack Query hook | WIRED | Line 39: `useProjectDependencies(scopes)` called; line 50: result assigned to `allDependencies`; line 184: passed to GanttView. Commits c216958 + 74957d1. |
| `web/src/components/gantt/GanttView.tsx` | `@svar-ui/react-gantt` | `import { Gantt }` | WIRED | `import type { ITask, ILink }` + dynamic import |
| `mobile/lib/features/projects/presentation/screens/gantt_screen.dart` | `task_dependency_dao.dart` | `ref.read(taskDependencyDaoProvider)` | WIRED | Line 192: `final depDao = ref.read(taskDependencyDaoProvider)`; line 197: `depDao.insertWithSyncQueue(...)`. Commit c02a5ff. |
| `mobile/lib/features/projects/presentation/widgets/gantt_chart_widget.dart` | `gantt_painter.dart` | `CustomPaint(painter: GanttPainter(...))` | WIRED | `GanttPainter` at line 196 + `DependencyArrowPainter` at line 208 |

---

## Requirements Coverage

| Requirement | Source Plan | Description | Status | Evidence |
|-------------|-------------|-------------|--------|----------|
| PROJ-04 | 20-01, 20-02, 20-04, 20-06 | System enforces cross-trade task dependencies (Task A must finish before Task B starts) | SATISFIED | Backend: DependencyService creates FS/SS/FF/SE edges, blocked status auto-compute, cycle detection (422). Mobile: TaskDependencies table, DAOs, insertWithSyncQueue wired in `_handleDependencyCreated` (Plan 06). REQUIREMENTS.md shows [x] PROJ-04 = Complete. |
| PROJ-05 | 20-03, 20-04, 20-05 | GC can view project timeline with all trades on a Gantt-style chart showing dependencies | SATISFIED | Web Gantt page with SVAR swim lanes. `useProjectDependencies` fetches real dependency data via `Promise.all`; arrows passed to GanttView. Mobile GanttScreen with CustomPainter swim lanes and DependencyArrowPainter. REQUIREMENTS.md shows [x] PROJ-05 = Complete. |
| AI-06 | 20-01, 20-03, 20-04 | AI detects cross-trade conflicts (e.g., two trades needing same space on same day) | SATISFIED | `ConflictService.detect_conflicts()` self-join query. Web ConflictBadge rendered when conflicts > 0. Mobile conflict MaterialBanner computed by `ganttDataProvider`. REQUIREMENTS.md shows [x] AI-06 = Complete. |

---

## Anti-Patterns Found

No blocker anti-patterns remain. The two previously identified blockers are resolved:

| File | Previous Issue | Resolution |
|------|---------------|------------|
| `web/src/app/(dashboard)/projects/[id]/gantt/page.tsx` | `allDependencies` always `[]`; no-op loop | Replaced with `useProjectDependencies(scopes)` call; `allDependencies` populated from real API data (commit c216958) |
| `mobile/lib/features/projects/presentation/screens/gantt_screen.dart` | Placeholder snackbar "Dependency created (pending sync)" without DAO write | Replaced with `insertWithSyncQueue` call using `TaskDependenciesCompanion`; full error handling and `ref.invalidate` (commit c02a5ff) |

---

## Human Verification Required

### 1. Web Gantt Dependency Arrow Rendering

**Test:** Navigate to `/projects/{id}/gantt` in a browser with tasks that have FS dependencies. Verify arrows connect task bars on the SVAR Gantt chart.
**Expected:** Bezier arrows (SVAR ILink elements) visible between connected task bars with arrowheads.
**Why human:** SVG/canvas arrow rendering in SVAR Gantt requires a real browser. The fetch wiring is verified programmatically; visual rendering is not.

### 2. Mobile Pinch-to-Zoom on Device

**Test:** On a physical Android/iOS device, open the Gantt screen for a project with multiple trade scopes, perform a pinch-to-zoom gesture.
**Expected:** Canvas zooms from 0.5x to 3.0x smoothly; task bars remain aligned with swim lane headers.
**Why human:** InteractiveViewer presence verified in widget tree, but actual touch gesture responsiveness requires real device.

### 3. Conflict Badge Visual Display

**Test:** Create two tasks in the same project zone with the same due date from different trade scopes, open the Gantt page.
**Expected:** Amber MaterialBanner (amber-100 background, amber-600 icon) with trade names, zone name, and conflict date appears above the Gantt chart.
**Why human:** Color/styling cannot be verified programmatically.

---

## Gaps Summary

No gaps remain. Both gaps from the initial verification are closed:

**Gap 1 (CLOSED):** Web dependency arrows no longer use a hardcoded empty array. `useProjectDependencies(scopes)` (Plan 05) fetches per-task dependencies via `Promise.all` over all task IDs extracted from scopes, deduplicates by `dep.id`, and populates `allDependencies` for the SVAR Gantt `links` prop. Cache invalidation on dependency creation ensures arrows refresh after new edges are added.

**Gap 2 (CLOSED):** Mobile drag-to-connect now persists. `_handleDependencyCreated` (Plan 06) reads `companyId` from `ref.read(authNotifierProvider) as AuthAuthenticated`, constructs a `TaskDependenciesCompanion` with a UUID v4 `id`, calls `depDao.insertWithSyncQueue(...)`, and invalidates the Gantt provider so arrows refresh. An unauthenticated guard and error-handling `catch` block ensure user-facing feedback on failure. E2E test #15 captures the companion and asserts correct field values.

---

_Verified: 2026-03-22_
_Verifier: Claude (gsd-verifier)_
