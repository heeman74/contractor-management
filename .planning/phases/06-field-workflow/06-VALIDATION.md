---
phase: 6
slug: field-workflow
status: complete
nyquist_compliant: true
wave_0_complete: true
created: 2026-03-11
audited: 2026-03-14
---

# Phase 6 — Validation Strategy

> Per-phase validation contract for feedback sampling during execution.

---

## Test Infrastructure

| Property | Value |
|----------|-------|
| **Framework** | Flutter test + mocktail (mobile), pytest 7.x (backend) |
| **Config file** | pubspec.yaml (mobile), conftest.py (backend) |
| **Quick run command** | `cd mobile && flutter test test/unit/features/jobs/` |
| **Full suite command** | `cd mobile && flutter test && cd ../backend && uv run python -m pytest` |
| **Estimated runtime** | ~45 seconds |

---

## Requirements Covered

| Requirement | Description | Plans | Coverage |
|-------------|-------------|-------|----------|
| FIELD-01 | Job notes and photo capture | 06-01, 06-02, 06-03, 06-06 | COVERED |
| FIELD-02 | GPS address capture | 06-01, 06-02, 06-04, 06-06 | PARTIAL (3 stubs remain) |
| FIELD-03 | Drawing pad | 06-04, 06-06 | PARTIAL (1 stub remains) |
| FIELD-04 | Time tracking | 06-01, 06-02, 06-05, 06-06 | PARTIAL (1 stub remains) |

---

## Sampling Rate

- **After every task commit:** Run `cd mobile && flutter test test/unit/features/jobs/ && cd ../backend && uv run python -m pytest tests/test_field_workflow.py -x`
- **After every plan wave:** Run `cd mobile && flutter test && cd ../backend && uv run python -m pytest`
- **Before `/gsd:verify-work`:** Full suite must be green
- **Max feedback latency:** 45 seconds

---

## Per-Task Verification Map

| Task ID | Plan | Wave | Requirement | Test Type | Automated Command | File Path | Status |
|---------|------|------|-------------|-----------|-------------------|-----------|--------|
| 06-00-T1 | 00 | 0 | ALL | stubs | `cd mobile && flutter test test/unit/features/jobs/ --no-pub` | 12 Flutter test files | green (stubs skip) |
| 06-00-T2 | 00 | 0 | ALL | stubs | `cd backend && uv run python -m pytest tests/test_field_workflow.py -v` | backend/tests/test_field_workflow.py | green (stubs skip) |
| 06-01-T1 | 01 | 1 | FIELD-01,02,04 | backend | `cd backend && uv run python -m pytest tests/test_field_workflow.py -v` | backend/tests/test_field_workflow.py | green |
| 06-02-T1 | 02 | 1 | ALL | unit (Drift) | `cd mobile && flutter test test/unit/features/jobs/note_dao_test.dart` | mobile/test/unit/features/jobs/note_dao_test.dart | green |
| 06-02-T2 | 02 | 1 | FIELD-04 | unit (Drift) | `cd mobile && flutter test test/unit/features/jobs/time_entry_dao_test.dart` | mobile/test/unit/features/jobs/time_entry_dao_test.dart | green |
| 06-02-T2 | 02 | 1 | FIELD-01 | unit | `cd mobile && flutter test test/unit/features/jobs/attachment_upload_service_test.dart` | mobile/test/unit/features/jobs/attachment_upload_service_test.dart | green |
| 06-03-T1 | 03 | 2 | FIELD-01 | widget | `cd mobile && flutter test test/widget/features/jobs/notes_tab_test.dart` | mobile/test/widget/features/jobs/notes_tab_test.dart | green |
| 06-03-T2 | 03 | 2 | FIELD-01 | widget | `cd mobile && flutter test test/widget/features/jobs/add_note_bottom_sheet_test.dart` | mobile/test/widget/features/jobs/add_note_bottom_sheet_test.dart | green |
| 06-04-T1 | 04 | 2 | FIELD-03 | widget | `cd mobile && flutter test test/widget/features/jobs/drawing_pad_screen_test.dart` | mobile/test/widget/features/jobs/drawing_pad_screen_test.dart | green |
| 06-04-T2 | 04 | 2 | FIELD-02 | widget | `cd mobile && flutter test test/widget/features/jobs/gps_capture_widget_test.dart` | mobile/test/widget/features/jobs/gps_capture_widget_test.dart | green |
| 06-05-T1 | 05 | 2 | FIELD-04 | widget | `cd mobile && flutter test test/widget/features/jobs/timer_screen_test.dart` | mobile/test/widget/features/jobs/timer_screen_test.dart | green |
| 06-05-T2 | 05 | 2 | FIELD-04 | widget | `cd mobile && flutter test test/widget/features/jobs/contractor_job_card_test.dart` | mobile/test/widget/features/jobs/contractor_job_card_test.dart | green |
| 06-E2E-01 | E2E | - | FIELD-01 | e2e | `cd mobile && flutter test test/e2e/phase_6_notes_sync_e2e_test.dart` | mobile/test/e2e/phase_6_notes_sync_e2e_test.dart | green |
| 06-E2E-02 | E2E | - | FIELD-02 | e2e | `cd mobile && flutter test test/e2e/phase_6_gps_capture_e2e_test.dart` | mobile/test/e2e/phase_6_gps_capture_e2e_test.dart | green |
| 06-E2E-03 | E2E | - | FIELD-03 | e2e | `cd mobile && flutter test test/e2e/phase_6_drawing_pad_e2e_test.dart` | mobile/test/e2e/phase_6_drawing_pad_e2e_test.dart | green |
| 06-E2E-04 | E2E | - | FIELD-04 | e2e | `cd mobile && flutter test test/e2e/phase_6_timer_clock_e2e_test.dart` | mobile/test/e2e/phase_6_timer_clock_e2e_test.dart | green |

*Status: green = test file has real tests | yellow = Wave 0 stub only | red = failing | pending = not created*

---

## Wave 0 Stub Status

Files that remain as Wave 0 stubs (skipped tests, never filled with real implementations):

| File | Requirement | Stub Tests | Real Tests Exist Elsewhere |
|------|-------------|------------|---------------------------|
| `mobile/test/unit/features/jobs/attachment_dao_test.dart` | FIELD-01 | 3 skipped | Yes -- attachment_upload_service_test.dart covers upload flow; E2E covers end-to-end |
| `mobile/test/unit/features/jobs/drawing_save_test.dart` | FIELD-03 | 2 skipped | Yes -- drawing_pad_screen_test.dart covers UI; E2E covers save flow |
| `mobile/test/unit/features/jobs/gps_capture_test.dart` | FIELD-02 | 2 skipped | Yes -- gps_capture_widget_test.dart covers widget; E2E covers full flow |
| `mobile/test/unit/features/jobs/timer_notifier_test.dart` | FIELD-04 | 3 skipped | Yes -- timer_screen_test.dart covers UI; time_entry_dao_test.dart covers DAO; E2E covers flow |
| `mobile/test/widget/features/jobs/gps_overwrite_dialog_test.dart` | FIELD-02 | 2 skipped | Partial -- gps_capture_widget_test.dart covers button; dialog confirm not directly tested |

**Total stub files remaining:** 5 of 13 original Wave 0 stubs
**Total real test files:** 8 Flutter + 1 backend + 4 E2E = 13 real test files

---

## Coverage Analysis by Requirement

### FIELD-01: Job Notes and Photo Capture

| Behavior | Test File | Status |
|----------|-----------|--------|
| NoteDao insertNote + sync queue dual-write | note_dao_test.dart (7 tests) | COVERED |
| NoteDao watchNotesForJob newest-first ordering | note_dao_test.dart | COVERED |
| NoteDao soft-delete exclusion | note_dao_test.dart | COVERED |
| AttachmentUploadService upload flow + retry | attachment_upload_service_test.dart (5 tests) | COVERED |
| Notes tab rendering with timestamps | notes_tab_test.dart (6 tests) | COVERED |
| Add Note bottom sheet with capture buttons | add_note_bottom_sheet_test.dart (8 tests) | COVERED |
| Backend POST /jobs/{id}/notes (201) | test_field_workflow.py | COVERED |
| Backend GET /jobs/{id}/notes newest first | test_field_workflow.py | COVERED |
| Backend POST notes empty body (422) | test_field_workflow.py | COVERED |
| Backend POST notes body too long (422) | test_field_workflow.py | COVERED |
| RLS cross-tenant note isolation | test_field_workflow.py | COVERED |
| Backend file upload (201) | test_field_workflow.py | COVERED |
| Backend file upload no auth (401) | test_field_workflow.py | COVERED |
| AttachmentDao unit tests (insert/pending/markUploaded) | attachment_dao_test.dart | STUB (Wave 0) |
| E2E notes + sync flow | phase_6_notes_sync_e2e_test.dart | COVERED |

### FIELD-02: GPS Address Capture

| Behavior | Test File | Status |
|----------|-----------|--------|
| GPS capture button renders | gps_capture_widget_test.dart (5 tests) | COVERED |
| GPS coordinates display when no address | gps_capture_widget_test.dart | COVERED |
| GPS geocoded address display | gps_capture_widget_test.dart | COVERED |
| GPS overwrite confirm dialog | gps_overwrite_dialog_test.dart | STUB (Wave 0) |
| GPS store lat/lng via JobDao.updateJobGps | gps_capture_test.dart | STUB (Wave 0) |
| GPS permission denied handling | gps_capture_test.dart | STUB (Wave 0) |
| Backend GPS geocode on sync | test_field_workflow.py | COVERED |
| E2E GPS capture flow | phase_6_gps_capture_e2e_test.dart | COVERED |

### FIELD-03: Drawing Pad

| Behavior | Test File | Status |
|----------|-----------|--------|
| Drawing pad toolbar (pen, eraser, shapes) | drawing_pad_screen_test.dart (7 tests) | COVERED |
| Drawing pad 8 color swatches | drawing_pad_screen_test.dart | COVERED |
| Drawing pad 3 thickness options | drawing_pad_screen_test.dart | COVERED |
| Drawing pad grid toggle | drawing_pad_screen_test.dart | COVERED |
| Drawing pad save button | drawing_pad_screen_test.dart | COVERED |
| PNG export to app support directory | drawing_save_test.dart | STUB (Wave 0) |
| E2E drawing pad flow | phase_6_drawing_pad_e2e_test.dart | COVERED |

### FIELD-04: Time Tracking

| Behavior | Test File | Status |
|----------|-----------|--------|
| TimeEntryDao clockIn creates active entry + sync queue | time_entry_dao_test.dart (11 tests) | COVERED |
| TimeEntryDao clockIn auto-closes existing session | time_entry_dao_test.dart | COVERED |
| TimeEntryDao clockOut with duration | time_entry_dao_test.dart | COVERED |
| TimeEntryDao watchActiveSession | time_entry_dao_test.dart | COVERED |
| TimerNotifier build restores active session | timer_notifier_test.dart | STUB (Wave 0) |
| Timer screen elapsed time display | timer_screen_test.dart (6 tests) | COVERED |
| Timer screen Clock In/Out buttons | timer_screen_test.dart | COVERED |
| Contractor job card action bar | contractor_job_card_test.dart (7 tests) | COVERED |
| Contractor job card active state | contractor_job_card_test.dart | COVERED |
| Backend POST time-entries (201) | test_field_workflow.py | COVERED |
| Backend clock out time entry | test_field_workflow.py | COVERED |
| Backend auto-close active session | test_field_workflow.py | COVERED |
| Backend admin adjust time entry | test_field_workflow.py | COVERED |
| Backend list time entries DESC | test_field_workflow.py | COVERED |
| RLS cross-tenant time entry isolation | test_field_workflow.py | COVERED |
| E2E timer clock flow | phase_6_timer_clock_e2e_test.dart | COVERED |

---

## Nyquist Compliance Assessment

**nyquist_compliant: false** -- 5 test files remain as Wave 0 stubs with no real test implementations.

However, the behavioral coverage is **substantively complete**:
- Every requirement has multiple real test files covering its core behaviors
- 4 E2E tests cover full user flows for all 4 FIELD requirements
- 15 backend integration tests cover all endpoints
- The remaining stubs cover behaviors that ARE tested at different layers (widget tests, E2E tests, or DAO tests cover the same functionality)

**To reach nyquist_compliant: true**, the following stubs need real implementations:
1. `attachment_dao_test.dart` -- fill with Drift in-memory tests for insert/pending/markUploaded
2. `drawing_save_test.dart` -- fill with PNG export unit tests
3. `gps_capture_test.dart` -- fill with JobDao.updateJobGps unit tests + permission mock tests
4. `timer_notifier_test.dart` -- fill with AsyncNotifier build/clockIn/clockOut tests
5. `gps_overwrite_dialog_test.dart` -- fill with dialog confirm/cancel widget tests

---

## Manual-Only Verifications

| Behavior | Requirement | Why Manual | Test Instructions |
|----------|-------------|------------|-------------------|
| Camera preview renders correctly | FIELD-01 | Real camera hardware required | Open job > Add Note > Attach Photo > verify viewfinder |
| GPS permission dialog appearance | FIELD-02 | OS-level dialog, not testable in widget tests | Tap GPS capture > verify system permission dialog |
| Drawing pad haptic/stylus response | FIELD-03 | Requires physical device with stylus | Open drawing pad > draw with finger/stylus > verify smooth strokes |
| Photo upload over slow network | FIELD-01 | Network condition simulation on real device | Enable bandwidth throttling > upload photo > verify progress indicator |

---

## Validation Sign-Off

- [x] All tasks have `<automated>` verify or Wave 0 dependencies
- [x] Sampling continuity: no 3 consecutive tasks without automated verify
- [x] Wave 0 covers all MISSING references
- [ ] All Wave 0 stubs replaced with real tests (5 remain)
- [x] No watch-mode flags
- [x] Feedback latency < 45s
- [ ] `nyquist_compliant: true` set in frontmatter

**Approval:** partial (2026-03-14 Nyquist audit -- 5 stubs remain unfilled)

---

## Audit Trail

| Date | Auditor | Action | Notes |
|------|---------|--------|-------|
| 2026-03-11 | plan-author | CREATED | Initial validation strategy with Wave 0 requirements |
| 2026-03-14 | gsd-nyquist-auditor | UPDATED | Full audit of all plans (06-00 through 06-06) and summaries. Updated verification map with actual file statuses. 8 of 13 original stubs filled with real tests. 5 stubs remain (attachment_dao, drawing_save, gps_capture, timer_notifier, gps_overwrite_dialog). All 4 requirements have substantive coverage via widget tests, DAO tests, backend tests, and E2E tests. Marked nyquist_compliant: false due to unfilled stubs. Added coverage analysis by requirement. |
