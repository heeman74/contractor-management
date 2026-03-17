---
phase: 15-scheduling-calendar
plan: "02"
subsystem: web/schedule
tags: [drag-and-drop, reschedule, conflict-check, optimistic-update, tanstack-query]
dependency_graph:
  requires: ["15-01"]
  provides: ["DnD reschedule with conflict pre-check", "cross-lane contractor reassignment"]
  affects: ["web/schedule calendar", "backend scheduling endpoint"]
tech_stack:
  added: []
  patterns:
    - "TanStack Query optimistic mutation with rollback (onMutate/onError/onSettled)"
    - "react-big-calendar EventInteractionArgs type bridging (stringOrDate coercion)"
    - "Conflict pre-check before optimistic update (hold-until-confirmed pattern)"
key_files:
  created:
    - web/src/app/(dashboard)/schedule/_hooks/use-reschedule.ts
    - web/src/app/(dashboard)/schedule/_hooks/use-conflict-check.ts
    - web/src/app/(dashboard)/schedule/_components/conflict-modal.tsx
  modified:
    - backend/app/features/scheduling/router.py
    - backend/app/features/scheduling/service.py
    - web/src/app/(dashboard)/schedule/_components/schedule-calendar.tsx
decisions:
  - "EventInteractionArgs.start/end are stringOrDate — coerce to Date before use to satisfy TypeScript strict mode"
  - "Conflict pre-check fires before any optimistic update — only apply optimistic update when no conflicts or user confirms"
  - "Persistent error toast (duration: Infinity) on both conflict-check failure and reschedule failure per project decision"
metrics:
  duration: "~10 minutes"
  completed_date: "2026-03-17"
  tasks_completed: 2
  files_changed: 6
---

# Phase 15 Plan 02: DnD Rescheduling with Conflict Pre-Check Summary

**One-liner:** Drag-and-drop rescheduling with optimistic update + rollback, conflict pre-check modal, and cross-lane contractor reassignment.

## What Was Built

### Backend
- Added `contractor_id: uuid.UUID | None = None` to `RescheduleRequest` in `router.py` — enables cross-lane DnD reassignment without breaking existing callers
- Updated `SchedulingService.reschedule_booking()` in `service.py` to accept `new_contractor_id` parameter — uses `new_contractor_id if new_contractor_id else existing.contractor_id`

### Web Hooks
- `use-conflict-check.ts`: `useConflictCheck()` mutation — fires `POST /api/v1/scheduling/conflicts` as a read-only pre-check before committing any drag-and-drop move
- `use-reschedule.ts`: `useRescheduleMutation()` mutation with full optimistic update lifecycle:
  - `onMutate`: cancels outgoing refetches, snapshots cache, applies optimistic update
  - `onError`: rolls back to snapshot + persistent error toast (`duration: Infinity`)
  - `onSuccess`: success toast with contractor name + time
  - `onSettled`: always invalidates bookings query for server consistency

### Web Components
- `conflict-modal.tsx`: `ConflictModal` dialog with `AlertTriangle` icon, scrollable conflict list (contractor name, job ID, time range), `Separator`, and `Confirm Anyway` / `Cancel` footer buttons

### Calendar Integration
- `schedule-calendar.tsx`:
  - `handleEventDrop` using `EventInteractionArgs<CalendarBooking>` type (fixes `stringOrDate` TS error) — fires conflict pre-check, either saves immediately (no conflicts) or holds in `pendingMove` state and shows modal
  - `handleConfirmConflict` — dispatches reschedule mutation for pending move
  - `handleCancelConflict` — clears pending state with no mutation (no optimistic update was applied)
  - `onEventDrop={handleEventDrop}`, `draggableAccessor={() => true}`, `resizable={false}` on DnDCalendar
  - DnD drag ghost CSS: `opacity: 0.7`, `outline: 2px dashed`
  - Escape key handler: closes conflict modal first, then booking panel
  - `ConflictModal` rendered alongside `BookingPanel`

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 1 - Bug] Fixed EventInteractionArgs type mismatch**
- **Found during:** Task 2 (TypeScript compilation)
- **Issue:** `EventInteractionArgs.start/end` is `stringOrDate` (not `Date`) per react-big-calendar types — handler signature `{ start: Date; end: Date }` failed TS compilation
- **Fix:** Import `EventInteractionArgs` type from `react-big-calendar/lib/addons/dragAndDrop`, coerce `start`/`end` with `instanceof Date ? start : new Date(start)` before use
- **Files modified:** `schedule-calendar.tsx`
- **Commit:** 4f25552

## Verification Results

- `npx tsc --noEmit`: PASS (0 errors)
- `npx next build`: PASS (all 11 routes compiled)
- `uv run python -c "from app.features.scheduling.router import RescheduleRequest; r = RescheduleRequest(..., contractor_id='...'); print('OK:', r.contractor_id)"`: PASS
- `ruff check` + `ruff format --check`: PASS
- Backend integration tests: Pre-existing DB connection error in test infrastructure (unrelated to this plan's changes)

## Self-Check: PASSED

All 5 key files exist on disk. Both task commits verified in git history:
- `a1e2db5` — feat(15-02): backend reschedule endpoint update + DnD hooks and conflict modal
- `4f25552` — feat(15-02): wire DnD handlers into calendar with conflict pre-check flow
