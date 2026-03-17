# Phase 15: Scheduling Calendar - Research

**Researched:** 2026-03-16
**Domain:** React calendar with resource lanes, drag-and-drop rescheduling, conflict detection
**Confidence:** HIGH (library API verified; patterns confirmed via official types and source)

<user_constraints>
## User Constraints (from CONTEXT.md)

### Locked Decisions
- **Library**: react-big-calendar with `resources` prop for contractor lanes
- **Localizer**: dateFnsLocalizer
- **SSR**: dynamic import with `ssr: false`
- **Data layer**: TanStack Query for all API data; Redux for UI state only (filter state, view preferences)
- **Booking display**: job title + client name + StatusBadge, color-coded by job status
- **Overflow**: text overflows block boundary (no truncation, no enforced minimum height)
- **Click action**: opens Sheet (side panel) — booking details + job summary, read-only with "View Job" link
- **Non-working hours**: grayed-out bands per lane
- **Multi-day bookings**: "Day X/Y" badge on each block
- **Drag pre-check**: POST /scheduling/conflicts before save; if clear → PATCH immediately; if conflicted → modal dialog
- **Conflict modal**: centered Dialog with conflicting booking details, "Confirm Anyway" + "Cancel" buttons
- **15-minute snap**: `step={15}` during drag
- **Success**: booking animates to new lane/time, success toast ("Booking moved to [Contractor] at [time]")
- **Failure (network/500)**: snap back to original, persistent error toast (`{ duration: Infinity }`)
- **Escape key**: cancels in-progress drag, snaps back
- **Lane headers**: avatar circle + contractor name per column
- **Horizontal scroll**: sticky time axis on left; contractor headers pinned (sticky) at top
- **Default order**: alphabetical by contractor name
- **Resizable column widths**: admin can drag column borders
- **Virtualize**: off-screen lanes for 20+ contractors
- **Views**: Week (default), Day, Month — switcher buttons in toolbar
- **Toolbar**: Today + prev/next + date picker + view switcher + Export dropdown
- **URL state**: `/schedule?date=2026-03-16&view=week` (bookmarkable, survives refresh)
- **Default range**: 6am–8pm business hours
- **Auto-scroll**: to current time on load (week and day views)
- **"Now" line**: red horizontal line across all lanes, updates every 60 seconds
- **Today header**: subtle light blue background tint
- **Day view**: all contractors shown; toggle to single-contractor by clicking lane header
- **Day view (single-contractor)**: free windows as green-tinted zones, blocked intervals as distinct markers
- **Month view**: day cells with booking counts; click navigates to Day view
- **Click empty slot**: opens booking creation panel, pre-fills contractor + time; job dropdown of "Scheduled"/"Quote" jobs
- **No new job creation from calendar** — only scheduling existing jobs
- **Filters**: trade type, job status, specific contractors (multi-select); second-row collapsible toolbar
- **Filter chips**: removable tags below toolbar with "Clear all"; filter state in URL params
- **PDF export**: server-side WeasyPrint (Phase 16 pattern); CSV export for current view
- **Export scope**: current view only
- **Timezone**: company timezone from `companies.timezone` column; backend stores UTC, frontend converts; fallback to browser tz
- **Skeleton**: full calendar grid with pulsing skeleton blocks while loading
- **refetchOnWindowFocus**: TanStack Query enabled
- **Debounced fetch**: update grid immediately (skeleton), debounce API call by 300ms on rapid week navigation
- **No-contractors empty state**: illustration + message + link to Contractors page
- **Keyboard shortcuts**: Left/Right arrows for prev/next week/day; "T" for today; Escape cancels drag
- **Tablet (768-1024px)**: touch drag-and-drop, horizontal scroll, mini sidebar auto-collapses
- **Mobile (<768px)**: forced single-day view, one contractor at a time, swipe to switch, read-only (no DnD)

### Claude's Discretion
- Exact skeleton block shapes and animation
- Exact spacing, typography, and component sizing
- react-big-calendar configuration details and customization approach
- Virtualization library choice (react-virtuoso, react-window, or custom)
- Exact resizable column implementation approach
- Touch drag-and-drop library/approach for tablet
- Swipe navigation implementation for mobile day view
- WeasyPrint HTML template design for PDF export
- Exact debounce timing (300ms suggested, can adjust)
- Availability API integration details for single-contractor deep view

### Deferred Ideas (OUT OF SCOPE)
None — discussion stayed within phase scope
</user_constraints>

<phase_requirements>
## Phase Requirements

| ID | Description | Research Support |
|----|-------------|-----------------|
| SCHED-01 | Admin can view a weekly calendar with side-by-side contractor lanes | react-big-calendar `resources` prop creates per-contractor lanes; `resourceIdAccessor`/`resourceTitleAccessor` map contractor data; `dateFnsLocalizer` handles date formatting; TanStack Query loads bookings via GET /scheduling/bookings |
| SCHED-02 | Admin can drag-and-drop bookings to reschedule or reassign contractors | `withDragAndDrop` HOC wraps Calendar; `onEventDrop` receives `{ event, start, end, resourceId }` for cross-lane drops; TanStack Query optimistic update with `onMutate`/`onError` rollback; PATCH /bookings/{id}/reschedule |
| SCHED-03 | Calendar displays conflict warnings before confirming a booking | POST /scheduling/conflicts read-only pre-check on drop; if conflicts returned → shadcn Dialog with ConflictDetail display; "Confirm Anyway" fires PATCH; "Cancel" triggers optimistic rollback |
</phase_requirements>

---

## Summary

Phase 15 implements a weekly resource calendar for scheduling contractor bookings. The locked library is react-big-calendar (v1.19.4) — the only React calendar library with built-in `resources` prop for side-by-side lanes. It ships a `withDragAndDrop` HOC that adds drag-and-drop with `onEventDrop` receiving `{ event, start, end, resourceId }` (the `resourceId` enables cross-lane contractor reassignment). The library requires `ssr: false` dynamic import in Next.js App Router because it references `window` internally.

The data layer follows established Phase 13/14 patterns exactly: TanStack Query for all API data (bookings, contractors), Redux for UI filter state and view preferences, URL search params for bookmarkable state. The conflict detection flow is a pre-check pattern: POST /scheduling/conflicts fires on drop before any save, displaying a shadcn Dialog if conflicts exist. The backend already supports all required endpoints: GET /scheduling/bookings, PATCH /bookings/{id}/reschedule, POST /scheduling/conflicts.

The most technically complex part is the optimistic update + rollback for drag-and-drop: `onMutate` snapshots the cache, applies the optimistic move, and returns a context for `onError` to roll back. CSS scoping is required because react-big-calendar's global stylesheet conflicts with Tailwind 4's reset.

**Primary recommendation:** Use react-big-calendar v1.19.4 with `withDragAndDrop` HOC, `dateFnsLocalizer`, `step={15}` for 15-min snap, TanStack Query optimistic mutations, and wrap the component in a `dynamic()` import with `ssr: false`. Scope the calendar CSS to avoid Tailwind conflicts.

---

## Standard Stack

### Core
| Library | Version | Purpose | Why Standard |
|---------|---------|---------|--------------|
| react-big-calendar | ^1.19.4 | Calendar with resource lanes, DnD HOC | Only React calendar with native `resources` prop; locked decision |
| date-fns | ^4.x (already in ecosystem) | dateFnsLocalizer for RBC | Lighter than moment, native ESM, already likely present |
| @tanstack/react-query | ^5.90.21 | Server state: bookings, contractors | Already installed — Phase 13/14 pattern |
| @reduxjs/toolkit | ^2.11.2 | UI state: filters, view, sidebar | Already installed — Phase 13 pattern |

### Supporting
| Library | Version | Purpose | When to Use |
|---------|---------|---------|-------------|
| react-window or react-virtuoso | latest | Virtualize off-screen contractor lanes | Only when 20+ contractors visible |
| date-fns-tz | ^3.x | Company timezone conversion (UTC → local) | Required for timezone display |

### Alternatives Considered
| Instead of | Could Use | Tradeoff |
|------------|-----------|----------|
| react-big-calendar | FullCalendar React | FullCalendar has better resource support but is heavier (~120kb) and paid for premium features |
| react-big-calendar | @schedule-x/react | Newer, lighter, but missing resource lane concept needed here |
| date-fns-tz | luxon | Luxon is heavier; date-fns-tz composable with existing date-fns |

**Installation:**
```bash
cd web && npm install react-big-calendar date-fns-tz
npm install --save-dev @types/react-big-calendar
```

Note: `date-fns` is likely already transitively installed. Verify with `npm ls date-fns`. If not:
```bash
npm install date-fns
```

---

## Architecture Patterns

### Recommended Project Structure
```
web/src/app/(dashboard)/schedule/
├── page.tsx                    # Suspense wrapper (required for useSearchParams)
├── _components/
│   ├── schedule-calendar.tsx   # DynDCalendar wrapper ("use client", no SSR)
│   ├── calendar-toolbar.tsx    # Toolbar: Today/prev/next/datepicker/view switcher/Export
│   ├── filter-toolbar.tsx      # Second-row collapsible filter bar
│   ├── filter-chips.tsx        # Removable filter chips with "Clear all"
│   ├── booking-panel.tsx       # Sheet side panel for booking detail on click
│   ├── conflict-modal.tsx      # Dialog for pre-check conflict warnings
│   ├── booking-create-panel.tsx # Sheet panel for click-to-book on empty slot
│   ├── contractor-lane-header.tsx # Avatar + contractor name column header
│   ├── booking-event.tsx       # Custom event block: title + client + StatusBadge
│   ├── now-indicator.tsx       # Red "now" line component (updates every 60s)
│   └── calendar-skeleton.tsx   # Full-grid skeleton while loading
└── _hooks/
    ├── use-bookings.ts         # TanStack Query: GET /scheduling/bookings
    ├── use-contractors.ts      # TanStack Query: GET /api/v1/users (role=contractor)
    ├── use-reschedule.ts       # TanStack useMutation: optimistic update + rollback
    ├── use-conflict-check.ts   # TanStack useMutation: POST /scheduling/conflicts
    └── use-schedule-url.ts     # Read/write URL params (date, view, filters)

web/src/store/slices/
└── schedule-slice.ts           # Redux: filter state, collapsible toolbar state
```

### Pattern 1: DnD Calendar with Resources

```typescript
// web/src/app/(dashboard)/schedule/_components/schedule-calendar.tsx
"use client";

import dynamic from "next/dynamic";
import { Calendar, dateFnsLocalizer, Views } from "react-big-calendar";
import withDragAndDrop from "react-big-calendar/lib/addons/dragAndDrop";
import { format, parse, startOfWeek, getDay } from "date-fns";
import { enUS } from "date-fns/locale";
import "react-big-calendar/lib/css/react-big-calendar.css";
import "react-big-calendar/lib/addons/dragAndDrop/styles.css";

const locales = { "en-US": enUS };
const localizer = dateFnsLocalizer({ format, parse, startOfWeek, getDay, locales });
const DnDCalendar = withDragAndDrop(Calendar);

// Source: react-big-calendar GitHub + @types/react-big-calendar v1.8.8
// resourceIdAccessor maps resource objects → ID; resourceAccessor maps events → resourceId
<DnDCalendar
  localizer={localizer}
  events={calendarEvents}
  resources={contractors}           // Contractor[] sorted alphabetically
  resourceIdAccessor={(r) => r.id}
  resourceTitleAccessor={(r) => r.name}
  resourceAccessor={(e) => e.resourceId}
  defaultView={Views.WEEK}
  views={[Views.WEEK, Views.DAY, Views.MONTH]}
  step={15}                          // 15-minute snap for drag-and-drop
  timeslots={2}                      // 2 slots per step = 30-min display slots
  min={new Date(0, 0, 0, 6, 0, 0)}   // 6am start
  max={new Date(0, 0, 0, 20, 0, 0)}  // 8pm end
  onEventDrop={handleEventDrop}      // receives { event, start, end, resourceId }
  onSelectSlot={handleSlotSelect}    // click empty slot → create booking
  onSelectEvent={handleEventClick}   // click booking → Sheet detail panel
  components={{ event: BookingEvent, resourceHeader: ContractorLaneHeader }}
  scrollToTime={new Date()}          // auto-scroll to current time on load
/>
```

**CRITICAL: Next.js SSR wrap.** The file above must itself be dynamically imported by the page:
```typescript
// web/src/app/(dashboard)/schedule/page.tsx
import dynamic from "next/dynamic";
const ScheduleCalendar = dynamic(
  () => import("./_components/schedule-calendar"),
  { ssr: false, loading: () => <CalendarSkeleton /> }
);
```

### Pattern 2: TanStack Query Optimistic Update with Rollback

```typescript
// web/src/app/(dashboard)/schedule/_hooks/use-reschedule.ts
// Source: TanStack Query v5 official docs — optimistic updates pattern
import { useMutation, useQueryClient } from "@tanstack/react-query";
import { apiPatch } from "@/lib/api-client";

export function useRescheduleMutation() {
  const queryClient = useQueryClient();

  return useMutation({
    mutationFn: ({ bookingId, start, end, contractorId }: RescheduleArgs) =>
      apiPatch(`/api/v1/scheduling/bookings/${bookingId}/reschedule`, {
        start: start.toISOString(),
        end: end.toISOString(),
        contractor_id: contractorId,  // for cross-lane reassignment
      }),

    onMutate: async (args) => {
      // 1. Cancel outgoing refetches to prevent overwrite
      await queryClient.cancelQueries({ queryKey: ["bookings"] });
      // 2. Snapshot current data for rollback
      const previousBookings = queryClient.getQueryData(["bookings"]);
      // 3. Optimistically update cache
      queryClient.setQueryData(["bookings"], (old: BookingEvent[]) =>
        old.map((b) =>
          b.id === args.bookingId
            ? { ...b, start: args.start, end: args.end, resourceId: args.contractorId }
            : b
        )
      );
      return { previousBookings }; // context for rollback
    },

    onError: (_err, _args, context) => {
      // Roll back to snapshot
      queryClient.setQueryData(["bookings"], context?.previousBookings);
      toast.error("Failed to reschedule — please try again", { duration: Infinity });
    },

    onSuccess: (data, args) => {
      toast.success(`Booking moved to [contractor] at [time]`);
    },

    onSettled: () => {
      // Always refetch after mutation to ensure consistency
      queryClient.invalidateQueries({ queryKey: ["bookings"] });
    },
  });
}
```

### Pattern 3: Conflict Pre-Check Flow

```typescript
// Drop handler: pre-check → modal or save immediately
async function handleEventDrop({ event, start, end, resourceId }) {
  // Snap to 15 minutes already handled by step={15}
  const conflicts = await conflictCheck.mutateAsync({
    contractor_id: resourceId ?? event.resourceId,
    start: start.toISOString(),
    end: end.toISOString(),
  });

  if (conflicts.length > 0) {
    // Show conflict modal — hold the proposed move in state
    setPendingMove({ event, start, end, contractorId: resourceId });
    setConflicts(conflicts);
    setConflictModalOpen(true);
    // Optimistic rollback until user confirms
  } else {
    // No conflicts — save immediately with optimistic update
    reschedule.mutate({ bookingId: event.id, start, end, contractorId: resourceId });
  }
}

// Conflict modal "Confirm Anyway" handler
function handleConfirmConflict() {
  reschedule.mutate(pendingMove);
  setConflictModalOpen(false);
}
```

### Pattern 4: URL-Driven State (bookmarkable)

```typescript
// web/src/app/(dashboard)/schedule/_hooks/use-schedule-url.ts
// Source: Phase 14 established pattern — useSearchParams + router.replace
"use client";
import { useSearchParams, useRouter } from "next/navigation";
import { parseISO, format } from "date-fns";

export function useScheduleUrl() {
  const searchParams = useSearchParams();
  const router = useRouter();

  const date = searchParams.get("date")
    ? parseISO(searchParams.get("date")!)
    : new Date();
  const view = (searchParams.get("view") ?? "week") as CalendarView;
  const filterTrades = searchParams.getAll("trade");
  const filterStatuses = searchParams.getAll("status");
  const filterContractors = searchParams.getAll("contractor");

  function navigate(newDate: Date, newView?: CalendarView) {
    const params = new URLSearchParams(searchParams.toString());
    params.set("date", format(newDate, "yyyy-MM-dd"));
    if (newView) params.set("view", newView);
    router.replace(`/schedule?${params.toString()}`);
  }

  return { date, view, filterTrades, filterStatuses, filterContractors, navigate };
}
```

### Pattern 5: Redux Slice for Calendar UI State

```typescript
// web/src/store/slices/schedule-slice.ts
// Mirrors ui-slice.ts pattern — filter state, toolbar collapse
interface ScheduleUiState {
  filterToolbarCollapsed: boolean;
  activeFilters: {
    trades: string[];
    statuses: string[];
    contractorIds: string[];
  };
}
// Note: date/view/filter values are authoritative in URL (source of truth)
// Redux holds transient UI state: toolbar collapse, modal open state
```

### Anti-Patterns to Avoid
- **Importing react-big-calendar in a Server Component** — always `"use client"` and `dynamic(..., { ssr: false })`. The library accesses `window` and will crash on the server.
- **Storing date/view in Redux** — URL params are the source of truth for bookmarkable state. Redux is only for transient UI (toolbar collapse, modal state).
- **Calling PATCH /reschedule before POST /conflicts** — always pre-check conflicts first on drop; the backend's reschedule endpoint also enforces constraints but the UX requires a pre-check to show the modal.
- **Using `step={30}` with 15-minute requirements** — `step={15}` is required for 15-min snap. Set `timeslots={2}` for readable 30-min visual rows.
- **Importing global CSS in a layout file** — import react-big-calendar CSS inside the `"use client"` calendar component to scope it and avoid Tailwind conflicts.
- **Not cancelling TanStack queries before optimistic update** — without `cancelQueries`, an in-flight refetch can overwrite the optimistic state before the mutation completes.

---

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| Resource lane calendar | Custom grid with CSS Grid | react-big-calendar `resources` | RBC handles event overlap, time axis, week navigation, view switching — hundreds of edge cases |
| Drag-and-drop on calendar | Pointer events + manual hit-testing | `withDragAndDrop` HOC | RBC's DnD addon knows about time slots, resource boundaries, and scroll containers |
| Date formatting/parsing | Custom formatters | `dateFnsLocalizer` + date-fns | Locale-aware, timezone-safe, already the RBC-endorsed integration |
| Conflict pre-check | Duplicate backend logic in frontend | POST /scheduling/conflicts | Backend has exact TSTZRANGE overlap query with GIST index — perfectly accurate |
| Timezone conversion | Manual offset math | `date-fns-tz` (toZonedTime, fromZonedTime) | IANA timezone rules, DST handling — don't reinvent this |
| Optimistic UI rollback | Manual ref/state for previous position | TanStack Query `onMutate`/`onError` cache snapshot | Already in the stack; handles race conditions automatically |

**Key insight:** The entire calendar grid, event positioning, time axis, and drag mechanics are solved problems in react-big-calendar. The implementation effort is configuration + customization, not calendar math.

---

## Common Pitfalls

### Pitfall 1: react-big-calendar SSR Crash
**What goes wrong:** Next.js App Router tries to render the calendar on the server; RBC references `window`/`document` → crashes with `ReferenceError: window is not defined`.
**Why it happens:** Next.js App Router renders all Server Components on the server by default, and `"use client"` alone doesn't prevent SSR.
**How to avoid:** Wrap the calendar component in `dynamic(() => import(...), { ssr: false })` at the page level. The `"use client"` directive inside the component is also required.
**Warning signs:** Build error or runtime error mentioning `window is not defined` in calendar-related files.

### Pitfall 2: CSS Conflicts Between react-big-calendar and Tailwind 4
**What goes wrong:** Tailwind 4's `@layer base` resets (box-sizing, border styles) conflict with RBC's global stylesheet, causing broken time grid rendering.
**Why it happens:** RBC's CSS is global (`react-big-calendar/lib/css/react-big-calendar.css`) and relies on specific border/box model assumptions.
**How to avoid:** Import RBC's CSS inside the `"use client"` calendar component file (not in `globals.css`). Add Tailwind specificity overrides for any remaining conflicts using `.rbc-calendar` scoped selectors.
**Warning signs:** Time grid lines missing, event blocks misaligned, toolbar buttons unstyled.

### Pitfall 3: onEventDrop resourceId Undefined for Same-Lane Drops
**What goes wrong:** When an event is dragged within the same contractor lane (time change only), `resourceId` in `onEventDrop` may be `undefined` — the backend contractor_id must come from the original event.
**Why it happens:** RBC only includes `resourceId` in the drop payload when the event crosses to a different resource.
**How to avoid:** Always fall back: `const contractorId = resourceId ?? event.resourceId`. Ensure your event objects carry `resourceId` as the contractor UUID.
**Warning signs:** PATCH request sent with null contractor_id; backend returns 422.

### Pitfall 4: Optimistic Update Race Condition
**What goes wrong:** A refetch triggered by `refetchOnWindowFocus` completes after the optimistic update, overwriting the optimistic state with stale server data before the mutation finishes.
**Why it happens:** TanStack Query refetches run in the background and overwrite cache on success.
**How to avoid:** Call `queryClient.cancelQueries({ queryKey: ["bookings"] })` in `onMutate` before setting optimistic state. Call `invalidateQueries` in `onSettled` to force a fresh fetch after mutation.
**Warning signs:** Calendar "jumps" after drop — event appears at new position then snaps back, then appears again.

### Pitfall 5: 15-Minute Snap with step/timeslots Confusion
**What goes wrong:** Setting `step={15}` alone creates 15-minute rows that are too short to read; events may render at incorrect heights.
**Why it happens:** `step` controls time slot granularity for snapping; `timeslots` controls how many slots per visual row.
**How to avoid:** Use `step={15} timeslots={2}` — this creates 15-minute snap increments but displays 30-minute rows, which is readable. Test event height rendering at 15, 30, 60-minute durations.
**Warning signs:** Extremely compressed time grid; 1-hour events rendering at 30-minute height.

### Pitfall 6: Timezone Mismatch Between Backend UTC and Calendar Display
**What goes wrong:** Bookings display at wrong times when company timezone differs from browser timezone.
**Why it happens:** `time_range_start`/`time_range_end` from the API are UTC ISO strings; `new Date()` parses them in browser's local timezone.
**How to avoid:** Use `date-fns-tz`'s `toZonedTime(utcDate, companyTimezone)` when mapping API responses to calendar events. Store company timezone from auth context (companies table `timezone` column). Fall back to `Intl.DateTimeFormat().resolvedOptions().timeZone` if not set.
**Warning signs:** Bookings appear at wrong hours; conflicts calculated incorrectly.

### Pitfall 7: BookingResponse Missing Job Title / Client Name
**What goes wrong:** Calendar event blocks can't display job title + client name because `BookingResponse` only contains `job_id`, not the job/client names.
**Why it happens:** The scheduling backend returns minimal booking data; job details require a separate fetch.
**How to avoid:** When loading bookings for the calendar, also fetch jobs (GET /api/v1/jobs) for the date range and join client-side by `job_id`. Or request a backend endpoint that returns enriched booking data. Plan this data-loading strategy explicitly in 15-01.
**Warning signs:** Event blocks show only UUIDs; empty job title/client name fields.

---

## Code Examples

Verified patterns from official sources and project conventions:

### dateFnsLocalizer Setup
```typescript
// Source: react-big-calendar README (v1.19.4 confirmed)
import { dateFnsLocalizer } from "react-big-calendar";
import { format, parse, startOfWeek, getDay } from "date-fns";
import { enUS } from "date-fns/locale";

const locales = { "en-US": enUS };
export const localizer = dateFnsLocalizer({ format, parse, startOfWeek, getDay, locales });
```

### withDragAndDrop HOC Wrapping
```typescript
// Source: react-big-calendar source + @types/react-big-calendar 1.8.8
import { Calendar } from "react-big-calendar";
import withDragAndDrop from "react-big-calendar/lib/addons/dragAndDrop";
import "react-big-calendar/lib/addons/dragAndDrop/styles.css";

const DnDCalendar = withDragAndDrop(Calendar);
```

### Resource Event Type (TypeScript)
```typescript
// Maps to BookingResponse + joined job data
interface CalendarBooking {
  id: string;               // booking.id
  title: string;            // job.description (job title)
  clientName: string;       // client name from job
  start: Date;              // booking.time_range_start (UTC → company tz)
  end: Date;                // booking.time_range_end (UTC → company tz)
  resourceId: string;       // booking.contractor_id
  status: string;           // job.status (for color coding)
  jobId: string;            // for "View Job" link
  dayIndex?: number;        // multi-day badge (booking.day_index)
  parentBookingId?: string; // multi-day grouping
}
```

### Contractor Resource Type
```typescript
interface ContractorResource {
  id: string;           // user.id
  name: string;         // user.full_name
  avatarUrl?: string;   // user.avatar_url
  tradeType?: string;   // user.trade_type (for filtering)
}
```

### Timezone-Safe Date Conversion
```typescript
// Source: date-fns-tz docs — toZonedTime converts UTC→local for display
import { toZonedTime } from "date-fns-tz";

function toCalendarEvent(booking: BookingResponse, job: Job, companyTimezone: string): CalendarBooking {
  const tz = companyTimezone || Intl.DateTimeFormat().resolvedOptions().timeZone;
  return {
    id: booking.id,
    title: job.description,
    clientName: job.client_name ?? "",
    start: toZonedTime(new Date(booking.time_range_start), tz),
    end: toZonedTime(new Date(booking.time_range_end), tz),
    resourceId: booking.contractor_id,
    status: job.status,
    jobId: booking.job_id,
    dayIndex: booking.day_index ?? undefined,
  };
}
```

### apiClient Usage (project pattern)
```typescript
// Source: web/src/lib/api-client.ts (Phase 13)
// GET bookings for week range
const bookings = await apiGet<BookingResponse[]>(
  `/api/v1/scheduling/bookings?date_from=${dateFrom}&date_to=${dateTo}`
);

// POST conflict check
const conflicts = await apiPost<ConflictDetail[]>(
  "/api/v1/scheduling/conflicts",
  { contractor_id: contractorId, start: start.toISOString(), end: end.toISOString() }
);

// PATCH reschedule
const updated = await apiPatch<BookingResponse>(
  `/api/v1/scheduling/bookings/${bookingId}/reschedule`,
  { start: start.toISOString(), end: end.toISOString() }
);
```

### Toast Pattern (project convention)
```typescript
// Source: Phase 13 decision — error toasts persist with duration: Infinity
import { toast } from "sonner";

toast.success(`Booking moved to ${contractorName} at ${formattedTime}`);
toast.error("Failed to reschedule — please try again", { duration: Infinity });
```

---

## State of the Art

| Old Approach | Current Approach | When Changed | Impact |
|--------------|------------------|--------------|--------|
| moment.js localizer | dateFnsLocalizer (date-fns) | 2020+ | Smaller bundle, ESM-native, no global mutation |
| Class-based Calendar | Functional with hooks | RBC v1.x | Hooks-compatible, better TypeScript |
| Manual drag-and-drop | `withDragAndDrop` HOC | RBC v0.x+ | Full calendar-aware DnD, time snap built-in |
| `pages/` router dynamic import | App Router `dynamic(..., { ssr: false })` | Next.js 13+ | Same pattern, App Router compatible |
| TanStack Query v4 optimistic | v5 `onMutate` context pattern | 2024 | Cleaner rollback; `variables` pattern also available |

**Deprecated/outdated:**
- `momentLocalizer`: Still works but moment.js is deprecated upstream; project should use `dateFnsLocalizer`
- `globalizeLocalizer`: Niche; not relevant for this project
- `react-big-calendar-fns` (npm package): Redundant wrapper; use the built-in `dateFnsLocalizer` directly

---

## Open Questions

1. **BookingResponse enrichment for job title + client name**
   - What we know: GET /scheduling/bookings returns `job_id` and `contractor_id` but not job title or client name
   - What's unclear: Whether to (a) fetch jobs separately and join client-side, (b) request a new backend endpoint, or (c) add a TanStack Query `select` transform that joins pre-fetched jobs
   - Recommendation: Option (a) — fetch GET /api/v1/jobs in the same `useQuery` load phase, join by job_id client-side. Avoids backend changes (additive-only rule from STATE.md). Plan 15-01 should document this join strategy.

2. **Company timezone column**
   - What we know: CONTEXT.md mentions "Need to add timezone column to companies table if not present"
   - What's unclear: Whether this column exists in the current backend schema
   - Recommendation: Plan 15-01 implementer should verify `backend/app/features/companies/models.py` before writing timezone conversion code. If missing, add as nullable column migration (additive-only).

3. **Resizable column widths implementation**
   - What we know: Marked as "Claude's Discretion"; react-big-calendar doesn't natively support resizable resource columns
   - What's unclear: Whether to use `react-resizable`, CSS resize handle, or a custom pointer-event approach
   - Recommendation: Use CSS `resize` property on resource column headers with `overflow: auto` — zero-dependency approach; falls back gracefully if not supported.

4. **Touch drag-and-drop for tablet**
   - What we know: Marked as "Claude's Discretion"; react-big-calendar's default DnD uses mouse events
   - What's unclear: Whether react-big-calendar's DnD addon supports touch natively
   - Recommendation: Test RBC DnD on tablet first. If touch doesn't work, add `@dnd-kit/core` for touch-aware DnD or use `react-dnd` with touch backend. This is a Plan 15-02 implementation detail.

---

## Validation Architecture

### Test Framework
| Property | Value |
|----------|-------|
| Framework | Playwright (installed, configured) |
| Config file | `web/playwright.config.ts` |
| Quick run command | `npx playwright test tests/schedule.spec.ts --project=chromium` |
| Full suite command | `npx playwright test --project=chromium` |

### Phase Requirements → Test Map
| Req ID | Behavior | Test Type | Automated Command | File Exists? |
|--------|----------|-----------|-------------------|-------------|
| SCHED-01 | Calendar renders with contractor resource lanes | E2E (Playwright) | `npx playwright test tests/schedule.spec.ts --project=chromium` | ❌ Wave 0 |
| SCHED-01 | Week view shows correct date range | E2E (Playwright) | same | ❌ Wave 0 |
| SCHED-01 | Booking events display job title + client + StatusBadge | E2E (Playwright) | same | ❌ Wave 0 |
| SCHED-01 | Clicking booking opens Sheet detail panel | E2E (Playwright) | same | ❌ Wave 0 |
| SCHED-01 | URL params drive date/view (bookmarkable) | E2E (Playwright) | same | ❌ Wave 0 |
| SCHED-02 | Drag booking to new time → PATCH called with correct payload | E2E (Playwright) | same | ❌ Wave 0 |
| SCHED-02 | Drag booking to different contractor lane → resourceId changes | E2E (Playwright) | same | ❌ Wave 0 |
| SCHED-02 | Network error → booking snaps back + persistent error toast | E2E (Playwright) | same | ❌ Wave 0 |
| SCHED-03 | Drop on conflicted slot → conflict modal appears | E2E (Playwright) | same | ❌ Wave 0 |
| SCHED-03 | "Confirm Anyway" → PATCH fires despite conflict | E2E (Playwright) | same | ❌ Wave 0 |
| SCHED-03 | "Cancel" in conflict modal → booking snaps back | E2E (Playwright) | same | ❌ Wave 0 |

### Sampling Rate
- **Per task commit:** `npx playwright test tests/schedule.spec.ts --project=chromium`
- **Per wave merge:** `npx playwright test --project=chromium`
- **Phase gate:** Full suite green before `/gsd:verify-work`

### Wave 0 Gaps
- [ ] `web/tests/schedule.spec.ts` — covers SCHED-01, SCHED-02, SCHED-03 (stub with `test.skip()` per Phase 14 pattern)

*(Playwright framework already installed and configured in `web/playwright.config.ts`. No new framework setup needed.)*

---

## Canonical References to Read Before Implementing

The following files are REQUIRED reading for any implementer of Phase 15 plans:

| File | What to Extract |
|------|----------------|
| `backend/app/features/scheduling/router.py` | All endpoint paths, request shapes, error codes (409, 422, 404) |
| `backend/app/features/scheduling/schemas.py` | BookingResponse fields, ConflictDetail fields for modal display |
| `web/src/lib/api-client.ts` | apiGet/apiPost/apiPatch helpers — use these, never raw fetch |
| `web/src/components/shared/status-badge.tsx` | colorMap — reuse exact same status→color mapping for booking blocks |
| `web/src/components/ui/sheet.tsx` | Sheet/SheetContent for booking detail panel |
| `web/src/components/ui/dialog.tsx` | Dialog/DialogContent for conflict modal |
| `web/src/components/ui/sonner.tsx` | Toaster — `{ duration: Infinity }` for error toasts (Phase 13 decision) |
| `web/src/components/layout/sidebar.tsx` | Schedule already in navItems at href="/schedule" — no change needed |
| `web/src/store/index.ts` | Add schedule-slice reducer here |
| `web/src/app/(dashboard)/jobs/page.tsx` | URL params pattern, TanStack Query usage, Suspense wrapper |

---

## Sources

### Primary (HIGH confidence)
- react-big-calendar GitHub source + README (v1.19.4, June 2025) — resources prop, withDragAndDrop HOC, CSS import paths
- `@types/react-big-calendar@1.8.8` type definitions (unpkg.com) — CalendarProps.resources, resourceIdAccessor, resourceTitleAccessor, resourceAccessor, step prop
- `web/src/lib/api-client.ts` — apiGet/apiPost/apiPatch usage verified by reading
- `backend/app/features/scheduling/router.py` — all endpoint paths, error codes verified by reading
- `backend/app/features/scheduling/schemas.py` — BookingResponse, ConflictDetail shapes verified by reading
- TanStack Query v5 official docs (tanstack.com/query/latest) — optimistic update onMutate/onError/onSettled pattern

### Secondary (MEDIUM confidence)
- WebSearch: onEventDrop receives `{ event, start, end, resourceId }` when dropping to different resource lane — confirmed by multiple community sources and @types structure
- WebSearch: `step={15} timeslots={2}` for 15-min snap with readable 30-min rows — confirmed by issues tracker discussion
- date-fns-tz `toZonedTime` for UTC → company timezone — standard date-fns-tz API, confirmed by usage pattern

### Tertiary (LOW confidence)
- CSS resize property for resizable column widths — suggested approach, needs implementation testing
- Touch DnD behavior of react-big-calendar on tablet — untested; may need supplemental library

---

## Metadata

**Confidence breakdown:**
- Standard stack: HIGH — react-big-calendar version confirmed, API types verified
- Architecture: HIGH — follows established Phase 13/14 patterns exactly
- Pitfalls: HIGH — several from real GitHub issues, others from code analysis
- Open questions: MEDIUM — data enrichment approach is clear but needs verification of company timezone column existence

**Research date:** 2026-03-16
**Valid until:** 2026-06-16 (react-big-calendar is stable; date-fns-tz API is stable)
