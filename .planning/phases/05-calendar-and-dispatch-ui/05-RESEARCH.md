# Phase 5: Calendar and Dispatch UI — Research

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
| SCHED-03 | Drag-and-drop calendar scheduling with color coding | Flutter `Draggable`/`LongPressDraggable`/`DragTarget` (built-in, stable). Custom `CustomPainter` grid recommended for multi-contractor lane layout. Status color palette defined in locked decisions, extend `JobStatus.calendarColor` getter. |
| SCHED-08 | Overdue task warnings when jobs miss scheduled completion | Local computation from Drift `scheduledCompletionDate` field vs `DateTime.now()`. Tiered severity is pure Dart. Flutter `Badge` widget (Material 3) wraps `NavigationDestination` icon. Works offline. |
| SCHED-09 | Forced delay justification — contractor must provide reason + new ETA | New `PATCH /api/v1/jobs/{job_id}/delay` backend endpoint appending `{type: "delay", ...}` to `status_history` JSONB and updating `scheduled_completion_date`. Offline-first: Drift mutation + sync queue dual-write identical to existing job mutations in `JobDao`. |
</phase_requirements>

---

## Summary

Phase 5 builds the visual dispatch interface on top of the already-complete backend scheduling and job lifecycle engines (Phases 3 and 4). The primary technical challenge is the custom multi-contractor lane calendar widget — no off-the-shelf Flutter package supports the exact dispatch-board layout with paginated side-by-side contractor lanes, travel-time hatching, sidebar drag source, and offline-first sync. The calendar is built as a custom Flutter widget using standard `Draggable`/`DragTarget`/`LongPressDraggable` primitives rather than adopting an opinionated third-party calendar package (all evaluated packages were rejected for concrete reasons detailed in Standard Stack below).

Three areas of new code are required: (1) the Flutter calendar widget complex (UI only — all backend APIs already exist), (2) a Drift `Bookings` table at schema version 4 with its DAO and sync handler, and (3) a new backend endpoint `PATCH /api/v1/jobs/{id}/delay` that appends a delay entry to `status_history` and updates `scheduled_completion_date`. Overdue detection is pure client-side logic against the existing Drift `jobs` table — no new backend query needed.

**Primary recommendation:** Build the day-view calendar as a custom `CustomPainter`-backed widget with a `ScrollController` for the time axis and a `PageView` for contractor-lane pagination. Use `patterns_canvas` for diagonal-striped travel time blocks. Use Flutter's `Badge` widget (Material 3) for the bottom nav overdue count. Follow the existing `JobDao`/`JobSyncHandler` pattern exactly for `BookingDao`/`BookingSyncHandler`.

---

## Standard Stack

### Core (Existing — no new deps needed)

| Library | Version | Purpose | Why Standard |
|---------|---------|---------|--------------|
| flutter | 3.32+ | UI framework | Already in project; `CustomPainter` + `Draggable` + `DragTarget` cover all calendar needs natively |
| flutter_riverpod | ^3.2.1 | State management | Already in project; `StateProvider` (legacy import) for view toggles, `AsyncNotifier` for data |
| drift | ^2.32.0 | Local DB | Already in project; add `Bookings` + `JobSites` tables via migration v4 |
| dio | ^5.9.2 | HTTP client | Already in project; booking push + delay report via existing `DioClient.pushWithIdempotency` |
| go_router | ^17.1.0 | Navigation | Already in project; add contractor calendar + schedule settings routes to Branch 2 |
| freezed_annotation | ^3.1.0 | Immutable entities | Already in project; `BookingEntity` follows `JobEntity` pattern |

### New Dependency (One Addition)

| Library | Version | Purpose | Why Standard |
|---------|---------|---------|--------------|
| patterns_canvas | ^0.5.0 | Diagonal stripe pattern for travel time blocks | Pure Dart, no platform channels, MIT license, verified publisher (whidev.com), paints directly via Canvas API; avoids hand-rolling diagonal line loops |

### Calendar Package Decision (Claude's Discretion Area — RESOLVED)

All third-party calendar packages were evaluated and rejected. The recommendation is a custom `CustomPainter` + `Stack` implementation.

| Package | Verdict | Reason |
|---------|---------|--------|
| kalender (v0.15.0) | REJECTED | Pre-1.0 API instability explicitly stated ("API will most likely change until 1.0"). No multi-resource side-by-side contractor lane support — assumes one timeline. |
| syncfusion_flutter_calendar | REJECTED | Commercial license required for production. Resource view exists but is heavily opinionated and fights customization. |
| table_calendar | REJECTED | Month/week date-picker only. No time axis. No drag-drop. No contractor lanes. |
| infinite_calendar_view | REJECTED | Timeline view without multi-resource lanes. Limited customization of background regions. |
| Custom (recommended) | SELECTED | Full control over contractor lanes, travel-time blocks, conflict highlights, overdue borders. Project already demonstrates custom layout fluency via `KanbanBoard` widget. |

**Installation (new dependency only):**
```bash
cd mobile && flutter pub add patterns_canvas
```

### Alternatives Considered
| Instead of | Could Use | Tradeoff |
|------------|-----------|----------|
| Custom `CustomPainter` | kalender package | kalender saves time on basic layout but doesn't support multi-contractor lane mode; pre-1.0 API risk |
| `patterns_canvas` | Hand-rolled diagonal line loop | Functionally identical; `patterns_canvas` is ~150 lines saved; low dependency risk (MIT, stable) |
| `LongPressDraggable` | `Draggable` (instant) | `Draggable` conflicts with scroll gestures on mobile; long-press delay naturally separates scroll from drag intent |

---

## Architecture Patterns

### Recommended Project Structure

```
mobile/lib/features/schedule/            # NEW feature domain
├── data/
│   ├── booking_dao.dart                 # Drift DAO: dual-write pattern (mirrors JobDao)
│   ├── booking_dao.g.dart               # Generated
│   ├── booking_sync_handler.dart        # SyncHandler: push CREATE/UPDATE/DELETE, applyPulled
│   └── job_site_sync_handler.dart       # SyncHandler: applyPulled only (read-only from server)
├── domain/
│   ├── booking_entity.dart              # Freezed entity (mirrors Booking backend model)
│   ├── booking_entity.freezed.dart      # Generated
│   └── booking_entity.g.dart           # Generated
└── presentation/
    ├── providers/
    │   ├── calendar_providers.dart      # AsyncNotifier for bookings + availability; StateProviders for view/date/filters
    │   ├── calendar_providers.g.dart    # Generated
    │   └── overdue_providers.dart       # Derived: overdue count + list from jobs stream
    ├── screens/
    │   ├── schedule_screen.dart         # Replaces placeholder; root admin dispatch calendar
    │   ├── contractor_schedule_screen.dart   # Contractor personal view (list + single lane toggle)
    │   └── schedule_settings_screen.dart     # Weekly template management (calls scheduling API)
    └── widgets/
        ├── calendar_day_view.dart       # CustomPainter grid + Stack + paginated lanes
        ├── calendar_week_view.dart      # Collapsed job cards per contractor
        ├── calendar_month_view.dart     # Job count badges per day
        ├── contractor_lane.dart         # Single contractor row: DragTarget cells + booking cards
        ├── booking_card.dart            # LongPressDraggable card: color, overdue badge, delay badge
        ├── travel_time_block.dart       # patterns_canvas diagonal stripes
        ├── unscheduled_jobs_drawer.dart # EndDrawer with filterable job queue (LongPressDraggable cards)
        ├── overdue_panel.dart           # Expandable AnimatedContainer listing overdue jobs
        └── delay_justification_dialog.dart  # StatefulBuilder dialog: reason field + date picker

mobile/lib/core/database/tables/
├── bookings.dart                        # NEW Drift table (schemaVersion v4)
└── job_sites.dart                       # NEW Drift table (for sync pull)

backend/app/features/jobs/
├── router.py   # Add PATCH /jobs/{job_id}/delay (BEFORE existing /jobs/{job_id} route)
├── service.py  # Add report_delay() method to JobService
└── schemas.py  # Add DelayReportRequest schema
```

### Pattern 1: Drift Schema v4 Migration

**What:** Add `Bookings` and `JobSites` tables; bump `schemaVersion` to 4.
**When to use:** Required for local booking storage (offline-first dispatch board).
**Example:**
```dart
// mobile/lib/core/database/tables/bookings.dart
class Bookings extends Table {
  TextColumn get id => text().clientDefault(() => const Uuid().v4())();
  TextColumn get companyId => text()();
  TextColumn get contractorId => text()();
  TextColumn get jobId => text()();
  TextColumn get jobSiteId => text().nullable()();
  // TSTZRANGE stored as two UTC datetimes (SQLite has no TSTZRANGE)
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

// In AppDatabase:
@override
int get schemaVersion => 4;  // was 3

// In onUpgrade:
if (from < 4) {
  await m.createTable(bookings);
  await m.createTable(jobSites);
}
```

### Pattern 2: BookingDao Dual-Write (mirrors JobDao exactly)

**What:** Every mutation writes to `Bookings` table AND `SyncQueue` in a single `db.transaction`. This is the established outbox pattern from `JobDao`.
**When to use:** Every booking CREATE/UPDATE/DELETE.
**Example:**
```dart
// Source: established pattern from mobile/lib/features/jobs/data/job_dao.dart
@DriftAccessor(tables: [Bookings, SyncQueue])
class BookingDao extends DatabaseAccessor<AppDatabase> with _$BookingDaoMixin {
  BookingDao(super.db);

  Stream<List<BookingEntity>> watchBookingsByContractorDate(
    String contractorId,
    DateTime date,
  ) {
    final dayStart = DateTime(date.year, date.month, date.day).toUtc();
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

  Future<void> upsertBookingFromSync(BookingsCompanion companion) async {
    await into(bookings).insertOnConflictUpdate(companion);
  }
}
```

### Pattern 3: Custom Calendar Day View with CustomPainter + DragTarget Grid

**What:** The day view renders a time axis and a `PageView` of contractor lane pages (5 per page). Each lane is a `Stack` with a `CustomPainter` background (grid lines, shading) and absolute-positioned `DragTarget` cells and booking cards on top.

**Key structural insight:** Drawing 1440 widgets per lane (one per minute) is too expensive. The grid is a single `CustomPainter`; only actual bookings + DragTarget cells are separate widgets.

**Example:**
```dart
// Source: Flutter CustomPainter official docs
class CalendarGridPainter extends CustomPainter {
  final List<BlockedInterval> blockedIntervals;
  final double pixelsPerMinute;  // e.g., 1.5px/minute = 90px/hour
  final DateTime dayStart;

  @override
  void paint(Canvas canvas, Size size) {
    final linePaint = Paint()
      ..color = Colors.grey.shade200
      ..strokeWidth = 0.5;
    // Hour lines
    for (int hour = 0; hour < 24; hour++) {
      final y = hour * 60 * pixelsPerMinute;
      canvas.drawLine(Offset(0, y), Offset(size.width, y), linePaint);
    }
    // Non-working hour shading
    final shadePaint = Paint()
      ..color = Colors.grey.shade100.withOpacity(0.8)
      ..style = PaintingStyle.fill;
    for (final interval in blockedIntervals) {
      if (interval.reason == 'outside_working_hours' ||
          interval.reason == 'time_off') {
        final top = _minuteOffset(interval.start) * pixelsPerMinute;
        final bottom = _minuteOffset(interval.end) * pixelsPerMinute;
        canvas.drawRect(Rect.fromLTRB(0, top, size.width, bottom), shadePaint);
      }
    }
  }

  double _minuteOffset(DateTime dt) =>
      dt.difference(dayStart).inMinutes.toDouble();

  @override
  bool shouldRepaint(CalendarGridPainter old) =>
      old.pixelsPerMinute != pixelsPerMinute ||
      old.blockedIntervals != blockedIntervals;
}
```

### Pattern 4: LongPressDraggable + DragTarget for Booking Drop

**What:** Booking cards in the lane and unscheduled cards in the sidebar are `LongPressDraggable`. The contractor lane has `DragTarget` cells (15-minute slot height each). `onWillAcceptWithDetails` checks local Drift data for conflicts (synchronous, offline-capable); `onAcceptWithDetails` triggers the Drift dual-write + sync queue.

**Critical:** `onWillAccept` is deprecated since Flutter 3.14. Use `onWillAcceptWithDetails`.

```dart
// Source: https://api.flutter.dev/flutter/widgets/LongPressDraggable-class.html
LongPressDraggable<BookingDragData>(
  data: BookingDragData(
    jobId: job.id,
    jobDescription: job.description,
    durationMinutes: job.estimatedDurationMinutes ?? 60,
  ),
  feedback: Material(
    elevation: 6,
    borderRadius: BorderRadius.circular(8),
    child: SizedBox(
      width: laneWidth - 8,
      height: (job.estimatedDurationMinutes ?? 60) * pixelsPerMinute,
      child: BookingCard(job: job, isDragging: true),
    ),
  ),
  childWhenDragging: Opacity(opacity: 0.3, child: BookingCard(job: job)),
  child: BookingCard(job: job),
)

// DragTarget — one per 15-minute time slot per contractor lane
DragTarget<BookingDragData>(
  onWillAcceptWithDetails: (details) {
    // Synchronous check against local Drift data — no network call
    return _isSlotFree(contractorId, slotStart, details.data.durationMinutes);
  },
  onAcceptWithDetails: (details) {
    _scheduleBooking(details.data, contractorId, slotStart);
  },
  builder: (context, candidateData, rejectedData) {
    final isActive = candidateData.isNotEmpty;
    final hasConflict = rejectedData.isNotEmpty;
    return Container(
      height: slotHeightPx,  // 15 * pixelsPerMinute
      color: isActive
          ? Colors.green.withOpacity(0.25)
          : hasConflict
              ? Colors.red.withOpacity(0.25)
              : Colors.transparent,
    );
  },
)
```

### Pattern 5: Travel Time Hatched Block (patterns_canvas)

**What:** `BlockedInterval` entries with `reason == "travel_buffer"` render as diagonal-striped rectangles on the contractor lane.

```dart
// Source: https://pub.dev/packages/patterns_canvas (v0.5.0, MIT)
import 'package:patterns_canvas/patterns_canvas.dart';

class TravelTimeBlockPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    DiagonalStripesLight(
      bgColor: Colors.grey.shade200,
      fgColor: Colors.grey.shade400,
    ).paintOnRect(canvas, size, rect);
  }

  @override
  bool shouldRepaint(TravelTimeBlockPainter old) => false;
}

class TravelTimeBlock extends StatelessWidget {
  final double heightPixels;
  final double widthPixels;
  const TravelTimeBlock({required this.heightPixels, required this.widthPixels, super.key});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: heightPixels,
      width: widthPixels,
      child: CustomPaint(painter: TravelTimeBlockPainter()),
    );
  }
}
```

### Pattern 6: Overdue Detection (Pure Local Computation)

**What:** A Riverpod derived provider computes overdue jobs by filtering the existing `jobListNotifierProvider` stream. Zero network calls — works fully offline.

**Date normalization critical:** Compare date portions only to avoid timezone-induced false positives on the due date itself.

```dart
// Source: Riverpod 3 provider pattern (mirrors existing job_providers.dart)
// import 'package:flutter_riverpod/legacy.dart'; not needed here — not a StateProvider

@riverpod
List<JobEntity> overdueJobs(OverdueJobsRef ref) {
  final jobsAsync = ref.watch(jobListNotifierProvider);
  return jobsAsync.when(
    data: (jobs) {
      final today = DateTime(DateTime.now().year, DateTime.now().month, DateTime.now().day);
      return jobs.where((job) {
        final isActiveStatus = job.status == 'scheduled' || job.status == 'in_progress';
        final eta = job.scheduledCompletionDate;
        if (!isActiveStatus || eta == null || job.deletedAt != null) return false;
        // Compare date portions only (avoid UTC midnight vs local noon false positives)
        final etaDate = DateTime(eta.year, eta.month, eta.day);
        return today.isAfter(etaDate);
      }).toList();
    },
    loading: () => [],
    error: (_, __) => [],
  );
}

@riverpod
int overdueJobCount(OverdueJobCountRef ref) =>
    ref.watch(overdueJobsProvider).length;

OverdueSeverity computeSeverity(DateTime scheduledCompletionDate) {
  final today = DateTime(DateTime.now().year, DateTime.now().month, DateTime.now().day);
  final etaDate = DateTime(
    scheduledCompletionDate.year,
    scheduledCompletionDate.month,
    scheduledCompletionDate.day,
  );
  final daysOverdue = today.difference(etaDate).inDays;
  if (daysOverdue >= 4) return OverdueSeverity.critical;   // red border
  if (daysOverdue >= 1) return OverdueSeverity.warning;    // orange border
  return OverdueSeverity.none;
}
```

### Pattern 7: NavigationBar Badge (AppShell modification)

**What:** Flutter's built-in Material 3 `Badge` widget wraps the Schedule tab icon. The badge count comes from `overdueJobCountProvider`. `AppShell` must become a `ConsumerWidget` (it already is — confirmed in codebase) and pass the count to the `NavigationDestination`.

```dart
// Source: Flutter Badge class - material library (Material 3)
// In app_shell.dart — build() now watches overdueJobCountProvider:
final overdueCount = ref.watch(overdueJobCountProvider);

NavigationDestination(
  icon: Badge(
    isLabelVisible: overdueCount > 0,
    label: Text('$overdueCount'),
    backgroundColor: Colors.red,
    child: const Icon(Icons.calendar_month_outlined),
  ),
  selectedIcon: Badge(
    isLabelVisible: overdueCount > 0,
    label: Text('$overdueCount'),
    backgroundColor: Colors.red,
    child: const Icon(Icons.calendar_month),
  ),
  label: 'Schedule',
),
```

### Pattern 8: Delay Justification Backend Endpoint (New)

**What:** New `PATCH /api/v1/jobs/{job_id}/delay` endpoint appends a `{type: "delay", ...}` entry to `status_history` JSONB and updates `scheduled_completion_date`. NOT a status lifecycle transition — job stays in same status. Follows the same list-replacement pattern established in `transition_status`.

**Route ordering critical:** Declare BEFORE `GET /jobs/{job_id}` to prevent FastAPI matching "delay" as a UUID job_id parameter (established STATE.md pattern for route ordering).

```python
# backend/app/features/jobs/schemas.py — Add:
class DelayReportRequest(BaseModel):
    """Payload for reporting a job delay.

    Appends a {type: delay} entry to status_history JSONB and updates
    scheduled_completion_date to new_eta. Does NOT change job.status.
    version is required for optimistic locking (same as JobTransitionRequest).
    """
    reason: str = Field(min_length=1)
    new_eta: date
    version: int


# backend/app/features/jobs/service.py — Add to JobService class:
async def report_delay(
    self,
    job_id: uuid.UUID,
    data: "DelayReportRequest",
    *,
    user_id: uuid.UUID,
) -> Job:
    """Append delay entry to status_history; update scheduled_completion_date.

    Validates: job exists, version matches, job is in scheduled/in_progress.
    Does NOT transition lifecycle status.
    Uses list replacement (not in-place append) per Pitfall 3 pattern.
    """
    job = await self.repository.get_by_id(job_id)
    if job is None:
        raise HTTPException(status_code=404, detail=f"Job {job_id} not found")
    if job.version != data.version:
        raise HTTPException(
            status_code=409,
            detail=f"Version conflict: expected {data.version}, job is at {job.version}. Fetch latest and retry.",
        )
    if job.status not in ('scheduled', 'in_progress'):
        raise HTTPException(
            status_code=422,
            detail="Delay can only be reported on jobs in 'scheduled' or 'in_progress' status.",
        )
    delay_entry: dict[str, Any] = {
        "type": "delay",
        "reason": data.reason,
        "new_eta": data.new_eta.isoformat(),
        "timestamp": datetime.now(UTC).isoformat(),
        "user_id": str(user_id),
    }
    # List replacement (never in-place append) — SQLAlchemy JSONB change detection
    job.status_history = [*job.status_history, delay_entry]
    job.scheduled_completion_date = data.new_eta
    job.version = job.version + 1  # type: ignore[assignment]
    await self.db.flush()
    await self.db.refresh(job)
    return job


# backend/app/features/jobs/router.py — Add BEFORE existing /jobs/{job_id} routes:
@router.patch("/jobs/{job_id}/delay", response_model=JobResponse)
async def report_job_delay(
    job_id: uuid.UUID,
    delay_data: DelayReportRequest,
    db: AsyncSession = Depends(get_db),
    current_user: CurrentUser = Depends(get_current_user),
) -> JobResponse:
    """Report a delay for a job in scheduled/in_progress status.

    Available to contractors (own jobs) and admins. Does NOT change job status.
    Returns 404 if not found, 409 on version conflict, 422 if wrong status.
    """
    svc = JobService(db)
    job = await svc.report_delay(job_id, delay_data, user_id=current_user.id)
    return JobResponse.model_validate(job)
```

### Pattern 9: Undo Snackbar (5-second explicit duration)

**What:** Show `SnackBar` immediately on drop with explicit `duration`. Apply sync queue write only after undo window expires.

**Breaking change (Flutter 3.29+):** `SnackBar` with an `action` no longer auto-dismisses. Must set `duration` explicitly.

```dart
// Source: Flutter docs + confirmed breaking change in 3.29
ScaffoldMessenger.of(context).showSnackBar(
  SnackBar(
    content: Text('Booked: ${job.description}'),
    // REQUIRED: must be explicit — Flutter 3.29+ no longer auto-dismisses with action
    duration: const Duration(seconds: 5),
    action: SnackBarAction(
      label: 'Undo',
      onPressed: () => ref.read(calendarNotifier.notifier).undoLastOperation(),
    ),
  ),
);
```

### Pattern 10: SyncEngine pullDelta Extension for Bookings

**What:** `SyncEngine.pullDelta()` hardcodes entity types. Add `bookings` and `job_sites` handlers to the pull loop. This mirrors the existing pattern for `companies`, `users`, `user_roles`, `jobs`.

```dart
// In mobile/lib/core/sync/sync_engine.dart pullDelta():
final List<dynamic>? pullBookings = data['bookings'] as List<dynamic>?;
if (pullBookings != null) {
  final handler = _registry.getHandler('booking');
  for (final entity in pullBookings) {
    await handler.applyPulled(entity as Map<String, dynamic>);
  }
}

final List<dynamic>? pullJobSites = data['job_sites'] as List<dynamic>?;
if (pullJobSites != null) {
  final handler = _registry.getHandler('job_site');
  for (final entity in pullJobSites) {
    await handler.applyPulled(entity as Map<String, dynamic>);
  }
}
```

### Pattern 11: Unscheduled Jobs Sidebar as EndDrawer

**What:** Use `Scaffold.endDrawer` to keep the full calendar visible when the drawer is closed. Open via `scaffoldKey.currentState!.openEndDrawer()`.

```dart
Scaffold(
  key: _scaffoldKey,
  endDrawer: UnscheduledJobsDrawer(
    // Close drawer when user starts dragging (gives full calendar visibility)
    onDragStarted: () => _scaffoldKey.currentState?.closeEndDrawer(),
  ),
  body: CalendarDayView(...),
  floatingActionButton: FloatingActionButton(
    onPressed: () => _scaffoldKey.currentState?.openEndDrawer(),
    child: const Icon(Icons.queue),
    tooltip: 'Unscheduled jobs',
  ),
)
```

### Anti-Patterns to Avoid

- **Nested ScrollViews with shared direction:** The day view has a vertical `ScrollController` (time axis) and horizontal `PageView` (contractor lane pages). Keep these as siblings, not nested scrollables.
- **Widget-per-minute time grid:** Building 1440 widget cells per lane causes layout thrashing. Use `CustomPainter` for the grid background; only actual bookings and `DragTarget` cells are widgets.
- **`onWillAccept` on DragTarget:** Deprecated since Flutter 3.14. Use `onWillAcceptWithDetails` with `DragTargetDetails<T>`.
- **In-place status_history mutation in backend:** `job.status_history.append(entry)` is never detected by SQLAlchemy JSONB change tracking. Always use list replacement: `job.status_history = [*job.status_history, entry]`. (Established pitfall from Phase 4 STATE.md.)
- **Calling DioClient directly from drag callbacks:** Drag accept callbacks must be fast. Use Drift dual-write (offline-first) — sync happens in background. Never `await` HTTP inside `onAcceptWithDetails`.
- **Declaring delay route after /jobs/{job_id}:** FastAPI would match "delay" as a UUID job_id param and return 422. (Established pitfall from Phase 4 route ordering STATE.md.)
- **Unregistered sync handlers silently park items:** `SyncEngine.drainQueue` catches `StateError` for unregistered entity types and calls `markParked`. Register `BookingSyncHandler` and `JobSiteSyncHandler` in `setupServiceLocator` BEFORE `SyncEngine.initialize()`.

---

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| Diagonal stripe "travel time" blocks | Custom line-drawing paint loop | `patterns_canvas` `DiagonalStripesLight.paintOnRect()` | Handles clip boundaries, angle, spacing, bg/fg color automatically |
| Overdue badge on nav bar | Stacked `Container` + `Positioned` | Flutter `Badge` widget (Material 3) | Built-in, theme-aware, handles label overflow; already available in this project (Flutter 3.32+) |
| Conflict check during live drag | Custom in-memory overlap logic | Query local Drift `Bookings` stream | Drift already has all bookings locally; simple DateTime range overlap check on the existing stream |
| Date picker for delay ETA | Custom date input field | `showDatePicker()` (built-in) | Material date picker with locale support; `firstDate` constraint prevents past ETAs |
| Booking sync push | Custom HTTP client logic | `DioClient.pushWithIdempotency(method: 'PATCH')` | Already extended in Phase 4 to support PATCH/DELETE; booking operations map directly |
| Scroll sync across contractor lanes + time axis | Complex ScrollNotifier chains | Shared `ScrollController` instance passed to all vertical scrollables | Flutter `ScrollController` supports multiple attached positions (built-in behavior, see `ScrollController.positions`) |
| Snackbar auto-dismiss detection | Timer management | `ScaffoldMessenger.showSnackBar` with explicit `duration` | Built-in; handles dismissal, action callbacks, and queue management |

**Key insight:** The scheduling engine (Phase 3) and job lifecycle (Phase 4) built all backend conflict detection, availability computation, booking creation, and status_history management. Phase 5 is entirely UI consumption of those APIs — the logic is done; only the visualization remains.

---

## Common Pitfalls

### Pitfall 1: SnackBar with Action Does Not Auto-Dismiss in Flutter 3.29+

**What goes wrong:** The undo snackbar stays visible indefinitely, blocking the UI.
**Why it happens:** Flutter 3.29 introduced a breaking change — `SnackBar` with an `action` no longer auto-dismisses by default to comply with Material Design accessibility guidelines.
**How to avoid:** Always set an explicit `duration: const Duration(seconds: 5)` on every `SnackBar` in this phase.
**Warning signs:** Snackbar visible after 10+ seconds during testing.

### Pitfall 2: StateProvider Import in Riverpod 3

**What goes wrong:** `StateProvider` import fails or produces deprecation warnings in new schedule provider files.
**Why it happens:** Riverpod 3 moved `StateProvider` to `package:riverpod/legacy.dart`.
**How to avoid:** Use `import 'package:riverpod/legacy.dart';` for all `StateProvider` and `StateNotifierProvider` uses. This is already the established project pattern — documented in STATE.md and visible in `job_providers.dart`.
**Warning signs:** "StateProvider is not defined" compilation error.

### Pitfall 3: Synchronized Vertical Scroll Requires Shared ScrollController

**What goes wrong:** Time axis and contractor lanes scroll independently; "now" line drifts out of sync with visible time slots.
**Why it happens:** Each `SingleChildScrollView` or `ListView` creates its own scroll position by default.
**How to avoid:** Create one `ScrollController` in the parent widget state and pass it to both the time axis column and each contractor lane column. Flutter's `ScrollController` supports multiple attached positions — driving them in sync.
**Warning signs:** Time axis shows "9:00 AM" while contractor lane content shows "2:00 PM" area.

### Pitfall 4: Drift DateTime Is UTC — Display Must Call .toLocal()

**What goes wrong:** Booking times display wrong timezone (off by hours for non-UTC users).
**Why it happens:** Drift stores `DateTime` as UTC microseconds. The backend sends UTC ISO-8601 strings. Display without `.toLocal()` shows UTC times.
**How to avoid:** When rendering booking start/end times in any widget, always convert: `booking.timeRangeStart.toLocal()`. Store in Drift as UTC; display with `.toLocal()`.
**Warning signs:** Bookings appear to start/end at wrong hours on device.

### Pitfall 5: Route Ordering — Delay Endpoint Must Be Before /jobs/{job_id}

**What goes wrong:** `PATCH /api/v1/jobs/{job_id}/delay` returns 422 "value is not a valid uuid" when called, because FastAPI matches "delay" as the `job_id` path parameter against the earlier `GET /jobs/{job_id}` route.
**Why it happens:** FastAPI route matching is first-match-wins in declaration order.
**How to avoid:** Declare `PATCH /jobs/{job_id}/delay` BEFORE any `@router.get("/{job_id}")`, `@router.patch("/{job_id}")`, or `@router.delete("/{job_id}")` routes. This is the established STATE.md pattern from Phase 4.
**Warning signs:** 422 with UUID validation error when the delay endpoint URL is correct.

### Pitfall 6: Drag Gesture Conflict Between Scroll and Booking Drag

**What goes wrong:** Attempting to scroll the time axis accidentally initiates a drag on a booking card.
**Why it happens:** Flutter's gesture arena has ambiguity between vertical scroll and drag gestures.
**How to avoid:** Use `LongPressDraggable` (not `Draggable`). The long-press delay (300ms+ default) naturally separates scroll intent from drag intent. The haptic feedback confirms drag mode started. Never use `Draggable` for booking cards — it fires immediately and conflicts with scroll.
**Warning signs:** Calendar scrolling unpredictably initiates drag mode.

### Pitfall 7: Drift Migration Must Handle All Upgrade Paths

**What goes wrong:** `if (from < 4)` block creates bookings table, but for a user upgrading from v1, the `if (from < 2)` and `if (from < 3)` blocks also run — they must be self-contained. If any block references tables that don't exist in older schemas, migration fails.
**Why it happens:** Each migration guard runs independently. The v4 guard adds tables that reference `companies` — that table exists from v1. The migration is safe, but this must be verified for every column reference.
**How to avoid:** Each migration block is self-contained with no references to columns or tables added in later blocks. Test cold migration from v1 to v4 (full install path), not just v3 to v4.
**Warning signs:** `DatabaseException: table X not found` on first launch for existing users upgrading from old app version.

### Pitfall 8: Overdue Computation Time-of-Day Normalization

**What goes wrong:** Jobs appear overdue during the morning on their scheduled completion date.
**Why it happens:** `scheduledCompletionDate` is stored as a UTC datetime with time component = 00:00:00Z. A device in UTC+5 at 8:00 AM local time is already past midnight UTC on that date.
**How to avoid:** Compare date portions only — strip the time component from both `now` and `eta`:
```dart
final today = DateTime(DateTime.now().year, DateTime.now().month, DateTime.now().day);
final etaDate = DateTime(eta.year, eta.month, eta.day);
return today.isAfter(etaDate);  // only true on the NEXT calendar day
```
**Warning signs:** Booking cards show overdue warning on the scheduled completion date itself (before end of day).

---

## Code Examples

Verified patterns from codebase and official documentation:

### JobStatus Color Mapping Extension

```dart
// Extend existing mobile/lib/features/jobs/domain/job_status.dart
// Add this getter to the JobStatus enum:
Color get calendarColor {
  return switch (this) {
    JobStatus.quote => Colors.grey,
    JobStatus.scheduled => Colors.blue,
    JobStatus.inProgress => Colors.orange,
    JobStatus.complete => Colors.green,
    JobStatus.invoiced => Colors.purple,
    JobStatus.cancelled => Colors.red,
  };
}
```

### Booking Entity (Freezed pattern from job_entity.dart)

```dart
// Source: mobile/lib/features/jobs/domain/job_entity.dart pattern
@freezed
abstract class BookingEntity with _$BookingEntity {
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

  factory BookingEntity.fromJson(Map<String, dynamic> json) =>
      _$BookingEntityFromJson(json);
}
```

### Overdue Booking Card Border

```dart
// Computed in booking_card.dart based on job's scheduledCompletionDate
BoxDecoration? _overdueDecoration(JobEntity job) {
  final eta = job.scheduledCompletionDate;
  if (eta == null) return null;
  final today = DateTime(DateTime.now().year, DateTime.now().month, DateTime.now().day);
  final etaDate = DateTime(eta.year, eta.month, eta.day);
  final daysOverdue = today.difference(etaDate).inDays;
  if (daysOverdue >= 4) {
    return BoxDecoration(
      border: Border.all(color: Colors.red, width: 2),
      borderRadius: BorderRadius.circular(6),
    );
  }
  if (daysOverdue >= 1) {
    return BoxDecoration(
      border: Border.all(color: Colors.orange, width: 2),
      borderRadius: BorderRadius.circular(6),
    );
  }
  return null;
}
```

### Delay Justification Dialog (Flutter)

```dart
// Uses StatefulBuilder inside showDialog so ETA state updates rebuild in-dialog
Future<(String reason, DateTime eta)?> showDelayDialog(
  BuildContext context,
  JobEntity job,
) async {
  final reasonController = TextEditingController();
  DateTime? selectedEta;

  return showDialog<(String, DateTime)?>(
    context: context,
    barrierDismissible: false,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setState) => AlertDialog(
        title: const Text('Report Delay'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: reasonController,
              decoration: const InputDecoration(
                labelText: 'Reason for delay *',
                hintText: 'Describe what caused the delay...',
              ),
              maxLines: 3,
            ),
            const SizedBox(height: 16),
            ListTile(
              title: Text(selectedEta == null
                  ? 'Select new ETA *'
                  : 'New ETA: ${DateFormat.yMMMd().format(selectedEta!)}'),
              trailing: const Icon(Icons.calendar_today),
              onTap: () async {
                final picked = await showDatePicker(
                  context: ctx,
                  initialDate: DateTime.now().add(const Duration(days: 1)),
                  firstDate: DateTime.now().add(const Duration(days: 1)),
                  lastDate: DateTime.now().add(const Duration(days: 365)),
                );
                if (picked != null) setState(() => selectedEta = picked);
              },
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: (reasonController.text.isNotEmpty && selectedEta != null)
                ? () => Navigator.pop(ctx, (reasonController.text, selectedEta!))
                : null,
            child: const Text('Submit'),
          ),
        ],
      ),
    ),
  );
}
```

---

## State of the Art

| Old Approach | Current Approach | When Changed | Impact |
|--------------|------------------|--------------|--------|
| `SnackBar` with action auto-dismisses | Must set explicit `duration` | Flutter 3.29 (2025) | Undo snackbar stays forever without `duration: const Duration(seconds: 5)` |
| `StateProvider` in main riverpod export | `StateProvider` in `legacy.dart` | Riverpod 3.0 | Import must be `package:riverpod/legacy.dart` (already done in `job_providers.dart`) |
| Custom `Container` + `Positioned` for nav badges | Flutter `Badge` widget | Flutter 3.22+ (Material 3) | Native, theme-aware badge; no custom stacking needed |
| `onWillAccept` on `DragTarget` | `onWillAcceptWithDetails` | Flutter 3.14 | Must use `WithDetails` variant; old callback deprecated |
| `BottomNavigationBar` | `NavigationBar` (Material 3) | Flutter 3.x | Project already uses M3 `NavigationBar` — `Badge` wraps icon naturally |

**Deprecated/outdated (avoid):**
- `Draggable` for mobile booking cards: use `LongPressDraggable` to avoid scroll conflict
- `onWillAccept` on `DragTarget`: use `onWillAcceptWithDetails`
- `StateProvider` in main Riverpod export: use `package:riverpod/legacy.dart`

---

## Open Questions

1. **Does the backend `/api/v1/sync` pull endpoint already include `bookings` and `job_sites`?**
   - What we know: The backend pull endpoint already handles `companies`, `users`, `user_roles`, `jobs`, `client_profiles`, `client_properties`, `job_requests`. Bookings and job_sites are backend entities from Phase 3.
   - What's unclear: Whether they were added to the pull payload during Phase 3 implementation.
   - Recommendation: Check the backend sync router before implementing `BookingSyncHandler.applyPulled`. If the pull payload doesn't include `bookings`, add them to the backend sync handler in Plan 01.

2. **`estimated_duration_minutes` is null on some jobs — what duration to use during drag?**
   - What we know: `JobEntity.estimatedDurationMinutes` is `int?` (nullable). Some jobs may not have a duration set.
   - Recommendation: Default to 60 minutes when null. Show a visual indicator ("~1h") on the dragged feedback card to signal that duration is estimated.

3. **Undo window: defer sync queue write vs. CREATE+DELETE sequence?**
   - What we know: The 5-second undo window means the sync_queue write should ideally be deferred. Immediate sync_queue write + DELETE on undo creates a CREATE+DELETE pair in the outbox that must be ordered correctly.
   - Recommendation: Use `Timer(const Duration(seconds: 5), _writeSyncQueueEntry)` inside `BookingDao`. Cancel the timer if undo is pressed. Only the Drift entity table write is immediate (for optimistic UI). The outbox write is deferred. Document this explicitly in `BookingDao` comments as a design decision.

---

## Sources

### Primary (HIGH confidence — verified against project codebase)
- `/mobile/lib/features/jobs/data/job_dao.dart` — dual-write transaction pattern; `BookingDao` template
- `/mobile/lib/core/database/app_database.dart` — `schemaVersion = 3`; v4 migration pattern
- `/mobile/lib/core/sync/sync_engine.dart` — `pullDelta` entity handling loop; `drainQueue` pattern
- `/mobile/lib/core/routing/app_router.dart` — Branch 2 sub-route pattern; `StatefulShellBranch`
- `/mobile/lib/shared/widgets/app_shell.dart` — `NavigationBar` structure; `ConsumerWidget` confirmed
- `/mobile/lib/features/jobs/presentation/widgets/kanban_board.dart` — custom layout precedent
- `/mobile/lib/features/jobs/domain/job_status.dart` — `JobStatus` enum for color mapping extension
- `/mobile/lib/features/jobs/presentation/providers/job_providers.dart` — `import 'package:riverpod/legacy.dart'` pattern; `AsyncNotifier` pattern
- `/backend/app/features/scheduling/router.py` — all scheduling endpoints verified
- `/backend/app/features/scheduling/schemas.py` — `BlockedInterval`, `BookingResponse`, `ConflictDetail`
- `/backend/app/features/jobs/service.py` — `status_history` list replacement pattern

### Secondary (HIGH confidence — official sources)
- [Flutter DragTarget API](https://api.flutter.dev/flutter/widgets/DragTarget-class.html) — `onWillAcceptWithDetails` confirmed; `onWillAccept` deprecated after 3.14
- [Flutter LongPressDraggable API](https://api.flutter.dev/flutter/widgets/LongPressDraggable-class.html) — `hapticFeedbackOnStart`, `feedback`, `childWhenDragging` confirmed
- [patterns_canvas pub.dev](https://pub.dev/packages/patterns_canvas) — v0.5.0, MIT license, verified publisher (whidev.com), `DiagonalStripesLight.paintOnRect()` API verified
- [kalender pub.dev](https://pub.dev/packages/kalender) — v0.15.0, pre-1.0 API instability confirmed → rejected
- [Flutter Badge class](https://api.flutter.dev/flutter/material/Badge-class.html) — `isLabelVisible`, `label`, `backgroundColor` confirmed for Material 3

### Tertiary (MEDIUM confidence — WebSearch, consistent with project patterns)
- Flutter 3.29 SnackBar breaking change — explicit `duration` required with `action`; consistent with official changelog reference
- Riverpod 3 `StateProvider` legacy import — consistent with existing `job_providers.dart` pattern in codebase

---

## Metadata

**Confidence breakdown:**
- Standard stack: HIGH — all existing packages confirmed from `pubspec.yaml`; `patterns_canvas` verified on pub.dev; calendar package decision supported by concrete rejection reasons for all alternatives
- Architecture: HIGH — all patterns derived directly from existing codebase (JobDao, SyncEngine, AppShell, KanbanBoard, job_providers)
- Pitfalls: HIGH — each pitfall sourced from STATE.md decisions (Phases 2, 3, 4), official Flutter breaking change docs, or SQLAlchemy JSONB behavior documented in Phase 4
- Delay endpoint: HIGH — mirrors `transition_status` pattern exactly; no new OOP base classes needed
- Scroll sync (Pitfall 3): MEDIUM — Flutter `ScrollController.positions` supports multi-attachment but needs validation during Plan 05-02 implementation

**Research date:** 2026-03-09
**Valid until:** 2026-04-09 (30 days — Flutter/Dart ecosystem stable; `patterns_canvas` unlikely to change)
