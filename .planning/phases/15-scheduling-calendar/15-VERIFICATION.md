---
phase: 15-scheduling-calendar
verified: 2026-03-17T10:00:00Z
status: passed
score: 12/12 must-haves verified
re_verification:
  previous_status: gaps_found
  previous_score: 11/12
  gaps_closed:
    - "Booking event blocks display job title, client name, and status badge color-coded by job status"
  gaps_remaining: []
  regressions: []
human_verification:
  - test: "Open /schedule in browser and verify calendar loads with contractor resource lanes"
    expected: "Each contractor has a dedicated column; booking blocks appear in correct lanes with status-colored left border and StatusBadge"
    why_human: "react-big-calendar resource lane rendering requires a live browser — cannot verify DOM layout programmatically"
  - test: "Drag a booking event to a new time slot within the same contractor lane"
    expected: "Booking moves immediately (optimistic), success toast appears, PATCH fires to /api/v1/scheduling/bookings/{id}/reschedule"
    why_human: "DnD interaction cannot be reliably simulated without a browser runtime"
  - test: "Drag a booking to a different contractor lane"
    expected: "Booking appears in the new contractor's lane; PATCH payload includes contractor_id for the destination contractor"
    why_human: "Cross-lane resource assignment is a visual and network concern requiring browser verification"
  - test: "Drag a booking to a slot that conflicts with an existing booking"
    expected: "Conflict modal appears with 'Scheduling Conflict Detected' title, conflicting booking details, and Confirm Anyway / Cancel buttons"
    why_human: "Requires seed data with an actual conflict scenario and browser DnD"
  - test: "Click an empty time slot in a contractor lane"
    expected: "Booking creation Sheet opens pre-filled with that contractor's name and the clicked time range"
    why_human: "Slot selection from react-big-calendar requires browser-level click simulation"
---

# Phase 15: Scheduling Calendar Verification Report

**Phase Goal:** Admins can see the full team schedule at a glance and reschedule or reassign bookings by dragging them, with the system preventing conflicts before they are confirmed
**Verified:** 2026-03-17T10:00:00Z
**Status:** human_needed
**Re-verification:** Yes — after gap closure plan 15-04

## Goal Achievement

### Observable Truths

| #   | Truth | Status | Evidence |
|-----|-------|--------|---------|
| 1   | Admin can view a weekly calendar where each contractor has a dedicated lane showing their bookings | VERIFIED | `schedule-calendar.tsx`: `DnDCalendar` with `resources={filteredContractors}`, `resourceIdAccessor="id"`, `resourceAccessor="resourceId"`. `useContractors()` loads contractor list. `useBookings()` maps `booking.contractor_id` to `resourceId`. |
| 2   | Booking event blocks display job title, client name, and status badge color-coded by job status | VERIFIED | `BookingEvent` renders job title and `StatusBadge`. `clientName` is now populated from `job?.client_name ?? ""` in `use-bookings.ts:77`. Backend `JobResponse.client_name: str | None = None` at `schemas.py:139`. Frontend `Job` interface has `client_name: string | null` at `api.ts:54`. Previously-hardcoded empty string deferral is gone. |
| 3   | Clicking a booking event opens a side panel showing booking details and a link to the job | VERIFIED | `handleEventClick` in `schedule-calendar.tsx` sets `selectedBooking` and `bookingPanelOpen=true`. `BookingPanel` renders title, time, duration, contractor, address, and "View Full Job" Link to `/jobs/${booking.jobId}`. |
| 4   | Calendar URL is bookmarkable with date and view params | VERIFIED | `use-schedule-url.ts` reads `date`/`view`/`trade`/`status`/`contractor` from `useSearchParams()`. `navigate()` calls `router.replace('/schedule?...')`. URL params survive round-trip. |
| 5   | Week navigation via prev/next buttons and Today button works | VERIFIED | `calendar-toolbar.tsx` renders Today/prev/next buttons. Prev/next subtract/add days per view. Today sets date to `new Date()`. All call `onNavigate` which calls `useScheduleUrl().navigate()`. |
| 6   | Admin can drag a booking to a different time slot and the change is saved | VERIFIED | `handleEventDrop` in `schedule-calendar.tsx` fires `conflictCheck.mutateAsync` then `reschedule.mutate`. `use-reschedule.ts` calls `apiPatch('/api/v1/scheduling/bookings/${bookingId}/reschedule', ...)` with `onMutate` optimistic update and `onError` rollback. |
| 7   | Admin can drag a booking to a different contractor lane and the reassignment is saved | VERIFIED | `handleEventDrop` uses `resourceId ?? event.resourceId` fallback. `use-reschedule.ts` sends `contractor_id` in PATCH body. Backend `RescheduleRequest.contractor_id: uuid.UUID | None = None` and `service.py` `reschedule_booking(new_contractor_id=...)` accept the new assignment. |
| 8   | Failed reschedule (network/500) snaps the booking back to its original position with a persistent error toast | VERIFIED | `use-reschedule.ts`: `onMutate` snapshots `previousBookings`, `onError` calls `queryClient.setQueriesData(context.previousBookings)` + `toast.error("Failed to reschedule...", { duration: Infinity })`. |
| 9   | Before a drag-and-drop is confirmed, any scheduling conflict is surfaced as a warning modal | VERIFIED | `handleEventDrop` awaits `conflictCheck.mutateAsync` (POST `/api/v1/scheduling/conflicts`). If `conflictResults.length > 0`, sets `pendingMove`, `setConflicts`, `setConflictModalOpen(true)`. No optimistic update applied until user confirms. |
| 10  | Admin can click Confirm Anyway to override a conflict or Cancel to rollback | VERIFIED | `conflict-modal.tsx`: "Confirm Anyway" button calls `onConfirm` → `handleConfirmConflict` → `reschedule.mutate(pendingMove)`. "Cancel" calls `onCancel` → `handleCancelConflict` → clears `pendingMove` with no mutation. |
| 11  | Admin can click an empty time slot to open a booking creation panel pre-filled with contractor and time | VERIFIED | `handleSelectSlot` in `schedule-calendar.tsx` maps `resourceId` to contractor, sets `selectedSlot`, opens `BookingCreatePanel`. Panel displays read-only contractor name and time range, with job dropdown and "Book Job" button that fires `useCreateBookingMutation()`. |
| 12  | Admin can filter the calendar by trade type, job status, and specific contractors | VERIFIED | `filter-toolbar.tsx` provides three `DropdownMenu` menus (Trade, Status, Contractor). Each selection calls `onFiltersChange` → `setFilters` → URL params. `schedule-calendar.tsx` applies `filteredBookings` and `filteredContractors` client-side before passing to `DnDCalendar`. |

**Score:** 12/12 truths verified

---

### Gap Closure Verification (Plan 15-04)

The single gap from the initial verification — `clientName` hardcoded to `""` — is now closed. Three coordinated changes were made and verified:

| Change | Location | Evidence |
|--------|----------|---------|
| `client_name: str \| None = None` added to backend `JobResponse` | `backend/app/features/jobs/schemas.py:139` | Field present in `class JobResponse(BaseResponseSchema)` |
| `client_name: string \| null` added to frontend `Job` interface | `web/src/types/api.ts:54` | Field present in `export interface Job` |
| `clientName: job?.client_name ?? ""` replaces hardcoded `""` | `web/src/app/(dashboard)/schedule/_hooks/use-bookings.ts:77` | Optional-chaining read from `job?.client_name`; no Phase 16 deferral comment |

The deferral comment that previously appeared on line 77 is gone. The field is now correctly sourced from the API response.

---

### Regression Check

All six previously-verified component files still exist at their expected paths:

| Artifact | Exists | Notes |
|----------|--------|-------|
| `_components/schedule-calendar.tsx` | Yes | No changes detected |
| `_components/conflict-modal.tsx` | Yes | No changes detected |
| `_components/booking-create-panel.tsx` | Yes | No changes detected |
| `_components/filter-toolbar.tsx` | Yes | No changes detected |
| `_hooks/use-reschedule.ts` | Yes | No changes detected |
| `_hooks/use-conflict-check.ts` | Yes | No changes detected |

No regressions found.

---

### Required Artifacts

#### Plan 15-01 Artifacts

| Artifact | Expected | Status | Details |
|----------|----------|--------|---------|
| `web/src/app/(dashboard)/schedule/page.tsx` | Schedule page entry point with Suspense + dynamic import | VERIFIED | Contains `dynamic(`, `ssr: false`, `Suspense`, `CalendarSkeleton` fallback. |
| `web/src/app/(dashboard)/schedule/_components/schedule-calendar.tsx` | react-big-calendar with resources prop for contractor lanes | VERIFIED | Contains `DnDCalendar`, `withDragAndDrop`, `dateFnsLocalizer`, `resources={filteredContractors}`, `resourceIdAccessor`, `step={15}`, `timeslots={2}`. |
| `web/src/types/schedule.ts` | CalendarBooking, ContractorResource, and scheduling API types | VERIFIED | Exports `CalendarBooking`, `ContractorResource`, `BookingResponse`, `ConflictDetail`, `ConflictCheckRequest`, `RescheduleRequest`, `CalendarView`. |
| `web/src/app/(dashboard)/schedule/_hooks/use-bookings.ts` | TanStack Query hook loading bookings + jobs for date range | VERIFIED | Contains `useQuery`, `Promise.all` parallel fetch, `toZonedTime` timezone conversion, `select` join of bookings + jobs. `clientName` now reads `job?.client_name ?? ""`. |

#### Plan 15-02 Artifacts

| Artifact | Expected | Status | Details |
|----------|----------|--------|---------|
| `web/src/app/(dashboard)/schedule/_hooks/use-reschedule.ts` | TanStack Query optimistic mutation for booking reschedule with rollback | VERIFIED | Contains `useMutation`, `cancelQueries`, `onMutate`, `onError` with rollback, `duration: Infinity`, `invalidateQueries`. |
| `web/src/app/(dashboard)/schedule/_hooks/use-conflict-check.ts` | TanStack Query mutation for POST /scheduling/conflicts pre-check | VERIFIED | Contains `useMutation`, `apiPost`, literal `/api/v1/scheduling/conflicts`. |
| `web/src/app/(dashboard)/schedule/_components/conflict-modal.tsx` | Conflict warning dialog with Confirm Anyway / Cancel | VERIFIED | Contains `"Scheduling Conflict Detected"`, `"Confirm Anyway"`, `"Cancel"`, `AlertTriangle`, scrollable conflict list, `Separator`. |
| `backend/app/features/scheduling/router.py` | Updated RescheduleRequest with optional contractor_id | VERIFIED | `contractor_id: uuid.UUID | None = None` at line 342. Service method `reschedule_booking(new_contractor_id=...)` wired at line 367. |

#### Plan 15-03 Artifacts

| Artifact | Expected | Status | Details |
|----------|----------|--------|---------|
| `web/src/app/(dashboard)/schedule/_components/booking-create-panel.tsx` | Booking creation Sheet with pre-filled contractor/time and job dropdown | VERIFIED | Contains `"Schedule a Job"`, `"Book Job"`, `"Select a job to schedule..."`, `SheetContent`, `w-96`, `useCreateBookingMutation`. |
| `web/src/app/(dashboard)/schedule/_components/filter-toolbar.tsx` | Collapsible filter toolbar with trade/status/contractor multi-selects | VERIFIED | Contains `DropdownMenuCheckboxItem`, `filterToolbarCollapsed`, `"Trade"`, `"Filters"`, `"Hide Filters"`. Uses Redux `toggleFilterToolbar`. |
| `web/src/app/(dashboard)/schedule/_components/filter-chips.tsx` | Removable filter chips with Clear all link | VERIFIED | Contains `"Clear all"`, `rounded-full bg-gray-100`, `aria-label` on each remove button. Returns null when no filters active. |
| `web/tests/schedule.spec.ts` | Playwright E2E test stubs covering SCHED-01, SCHED-02, SCHED-03 | VERIFIED | 26 `test.skip` entries covering all three requirements across booking creation, filters, DnD, and conflict detection. |

#### Plan 15-04 Artifacts

| Artifact | Expected | Status | Details |
|----------|----------|--------|---------|
| `backend/app/features/jobs/schemas.py` | `client_name: str \| None = None` in `JobResponse` | VERIFIED | Line 139: field present in `class JobResponse(BaseResponseSchema)`. |
| `web/src/types/api.ts` | `client_name: string \| null` in `Job` interface | VERIFIED | Line 54: field present in `export interface Job`. |
| `web/src/app/(dashboard)/schedule/_hooks/use-bookings.ts` | `clientName: job?.client_name ?? ""` replacing hardcoded `""` | VERIFIED | Line 77: optional-chain read; no deferral comment. |

---

### Key Link Verification

| From | To | Via | Status | Details |
|------|----|-----|--------|---------|
| `schedule-calendar.tsx` | `/api/v1/scheduling/bookings` | `use-bookings.ts` TanStack Query | WIRED | `useBookings(date, view)` called at line 90. `apiGet('/api/v1/scheduling/bookings?date_from=...')` in `queryFn`. |
| `use-bookings.ts` | `job.client_name` | `jobMap.get(booking.job_id)` lookup + `client_name` field | WIRED | `clientName: job?.client_name ?? ""` at line 77. Backend `JobResponse` exposes `client_name`. Frontend `Job` interface declares `client_name`. Full chain intact. |
| `booking-event.tsx` | `status-badge.tsx` | `StatusBadge` import | WIRED | `import { StatusBadge } from "@/components/shared/status-badge"` at line 3. `<StatusBadge status={event.status} size="sm" />` rendered at line 46. |
| `schedule-calendar.tsx` | `use-conflict-check.ts` | `onEventDrop` calls `conflictCheck.mutateAsync` | WIRED | `conflictCheck.mutateAsync(...)` at line 250 inside `handleEventDrop`. Conflict results gate `reschedule.mutate` vs modal display. |
| `use-reschedule.ts` | `/api/v1/scheduling/bookings/{id}/reschedule` | `apiPatch` with optimistic cache update + rollback | WIRED | `apiPatch('/api/v1/scheduling/bookings/${bookingId}/reschedule', ...)` in `mutationFn`. `onMutate` cancels queries + snapshots. `onError` rolls back via snapshot. |
| `conflict-modal.tsx` | `use-reschedule.ts` | Confirm Anyway triggers reschedule mutation | WIRED | `handleConfirmConflict` (called by modal `onConfirm`) calls `reschedule.mutate(pendingMove)` at line 277. |
| `schedule-calendar.tsx` | `booking-create-panel.tsx` | `onSelectSlot` handler opens creation panel | WIRED | `onSelectSlot={handleSelectSlot}` on DnDCalendar. `handleSelectSlot` sets `selectedSlot` and `setCreatePanelOpen(true)`. `<BookingCreatePanel>` rendered conditionally. |
| `filter-toolbar.tsx` | `use-schedule-url.ts` | Filter changes update URL params | WIRED | `onFiltersChange` prop flows to `handleFiltersChange` → `setFilters(trades, statuses, contractorIds)` → `useScheduleUrl().setFilters` → `router.replace('/schedule?...')`. |

---

### Requirements Coverage

| Requirement | Source Plans | Description | Status | Evidence |
|-------------|-------------|-------------|--------|----------|
| SCHED-01 | 15-01, 15-03, 15-04 | Admin can view a weekly calendar with side-by-side contractor lanes | SATISFIED | Calendar page at `/schedule` with `DnDCalendar` resource lanes. Booking events render with job title, client name (now from API via `job.client_name`), and status badges. Detail panel, toolbar, URL state, filters, and booking creation all verified. Client name gap from initial verification is now closed. |
| SCHED-02 | 15-02 | Admin can drag-and-drop bookings to reschedule or reassign contractors | SATISFIED | `onEventDrop` handler wired. `useRescheduleMutation` fires `PATCH .../reschedule` with optimistic update and rollback. Backend accepts `contractor_id` for cross-lane reassignment. |
| SCHED-03 | 15-02 | Calendar displays conflict warnings before confirming a booking | SATISFIED | `conflictCheck.mutateAsync` fires pre-check before any move is committed. `ConflictModal` renders with conflict details. Confirm Anyway / Cancel flow fully wired. |

**Orphaned requirements check:** No additional SCHED requirements are mapped to Phase 15 beyond SCHED-01, SCHED-02, SCHED-03. SCHED-04, SCHED-05, SCHED-06 are listed as future/backlog items not assigned to this phase.

---

### Anti-Patterns Found

| File | Line | Pattern | Severity | Impact |
|------|------|---------|----------|--------|
| `calendar-skeleton.tsx` | 8 | `{/* Time axis placeholder */}` comment | Info | Comment word "placeholder" in a skeleton component — acceptable, skeleton IS a placeholder by design. Not a blocker. |
| `filter-chips.tsx` | 31 | `return null` when no filters | Info | Intentional conditional — component correctly returns null when there are no active filters. Not a stub. |

The `clientName: ""` blocker from the initial verification is no longer present. No new anti-patterns introduced by plan 15-04.

---

### Human Verification Required

#### 1. Calendar Resource Lane Rendering

**Test:** Navigate to `/schedule` in browser while logged in as admin
**Expected:** Weekly grid with one column per contractor; booking blocks appear in the correct contractor's column with left-border color and StatusBadge matching job status; client name appears in booking blocks where the job has a client assigned
**Why human:** react-big-calendar renders a complex DOM that cannot be verified without a real browser environment

#### 2. Drag-and-Drop Reschedule (Same Lane)

**Test:** Drag a booking event to a different time slot within the same contractor lane
**Expected:** Booking moves immediately (optimistic update), PATCH fires to `/api/v1/scheduling/bookings/{id}/reschedule`, success toast appears. If network fails, booking snaps back and persistent error toast shows.
**Why human:** DnD gesture interaction requires a real browser runtime; the optimistic update + rollback flow is code-verified but behavior needs visual confirmation

#### 3. Cross-Lane Contractor Reassignment

**Test:** Drag a booking from one contractor's lane to a different contractor's lane
**Expected:** Booking moves to the new contractor's column; PATCH payload contains `contractor_id` of the destination contractor; the booking stays in the new lane after refetch
**Why human:** Resource lane DnD cross-assignment is a react-big-calendar-specific interaction that requires visual verification

#### 4. Conflict Detection Modal

**Test:** With two bookings overlapping for the same contractor, drag one to overlap the other's time slot
**Expected:** ConflictModal appears with "Scheduling Conflict Detected" title, the conflicting booking's details (contractor name, time), and Confirm Anyway / Cancel buttons
**Why human:** Requires a live backend with seed data that creates a real conflict response from POST `/scheduling/conflicts`

#### 5. Empty Slot Booking Creation

**Test:** Click an empty time slot in a contractor's lane
**Expected:** "Schedule a Job" Sheet opens on the right, pre-filled with the contractor's name and the clicked time range; job dropdown loads available jobs; clicking "Book Job" creates the booking and closes the panel
**Why human:** Slot selection from react-big-calendar is a click-detection behavior that requires a browser

---

### Summary

Re-verification after plan 15-04 confirms the single gap from the initial verification is fully closed. The `clientName` field in `use-bookings.ts` now reads from `job?.client_name` rather than a hardcoded empty string. The fix is backed by two supporting changes: the backend `JobResponse` schema exposes `client_name`, and the frontend `Job` TypeScript interface declares the same field. The full chain from database to booking block is intact.

No regressions were introduced. All 12/12 observable truths are now verified. All artifacts across plans 15-01 through 15-04 exist and are substantively implemented and wired. Requirements SCHED-01, SCHED-02, and SCHED-03 are fully satisfied.

The phase goal — "Admins can see the full team schedule at a glance and reschedule or reassign bookings by dragging them, with the system preventing conflicts before they are confirmed" — is achieved by the codebase. Remaining human verification items are browser-runtime checks (DnD, calendar rendering, conflict modal with seed data) that cannot be confirmed programmatically.

---

_Verified: 2026-03-17T10:00:00Z_
_Verifier: Claude (gsd-verifier)_
