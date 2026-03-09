---
phase: 05-calendar-and-dispatch-ui
plan: 04
subsystem: ui
tags: [flutter, riverpod, drift, offline-first, overdue, delay-reporting, badge]

# Dependency graph
requires:
  - phase: 05-02
    provides: overdue_providers.dart with base overdueJobsProvider and overdueJobCountProvider
  - phase: 05-03
    provides: showOverduePanelProvider toggle in calendar_providers.dart
  - phase: 04-job-lifecycle
    provides: JobEntity, JobDao, job_detail_screen.dart, JobStatus enum
provides:
  - OverdueJobInfo model with severity, daysOverdue, hasDelayReport, latestDelayReason
  - OverduePanel widget: expandable list of overdue jobs sorted by severity tier
  - Bottom nav Schedule tab red Badge with live overdue count (visible on all tabs)
  - DelayJustificationDialog: modal enforcing reason text + new ETA before submission
  - JobDao.reportDelay: transactional Drift write + sync queue dual-write for delays
  - Job detail screen Report Delay button visible for Scheduled and In Progress jobs
affects: [05-05, 05-06]

# Tech tracking
tech-stack:
  added: []
  patterns:
    - "Material 3 Badge widget on NavigationDestination for bottom nav status indicators"
    - "AnimatedContainer overlay panel pattern for expandable calendar section"
    - "Offline delay reporting via Drift transactional outbox (no HTTP in dialog)"
    - "Static show() factory pattern on dialog class for ergonomic modal invocation"

key-files:
  created:
    - mobile/lib/features/schedule/presentation/widgets/overdue_panel.dart
    - mobile/lib/features/schedule/presentation/widgets/delay_justification_dialog.dart
  modified:
    - mobile/lib/features/schedule/presentation/providers/overdue_providers.dart
    - mobile/lib/shared/widgets/app_shell.dart
    - mobile/lib/features/jobs/presentation/screens/job_detail_screen.dart
    - mobile/lib/features/jobs/data/job_dao.dart

key-decisions:
  - "OverdueJobInfo returned as enriched model from overdueJobsProvider replacing raw JobEntity list — OverduePanel doesn't need to recompute severity/daysOverdue itself"
  - "Report Delay in bottomNavigationBar (not FAB) — visible on all three tabs without obscuring content"
  - "DelayJustificationDialog reads/writes JobDao directly (static show() factory) — clean API, avoids provider coupling inside dialog"
  - "History tab renders delay entries distinctly (schedule_send icon, red color, new ETA display) for better audit trail readability"

patterns-established:
  - "Badge widget wraps NavigationDestination icon and selectedIcon symmetrically so badge appears in both states"
  - "debugPrint in catch blocks on DAO operations — CLAUDE.md requires no silent swallowing"
  - "DateTime.utc normalization before Drift DATE storage to avoid timezone-shifted midnight reads"

requirements-completed: [SCHED-08, SCHED-09]

# Metrics
duration: 26min
completed: 2026-03-09
---

# Phase 5 Plan 04: Overdue Warnings and Delay Justification Summary

**Tiered overdue panel with severity badges, bottom nav red count badge, and offline delay reporting dialog with reason + ETA enforcement via Drift transactional outbox**

## Performance

- **Duration:** 26 min
- **Started:** 2026-03-09T21:25:00Z
- **Completed:** 2026-03-09T21:51:00Z
- **Tasks:** 2
- **Files modified:** 6

## Accomplishments

- Overdue panel lists all overdue jobs with tiered severity colors (warning=orange, critical=red), days overdue count, latest delay reason, and View Job + Contact Contractor quick actions
- Bottom nav Schedule tab shows persistent red Badge with live overdue count — visible across all tabs without entering the calendar screen
- Delay justification dialog enforces both reason text and new ETA date — barrierDismissible=false prevents accidental closure with empty fields
- JobDao.reportDelay writes atomically to Drift + sync queue: reads existing statusHistory, appends delay entry, updates scheduledCompletionDate — fully offline-capable
- Report Delay button appears on job detail screen (bottomNavigationBar) for Scheduled and In Progress jobs only; History tab shows delay entries with distinct icon and new ETA

## Task Commits

1. **Task 1: Overdue panel, bottom nav badge, and overdue provider enhancements** - `3429ff2` (feat)
2. **Task 2: Delay justification dialog and job detail integration** - `88842b9` (feat)

**Plan metadata:** (docs commit — see below)

## Files Created/Modified

- `mobile/lib/features/schedule/presentation/widgets/overdue_panel.dart` — Expandable AnimatedContainer panel listing overdue jobs with severity colors, days count, delay reasons, and action buttons
- `mobile/lib/features/schedule/presentation/widgets/delay_justification_dialog.dart` — Modal dialog with reason TextFormField + date picker ETA field; validates both before submission; calls JobDao.reportDelay
- `mobile/lib/features/schedule/presentation/providers/overdue_providers.dart` — Enhanced to return List<OverdueJobInfo> with severity, daysOverdue, hasDelayReport, latestDelayReason; sorted by severity then days overdue
- `mobile/lib/shared/widgets/app_shell.dart` — Added overdueJobCountProvider watch + Badge widget wrapping Schedule tab NavigationDestination icons
- `mobile/lib/features/jobs/presentation/screens/job_detail_screen.dart` — Added currentUserId from auth state; Report Delay button in bottomNavigationBar for active jobs; delay entries in History tab
- `mobile/lib/features/jobs/data/job_dao.dart` — Added reportDelay() method with transactional dual-write; added flutter/foundation.dart for debugPrint

## Decisions Made

- `OverdueJobInfo` returned as enriched model from `overdueJobsProvider` replacing raw `JobEntity` list — OverduePanel doesn't need to recompute severity/daysOverdue itself
- `Report Delay` placed in `bottomNavigationBar` (not FAB) — visible on all three tabs without obscuring tab content
- `DelayJustificationDialog.show()` static factory reads `JobDao` from GetIt directly — clean API, avoids provider coupling inside dialog
- History tab renders delay entries distinctly with schedule_send icon, red color, and new ETA display — better audit trail readability than generic status entries

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 2 - Missing Critical] Added debugPrint to JobDao.reportDelay catch block**
- **Found during:** Task 2 (job_dao.dart reportDelay implementation)
- **Issue:** Empty `catch (_) {}` would silently swallow JSON parse errors — CLAUDE.md requires at minimum `debugPrint`
- **Fix:** Added `flutter/foundation.dart` import and replaced `catch (_)` with `catch (e)` + `debugPrint`
- **Files modified:** mobile/lib/features/jobs/data/job_dao.dart
- **Verification:** `dart analyze` shows no errors
- **Committed in:** `88842b9` (Task 2 commit)

---

**Total deviations:** 1 auto-fixed (Rule 2 — missing critical error logging)
**Impact on plan:** Necessary for CLAUDE.md compliance and debuggability. No scope creep.

## Issues Encountered

None — plan executed cleanly. Pre-existing `dart analyze` errors in `booking_dao.dart` and `booking_entity.dart` (missing generated `.g.dart` files from Drift code gen) are out of scope.

## User Setup Required

None — no external service configuration required.

## Next Phase Readiness

- SCHED-08 (overdue warnings) and SCHED-09 (forced delay justification) are complete
- OverduePanel is ready to be embedded in ScheduleScreen (Plan 05 if applicable)
- overdueJobsProvider now returns OverdueJobInfo; any consumer that previously watched it for raw JobEntity list will need to update (Plans 05-05, 05-06)
- JobDao.reportDelay follows established transactional outbox pattern — backend sync will pick up delay updates naturally

---
*Phase: 05-calendar-and-dispatch-ui*
*Completed: 2026-03-09*
