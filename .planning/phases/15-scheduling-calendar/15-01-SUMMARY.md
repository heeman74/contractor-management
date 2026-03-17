---
phase: 15-scheduling-calendar
plan: 01
subsystem: ui
tags: [react-big-calendar, tanstack-query, redux-toolkit, date-fns, date-fns-tz, scheduling, calendar, typescript]

# Dependency graph
requires:
  - phase: 13-web-foundation-and-auth
    provides: auth, API client (apiGet), Redux store factory pattern, TanStack Query setup
  - phase: 14-job-management
    provides: Job types, StatusBadge component, jobs page patterns
provides:
  - Weekly scheduling calendar at /schedule with contractor resource lanes
  - Booking event blocks with job title, status badge, and color-coded status accents
  - Read-only booking detail Sheet panel with "View Full Job" link
  - Bookmarkable URL state: /schedule?date=YYYY-MM-DD&view=week|day|month
  - CalendarToolbar with Today/prev/next navigation and week/day/month view switcher
  - Keyboard shortcuts: ArrowLeft/Right (navigate), T (today), Escape (close panel)
  - Skeleton loading state (CalendarSkeleton) during data fetch
  - Empty state when no contractors exist (with Add Contractors link)
  - Redux schedule slice with bookingPanelOpen, filterToolbarCollapsed, conflictModalOpen state
  - Playwright E2E test stubs for SCHED-01, SCHED-02, SCHED-03 (all skipped)
affects:
  - 15-02 (drag-and-drop reschedule builds on this calendar infrastructure)
  - 15-03 (conflict detection uses DnDCalendar events and booking panel)

# Tech tracking
tech-stack:
  added:
    - react-big-calendar@1.x (calendar library with resource lanes)
    - date-fns-tz@3.x (timezone conversion for UTC booking times)
    - "@types/react-big-calendar" (TypeScript types)
  patterns:
    - "dynamic import with ssr:false for react-big-calendar (SSR-incompatible CSS imports)"
    - "dateFnsLocalizer for react-big-calendar locale setup"
    - "withDragAndDrop wrapper typed with CalendarBooking + ContractorResource generics"
    - "EventProps wrapper component to adapt react-big-calendar types to custom event props"
    - "buttonVariants + Link pattern for link-styled buttons (base-ui Button has no asChild prop)"
    - "TanStack Query parallel Promise.all fetch for bookings + jobs"
    - "toZonedTime for UTC -> company timezone conversion in query select"

key-files:
  created:
    - web/src/types/schedule.ts
    - web/src/app/(dashboard)/schedule/page.tsx
    - web/src/app/(dashboard)/schedule/_components/schedule-calendar.tsx
    - web/src/app/(dashboard)/schedule/_components/calendar-toolbar.tsx
    - web/src/app/(dashboard)/schedule/_components/booking-event.tsx
    - web/src/app/(dashboard)/schedule/_components/booking-panel.tsx
    - web/src/app/(dashboard)/schedule/_components/contractor-lane-header.tsx
    - web/src/app/(dashboard)/schedule/_components/calendar-skeleton.tsx
    - web/src/app/(dashboard)/schedule/_hooks/use-bookings.ts
    - web/src/app/(dashboard)/schedule/_hooks/use-contractors.ts
    - web/src/app/(dashboard)/schedule/_hooks/use-schedule-url.ts
    - web/src/store/slices/schedule-slice.ts
    - web/tests/schedule.spec.ts
  modified:
    - web/src/store/index.ts (added schedule reducer)
    - web/package.json (added react-big-calendar, date-fns-tz)

key-decisions:
  - "page.tsx requires use client directive for ssr:false with next/dynamic in Next.js App Router — Server Components cannot use ssr:false"
  - "base-ui Button has no asChild prop — use buttonVariants + Link for link-styled buttons"
  - "BookingEventWrapper adapter component bridges react-big-calendar EventProps (with title, continuesPrior, etc.) to simple event prop expected by BookingEvent"
  - "withDragAndDrop typed as withDragAndDrop<CalendarBooking, ContractorResource>(Calendar) to avoid any-type resource accessor errors"
  - "CalendarView->View and View->CalendarView bidirectional mapping functions keep react-big-calendar internal types isolated"

patterns-established:
  - "CSS imports for react-big-calendar in the calendar component file (not layout) to keep SSR-incompatible styles co-located with ssr:false component"
  - "Inline <style> JSX block for react-big-calendar CSS overrides (.rbc-today, .rbc-current-time-indicator) — avoids global CSS pollution"
  - "Schedule URL state pattern: useScheduleUrl hook owns all URL param read/write for bookmarkable calendar state"
  - "Booking panel as controlled Sheet component with open/onOpenChange — consistent with shadcn/base-ui Sheet API"

requirements-completed:
  - SCHED-01

# Metrics
duration: 8min
completed: 2026-03-17
---

# Phase 15 Plan 01: Scheduling Calendar Infrastructure Summary

**react-big-calendar weekly calendar with contractor resource lanes, booking event blocks with status color coding, read-only detail Sheet, bookmarkable URL state, and full data loading infrastructure via TanStack Query**

## Performance

- **Duration:** 8 min
- **Started:** 2026-03-17T06:51:13Z
- **Completed:** 2026-03-17T06:59:00Z
- **Tasks:** 2
- **Files modified:** 15 (13 created, 2 modified)

## Accomplishments

- Weekly scheduling calendar at /schedule with per-contractor resource lanes using react-big-calendar DnDCalendar
- Booking event blocks display job title + client name + color-coded status badge matching StatusBadge component color map
- Clicking a booking opens a read-only Sheet panel with job details (time, duration, contractor, address) and a "View Full Job" link
- Toolbar with Today/prev/next buttons and Week/Day/Month view switcher, all URL-synchronized
- Keyboard shortcuts (ArrowLeft/Right for week navigation, T for today, Escape to close panel)
- TanStack Query hooks: useBookings (parallel fetch bookings+jobs, UTC->timezone conversion), useContractors (5-min stale), useScheduleUrl (URL state)
- Redux schedule slice with filterToolbarCollapsed, bookingPanelOpen, selectedBookingId, conflictModalOpen
- 11 Playwright test stubs for SCHED-01/02/03 (all test.skip, ready for Plan 15-02/03 implementation)

## Task Commits

Each task was committed atomically:

1. **Task 1: Types, hooks, Redux slice, and data loading infrastructure** - `8bd10b6` (feat)
2. **Task 2: Calendar page, custom components, toolbar, booking detail panel** - `5eab461` (feat)

## Files Created/Modified

- `web/src/types/schedule.ts` - CalendarBooking, ContractorResource, BookingResponse, ConflictDetail, CalendarView types
- `web/src/app/(dashboard)/schedule/page.tsx` - Schedule page with dynamic import (ssr:false) and Suspense
- `web/src/app/(dashboard)/schedule/_components/schedule-calendar.tsx` - Main calendar with DnDCalendar, resource lanes, keyboard shortcuts, empty state
- `web/src/app/(dashboard)/schedule/_components/calendar-toolbar.tsx` - Today/prev/next + view switcher toolbar
- `web/src/app/(dashboard)/schedule/_components/booking-event.tsx` - Event block with status border + bg tint + StatusBadge
- `web/src/app/(dashboard)/schedule/_components/booking-panel.tsx` - Read-only Sheet with job details + View Full Job link
- `web/src/app/(dashboard)/schedule/_components/contractor-lane-header.tsx` - Avatar + name + trade type for resource column header
- `web/src/app/(dashboard)/schedule/_components/calendar-skeleton.tsx` - Animate-pulse skeleton loading state
- `web/src/app/(dashboard)/schedule/_hooks/use-bookings.ts` - TanStack Query hook with parallel fetch + timezone conversion
- `web/src/app/(dashboard)/schedule/_hooks/use-contractors.ts` - TanStack Query hook for contractors with 5-min stale
- `web/src/app/(dashboard)/schedule/_hooks/use-schedule-url.ts` - URL state hook for date/view/filters
- `web/src/store/slices/schedule-slice.ts` - Redux slice for schedule UI state
- `web/src/store/index.ts` - Added schedule reducer
- `web/package.json` - Added react-big-calendar, date-fns-tz
- `web/tests/schedule.spec.ts` - 11 Playwright test stubs for SCHED-01/02/03

## Decisions Made

- **page.tsx needs `"use client"`**: Next.js App Router does not allow `ssr: false` in Server Components. Adding `"use client"` to page.tsx keeps the dynamic import pattern as specified.
- **base-ui Button has no `asChild` prop**: The project uses base-ui Button (not Radix). Used `buttonVariants + Link` pattern instead of `asChild` for link-styled buttons — consistent with other pages.
- **Typed DnDCalendar generics**: `withDragAndDrop<CalendarBooking, ContractorResource>` ensures string accessor keys are properly typed as `keyof ContractorResource` and `keyof CalendarBooking`.
- **EventProps adapter**: Created `BookingEventWrapper` to bridge react-big-calendar's `EventProps<CalendarBooking>` (which includes title, continuesPrior, etc.) to the simpler `{ event: CalendarBooking }` interface expected by `BookingEvent`.

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 1 - Bug] Fixed `??` and `||` operator precedence in use-contractors.ts**
- **Found during:** Task 1 (TypeScript compilation)
- **Issue:** `user.full_name ?? someString.trim() || "Unknown"` — TypeScript TS5076 error: cannot mix `??` and `||` without parentheses
- **Fix:** Added parentheses: `user.full_name ?? (someString.trim() || "Unknown")`
- **Files modified:** web/src/app/(dashboard)/schedule/_hooks/use-contractors.ts
- **Verification:** `npx tsc --noEmit` exits 0
- **Committed in:** 8bd10b6 (Task 1 commit)

**2. [Rule 3 - Blocking] Added `"use client"` to schedule/page.tsx**
- **Found during:** Task 2 (Next.js build)
- **Issue:** `ssr: false` with `next/dynamic` is not allowed in Server Components in Next.js App Router — Turbopack build error
- **Fix:** Added `"use client"` directive to page.tsx
- **Files modified:** web/src/app/(dashboard)/schedule/page.tsx
- **Verification:** `npx next build` succeeds, `/schedule` renders as static client page
- **Committed in:** 5eab461 (Task 2 commit)

**3. [Rule 1 - Bug] Replaced `asChild` pattern with `buttonVariants + Link`**
- **Found during:** Task 2 (TypeScript compilation)
- **Issue:** base-ui `Button` component has no `asChild` prop (unlike Radix). `asChild: true` causes TS2322 type error.
- **Fix:** Used `buttonVariants({ variant, size })` with Tailwind `cn()` on `<Link>` elements directly
- **Files modified:** booking-panel.tsx, schedule-calendar.tsx
- **Verification:** `npx tsc --noEmit` exits 0
- **Committed in:** 5eab461 (Task 2 commit)

---

**Total deviations:** 3 auto-fixed (1 type-safety bug, 1 blocking build error, 1 type error)
**Impact on plan:** All auto-fixes necessary for TypeScript correctness and Next.js build compatibility. No scope creep.

## Issues Encountered

None beyond the auto-fixed deviations above.

## User Setup Required

None - no external service configuration required.

## Next Phase Readiness

- Calendar infrastructure complete: DnDCalendar renders with resource lanes, bookings display from API, URL state works
- Plan 15-02 (drag-and-drop reschedule) can build directly on the DnDCalendar setup and useScheduleUrl hook
- Plan 15-03 (conflict detection) can use the existing booking panel and extend the conflict modal Redux state (conflictModalOpen is already in schedule-slice.ts)
- The E2E test stubs in schedule.spec.ts are ready to be filled in as each plan ships

---
*Phase: 15-scheduling-calendar*
*Completed: 2026-03-17*
