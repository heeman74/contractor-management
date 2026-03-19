---
phase: 17-crm-clients-and-contractors
plan: "04"
subsystem: ui
tags: [nextjs, react, typescript, tanstack-query, shadcn, tailwind, schedule-grid, drag-to-paint]

requires:
  - phase: 17-03
    provides: contractor profile page and scheduling API endpoints

provides:
  - CSS-grid drag-to-paint ScheduleGrid component (7 cols x 15 rows, pointer events)
  - Schedule editor page at /contractors/[id]/schedule
  - Date overrides section with shadcn Calendar, toggle, time pickers, confirmation dialog
  - apiPut convenience method in api-client.ts

affects:
  - 17-05 (phase 17 wrap-up and cross-linking)

tech-stack:
  added: []
  patterns:
    - "Drag-to-paint grid: onPointerDown sets pointer capture + paint mode, onPointerEnter paints if dragging, onPointerUp saves all changed days"
    - "Per-day auto-save: collect changedDays during drag, fire mutations on pointerUp"
    - "hoursToBlocks: converts Set<hour> to contiguous TimeBlock[] for API"
    - "Select<string> generic required for base-ui Select onValueChange null handling"
    - "Calendar modifiers/modifiersClassNames for override date highlighting"

key-files:
  created:
    - web/src/components/crm/schedule-grid.tsx
    - web/src/app/(dashboard)/contractors/[id]/schedule/page.tsx
  modified:
    - web/src/lib/api-client.ts

key-decisions:
  - "Select<string> generic annotation on base-ui Select to handle null from onValueChange (consistent with Phase 16 pattern)"
  - "ScheduleGrid initialSchedule converted from WeeklyBlock[] API response to Record<number, number[]> hour-index sets in useMemo on page"
  - "Date override list deduplicates by override_date since API returns one row per block_index"
  - "changedDays Set accumulated during drag; all saves fired in single pointerUp handler"

patterns-established:
  - "Drag-to-paint pointer event pattern with setPointerCapture for cell capture during drag"
  - "Per-day save fires after drag ends (pointerUp), not on each individual cell toggle"

requirements-completed:
  - CONTR-03
  - CONTR-04

duration: 3min
completed: 2026-03-19
---

# Phase 17 Plan 04: Schedule Editor Summary

**CSS-grid drag-to-paint ScheduleGrid (7-col x 15-row, pointer events) with per-day auto-save, plus date overrides calendar with shadcn Calendar, unavailable toggle, and custom time pickers**

## Performance

- **Duration:** ~3 min
- **Started:** 2026-03-19T05:38:18Z
- **Completed:** 2026-03-19T05:41:19Z
- **Tasks:** 3 (Tasks 1, 2a, 2b)
- **Files modified:** 3

## Accomplishments

- ScheduleGrid component with pointer-event drag-to-paint: cells fill indigo-500 when painted, gray-100 when empty. Uses `setPointerCapture` for smooth drag continuity across cells.
- Per-day auto-save fires PUT `/scheduling/schedules/{id}/weekly/{dow}` on pointerUp with success/error toasts.
- Schedule editor page at `/contractors/[id]/schedule` with breadcrumb, weekly grid section, and date overrides section.
- Date overrides calendar highlights existing override dates in indigo; override form shows unavailable toggle or custom hour blocks; remove override flows through confirmation dialog.

## Task Commits

1. **Task 1: ScheduleGrid component** - `25ebb7b` (feat)
2. **Task 2a+2b: Schedule editor page** - `254064c` (feat)

## Files Created/Modified

- `web/src/components/crm/schedule-grid.tsx` - CSS-grid drag-to-paint component with pointer events and per-day save mutations
- `web/src/app/(dashboard)/contractors/[id]/schedule/page.tsx` - Schedule editor page with weekly grid and date overrides sections
- `web/src/lib/api-client.ts` - Added `apiPut<T>` convenience method

## Decisions Made

- `Select<string>` generic annotation needed on base-ui Select component to handle `string | null` from `onValueChange` — consistent with Phase 16 pattern documented in STATE.md.
- Date override list deduplicates entries by `override_date` since the API returns one row per `block_index` (multiple blocks on one day appear as multiple rows in the response).
- `changedDays` set is accumulated during drag so all changed days are saved in a single batch on pointerUp rather than mid-drag.

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 1 - Bug] Fixed base-ui Select<string> null type error**
- **Found during:** Task 2b (date overrides time pickers)
- **Issue:** base-ui Select `onValueChange` callback types `v` as `string | null`; passing directly to `updateCustomBlock` caused TS2345 error
- **Fix:** Added `Select<string>` generic annotation and null guard `v != null && updateCustomBlock(...)` on both start/end hour selects
- **Files modified:** `web/src/app/(dashboard)/contractors/[id]/schedule/page.tsx`
- **Verification:** `npx tsc --noEmit` exits 0
- **Committed in:** `254064c` (Task 2 commit)

---

**Total deviations:** 1 auto-fixed (Rule 1 - Bug)
**Impact on plan:** Required for TypeScript compilation. No scope change.

## Issues Encountered

None beyond the Select null type error above.

## User Setup Required

None - no external service configuration required.

## Next Phase Readiness

- Schedule editor (CONTR-03, CONTR-04) is complete.
- Ready for Phase 17 Plan 05: cross-page linking (job detail sidebar, quote/invoice sidebar contractor/client links, schedule calendar lane headers).

---
*Phase: 17-crm-clients-and-contractors*
*Completed: 2026-03-19*
