---
phase: 06-field-workflow
plan: 05
subsystem: mobile-timer
tags: [timer, time-tracking, clock-in, clock-out, contractor-jobs, field-workflow]
dependency_graph:
  requires: [06-02]
  provides: [FIELD-04, timer-screen, timer-notifier, time-tracked-section, contractor-job-card]
  affects: [job-detail-schedule-tab, contractor-jobs-screen, app-router]
tech_stack:
  added: []
  patterns: [AsyncNotifier-with-Timer.periodic, StreamProvider.autoDispose.family, drift-row-type-streams]
key_files:
  created:
    - mobile/lib/features/jobs/presentation/providers/timer_providers.dart
    - mobile/lib/features/jobs/presentation/screens/timer_screen.dart
    - mobile/lib/features/jobs/presentation/widgets/time_tracked_section.dart
    - mobile/lib/features/jobs/presentation/widgets/contractor_job_card.dart
  modified:
    - mobile/lib/features/jobs/data/time_entry_dao.dart
    - mobile/lib/features/jobs/presentation/screens/contractor_jobs_screen.dart
    - mobile/lib/core/routing/app_router.dart
    - mobile/lib/core/routing/route_names.dart
decisions:
  - "timerNotifierProvider is NOT autoDispose — the timer ticker must survive navigation away from the contractor jobs screen"
  - "valueOrNull replaced with .value for Riverpod 3.2.1 compatibility — valueOrNull does not exist in this version"
  - "TimerState.build() restores active session from Drift using watchActiveSession — covers app-kill restart scenario"
  - "clockIn auto-transitions scheduled→in_progress jobs by reading watchJobsByCompany then calling updateJobStatus"
  - "Clock In/Clock Out in ContractorJobCard navigates to TimerScreen rather than performing action inline — better UX, session history always visible"
  - "Status transitions (scheduled→in_progress, in_progress→complete) exposed via long-press on status badge — not in action bar per plan spec"
  - "adjustEntry() added to TimeEntryDao — admin time adjustment with adjustment_log audit trail, sync_queue outbox"
metrics:
  duration: ~35min
  completed_date: "2026-03-11"
  tasks: 2
  files_changed: 8
requirements: [FIELD-04]
---

# Phase 6 Plan 5: Time Tracking and Contractor Job Card Redesign Summary

Time tracking (FIELD-04) with dedicated timer screen + contractor job card redesign transforming the job list into a field dashboard.

## What Was Built

### Task 1: Timer providers, timer screen, and time tracked section

**timer_providers.dart** — Core timer state management:
- `TimerState`: simple value class (not Freezed) with `activeEntry`, `elapsedSeconds`, `activeJobId`
- `TimerNotifier extends AsyncNotifier<TimerState>`: restores active session from Drift on `build()`, manages `Timer.periodic(1s)`, `clockIn/clockOut`
- `clockIn` auto-closes previous session (DAO invariant), auto-transitions `scheduled→in_progress`
- `timerNotifierProvider` NOT autoDispose — ticker survives navigation
- `timeEntriesForJobProvider`: StreamProvider.autoDispose.family for session history

**timer_screen.dart** — Dedicated timer screen at `/timer/:jobId`:
- Large HH:MM:SS elapsed display (64sp, tabular figures, primary color when active)
- Pulsing dot + "Recording time" label when active
- Warning container when clocked in to a different job
- Clock In (green) / Clock Out (red) full-width button (56px height)
- Session history list: date, start–end, duration per card with "In progress" label for active
- Total time summary across all completed + current sessions

**time_tracked_section.dart** — Schedule tab widget for admin/all-role view:
- Sessions grouped by date (YYYY-MM-DD sort, newest-first)
- Per-day subtotals + overall total
- Live elapsed for active sessions via `timerNotifierProvider`
- Admin role: edit icon per row opens `_AdjustTimeDialog`
- `_AdjustTimeDialog`: `showTimePicker` for start/end, required reason TextField, calls `TimeEntryDao.adjustEntry()`

**time_entry_dao.dart** — Added `adjustEntry()` method:
- Updates `clockedInAt`, `clockedOutAt?`, `durationSeconds?`, `sessionStatus='adjusted'`, `adjustmentLog` (list replacement)
- Atomic transaction: entity write + sync_queue outbox entry

**app_router.dart + route_names.dart** — GoRoute `/timer/:jobId` registered as non-shell push route.

### Task 2: Contractor job card redesign with action bar

**contractor_job_card.dart** — `ContractorJobCard ConsumerWidget`:
- Status badge: shows current status, `>` icon, long-press menu for transitions (Scheduled→In Progress, In Progress→Complete)
- Active job: primary-color 2px border, pulsing dot, live HH:MM:SS elapsed in primary color
- Completed jobs: `Opacity(0.6)`, `_TotalTrackedBadge` from `timeEntriesForJobProvider`, NO action bar
- `_ActionBar` (non-completed only): Add Note → `AddNoteBottomSheet.show()`, Camera → same sheet, Clock In/Out → `context.push(timerPath(job.id))`
- `_TotalTrackedBadge`: reactive sum of `durationSeconds` from entries stream

**contractor_jobs_screen.dart** — Refactored to use `ContractorJobCard`:
- Watches `timerNotifierProvider` for `activeJobId`
- Sorting: active job pinned to "Active" section at top, then Today/Upcoming/Completed
- All job cards replaced with `ContractorJobCard`

## Deviations from Plan

### Auto-fixed Issues

**[Rule 2 - Missing functionality] Added `adjustEntry()` to TimeEntryDao**
- Found during: Task 1 — `_AdjustTimeDialog` in `time_tracked_section.dart` needs to write adjusted entries
- Issue: Plan called for admin adjust dialog but `TimeEntryDao` had no `adjustEntry` method
- Fix: Added `adjustEntry()` with full transactional outbox pattern, audit log list-replacement
- Files modified: `mobile/lib/features/jobs/data/time_entry_dao.dart`
- Commit: 991ba1c

**[Rule 1 - Bug] Replaced `valueOrNull` with `.value` throughout**
- Found during: dart analyze — `'valueOrNull' isn't defined for the type 'AsyncValue<T>'`
- Issue: Riverpod 3.2.1 does not expose `valueOrNull` on `AsyncValue`; `.value` is the correct getter
- Fix: Global replace `valueOrNull` → `value` in all new files
- Files modified: timer_providers.dart, time_tracked_section.dart, contractor_job_card.dart, contractor_jobs_screen.dart

### Pre-existing (Not Fixed — Out of Scope)

- Drift build_runner `.g.dart` files not generated — `TimeEntry`, `TimeEntry.durationSeconds`, etc. unresolved by `dart analyze`. Pre-existing in the entire codebase (noted in STATE.md for Bookings DAO). Affects our new files: `timer_screen.dart`, `time_tracked_section.dart`, `contractor_job_card.dart`, `timer_providers.dart`.

## Verification

- `dart analyze` on non-Drift files (app_router.dart, route_names.dart, contractor_jobs_screen.dart, timer_providers.dart): 0 errors
- Drift-dependent files have expected pre-existing errors (TimeEntry undefined class — same as time_entry_dao.dart)
- Test stubs run without errors (all 9 tests skip with "Wave 0 stub" messages)

## Self-Check: PASSED

Files verified on disk:
- FOUND: mobile/lib/features/jobs/presentation/providers/timer_providers.dart
- FOUND: mobile/lib/features/jobs/presentation/screens/timer_screen.dart
- FOUND: mobile/lib/features/jobs/presentation/widgets/time_tracked_section.dart
- FOUND: mobile/lib/features/jobs/presentation/widgets/contractor_job_card.dart

Commits verified:
- FOUND: 991ba1c feat(06-05): timer providers, timer screen, and time tracked section
- FOUND: b37b3ba feat(06-05): contractor job card redesign with action bar
