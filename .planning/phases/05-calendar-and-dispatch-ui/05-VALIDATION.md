---
phase: 5
slug: calendar-and-dispatch-ui
status: complete
nyquist_compliant: true
created: 2026-03-14
audited: 2026-03-14
---

# Phase 5 — Validation Map

> Per-phase validation contract for feedback sampling during execution.

---

## Test Infrastructure

| Property | Value |
|----------|-------|
| **Framework** | Flutter test + mocktail (mobile), pytest 7.x (backend) |
| **Config file** | pubspec.yaml (mobile), conftest.py (backend) |
| **Quick run command** | `cd mobile && flutter test test/unit/features/schedule/ test/widget/features/schedule/` |
| **Full suite command** | `cd mobile && flutter test && cd ../backend && uv run python -m pytest` |
| **Estimated runtime** | ~60 seconds |

---

## Requirements Covered

| Requirement | Description | Plans | Coverage |
|-------------|-------------|-------|----------|
| SCHED-03 | Drag-and-drop dispatch calendar with booking management | 05-01, 05-02, 05-03, 05-05, 05-06 | COVERED |
| SCHED-08 | Overdue job warnings with tiered severity | 05-02, 05-04, 05-05, 05-06 | COVERED |
| SCHED-09 | Forced delay justification (reason + new ETA) | 05-01, 05-04, 05-06 | COVERED |

---

## Per-Task Verification Map

| Task ID | Plan | Requirement | Test Type | Automated Command | File Path | Status |
|---------|------|-------------|-----------|-------------------|-----------|--------|
| 05-01-T1 | 01 | SCHED-03 | unit (Drift) | `cd mobile && flutter test test/unit/features/schedule/booking_dao_test.dart` | mobile/test/unit/features/schedule/booking_dao_test.dart | green |
| 05-01-T2 | 01 | SCHED-09 | integration | `cd backend && uv run python -m pytest tests/integration/test_delay_endpoint.py -v` | backend/tests/integration/test_delay_endpoint.py | green |
| 05-02-T1 | 02 | SCHED-08 | unit | `cd mobile && flutter test test/unit/features/schedule/overdue_service_test.dart` | mobile/test/unit/features/schedule/overdue_service_test.dart | green |
| 05-02-T2 | 02 | SCHED-03 | widget | `cd mobile && flutter test test/widget/features/schedule/calendar_day_view_test.dart` | mobile/test/widget/features/schedule/calendar_day_view_test.dart | green |
| 05-02-T3 | 02 | SCHED-03 | widget | `cd mobile && flutter test test/widget/features/schedule/schedule_screen_test.dart` | mobile/test/widget/features/schedule/schedule_screen_test.dart | green |
| 05-03-T1 | 03 | SCHED-03 | widget | `cd mobile && flutter test test/widget/features/schedule/unscheduled_jobs_drawer_test.dart` | mobile/test/widget/features/schedule/unscheduled_jobs_drawer_test.dart | green |
| 05-03-T1 | 03 | SCHED-03 | widget | `cd mobile && flutter test test/widget/features/schedule/booking_card_interactions_test.dart` | mobile/test/widget/features/schedule/booking_card_interactions_test.dart | green |
| 05-03-T2 | 03 | SCHED-03 | widget | `cd mobile && flutter test test/widget/features/schedule/multi_day_wizard_dialog_test.dart` | mobile/test/widget/features/schedule/multi_day_wizard_dialog_test.dart | green |
| 05-04-T1 | 04 | SCHED-08 | widget | `cd mobile && flutter test test/widget/features/schedule/overdue_panel_test.dart` | mobile/test/widget/features/schedule/overdue_panel_test.dart | green |
| 05-04-T2 | 04 | SCHED-09 | widget | `cd mobile && flutter test test/widget/features/schedule/delay_dialog_test.dart` | mobile/test/widget/features/schedule/delay_dialog_test.dart | green |
| 05-05-T1 | 05 | SCHED-03 | widget | `cd mobile && flutter test test/widget/features/schedule/calendar_week_view_test.dart` | mobile/test/widget/features/schedule/calendar_week_view_test.dart | green |
| 05-05-T1 | 05 | SCHED-03 | widget | `cd mobile && flutter test test/widget/features/schedule/calendar_month_view_test.dart` | mobile/test/widget/features/schedule/calendar_month_view_test.dart | green |
| 05-05-T2 | 05 | SCHED-03 | widget | `cd mobile && flutter test test/widget/features/schedule/contractor_schedule_screen_test.dart` | mobile/test/widget/features/schedule/contractor_schedule_screen_test.dart | green |
| 05-05-T2 | 05 | SCHED-03 | widget | `cd mobile && flutter test test/widget/features/schedule/schedule_settings_screen_test.dart` | mobile/test/widget/features/schedule/schedule_settings_screen_test.dart | green |
| 05-E2E | E2E | SCHED-03, SCHED-08, SCHED-09 | e2e | `cd mobile && flutter test test/e2e/phase_5_calendar_dispatch_e2e_test.dart` | mobile/test/e2e/phase_5_calendar_dispatch_e2e_test.dart | green |

*Status: green = test file exists with real tests | yellow = stub only | red = failing | pending = not created*

---

## Coverage Analysis by Requirement

### SCHED-03: Drag-and-Drop Dispatch Calendar

| Behavior | Test File | Test Count | Coverage |
|----------|-----------|------------|----------|
| BookingDao insert/update/delete with sync queue dual-write | booking_dao_test.dart | 7 | COVERED |
| BookingDao watchUnscheduledJobs LEFT JOIN | booking_dao_test.dart | 1 | COVERED |
| Schedule screen view mode switching (day/week/month) | schedule_screen_test.dart | 9 | COVERED |
| Day view booking card rendering with status colors | calendar_day_view_test.dart | 14 | COVERED |
| Unscheduled jobs drawer rendering | unscheduled_jobs_drawer_test.dart | varies | COVERED |
| Booking card drag interactions | booking_card_interactions_test.dart | varies | COVERED |
| Multi-day wizard dialog | multi_day_wizard_dialog_test.dart | varies | COVERED |
| Week view grid rendering | calendar_week_view_test.dart | varies | COVERED |
| Month view badge rendering | calendar_month_view_test.dart | varies | COVERED |
| Contractor personal schedule | contractor_schedule_screen_test.dart | varies | COVERED |
| Schedule settings form | schedule_settings_screen_test.dart | varies | COVERED |
| E2E calendar dispatch flow | phase_5_calendar_dispatch_e2e_test.dart | varies | COVERED |

### SCHED-08: Overdue Job Warnings

| Behavior | Test File | Test Count | Coverage |
|----------|-----------|------------|----------|
| OverdueService.computeSeverity (none/warning/critical) | overdue_service_test.dart | 6 | COVERED |
| OverdueService.isOverdue (status + date checks) | overdue_service_test.dart | 4 | COVERED |
| Overdue panel rendering with severity tiers | overdue_panel_test.dart | varies | COVERED |
| Bottom nav badge with overdue count | schedule_screen_test.dart | 1 | COVERED |
| Overdue booking card borders (warning/critical) | calendar_day_view_test.dart | 2 | COVERED |

### SCHED-09: Forced Delay Justification

| Behavior | Test File | Test Count | Coverage |
|----------|-----------|------------|----------|
| Backend delay endpoint happy path | test_delay_endpoint.py | 1 | COVERED |
| Backend delay endpoint wrong status (422) | test_delay_endpoint.py | 1 | COVERED |
| Backend delay endpoint version conflict (409) | test_delay_endpoint.py | 1 | COVERED |
| Backend delay endpoint not found (404) | test_delay_endpoint.py | 1 | COVERED |
| Backend delay endpoint multiple delays | test_delay_endpoint.py | 1 | COVERED |
| Backend delay endpoint in_progress status | test_delay_endpoint.py | 1 | COVERED |
| Backend delay endpoint empty reason (422) | test_delay_endpoint.py | 1 | COVERED |
| Delay dialog validation (empty reason) | delay_dialog_test.dart | 1 | COVERED |
| Delay dialog validation (no ETA) | delay_dialog_test.dart | 1 | COVERED |
| Delay dialog cancel | delay_dialog_test.dart | 1 | COVERED |
| Delay dialog submit with both fields | delay_dialog_test.dart | 1 | COVERED |

---

## Manual-Only Verifications

| Behavior | Requirement | Why Manual | Test Instructions |
|----------|-------------|------------|-------------------|
| Drag-and-drop visual feedback (green/red zones) | SCHED-03 | Gesture simulation limitations in widget tests | Open calendar > drag job from sidebar > verify green zones on valid slots, red on conflicts |
| Edge resize on booking cards | SCHED-03 | Complex gesture timing in tests | Long-press booking card edge > drag up/down > verify time range updates |
| Calendar auto-scroll to working hours | SCHED-03 | ScrollController behavior in test viewports | Open day view > verify it scrolls to 06:00 not midnight |
| Haptic feedback on drag start | SCHED-03 | Requires physical device | Long-press job card > verify haptic vibration |

---

## Validation Sign-Off

- [x] All requirements (SCHED-03, SCHED-08, SCHED-09) have automated test coverage
- [x] Backend delay endpoint has 7 integration tests (all passing per 05-06-SUMMARY)
- [x] Mobile unit tests: 17 tests (10 overdue + 7 booking DAO)
- [x] Mobile widget tests: 29+ tests across 11 test files
- [x] E2E test file exists with comprehensive flows
- [x] No requirement has zero automated coverage
- [x] `nyquist_compliant: true` set in frontmatter

**Approval:** validated (2026-03-14 Nyquist audit)

---

## Audit Trail

| Date | Auditor | Action | Notes |
|------|---------|--------|-------|
| 2026-03-14 | gsd-nyquist-auditor | CREATED | Initial validation map built from plans 05-01 through 05-06 summaries. All 3 requirements have test coverage across 17 test files. No gaps identified. |
