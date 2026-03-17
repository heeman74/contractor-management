# Phase 15: Scheduling Calendar - Context

**Gathered:** 2026-03-16
**Status:** Ready for planning

<domain>
## Phase Boundary

Admins can view the full team schedule on a weekly calendar with side-by-side contractor lanes, drag-and-drop bookings to reschedule or reassign contractors, and receive conflict warnings before confirming any move. Also includes day view, month overview, click-to-book from empty slots, multi-filter toolbar, PDF/CSV export, and mobile-responsive fallback. No new job creation from calendar — only scheduling existing jobs.

</domain>

<decisions>
## Implementation Decisions

### Booking event display
- Standard info density: job title + client name + small StatusBadge per booking block
- Color-coded by job status (reuse StatusBadge semantic colors: blue=scheduled, yellow=in-progress, green=complete)
- Overflow visible for short booking blocks (text overflows block boundary rather than truncating or enforcing minimum height)
- Click booking block opens a side panel (Sheet) showing booking details + job summary — read-only with "View Job" link to /jobs/[id], no status transition buttons
- Non-working hours displayed as grayed-out bands per contractor lane
- Only actual bookings shown on calendar — no travel buffers or time-off blocks (conflict detection handles those on drop)
- Multi-day bookings show connected "Day X/Y" badge on each block
- Empty contractor lanes show blank lane with grayed non-working hours (no text message)

### Drag-and-drop & conflict UX
- Pre-check on drop: call POST /scheduling/conflicts before saving. If conflicts found, show modal dialog before saving. If clear, save immediately with PATCH /bookings/{id}/reschedule
- Conflict warning modal: centered dialog showing conflicting booking details (job title, time, contractor) with "Confirm Anyway" and "Cancel" buttons
- 15-minute snap during drag — booking snaps to nearest 15-min increment
- Successful reassignment: booking animates to new lane/time, success toast ("Booking moved to [Contractor] at [time]")
- Failed reschedule (network/500): snap booking back to original position, persistent error toast ("Failed to reschedule — please try again")
- Escape key cancels in-progress drag, snapping back to original position

### Contractor lane layout
- Lane headers: avatar circle + contractor name per column
- Horizontal scroll for many contractors (10+), time axis stays fixed on left (sticky)
- Contractor headers pinned (sticky) at top when scrolling vertically
- Default ordering: alphabetical by name
- Resizable column widths — admin can drag column borders to resize lanes
- Virtualize off-screen lanes for companies with 20+ contractors

### Navigation & time controls
- Three views: Week (default), Day, Month — view switcher buttons in toolbar
- Toolbar: "Today" button + prev/next arrows + date picker + view switcher + Export dropdown
- URL query params for state: /schedule?date=2026-03-16&view=week (bookmarkable, survives refresh)
- Default time range: 6am–8pm (business hours)
- Auto-scroll to current time on load (week and day views)

### Current time indicator
- Red horizontal "now" line across all lanes at current time
- Updates every 60 seconds (live feel)
- Today's date header gets subtle light blue background tint

### Day view specifics
- Default: all contractors shown with one day (same resource lane layout as week view, wider lanes)
- Toggle to single-contractor deep view by clicking lane header
- Richer event blocks in day view: title + client + status + address + time (wider lanes allow more info)
- Single-contractor mode shows availability windows: free windows as green-tinted zones, blocked intervals as distinct markers
- Month view click navigates to Day view for that date

### Month view
- Day cells with booking counts (not full resource lanes)
- Click day cell navigates to Day view for that date

### Booking creation from calendar
- Click empty time slot opens booking creation panel/modal
- Pre-fills contractor and time from click position
- Job selection: dropdown of existing jobs in "Scheduled" or "Quote" status that need booking
- No new job creation from calendar — only scheduling existing jobs

### Calendar filtering
- Multi-filter toolbar: filter by trade type, job status, and specific contractors (multi-select)
- Filter toolbar positioned below main toolbar (second row), collapsible
- Active filters displayed as removable chips/tags below toolbar ("Trade: Plumbing x", "Status: In Progress x") with "Clear all" link
- Filter state persists in URL query params alongside date/view

### Export
- PDF export: server-side with WeasyPrint (reuses Phase 16 pattern), exports current view as-is with company header + date range
- CSV export: tabular booking data for the current view
- Export buttons in toolbar dropdown ("Export" button with PDF/CSV options)
- Export scope: current view only (whatever the admin sees)

### Timezone handling
- Calendar displays in company's configured timezone
- Company timezone from companies table timezone column (e.g., 'America/New_York')
- Backend stores UTC, frontend converts for display
- Fallback to browser timezone if company timezone not set

### Loading & error states
- Skeleton grid while bookings load: full calendar grid (time axis + contractor headers) with pulsing skeleton blocks
- Refetch on window focus (TanStack Query refetchOnWindowFocus) for stale data prevention
- Debounced fetch on rapid week navigation: update grid immediately (skeleton), debounce API call by 300ms
- No-contractors empty state: illustration + "No contractors yet. Add your team to start scheduling." with link to Contractors page

### Keyboard shortcuts
- Left/Right arrow keys for prev/next week (or day in day view)
- "T" key to jump to today
- Escape cancels in-progress drag

### Responsive behavior
- Tablet (768-1024px): same layout with touch drag-and-drop, horizontal scroll, mini sidebar auto-collapses (Phase 13)
- Mobile (<768px): forced to single-day view, one contractor at a time with swipe to switch, no drag-and-drop (read-only schedule)

### Performance
- Virtualize off-screen contractor lanes for 20+ contractors
- Debounced API fetch (300ms) on rapid week navigation

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

</decisions>

<canonical_refs>
## Canonical References

**Downstream agents MUST read these before planning or implementing.**

### Backend API — Scheduling
- `backend/app/features/scheduling/router.py` — All scheduling endpoints: bookings CRUD, reschedule, conflicts pre-check, availability, weekly schedule, date overrides
- `backend/app/features/scheduling/schemas.py` — BookingResponse, ConflictDetail, AvailabilityResponse (free_windows + blocked_intervals), BookingCreate
- `backend/app/features/scheduling/service.py` — SchedulingService with conflict detection, reschedule (atomic soft-delete + create), availability engine
- `backend/app/features/scheduling/models.py` — Booking model (TSTZRANGE column), ContractorWeeklySchedule, ContractorDateOverride

### Backend API — Users/Contractors
- `backend/app/features/users/models.py` — User model with roles, trade type, avatar — needed for contractor lane headers and filtering

### Web Foundation (Phase 13)
- `web/src/lib/api-client.ts` — apiClient with 401 auto-refresh proxy pattern
- `web/src/components/shared/status-badge.tsx` — StatusBadge with semantic color map (reuse for booking status colors)
- `web/src/components/layout/sidebar.tsx` — Sidebar navigation (add Schedule route)
- `web/src/components/layout/topbar.tsx` — Topbar with breadcrumbs
- `web/src/components/layout/dashboard-shell.tsx` — Dashboard shell wrapper
- `web/src/store/slices/` — Redux slices for UI state (filter state, sidebar)

### UI Components
- `web/src/components/ui/` — shadcn/ui: Card, Badge, Button, Sheet, Dialog, Skeleton, Sonner (toast), Tabs, DropdownMenu

### Phase 14 Patterns
- `web/src/app/(dashboard)/jobs/` — Job list and detail pages (link target for "View Job" from booking panel)

### Requirements
- `.planning/REQUIREMENTS.md` — SCHED-01 (weekly calendar with contractor lanes), SCHED-02 (drag-and-drop reschedule/reassign), SCHED-03 (conflict warnings)

</canonical_refs>

<code_context>
## Existing Code Insights

### Reusable Assets
- **StatusBadge** (`web/src/components/shared/status-badge.tsx`): Maps all statuses to semantic colors — direct reuse for booking block color coding
- **apiClient** (`web/src/lib/api-client.ts`): GET/POST/PATCH/DELETE helpers with proxy and 401 refresh — use for all scheduling API calls
- **Sheet component** (`web/src/components/ui/sheet.tsx`): Side panel for booking detail on click
- **Dialog component** (`web/src/components/ui/dialog.tsx`): Modal for conflict warnings
- **Sonner toast** (`web/src/components/ui/sonner.tsx`): Success/error toasts, error persists until dismissed
- **Skeleton** (`web/src/components/ui/skeleton.tsx`): Loading state skeleton blocks

### Established Patterns
- **TanStack Query for server state**: All API data fetched/cached via TanStack Query (Phase 13), supports refetchOnWindowFocus
- **Redux for UI state only**: Filter state, sidebar collapse, view preferences
- **httpOnly cookie auth**: All API calls through /api/proxy route handler
- **URL-driven state**: Next.js App Router with searchParams for bookmarkable views

### Integration Points
- **Sidebar nav**: Add "Schedule" route to sidebar items array (module order: Dashboard > Jobs > Schedule > ...)
- **Dashboard route group**: New pages at `web/src/app/(dashboard)/schedule/` for calendar
- **Backend endpoints**: GET /scheduling/bookings (date range filter), PATCH /bookings/{id}/reschedule, POST /scheduling/conflicts, GET /scheduling/availability/{id}
- **Jobs link**: Booking detail panel links to /jobs/[id] (Phase 14 pages)
- **Company timezone**: Need to add timezone column to companies table if not present, serve in auth/company response
- **WeasyPrint**: Server-side PDF generation (shared with Phase 16 quotes/invoices)

</code_context>

<specifics>
## Specific Ideas

- Calendar should feel like Google Calendar's resource view — side-by-side contractor lanes with a clean grid
- Drag-and-drop should feel snappy with 15-min snap — similar to Calendly's scheduling grid
- Conflict modal should be clear and unambiguous — show exactly what's conflicting and let admin choose
- Multi-filter chips pattern similar to Stripe's filter pills — removable tags showing active filters
- Day view single-contractor mode inspired by employee scheduling tools (When I Work, Deputy) — full availability visibility
- Month view should be a simple overview for capacity planning, not a detailed scheduling view

</specifics>

<deferred>
## Deferred Ideas

None — discussion stayed within phase scope

</deferred>

---

*Phase: 15-scheduling-calendar*
*Context gathered: 2026-03-16*
