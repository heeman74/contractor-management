# Phase 5: Calendar and Dispatch UI - Research

**Researched:** 2026-03-09
**Domain:** Flutter calendar UI, drag-and-drop scheduling, Drift local bookings, FastAPI delay endpoint
**Confidence:** HIGH

---

<user_constraints>
## User Constraints (from CONTEXT.md)

### Locked Decisions

**Calendar Views and Layout**
- Three views: Day, Week, and Month
- Day view: Contractor lanes (horizontal rows, one per contractor). Vertical time axis (scrollable 24-hour, auto-scrolls to earliest contractor's working hours on load). "Now" line across all lanes showing current time.
- Week view: Collapsed summary — one card per job per contractor, no time axis. Tap to drill into day view for time details.
- Month view: Job count badges per day cell. Tap a day to switch to day view.
- Portrait orientation only (no landscape)
- Date navigation: swipe left/right between days/weeks + date picker button in header + "Today" button to snap back
- Today's date: highlighted header + horizontal "now" line across all contractor lanes (day view)

**Contractor Display**
- Default: show all active contractors in the company
- Paginated lanes: 5 contractors per page with pagination controls (handles 10+ teams)
- Filter by trade type to narrow down visible contractors
- Non-working hours: grayed-out background on contractor lanes
- Date overrides (days off, holidays): blocked with label ("Day Off", "Holiday") across full lane width
- Contractor schedule management: both inline quick actions from calendar (long-press for day off, adjust hours) AND a separate settings screen for weekly template management

**Booking Card Design**
- Minimal: job description (truncated) + client name + status-based color
- Status color palette: Quote=gray, Scheduled=blue, In Progress=orange, Complete=green, Invoiced=purple, Cancelled=red
- Travel time between consecutive bookings: hatched/striped blocks — visually distinct as "in transit" time
- Active jobs only by default; toggle to include Complete/Invoiced/Cancelled (dimmed/faded)

**Drag-and-Drop Scheduling**
- Two scheduling methods:
  1. Sidebar drag: Collapsible drawer with filterable unscheduled job queue (filter by status, trade type, priority, client). Admin drags job card from drawer onto a contractor's time slot.
  2. Tap-to-schedule: Admin taps empty time slot on contractor's lane, picks from job list in bottom sheet.
- Dragged booking auto-sizes based on job's estimated_duration_minutes
- Live drag feedback: valid drop zones highlight green, conflicting zones highlight red, non-working hours stay grayed
- On conflict: booking snaps back to original position. Toast/snackbar shows conflicting job name and time range.
- Drag between contractor lanes to reassign existing bookings
- Edge resize: drag top/bottom edges of booking card to adjust start/end time
- Confirmation: instant on drop with undo snackbar (5 seconds)
- Undo supported for all calendar operations: new bookings, reschedules, reassignments, and deletions
- Multi-day jobs: wizard modal after initial drop — configure additional days, set times per day, uses suggest-dates endpoint for recommendations
- Booking creation auto-transitions job from Quote to Scheduled status (recorded in status_history)

**Tap Interaction**
- Tap existing booking card: navigate to full job detail screen (Phase 4 tabbed layout: Details, Schedule, History)

**Data Refresh**
- Pull-to-refresh only (triggers SyncEngine.syncNow()). No auto-refresh. Consistent with existing app patterns.

**Contractor View**
- Contractor sees both a date-grouped list AND a personal single-lane calendar view, with toggle to switch
- "Report Delay" button visible on job cards

**Overdue Warnings (SCHED-08)**
- Definition: Job is overdue when today > scheduled_completion_date AND status is 'scheduled' or 'in_progress'
- Tiered severity:
  - Warning tier (1-3 days overdue): yellow/orange border + warning icon on booking card
  - Critical tier (4+ days overdue): red border + warning icon on booking card
- Overdue panel: Badge count in calendar header (e.g., "3 overdue"). Tapping expands a panel listing all overdue jobs with days count, tier color, and quick actions (view job, contact contractor).
- Detection: Local computation — compare system date with scheduled_completion_date in Drift DB. Works offline.
- Bottom nav badge: Schedule tab in bottom navigation shows red badge with overdue count (always visible)
- Contractor view: Overdue jobs shown with different messaging — prompt like "This job is past its scheduled completion — update status or report a delay"

**Delay Justification Flow (SCHED-09)**
- Trigger: Dedicated "Report Delay" button on job detail screen. Available on any job in Scheduled or In Progress status (proactive delays allowed, not just overdue jobs).
- Required fields: Free-text reason (required) + new ETA date picker (required)
- Storage: New entry in job's status_history JSONB array: {type: "delay", reason: "...", new_eta: "YYYY-MM-DD", timestamp: "...", user_id: "..."}
- ETA update: Reporting a delay auto-updates the job's scheduled_completion_date to the new ETA. If new ETA passes without completion, job becomes overdue again.
- Multiple delays: Unlimited per job. Each creates a new status_history entry. Latest new_eta replaces previous scheduled_completion_date. Full audit trail in job history tab.
- Admin visibility: Delay icon badge on calendar booking card + entry in overdue panel with delay reason and new ETA
- Offline: Delay reports stored in Drift + sync queue. Works offline like other job mutations.
- No admin response needed: Delay is informational. Admin acts through existing tools (reschedule, reassign).

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

### Deferred Ideas (OUT OF SCOPE)
- Address autocomplete/typeahead as user types (user requested — could use ORS Pelias geocoding from Phase 3, but it's a new capability beyond SCHED-03/08/09)
- Real-time push updates for calendar changes (WebSocket/SSE — overkill for current offline-first architecture)
- Drag-and-drop from month view directly (drill to day view first)
</user_constraints>

---

<phase_requirements>
## Phase Requirements

| ID | Description | Research Support |
|----|-------------|-----------------|
| SCHED-03 | Drag-and-drop calendar scheduling with color coding | Custom calendar widget using Flutter's built-in Draggable/DragTarget + LongPressDraggable; custom painter for contractor lane grid; patterns_canvas for travel time hatching |
| SCHED-08 | Overdue task warnings when jobs miss scheduled completion | Local Drift computation (compare DateTime.now() vs scheduledCompletionDate); Badge widget on NavigationBar Schedule tab; tiered severity (1-3 days = warning, 4+ = critical) |
| SCHED-09 | Forced delay justification — contractor must provide reason + new ETA | New PATCH /jobs/{id}/delay backend endpoint; delay entry in status_history JSONB; Drift local update + sync queue push; offline-capable like other job mutations |
</phase_requirements>

---

## Summary

Phase 5 builds the visual dispatch interface on top of already-complete backend scheduling and job lifecycle engines (Phases 3 and 4). The primary technical challenge is the custom multi-contractor lane calendar widget on mobile — no off-the-shelf Flutter package supports the exact dispatch-board layout with paginated side-by-side contractor lanes, sidebar drag source, and offline-first sync. The calendar will be built as a custom Flutter widget using standard `Draggable`/`DragTarget`/`LongPressDraggable` primitives rather than adopting an opinionated third-party calendar package.

Three areas of new code are required: (1) the Flutter calendar widget complex (UI only — the data layer and backend already exist), (2) a Drift `Bookings` table at schema version 4 with its DAO and sync handler, and (3) a new backend endpoint `PATCH /api/v1/jobs/{id}/delay` that appends a delay entry to `status_history` and updates `scheduled_completion_date`. Overdue detection is pure client-side logic against the existing Drift jobs table — no new backend query is needed.

**Primary recommendation:** Build the day-view calendar as a custom `CustomPainter`-backed widget with a `ScrollController` for the time axis and a `PageView` for contractor-lane pagination. Use `patterns_canvas` for diagonal-striped travel time blocks. Use Flutter's `Badge` widget (Material 3, available since Flutter 3.22) for the bottom nav overdue count. Follow the existing `JobDao`/`JobSyncHandler` pattern exactly for `BookingDao`/`BookingSyncHandler`.

---

## Standard Stack

### Core (Existing — no new deps needed)

| Library | Version | Purpose | Why Standard |
|---------|---------|---------|--------------|
| flutter | 3.32+ | UI framework | Already in project; CustomPainter + Draggable cover all calendar needs natively |
| flutter_riverpod | ^3.2.1 | State management | Already in project; StateProvider (legacy import) for view toggles, AsyncNotifier for data |
| drift | ^2.32.0 | Local DB | Already in project; add Bookings table via migration v4 |
| dio | ^5.9.2 | HTTP client | Already in project; delay push via existing DioClient.pushWithIdempotency |
| go_router | ^17.1.0 | Navigation | Already in project; add contractor calendar + schedule settings routes |
| freezed_annotation | ^3.1.0 | Immutable entities | Already in project; BookingEntity, CalendarViewState |

### New Dependency (One Addition)

| Library | Version | Purpose | Why Standard |
|---------|---------|---------|--------------|
| patterns_canvas | ^0.5.0 | Diagonal stripe pattern for travel time blocks | Pure Dart, no platform channels, MIT license, paints directly onto Canvas API |

### NOT Needed (Packages Evaluated and Rejected)

| Package | Reason Rejected |
|---------|-----------------|
| syncfusion_flutter_calendar | Commercial license required; resource view exists but is heavily opinionated — fighting it for custom dispatch layout costs more than building custom |
| kalender | v0.15.0 (recent), MIT, drag-drop supported, but NO multi-resource side-by-side lane support (confirmed from GitHub README) — the core requirement for this dispatch board |
| table_calendar | Month/week views only, no time axis, no drag-drop, no lanes |
| infinite_calendar_view | Timeline view, but no multi-resource lanes; limited customization of time region backgrounds |

**Installation:**
```bash
flutter pub add patterns_canvas
```

---

## Architecture Patterns

### Recommended Project Structure

```
mobile/lib/features/schedule/
├── data/
│   ├── booking_dao.dart              # Drift DAO for Bookings table
│   ├── booking_dao.g.dart            # Generated
│   ├── booking_sync_handler.dart     # SyncHandler: push CREATE/UPDATE/DELETE, applyPulled
│   └── job_site_sync_handler.dart    # SyncHandler: applyPulled for JobSite entities
├── domain/
│   ├── booking_entity.dart           # Freezed entity (mirrors Booking backend model)
│   ├── booking_entity.freezed.dart   # Generated
│   └── overdue_service.dart          # Pure Dart: computes overdue status from job list
├── presentation/
│   ├── providers/
│   │   ├── calendar_providers.dart   # AsyncNotifier for bookings/availability, StateProviders for view/date/filters
│   │   └── overdue_providers.dart    # Derived provider: counts and lists overdue jobs
│   ├── screens/
│   │   ├── schedule_screen.dart      # Replaces placeholder; root of admin dispatch calendar
│   │   ├── contractor_schedule_screen.dart   # Contractor's personal view (list + single lane)
│   │   └── schedule_settings_screen.dart     # Weekly template management for contractors
│   └── widgets/
│       ├── calendar_day_view.dart          # Day view: paginated contractor lanes + time axis
│       ├── calendar_week_view.dart         # Week view: collapsed job cards per contractor
│       ├── calendar_month_view.dart        # Month view: job count badges per day
│       ├── contractor_lane.dart            # Single contractor's time row with DragTarget cells
│       ├── booking_card.dart               # Draggable card: color, overdue badge, delay badge
│       ├── travel_time_block.dart          # Hatched "in transit" block using patterns_canvas
│       ├── unscheduled_jobs_drawer.dart    # Collapsible sidebar with LongPressDraggable cards
│       ├── overdue_panel.dart              # Expandable panel listing overdue jobs
│       └── delay_justification_dialog.dart # Modal: reason text field + ETA date picker
```

```
mobile/lib/core/database/tables/
└── bookings.dart    # New Drift table, schemaVersion → 4
```

```
backend/app/features/jobs/
├── router.py    # Add PATCH /jobs/{id}/delay endpoint
├── service.py   # Add report_delay() method to JobService
└── schemas.py   # Add DelayReportRequest schema
```

### Pattern 1: Custom Calendar Day View with CustomPainter + DragTarget Grid

**What:** The day view renders a time axis on the left and a horizontally paginated grid of contractor lanes. Each lane is a column of `DragTarget` cells (one per time-slot increment, e.g., 15 minutes). Booking cards are `LongPressDraggable` widgets absolutely positioned within their contractor lane using a `Stack`.

**When to use:** Whenever no off-the-shelf package fits the exact multi-resource dispatch-board layout. Building custom is cost-justified here because the data layer (availability, conflict API) is already done.

**Key considerations:**
- The time axis and lane backgrounds are drawn with `CustomPainter` for performance (avoids widget-per-minute overhead)
- `DragTarget` cells snap dropped bookings to 15-minute increments
- `PageView` handles contractor lane pagination (5 per page)
- A shared `ScrollController` synchronizes vertical scroll across the time axis and all lane columns
- Non-working hour regions are painted gray by the `CustomPainter` using `BlockedInterval` data with `reason == "outside_working_hours"` or `reason == "time_off"`

```dart
// Source: Flutter official docs - CustomPainter
class CalendarGridPainter extends CustomPainter {
  final List<BlockedInterval> blockedIntervals;
  final DateTime dayStart; // start of 24h range
  final double pixelsPerMinute;

  @override
  void paint(Canvas canvas, Size size) {
    // Draw hour lines
    final linePaint = Paint()
      ..color = Colors.grey.shade200
      ..strokeWidth = 0.5;
    for (int hour = 0; hour < 24; hour++) {
      final y = hour * 60 * pixelsPerMinute;
      canvas.drawLine(Offset(0, y), Offset(size.width, y), linePaint);
    }

    // Draw non-working hour shading
    final shadePaint = Paint()
      ..color = Colors.grey.shade100
      ..style = PaintingStyle.fill;
    for (final interval in blockedIntervals) {
      if (interval.reason == 'outside_working_hours' ||
          interval.reason == 'time_off') {
        final top = _minutesFromDayStart(interval.start) * pixelsPerMinute;
        final bottom = _minutesFromDayStart(interval.end) * pixelsPerMinute;
        canvas.drawRect(Rect.fromLTRB(0, top, size.width, bottom), shadePaint);
      }
    }
  }
  // ...
}
```

### Pattern 2: LongPressDraggable + DragTarget for Booking Drag

**What:** Each booking card wraps in `LongPressDraggable`. The DragTarget cells in the contractor lane grid use `onWillAcceptWithDetails` to visually validate the drop (green highlight for free, red for conflict) and `onAcceptWithDetails` to trigger the booking API call. On conflict, the SnackBar shows the conflicting job name; the card snaps back automatically because no state update is made.

```dart
// Source: Flutter official docs - LongPressDraggable
LongPressDraggable<BookingDragData>(
  data: BookingDragData(jobId: job.id, durationMinutes: job.estimatedDurationMinutes ?? 60),
  feedback: Material(
    elevation: 4,
    borderRadius: BorderRadius.circular(8),
    child: SizedBox(
      width: laneWidth,
      height: durationToPixels(job.estimatedDurationMinutes ?? 60),
      child: BookingCard(job: job, isDragging: true),
    ),
  ),
  childWhenDragging: Opacity(
    opacity: 0.3,
    child: BookingCard(job: job),
  ),
  child: BookingCard(job: job),
)
```

```dart
// DragTarget cell (15-minute time slot within a contractor lane)
DragTarget<BookingDragData>(
  onWillAcceptWithDetails: (details) {
    // Check against local Drift data — instant, offline-capable
    return !hasConflict(contractorId, slotStart, details.data.durationMinutes);
  },
  onAcceptWithDetails: (details) async {
    // Call POST /api/v1/scheduling/bookings (or local Drift insert + sync queue)
    await ref.read(calendarProvidersNotifier.notifier).bookSlot(
      contractorId: contractorId,
      jobId: details.data.jobId,
      start: slotStart,
      durationMinutes: details.data.durationMinutes,
    );
  },
  builder: (context, candidateData, rejectedData) {
    final isHighlighted = candidateData.isNotEmpty;
    return Container(
      height: slotHeightPx,
      color: isHighlighted ? Colors.green.withOpacity(0.2) : Colors.transparent,
    );
  },
)
```

### Pattern 3: Travel Time Hatched Block via patterns_canvas

**What:** `BlockedInterval` entries with `reason == "travel_buffer"` render as hatched rectangles overlaid on the contractor lane using a `CustomPainter` that calls `patterns_canvas`.

```dart
// Source: patterns_canvas 0.5.0 (MIT)
import 'package:patterns_canvas/patterns_canvas.dart';

class TravelTimeBlockPainter extends CustomPainter {
  final Rect blockRect;

  @override
  void paint(Canvas canvas, Size size) {
    DiagonalStripesLight(
      bgColor: Colors.grey.shade200,
      fgColor: Colors.grey.shade400,
    ).paintOnRect(canvas, size, blockRect);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
```

### Pattern 4: Drift BookingDao with Sync Queue (mirrors JobDao)

**What:** `BookingDao` follows the exact same transactional outbox pattern as `JobDao`. Every mutation writes to `Bookings` table AND `SyncQueue` atomically.

```dart
// Source: existing JobDao pattern in mobile/lib/features/jobs/data/job_dao.dart
@DriftAccessor(tables: [Bookings, SyncQueue])
class BookingDao extends DatabaseAccessor<AppDatabase> with _$BookingDaoMixin {
  BookingDao(super.db);

  Stream<List<BookingEntity>> watchBookingsByContractor(
    String contractorId,
    DateTime date,
  ) {
    final dayStart = DateTime(date.year, date.month, date.day);
    final dayEnd = dayStart.add(const Duration(days: 1));
    return (select(bookings)
          ..where((tbl) =>
              tbl.contractorId.equals(contractorId) &
              tbl.timeRangeStart.isBiggerOrEqualValue(dayStart) &
              tbl.timeRangeStart.isSmallerThanValue(dayEnd) &
              tbl.deletedAt.isNull()))
        .watch()
        .map((rows) => rows.map(_rowToEntity).toList());
  }

  Future<void> insertBooking(BookingsCompanion entry) async {
    await db.transaction(() async {
      await into(bookings).insert(entry);
      await into(syncQueue).insert(_buildQueueEntry(
        entityType: 'booking',
        entityId: entry.id.value,
        operation: 'CREATE',
        payload: _bookingPayload(entry),
      ));
    });
  }
  // ... upsertBookingFromSync, softDeleteBooking, updateBookingTime
}
```

### Pattern 5: Drift Bookings Table (schema v4)

**What:** New Drift table mirroring the backend `Booking` model. The time range is split into two DateTime columns (SQLite has no native TSTZRANGE). The `day_index` and `parent_booking_id` columns support multi-day jobs.

```dart
// New file: mobile/lib/core/database/tables/bookings.dart
class Bookings extends Table {
  TextColumn get id => text().clientDefault(() => const Uuid().v4())();
  TextColumn get companyId => text()();
  TextColumn get contractorId => text()();
  TextColumn get jobId => text()();
  TextColumn get jobSiteId => text().nullable()();
  // TSTZRANGE stored as two UTC datetimes (SQLite limitation)
  DateTimeColumn get timeRangeStart => dateTime()();
  DateTimeColumn get timeRangeEnd => dateTime()();
  IntColumn get dayIndex => integer().nullable()();
  TextColumn get parentBookingId => text().nullable()();
  TextColumn get notes => text().nullable()();
  IntColumn get version => integer().withDefault(const Constant(1))();
  DateTimeColumn get createdAt => dateTime()();
  DateTimeColumn get updatedAt => dateTime()();
  DateTimeColumn get deletedAt => dateTime().nullable()();

  @override
  Set<Column> get primaryKey => {id};
}
```

**AppDatabase migration:**
```dart
// Bump schemaVersion from 3 → 4
@override
int get schemaVersion => 4;

// In onUpgrade:
if (from < 4) {
  await m.createTable(bookings);
  // JobSites table also needed for sync pull
  await m.createTable(jobSites);
}
```

### Pattern 6: Overdue Detection (Pure Local Computation)

**What:** A derived Riverpod provider computes overdue jobs by filtering the existing `watchJobsByCompany` stream. No backend endpoint needed — uses data already in Drift from normal job sync.

```dart
// Source: Riverpod 3 Provider (from existing project patterns)
@riverpod
int overdueJobCount(OverdueJobCountRef ref) {
  final jobsAsync = ref.watch(jobsByCompanyProvider);
  return jobsAsync.when(
    data: (jobs) {
      final today = DateTime.now();
      return jobs.where((job) {
        final isActiveStatus = job.status == 'scheduled' || job.status == 'in_progress';
        final completionDate = job.scheduledCompletionDate;
        if (!isActiveStatus || completionDate == null) return false;
        return today.isAfter(completionDate);
      }).length;
    },
    loading: () => 0,
    error: (_, __) => 0,
  );
}

OverdueSeverity computeSeverity(DateTime scheduledCompletionDate) {
  final daysOverdue = DateTime.now().difference(scheduledCompletionDate).inDays;
  if (daysOverdue >= 4) return OverdueSeverity.critical;  // red border
  if (daysOverdue >= 1) return OverdueSeverity.warning;   // yellow/orange border
  return OverdueSeverity.none;
}
```

### Pattern 7: Bottom Nav Badge for Overdue Count

**What:** Flutter's Material 3 `Badge` widget wraps the Schedule tab icon in `AppShell`. The badge count comes from the `overdueJobCountProvider`.

```dart
// Source: Flutter Badge class - material library
// AppShell NavigationBar destination for Schedule tab:
NavigationDestination(
  icon: Badge(
    isLabelVisible: overdueCount > 0,
    label: Text('$overdueCount'),
    child: const Icon(Icons.calendar_month_outlined),
  ),
  selectedIcon: Badge(
    isLabelVisible: overdueCount > 0,
    label: Text('$overdueCount'),
    child: const Icon(Icons.calendar_month),
  ),
  label: 'Schedule',
)
```

**Important:** In Riverpod 3, `StateProvider` for view toggles (day/week/month, contractor page index) must be imported from `package:riverpod/legacy.dart` — this is already the established project pattern (documented in STATE.md: `StateProvider imported from package:riverpod/legacy.dart`).

### Pattern 8: Delay Justification Backend Endpoint (New)

**What:** New `PATCH /api/v1/jobs/{id}/delay` endpoint appends a delay entry to `status_history` and updates `scheduled_completion_date`. This is NOT a status transition (job stays in same lifecycle state) — it is a separate mutation using existing service patterns.

```python
# backend/app/features/jobs/schemas.py — Add:
class DelayReportRequest(BaseModel):
    """Payload for reporting a job delay.

    Appends a delay entry to status_history JSONB and updates
    scheduled_completion_date to the new ETA. Does NOT change job.status.
    """
    reason: str = Field(min_length=1, description="Required written delay reason")
    new_eta: date = Field(description="New expected completion date (YYYY-MM-DD)")
    version: int = Field(description="Current job version for optimistic locking")


# backend/app/features/jobs/service.py — Add to JobService:
async def report_delay(
    self,
    job_id: uuid.UUID,
    data: DelayReportRequest,
    *,
    user_id: uuid.UUID,
) -> Job:
    """Append a delay entry to status_history and update scheduled_completion_date.

    Validates job is in 'scheduled' or 'in_progress' status.
    Does NOT transition status — delay is informational only.
    Uses optimistic locking (version check) consistent with transition_status().
    """
    job = await self.repository.get_by_id(job_id)
    if job is None:
        raise HTTPException(status_code=404, detail=f"Job {job_id} not found")

    if job.version != data.version:
        raise HTTPException(status_code=409, detail="Version conflict — fetch latest and retry")

    if job.status not in ('scheduled', 'in_progress'):
        raise HTTPException(
            status_code=422,
            detail="Delay can only be reported on jobs in 'scheduled' or 'in_progress' status",
        )

    delay_entry = {
        "type": "delay",
        "reason": data.reason,
        "new_eta": data.new_eta.isoformat(),
        "timestamp": datetime.now(UTC).isoformat(),
        "user_id": str(user_id),
    }
    job.status_history = [*job.status_history, delay_entry]
    job.scheduled_completion_date = data.new_eta
    job.version = job.version + 1  # type: ignore[assignment]

    await self.db.flush()
    await self.db.refresh(job)
    return job
```

```python
# backend/app/features/jobs/router.py — Add before /jobs/{job_id}:
@router.patch("/jobs/{job_id}/delay", response_model=JobResponse)
async def report_job_delay(
    job_id: uuid.UUID,
    delay_data: DelayReportRequest,
    db: AsyncSession = Depends(get_db),
    current_user: CurrentUser = Depends(get_current_user),
) -> JobResponse:
    """Report a delay for a job in 'scheduled' or 'in_progress' status.

    Appends a delay entry to status_history and updates scheduled_completion_date.
    Available to both contractors (own jobs) and admins. Does NOT change job status.
    Returns 404 if job not found, 409 on version conflict, 422 if wrong status.
    """
    svc = JobService(db)
    job = await svc.report_delay(job_id, delay_data, user_id=current_user.id)
    return JobResponse.model_validate(job)
```

### Anti-Patterns to Avoid

- **Nested ScrollViews with shared direction:** The day view has a vertical ScrollController (time axis) and horizontal PageView (contractor lanes). Mixing both axes in the same scroll context causes gesture conflicts. Solution: the vertical scroll handles the time axis; the PageView is a sibling that only scrolls horizontally.
- **Widget-per-minute time grid:** Building 1440 widget cells per contractor lane causes layout thrashing. Use `CustomPainter` for the background grid; only actual booking cards are widgets.
- **DragTarget covering entire contractor lane:** A single DragTarget for the full lane cannot provide 15-minute snap zones. Use a `Stack` with a `ListView` of thin DragTarget strips behind the booking cards.
- **In-place status_history mutation:** The backend pattern uses list replacement `[*job.status_history, new_entry]` not `.append()`. The Flutter side must do the same: decode → add entry → re-encode to JSON string.
- **Calling DioClient directly from drag callbacks:** Drag operations must be synchronous enough to provide immediate visual feedback. Queue to Drift + sync queue (offline-first pattern), not direct HTTP. Visual feedback is instant from local state; sync happens in background.

---

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| Diagonal stripe "travel time" blocks | Custom line-drawing painter | `patterns_canvas` DiagonalStripesLight | Edge cases: angle, spacing, clipping to rect boundaries; patterns_canvas handles all of this |
| Overdue count badge on nav bar | Stacked Container + Positioned | Flutter `Badge` widget (Material 3) | Built-in, theme-aware, handles label overflow, correct M3 semantics |
| Snackbar-with-undo dismissal | Timer + manual widget management | `ScaffoldMessenger.showSnackBar` + `SnackBarAction` + `duration` | Flutter 3.29+ changed SnackBar with action to NOT auto-dismiss; set `SnackBar(duration: const Duration(seconds: 5))` explicitly |
| Conflict check before drag accept | Custom local overlap logic | Read from local Drift bookings stream | Drift already has all bookings locally; compare `timeRangeStart`/`timeRangeEnd` — no HTTP needed for live drag feedback |
| Date picker for ETA | Custom date input | `showDatePicker()` | Built-in Material date picker with locale support; no package needed |
| Booking sync push | Custom HTTP logic | `DioClient.pushWithIdempotency(..., method: 'PATCH')` | Already extended in Phase 4 for PATCH/DELETE; booking CREATE/UPDATE/DELETE maps directly |

---

## Common Pitfalls

### Pitfall 1: SnackBar with Action Does Not Auto-Dismiss in Flutter 3.29+

**What goes wrong:** Undo snackbar stays visible forever, blocking the UI.
**Why it happens:** Breaking change introduced in Flutter 3.29 — `SnackBar` with an `action` no longer auto-dismisses by default.
**How to avoid:** Always set an explicit `duration: const Duration(seconds: 5)` on the SnackBar. Verify behavior in your Flutter version. Official breaking change doc: https://docs.flutter.dev/release/breaking-changes/snackbar-with-action-behavior-update
**Warning signs:** Snackbar visible after 5+ seconds in testing.

### Pitfall 2: StateProvider Import in Riverpod 3

**What goes wrong:** `StateProvider` import fails or produces deprecation warnings.
**Why it happens:** Riverpod 3 moved `StateProvider` to `package:riverpod/legacy.dart`.
**How to avoid:** Import `package:flutter_riverpod/legacy.dart` for all `StateProvider` and `StateNotifierProvider` uses — this is already the project-established pattern (see STATE.md Decisions).
**Warning signs:** "StateProvider is not defined" or IDE warnings about deprecated imports.

### Pitfall 3: Synchronized Vertical Scroll Across Contractor Lanes

**What goes wrong:** Time axis and contractor lanes scroll independently; the "now" line drifts out of sync.
**Why it happens:** Each `ListView` or `SingleChildScrollView` has its own scroll position.
**How to avoid:** Share a single `ScrollController` across the time axis column and all contractor lane columns. Pass `controller: sharedScrollController` to every vertical scrollable child. Use `LinkedScrollControllerGroup` from the `linked_scroll_controller` pub package, OR manually implement by listening to one controller and driving others.
**Warning signs:** Time axis shows different time than the visible booking slots.

### Pitfall 4: Drift DateTime Columns Are in UTC — Local Time Display Must Convert

**What goes wrong:** Booking times displayed in wrong timezone (off by hours).
**Why it happens:** Drift stores `DateTime` as UTC microseconds. Backend sends UTC ISO-8601 strings. Display needs to show times in the device's local timezone.
**How to avoid:** Always convert stored/received UTC `DateTime` to local before display: `booking.timeRangeStart.toLocal()`. Store in Drift as UTC (backend sends UTC); display with `.toLocal()`.
**Warning signs:** Bookings appear to start at wrong hours on device.

### Pitfall 5: Route Shadowing When Adding /jobs/{id}/delay

**What goes wrong:** FastAPI matches `/jobs/{job_id}/delay` as `job_id = "delay"` and hits the `GET /jobs/{job_id}` route with a non-UUID param, returning 422.
**Why it happens:** FastAPI route ordering — declared routes are matched in order.
**How to avoid:** Declare `PATCH /jobs/{job_id}/delay` BEFORE `GET /jobs/{job_id}` in the router. This is the established pattern in Phase 4 (see STATE.md: "Route ordering in FastAPI: /jobs/requests* must be declared BEFORE /jobs/{job_id}").
**Warning signs:** 422 Unprocessable Entity with `msg: value is not a valid uuid` when calling the delay endpoint.

### Pitfall 6: Drag Gesture Conflict Between Lane Scroll and Booking Drag

**What goes wrong:** Trying to scroll the time axis also initiates a drag on a booking card.
**Why it happens:** `LongPressDraggable` requires a long-press, which by default also scrolls. The gesture arena has a conflict.
**How to avoid:** Use `LongPressDraggable` (not `Draggable`) — the long-press delay naturally separates scroll intent from drag intent on mobile. Avoid `Draggable` (instant drag) which fights scroll gestures. The `hapticFeedbackOnStart: true` default gives the user tactile confirmation that drag mode has started.
**Warning signs:** Calendar scrolling accidentally triggers drag mode.

### Pitfall 7: Drift Migration Version Must Be Sequential

**What goes wrong:** `MigrationStrategy.onUpgrade` skips bookings table creation for users upgrading from v1 or v2.
**Why it happens:** Upgrade guards like `if (from < 4)` only run if `from < 4`. But if `from` is 1, the `from < 3` guard also runs, which may add columns that don't exist in v1. Each guard must be independent.
**How to avoid:** Keep each migration block self-contained. Always test upgrade from version 1 to current (full cold migration path), not just N-1 to N.
**Warning signs:** `DatabaseException: table bookings not found` on first launch for existing users.

---

## Code Examples

### Booking Entity (Freezed)

```dart
// Source: established project pattern (see job_entity.dart)
@freezed
class BookingEntity with _$BookingEntity {
  const factory BookingEntity({
    required String id,
    required String companyId,
    required String contractorId,
    required String jobId,
    String? jobSiteId,
    required DateTime timeRangeStart,
    required DateTime timeRangeEnd,
    int? dayIndex,
    String? parentBookingId,
    String? notes,
    required int version,
    required DateTime createdAt,
    required DateTime updatedAt,
    DateTime? deletedAt,
  }) = _BookingEntity;
}
```

### Delay Justification Dialog (Flutter)

```dart
// Contractor triggers this from job detail screen; admin can also trigger
Future<void> showDelayJustificationDialog(BuildContext context, JobEntity job) async {
  final reasonController = TextEditingController();
  DateTime? selectedEta;

  final confirmed = await showDialog<bool>(
    context: context,
    barrierDismissible: false,  // Required fields — no accidental dismiss
    builder: (ctx) => AlertDialog(
      title: const Text('Report Delay'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextFormField(
            controller: reasonController,
            decoration: const InputDecoration(
              labelText: 'Reason for delay *',
              hintText: 'Describe the reason...',
            ),
            maxLines: 3,
            validator: (v) => v == null || v.isEmpty ? 'Required' : null,
          ),
          const SizedBox(height: 16),
          ListTile(
            title: Text(selectedEta == null
                ? 'Select new ETA *'
                : 'New ETA: ${DateFormat.yMd().format(selectedEta!)}'),
            trailing: const Icon(Icons.date_range),
            onTap: () async {
              final picked = await showDatePicker(
                context: ctx,
                initialDate: job.scheduledCompletionDate ?? DateTime.now().add(const Duration(days: 1)),
                firstDate: DateTime.now().add(const Duration(days: 1)),
                lastDate: DateTime.now().add(const Duration(days: 365)),
              );
              if (picked != null) {
                // setState inside dialog via StatefulBuilder
              }
            },
          ),
        ],
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
        ElevatedButton(
          onPressed: () {
            if (reasonController.text.isNotEmpty && selectedEta != null) {
              Navigator.pop(ctx, true);
            }
          },
          child: const Text('Submit'),
        ),
      ],
    ),
  );

  if (confirmed == true) {
    // Delegate to provider → Drift write + sync queue (offline-first)
  }
}
```

### Undo Snackbar (5-second, Explicit Duration)

```dart
// Source: Flutter docs + breaking change note (flutter 3.29+)
ScaffoldMessenger.of(context).showSnackBar(
  SnackBar(
    content: Text('Booked: ${job.description} at ${formatTime(slotStart)}'),
    duration: const Duration(seconds: 5),  // REQUIRED — no auto-dismiss with action in 3.29+
    action: SnackBarAction(
      label: 'Undo',
      onPressed: () {
        ref.read(calendarProvidersNotifier.notifier).undoLastBooking();
      },
    ),
  ),
);
```

### NavigationBar Badge for Overdue Count

```dart
// Source: Flutter Badge class - material library
// In AppShell._buildTabs():
final overdueCount = ref.watch(overdueJobCountProvider);

// Schedule tab destination:
NavigationDestination(
  icon: Badge(
    isLabelVisible: overdueCount > 0,
    label: Text('$overdueCount'),  // Caps at 99 visually if needed
    child: const Icon(Icons.calendar_month_outlined),
  ),
  selectedIcon: Badge(
    isLabelVisible: overdueCount > 0,
    label: Text('$overdueCount'),
    child: const Icon(Icons.calendar_month),
  ),
  label: 'Schedule',
),
```

---

## State of the Art

| Old Approach | Current Approach | When Changed | Impact |
|--------------|------------------|--------------|--------|
| SnackBar with action auto-dismisses | Must set explicit `duration` | Flutter 3.29 (2025) | Undo snackbar would stick forever without explicit duration |
| `StateProvider` in main riverpod export | `StateProvider` in `legacy.dart` | Riverpod 3.0 | Import must be `package:flutter_riverpod/legacy.dart` |
| Custom Container + Positioned for badges | Flutter `Badge` widget | Flutter 3.22+ (M3) | Native, theme-aware badge; no custom stacking needed |
| `BottomNavigationBar` | `NavigationBar` (Material 3) | Flutter 3.x | Project already uses M3 `NavigationBar`; Badge wraps icon naturally |

**Deprecated/outdated:**
- `Draggable` for mobile drag-and-drop: prefer `LongPressDraggable` to avoid conflicts with scroll gestures
- `StateProvider` in main riverpod import: moved to legacy, use `package:flutter_riverpod/legacy.dart`

---

## Open Questions

1. **JobSite sync handler — should it upsert without a CREATE push?**
   - What we know: `JobSite` records are created by admin (via geocoding in Phase 3); the mobile app only needs to read them, not create them offline.
   - What's unclear: Whether `job_site_sync_handler.dart` needs push logic or only `applyPulled`.
   - Recommendation: Implement `applyPulled` only (read-only sync from server); no CREATE push from mobile for job sites. Mobile creates bookings that reference a `job_site_id` chosen from a pre-synced list.

2. **Booking sync: which entity type string does the server pull endpoint filter on?**
   - What we know: The sync pull endpoint at `/api/v1/sync/pull` returns entities by type based on `updated_at > cursor`. Bookings and job_sites need to be added to the pull handler registry.
   - What's unclear: Whether the backend pull handler for `booking` and `job_site` entities exists or needs to be created.
   - Recommendation: Check the backend `sync/` module for existing entity registrations. If missing, add `booking` and `job_site` to the pull handler (follow existing `job` pattern). This is a Phase 5 Plan 05-01 task.

3. **How to handle `estimated_duration_minutes = null` during drag?**
   - What we know: The booking card auto-sizes based on `estimated_duration_minutes`. Some jobs may have null duration.
   - Recommendation: Default to 60 minutes when null. Show a visual indicator on the booking card ("duration unset") so admin knows to check job details.

---

## Sources

### Primary (HIGH confidence)
- Codebase: `/mobile/lib/core/database/app_database.dart` — confirmed schemaVersion = 3; v4 is next
- Codebase: `/mobile/lib/features/jobs/data/job_dao.dart` — transactional outbox pattern to follow
- Codebase: `/backend/app/features/scheduling/schemas.py` — `BlockedInterval` reason enum values
- Codebase: `/backend/app/features/scheduling/router.py` — all scheduling endpoints (availability, bookings, conflicts, suggest-dates)
- Codebase: `/backend/app/features/jobs/service.py` — status_history list-replacement pattern (Pitfall 3)
- Codebase: `/backend/app/features/jobs/schemas.py` — `StatusHistoryEntry` shape; delay entry will use same JSONB array
- Flutter official docs: `LongPressDraggable`, `DragTarget`, `CustomPainter`, `Badge`, `SnackBar`

### Secondary (MEDIUM confidence)
- [pub.dev kalender 0.15.0](https://pub.dev/packages/kalender) — confirmed: no multi-resource side-by-side lane support → rejected
- [pub.dev syncfusion_flutter_calendar 32.2.8](https://pub.dev/packages/syncfusion_flutter_calendar) — confirmed: commercial license required, resource view exists but opinionated → rejected for this project
- [pub.dev patterns_canvas 0.5.0](https://pub.dev/packages/patterns_canvas) — confirmed: pure Dart, MIT, `DiagonalStripesLight.paintOnRect()` for travel time blocks
- [Flutter breaking change: SnackBar with action behavior](https://docs.flutter.dev/release/breaking-changes/snackbar-with-action-behavior-update) — confirmed: must set explicit `duration`
- [Flutter Badge class](https://api.flutter.dev/flutter/material/Badge-class.html) — Material 3 badge, `isLabelVisible`, `label` constructor

### Tertiary (LOW confidence)
- `linked_scroll_controller` package for synchronized vertical scroll across lanes — not verified against pub.dev, but commonly referenced pattern. Validate during Plan 05-02.

---

## Metadata

**Confidence breakdown:**
- Standard stack: HIGH — all existing packages confirmed from pubspec.yaml; one new dep (`patterns_canvas`) verified on pub.dev
- Architecture: HIGH — custom calendar approach confirmed by rejecting all third-party packages (lacking multi-resource lane support); all patterns mirror existing codebase patterns
- Pitfalls: HIGH — most sourced from existing STATE.md decisions or official Flutter breaking change docs; Pitfall 3 (scroll sync) is MEDIUM until implementation is tested
- Delay endpoint design: HIGH — mirrors `transition_status` pattern exactly; no new OOP base classes needed

**Research date:** 2026-03-09
**Valid until:** 2026-04-09 (30 days — Flutter/Dart ecosystem is relatively stable; patterns_canvas version unlikely to change)
