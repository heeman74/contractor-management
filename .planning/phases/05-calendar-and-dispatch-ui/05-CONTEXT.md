# Phase 5: Calendar and Dispatch UI - Context

**Gathered:** 2026-03-09
**Status:** Ready for planning

<domain>
## Phase Boundary

Company admins can visually schedule and reschedule contractor assignments using a drag-and-drop calendar that surfaces conflicts, travel time gaps, and overdue job warnings. Contractors can report delays with a required reason and new ETA. This phase builds the UI layer on top of the Phase 3 scheduling engine and Phase 4 job lifecycle.

Requirements: SCHED-03, SCHED-08, SCHED-09

</domain>

<decisions>
## Implementation Decisions

### Calendar Views and Layout
- Three views: Day, Week, and Month
- **Day view**: Contractor lanes (horizontal rows, one per contractor). Vertical time axis (scrollable 24-hour, auto-scrolls to earliest contractor's working hours on load). "Now" line across all lanes showing current time.
- **Week view**: Collapsed summary — one card per job per contractor, no time axis. Tap to drill into day view for time details.
- **Month view**: Job count badges per day cell. Tap a day to switch to day view.
- Portrait orientation only (no landscape)
- Date navigation: swipe left/right between days/weeks + date picker button in header + "Today" button to snap back
- Today's date: highlighted header + horizontal "now" line across all contractor lanes (day view)

### Contractor Display
- Default: show all active contractors in the company
- Paginated lanes: 5 contractors per page with pagination controls (handles 10+ teams)
- Filter by trade type to narrow down visible contractors
- Non-working hours: grayed-out background on contractor lanes
- Date overrides (days off, holidays): blocked with label ("Day Off", "Holiday") across full lane width
- Contractor schedule management: both inline quick actions from calendar (long-press for day off, adjust hours) AND a separate settings screen for weekly template management

### Booking Card Design
- Minimal: job description (truncated) + client name + status-based color
- Status color palette: Quote=gray, Scheduled=blue, In Progress=orange, Complete=green, Invoiced=purple, Cancelled=red
- Travel time between consecutive bookings: hatched/striped blocks — visually distinct as "in transit" time
- Active jobs only by default; toggle to include Complete/Invoiced/Cancelled (dimmed/faded)

### Drag-and-Drop Scheduling
- Two scheduling methods:
  1. **Sidebar drag**: Collapsible drawer with filterable unscheduled job queue (filter by status, trade type, priority, client). Admin drags job card from drawer onto a contractor's time slot.
  2. **Tap-to-schedule**: Admin taps empty time slot on contractor's lane, picks from job list in bottom sheet.
- Dragged booking auto-sizes based on job's estimated_duration_minutes
- Live drag feedback: valid drop zones highlight green, conflicting zones highlight red, non-working hours stay grayed
- On conflict: booking snaps back to original position. Toast/snackbar shows conflicting job name and time range.
- Drag between contractor lanes to reassign existing bookings
- Edge resize: drag top/bottom edges of booking card to adjust start/end time
- Confirmation: instant on drop with undo snackbar (5 seconds)
- Undo supported for all calendar operations: new bookings, reschedules, reassignments, and deletions
- Multi-day jobs: wizard modal after initial drop — configure additional days, set times per day, uses suggest-dates endpoint for recommendations
- Booking creation auto-transitions job from Quote to Scheduled status (recorded in status_history)

### Tap Interaction
- Tap existing booking card: navigate to full job detail screen (Phase 4 tabbed layout: Details, Schedule, History)

### Data Refresh
- Pull-to-refresh only (triggers SyncEngine.syncNow()). No auto-refresh. Consistent with existing app patterns.

### Contractor View
- Contractor sees both a date-grouped list AND a personal single-lane calendar view, with toggle to switch
- "Report Delay" button visible on job cards (see delay justification below)

### Overdue Warnings (SCHED-08)
- **Definition**: Job is overdue when today > scheduled_completion_date AND status is 'scheduled' or 'in_progress'
- **Tiered severity**:
  - Warning tier (1-3 days overdue): yellow/orange border + warning icon on booking card
  - Critical tier (4+ days overdue): red border + warning icon on booking card
- **Overdue panel**: Badge count in calendar header (e.g., "3 overdue"). Tapping expands a panel listing all overdue jobs with days count, tier color, and quick actions (view job, contact contractor).
- **Detection**: Local computation — compare system date with scheduled_completion_date in Drift DB. Works offline.
- **Bottom nav badge**: Schedule tab in bottom navigation shows red badge with overdue count (always visible)
- **Contractor view**: Overdue jobs shown with different messaging — prompt like "This job is past its scheduled completion — update status or report a delay"

### Delay Justification Flow (SCHED-09)
- **Trigger**: Dedicated "Report Delay" button on job detail screen. Available on any job in Scheduled or In Progress status (proactive delays allowed, not just overdue jobs).
- **Required fields**: Free-text reason (required) + new ETA date picker (required)
- **Storage**: New entry in job's status_history JSONB array: {type: "delay", reason: "...", new_eta: "YYYY-MM-DD", timestamp: "...", user_id: "..."}
- **ETA update**: Reporting a delay auto-updates the job's scheduled_completion_date to the new ETA. If new ETA passes without completion, job becomes overdue again.
- **Multiple delays**: Unlimited per job. Each creates a new status_history entry. Latest new_eta replaces previous scheduled_completion_date. Full audit trail in job history tab.
- **Admin visibility**: Delay icon badge on calendar booking card + entry in overdue panel with delay reason and new ETA
- **Offline**: Delay reports stored in Drift + sync queue. Works offline like other job mutations.
- **No admin response needed**: Delay is informational. Admin acts through existing tools (reschedule, reassign).

### Claude's Discretion
- Calendar Flutter package selection (table_calendar, syncfusion, custom, etc.)
- Exact hatched/striped pattern implementation for travel time blocks
- Pagination controls design for contractor lanes
- Sidebar drawer animation and gesture handling
- Undo snackbar timing and animation
- Multi-day wizard modal layout
- Overdue panel expand/collapse animation
- "Report Delay" button placement and styling on job cards
- Drift table schema for bookings (local mobile storage)
- Sync handler registration for bookings/job sites
- Calendar widget internal architecture

</decisions>

<specifics>
## Specific Ideas

- The day view with contractor lanes should feel like a dispatch board — "who's doing what when" at a glance
- Travel time hatched blocks should be clearly "in transit" time, not confused with free time or bookings
- The collapsible job queue drawer on mobile should feel natural — slide in from side, full calendar when closed
- Contractor view should be dead simple — Phase 4 decision: "just 'my jobs today' with big tap targets"
- Overdue tiering (warning vs critical) gives contractors a grace period before it looks alarming
- Delay flow should encourage early communication — available proactively, not just reactively

</specifics>

<code_context>
## Existing Code Insights

### Reusable Assets
- `SchedulingService` (backend): `get_available_slots()`, `book_slot()`, `book_multiday_job()`, `suggest_dates()`, conflict checking — full scheduling engine ready
- `GET /api/v1/scheduling/availability` endpoint: multi-contractor availability queries with proximity sorting
- `POST /api/v1/scheduling/bookings` and `POST /api/v1/scheduling/bookings/multi-day` endpoints ready
- `POST /api/v1/scheduling/conflicts` endpoint: dry-run conflict check before booking
- `Booking` model with EXCLUDE USING GIST constraint: DB-level double-booking prevention
- `BlockedInterval` schema with reason enum ("existing_job", "travel_buffer", "outside_working_hours", "time_off") — feeds into calendar visualization
- `KanbanBoard` widget (mobile): horizontal scrollable columns pattern — similar lane concept for calendar
- `JobDao` with sync queue dual-write pattern — template for BookingDao
- `JobsPipelineScreen`: filter chip pattern, batch mode, pull-to-refresh pattern
- `AppShell` with bottom navigation: Schedule tab placeholder exists at `RouteNames.schedule`
- `ScheduleScreen` placeholder at `mobile/lib/shared/screens/schedule_screen.dart`
- `JobStatus` enum (mobile) with `displayLabel` and `backendValue` — reuse for color mapping
- `SyncEngine` + `SyncHandler` pattern — register booking sync handler

### Established Patterns
- Feature-first Flutter structure: `lib/features/<domain>/`
- Domain-driven backend: `app/features/<domain>/` with routes, services, models, schemas
- Drift streams for reactive UI updates (watch queries)
- AsyncNotifier + StreamProvider for Riverpod state
- StateProvider for UI state (filters, toggles, view mode)
- Pull-to-refresh via `SyncEngine.syncNow()`
- UUID client-generated PKs for offline-first sync
- ConsumerWidget pattern for all screens
- Empty state pattern with contextual messaging

### Integration Points
- `RouteNames.schedule` route: replace placeholder with calendar screen
- `AppShell` bottom nav: add overdue badge count to Schedule tab
- Job's `status_history` JSONB: extend with delay entry type
- Job's `scheduled_completion_date`: updated on delay report
- Drift migration v3→v4: add Bookings table for local storage
- SyncEngine: register booking + job_site sync handlers
- GoRouter: add routes for contractor personal calendar, schedule settings

</code_context>

<deferred>
## Deferred Ideas

- Address autocomplete/typeahead as user types (user requested — could use ORS Pelias geocoding from Phase 3, but it's a new capability beyond SCHED-03/08/09)
- Real-time push updates for calendar changes (WebSocket/SSE — overkill for current offline-first architecture)
- Drag-and-drop from month view directly (drill to day view first)

</deferred>

---

*Phase: 05-calendar-and-dispatch-ui*
*Context gathered: 2026-03-09*
