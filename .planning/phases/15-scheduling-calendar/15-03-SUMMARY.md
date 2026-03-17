---
phase: 15-scheduling-calendar
plan: "03"
subsystem: web-schedule
tags: [scheduling, calendar, booking-creation, filters, e2e-stubs]
dependency_graph:
  requires: ["15-02"]
  provides: ["booking-create-panel", "filter-toolbar", "filter-chips", "e2e-stubs"]
  affects: ["schedule-calendar.tsx", "schedule/page.tsx"]
tech_stack:
  added: []
  patterns:
    - "useMutation hook for POST /api/v1/scheduling/bookings"
    - "Client-side filtering applied before passing events/resources to react-big-calendar"
    - "URL param filter persistence via useScheduleUrl setFilters/clearFilters"
    - "Redux schedule slice filterToolbarCollapsed for collapsible filter row"
key_files:
  created:
    - web/src/app/(dashboard)/schedule/_hooks/use-create-booking.ts
    - web/src/app/(dashboard)/schedule/_components/booking-create-panel.tsx
    - web/src/app/(dashboard)/schedule/_components/filter-toolbar.tsx
    - web/src/app/(dashboard)/schedule/_components/filter-chips.tsx
  modified:
    - web/src/app/(dashboard)/schedule/_components/schedule-calendar.tsx
    - web/tests/schedule.spec.ts
decisions:
  - "SlotInfo.resourceId typed as string|number|undefined — coerce to String() before contractor lookup to satisfy TypeScript strict mode"
  - "DropdownMenuTrigger styled with inline Tailwind classes (no asChild) — consistent with Phase 15 base-ui decision"
  - "Filter logic is client-side only — server-side filter params not sent to bookings API (fast UX, acceptable for current data volumes)"
metrics:
  duration: "7 minutes"
  completed_date: "2026-03-17"
  tasks_completed: 2
  tasks_total: 2
  files_created: 4
  files_modified: 2
---

# Phase 15 Plan 03: Booking Creation, Filters, and E2E Stubs Summary

**One-liner:** Click-to-book from empty slots via Sheet panel + collapsible trade/status/contractor filter toolbar with removable chips and URL-persisted state.

## Tasks Completed

| # | Task | Commit | Files |
|---|------|--------|-------|
| 1 | Booking creation panel + create booking hook | 2b53cd8 | use-create-booking.ts, booking-create-panel.tsx, schedule-calendar.tsx |
| 2 | Filter toolbar, filter chips, E2E test finalization | e8e6a0d | filter-toolbar.tsx, filter-chips.tsx, schedule-calendar.tsx, schedule.spec.ts |

## What Was Built

### Task 1: Booking Creation

- **`use-create-booking.ts`** — `useCreateBookingMutation()` hook wrapping `POST /api/v1/scheduling/bookings` via TanStack Query `useMutation`. On success: `toast.success` + `invalidateQueries(["bookings"])`. On error: persistent `toast.error`.

- **`booking-create-panel.tsx`** — Sheet component (`w-96`) that pre-fills contractor name and time slot. Loads bookable jobs (status=quote|scheduled) via `useQuery`. Job select dropdown with placeholder and no-jobs empty state. Fires `createBooking.mutate()` on "Book Job" click; shows inline error on failure.

- **`schedule-calendar.tsx`** — Added `handleSelectSlot` callback on `onSelectSlot` prop. Coerces `resourceId` from `string | number | undefined` to `string`. Opens `BookingCreatePanel` with pre-filled slot data.

### Task 2: Filters + E2E

- **`filter-toolbar.tsx`** — Collapsible filter bar using Redux `filterToolbarCollapsed` state. Three `DropdownMenu` menus for Trade, Status, Contractor. Trade options derived from contractor list, Status hardcoded to 5 options. Each selection immediately calls `onFiltersChange` → `setFilters` → URL update.

- **`filter-chips.tsx`** — Renders removable chips for each active filter. "Clear all" link. Only renders when at least one filter is active.

- **`schedule-calendar.tsx`** — Added client-side `filteredBookings` and `filteredContractors` derived state. Passes filtered data to `DnDCalendar`. `handleFiltersChange`, `handleRemoveTrade`, `handleRemoveStatus`, `handleRemoveContractor` callbacks all delegate to `setFilters`.

- **`schedule.spec.ts`** — Expanded from 9 to 26 `test.skip` stubs covering SCHED-01 (booking creation + filtering + views), SCHED-02 (drag-drop), SCHED-03 (conflict detection). All 26 run and skip cleanly.

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 1 - Bug] SlotInfo.resourceId type mismatch**
- **Found during:** Task 1 TypeScript check
- **Issue:** `react-big-calendar`'s `SlotInfo.resourceId` is typed as `string | number | undefined`, but handler expected `string | undefined`. TypeScript strict mode rejected it.
- **Fix:** Changed handler parameter type to `string | number | undefined` and coerced with `String(resourceId)` before use.
- **Files modified:** schedule-calendar.tsx
- **Commit:** 2b53cd8 (part of task commit)

## Self-Check: PASSED

Files verified present:
- web/src/app/(dashboard)/schedule/_hooks/use-create-booking.ts ✓
- web/src/app/(dashboard)/schedule/_components/booking-create-panel.tsx ✓
- web/src/app/(dashboard)/schedule/_components/filter-toolbar.tsx ✓
- web/src/app/(dashboard)/schedule/_components/filter-chips.tsx ✓

Commits verified:
- 2b53cd8: feat(15-03): booking creation panel from empty slot click ✓
- e8e6a0d: feat(15-03): filter toolbar, filter chips, and E2E test stubs ✓
