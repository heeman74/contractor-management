---
phase: 20-dependency-engine
plan: 03
subsystem: ui
tags: [react, gantt, svar, playwright, typescript, tanstack-query]

# Dependency graph
requires:
  - phase: 20-01
    provides: "Backend task dependency, zone, and conflict endpoints"

provides:
  - "Gantt page at /projects/[id]/gantt with SVAR React Gantt trade swim lanes"
  - "Dependency arrow visualization between task bars"
  - "ConflictBadge component for zone/date overlap warnings"
  - "CycleErrorDialog showing cycle chain on 422 dependency errors"
  - "DependencyTypeSelect popover for FS/SS/FF/SE with lag/lead"
  - "ZoneManageModal for adding/deleting project zones"
  - "ProjectTree blocked task status badges"
  - "TypeScript types in web/src/types/dependencies.ts"
  - "11 passing Playwright E2E tests for Gantt page"

affects:
  - "21-ai-planner: AI suggestions displayed on Gantt timeline"
  - "22-contractor-mobile: Task dependencies visible on mobile Gantt"

# Tech tracking
tech-stack:
  added: ["@svar-ui/react-gantt@2.5.2"]
  patterns:
    - "SVAR Gantt wrapped in next/dynamic with ssr:false to avoid SSR hydration issues"
    - "ILink type mapping: FS→e2s, SS→s2s, FF→e2e, SE→s2e"
    - "Conflict task highlighting via css class on ITask objects"
    - "Playwright mock routes ordered most-specific-first to prevent false matches"

key-files:
  created:
    - "web/src/types/dependencies.ts"
    - "web/src/components/gantt/GanttView.tsx"
    - "web/src/components/gantt/ConflictBadge.tsx"
    - "web/src/components/gantt/CycleErrorDialog.tsx"
    - "web/src/components/gantt/DependencyTypeSelect.tsx"
    - "web/src/components/gantt/ZoneManageModal.tsx"
    - "web/src/app/(dashboard)/projects/[id]/gantt/page.tsx"
    - "web/tests/phase_20_gantt.spec.ts"
  modified:
    - "web/src/types/projects.ts — added zone_id/start_date, removed depends_on from TaskResponse"
    - "web/src/lib/api/projects.ts — added dependencies/zones/conflicts API functions"
    - "web/src/app/(dashboard)/projects/components/ProjectTree.tsx — blocked task StatusBadge"
    - "web/src/app/(dashboard)/projects/components/TaskDetail.tsx — removed depends_on UI"

key-decisions:
  - "SVAR Gantt loaded via next/dynamic (ssr:false) to avoid SSR issues with browser-only APIs"
  - "ILink.type cast via as ILink['type'] since TLinkType not re-exported from @svar-ui/react-gantt"
  - "Task conflict highlighting via css class key on ITask (SVAR doesn't support taskStyle prop)"
  - "Playwright route mocks ordered: conflicts/zones before single-project to prevent path substring collision"
  - "Array.isArray() defensive check on conflicts/zones API data prevents 'not iterable' runtime errors"

patterns-established:
  - "SVAR Gantt dependency type mapping: backend FS/SS/FF/SE ↔ SVAR e2s/s2s/e2e/s2e"
  - "Playwright strict mode: use .first() when SVAR renders labels in grid AND chart area"
  - "Route mock ordering: exact paths before substring-matching paths"

requirements-completed: [PROJ-05, AI-06]

# Metrics
duration: 45min
completed: 2026-03-22
---

# Phase 20 Plan 03: Dependency Engine Web Gantt Summary

**SVAR React Gantt timeline page with trade swim lanes, dependency arrows, conflict badges, cycle error dialog, zone management, and 11 Playwright E2E tests**

## Performance

- **Duration:** ~45 min
- **Started:** 2026-03-22T03:03:00Z
- **Completed:** 2026-03-22T03:48:51Z
- **Tasks:** 2
- **Files modified:** 13

## Accomplishments
- Gantt page at `/projects/[id]/gantt` with SVAR React Gantt, trade swim lanes (summary rows per trade scope), dependency arrows via ILink, and zoom controls (Day/Week/Month)
- Conflict banner with ConflictBadge showing trade names, zone, and date for each overlap
- CycleErrorDialog with "Dependency creates a loop" message and full cycle chain on 422 responses
- ZoneManageModal with add/delete zones, duplicate name validation, and inline delete confirmation
- ProjectTree updated to show red StatusBadge next to blocked tasks
- 11 Playwright E2E tests: gantt page load, swim lane labels, dependency arrows, conflict badges (shown + data), cycle dialog trigger, zone modal open/close, zoom controls (visibility + active state), blocked task badge

## Task Commits

Each task was committed atomically:

1. **Task 1: TypeScript types, SVAR Gantt install, components** - `da3618d` (feat)
2. **Task 2: Gantt page route, ProjectTree, Playwright tests** - `eea4138` (feat)

## Files Created/Modified
- `web/src/types/dependencies.ts` - TaskDependencyResponse, ProjectZoneResponse, ConflictRecord, CycleErrorDetail
- `web/src/types/projects.ts` - Added zone_id/start_date, removed depends_on from TaskResponse
- `web/src/components/gantt/GanttView.tsx` - SVAR Gantt wrapper with swim lanes, dependency arrows, zoom
- `web/src/components/gantt/ConflictBadge.tsx` - Yellow badge with AlertTriangle icon, role=alert
- `web/src/components/gantt/CycleErrorDialog.tsx` - AlertDialog with cycle chain display
- `web/src/components/gantt/DependencyTypeSelect.tsx` - FS/SS/FF/SE select + lag/lead input popover
- `web/src/components/gantt/ZoneManageModal.tsx` - Zone list with add/delete and duplicate validation
- `web/src/app/(dashboard)/projects/[id]/gantt/page.tsx` - Gantt page route with full data flow
- `web/src/app/(dashboard)/projects/components/ProjectTree.tsx` - Blocked task StatusBadge
- `web/src/app/(dashboard)/projects/components/TaskDetail.tsx` - Removed depends_on UI (field removed from type)
- `web/src/lib/api/projects.ts` - Added createTaskDependency, fetchProjectZones, fetchProjectConflicts, hooks
- `web/tests/phase_20_gantt.spec.ts` - 11 Playwright E2E tests (all passing)
- `web/package.json` / `web/package-lock.json` - @svar-ui/react-gantt@2.5.2

## Decisions Made
- SVAR Gantt loaded via `next/dynamic` with `ssr: false` to avoid SSR hydration issues with browser-only canvas/DOM APIs
- `TLinkType` not re-exported from `@svar-ui/react-gantt` so cast via `as ILink["type"]`
- SVAR doesn't support `taskStyle` prop — conflict task highlighting done via `css` key on ITask objects
- Playwright route mocks ordered most-specific-first (conflicts/zones exact paths before general project ID substring match) to prevent false route fulfillment

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 1 - Bug] Fixed TaskDetail.tsx using removed depends_on field**
- **Found during:** Task 1 (after updating TaskResponse type)
- **Issue:** TaskDetail.tsx rendered a "Depends On" section using `task.depends_on` which no longer exists on the type
- **Fix:** Replaced the section with a comment noting dependencies are now managed via Gantt view
- **Files modified:** `web/src/app/(dashboard)/projects/components/TaskDetail.tsx`
- **Verification:** TypeScript check passes with no errors on this file
- **Committed in:** `da3618d` (Task 1 commit)

**2. [Rule 1 - Bug] Fixed taskStyle prop not existing on SVAR Gantt component**
- **Found during:** Task 1 TypeScript check
- **Issue:** Plan specified `taskStyle` callback prop on Gantt component but SVAR doesn't expose that prop
- **Fix:** Applied conflict highlighting via `css` key on ITask objects (SVAR's supported approach)
- **Files modified:** `web/src/components/gantt/GanttView.tsx`
- **Verification:** TypeScript check passes, Playwright tests pass
- **Committed in:** `da3618d` (Task 1 commit)

**3. [Rule 2 - Missing Critical] Added Array.isArray() defensive checks for API data**
- **Found during:** Task 2 (runtime error "conflicts is not iterable")
- **Issue:** TanStack Query returns `{}` (not `[]`) when fallback mock returns object; code destructured with `= []` default but TanStack only applies default for `undefined`
- **Fix:** Added `Array.isArray(conflictsRaw) ? conflictsRaw : []` guards
- **Files modified:** `web/src/app/(dashboard)/projects/[id]/gantt/page.tsx`
- **Verification:** All Playwright tests pass
- **Committed in:** `eea4138` (Task 2 commit)

**4. [Rule 1 - Bug] Fixed Playwright route mock ordering causing wrong data**
- **Found during:** Task 2 test execution
- **Issue:** `/api/v1/projects/{id}/conflicts` was being matched by the general `/api/v1/projects/{id}` handler before the specific conflicts handler
- **Fix:** Reordered mock conditions: conflicts/zones exact match → single project → list
- **Files modified:** `web/tests/phase_20_gantt.spec.ts`
- **Verification:** Conflict badge tests pass
- **Committed in:** `eea4138` (Task 2 commit)

---

**Total deviations:** 4 auto-fixed (2 Rule 1 bugs, 1 Rule 2 missing critical, 1 Rule 1 test bug)
**Impact on plan:** All auto-fixes necessary for correctness. No scope creep.

## Issues Encountered

**Pre-existing TypeScript build errors (out of scope, logged to deferred-items.md):**
- `web/src/app/(dashboard)/contractors/_components/create-contractor-dialog.tsx:208` — Select `onValueChange` receives `string | null` but state setter typed as `string`
- `web/src/app/(dashboard)/jobs/_components/create-job-dialog.tsx` — Same issue (4 instances)
These were present before Phase 20-03 and prevent `npx next build` from succeeding. All new Phase 20-03 files compile without TypeScript errors (verified via `npx tsc --noEmit`).

## Next Phase Readiness
- Web Gantt timeline page is live at `/projects/{id}/gantt`
- Phase 21 (AI Planner) can add AI-suggested task reordering to the Gantt view
- Dependencies infrastructure ready for Phase 22 (contractor mobile) to consume
- Note: Pre-existing build errors in contractors/jobs components should be fixed before Phase 21 web work

## Self-Check: PASSED

All created files exist on disk. Both task commits (da3618d, eea4138) are present in git history.

---
*Phase: 20-dependency-engine*
*Completed: 2026-03-22*
