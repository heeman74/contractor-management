---
phase: 6
slug: field-workflow
status: draft
nyquist_compliant: false
wave_0_complete: false
created: 2026-03-11
---

# Phase 6 — Validation Strategy

> Per-phase validation contract for feedback sampling during execution.

---

## Test Infrastructure

| Property | Value |
|----------|-------|
| **Framework** | Flutter test + mocktail (mobile), pytest 7.x (backend) |
| **Config file** | pubspec.yaml (mobile), conftest.py (backend) |
| **Quick run command** | `flutter test test/unit/features/jobs/` |
| **Full suite command** | `flutter test && uv run python -m pytest` |
| **Estimated runtime** | ~45 seconds |

---

## Sampling Rate

- **After every task commit:** Run `flutter test test/unit/features/jobs/ && uv run python -m pytest tests/test_field_workflow.py -x`
- **After every plan wave:** Run `flutter test && uv run python -m pytest`
- **Before `/gsd:verify-work`:** Full suite must be green
- **Max feedback latency:** 45 seconds

---

## Per-Task Verification Map

| Task ID | Plan | Wave | Requirement | Test Type | Automated Command | File Exists | Status |
|---------|------|------|-------------|-----------|-------------------|-------------|--------|
| 06-01-01 | 01 | 1 | FIELD-01 | unit (Drift) | `flutter test test/unit/features/jobs/note_dao_test.dart -x` | ❌ W0 | ⬜ pending |
| 06-01-02 | 01 | 1 | FIELD-01 | unit (Drift) | `flutter test test/unit/features/jobs/attachment_dao_test.dart -x` | ❌ W0 | ⬜ pending |
| 06-01-03 | 01 | 1 | FIELD-01 | widget | `flutter test test/widget/features/jobs/add_note_bottom_sheet_test.dart -x` | ❌ W0 | ⬜ pending |
| 06-01-04 | 01 | 1 | FIELD-01 | widget | `flutter test test/widget/features/jobs/notes_tab_test.dart -x` | ❌ W0 | ⬜ pending |
| 06-01-05 | 01 | 1 | FIELD-01 | backend | `uv run python -m pytest tests/test_field_workflow.py::test_create_note -x` | ❌ W0 | ⬜ pending |
| 06-02-01 | 02 | 1 | FIELD-02 | unit | `flutter test test/unit/features/jobs/gps_capture_test.dart -x` | ❌ W0 | ⬜ pending |
| 06-02-02 | 02 | 1 | FIELD-02 | widget | `flutter test test/widget/features/jobs/gps_capture_widget_test.dart -x` | ❌ W0 | ⬜ pending |
| 06-02-03 | 02 | 1 | FIELD-02 | widget | `flutter test test/widget/features/jobs/gps_overwrite_dialog_test.dart -x` | ❌ W0 | ⬜ pending |
| 06-02-04 | 02 | 1 | FIELD-02 | backend | `uv run python -m pytest tests/test_field_workflow.py::test_gps_geocode_on_sync -x` | ❌ W0 | ⬜ pending |
| 06-03-01 | 03 | 2 | FIELD-03 | widget | `flutter test test/widget/features/jobs/drawing_pad_screen_test.dart -x` | ❌ W0 | ⬜ pending |
| 06-03-02 | 03 | 2 | FIELD-03 | unit | `flutter test test/unit/features/jobs/drawing_save_test.dart -x` | ❌ W0 | ⬜ pending |
| 06-04-01 | 04 | 2 | FIELD-04 | unit (Drift) | `flutter test test/unit/features/jobs/time_entry_dao_test.dart -x` | ❌ W0 | ⬜ pending |
| 06-04-02 | 04 | 2 | FIELD-04 | unit | `flutter test test/unit/features/jobs/timer_notifier_test.dart -x` | ❌ W0 | ⬜ pending |
| 06-04-03 | 04 | 2 | FIELD-04 | widget | `flutter test test/widget/features/jobs/timer_screen_test.dart -x` | ❌ W0 | ⬜ pending |
| 06-04-04 | 04 | 2 | FIELD-04 | backend | `uv run python -m pytest tests/test_field_workflow.py::test_time_entry_clock_in -x` | ❌ W0 | ⬜ pending |

*Status: ⬜ pending · ✅ green · ❌ red · ⚠️ flaky*

---

## Wave 0 Requirements

- [ ] `mobile/test/unit/features/jobs/note_dao_test.dart` — stubs for FIELD-01
- [ ] `mobile/test/unit/features/jobs/attachment_dao_test.dart` — stubs for FIELD-01
- [ ] `mobile/test/widget/features/jobs/add_note_bottom_sheet_test.dart` — stubs for FIELD-01
- [ ] `mobile/test/widget/features/jobs/notes_tab_test.dart` — stubs for FIELD-01
- [ ] `mobile/test/unit/features/jobs/gps_capture_test.dart` — stubs for FIELD-02
- [ ] `mobile/test/widget/features/jobs/gps_capture_widget_test.dart` — stubs for FIELD-02
- [ ] `mobile/test/widget/features/jobs/gps_overwrite_dialog_test.dart` — stubs for FIELD-02
- [ ] `mobile/test/unit/features/jobs/drawing_save_test.dart` — stubs for FIELD-03
- [ ] `mobile/test/widget/features/jobs/drawing_pad_screen_test.dart` — stubs for FIELD-03
- [ ] `mobile/test/unit/features/jobs/time_entry_dao_test.dart` — stubs for FIELD-04
- [ ] `mobile/test/unit/features/jobs/timer_notifier_test.dart` — stubs for FIELD-04
- [ ] `mobile/test/widget/features/jobs/timer_screen_test.dart` — stubs for FIELD-04
- [ ] `backend/tests/test_field_workflow.py` — backend integration stubs for all FIELD reqs
- [ ] `flutter pub add flutter_drawing_board geolocator flutter_image_compress file_picker` — new packages

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

- [ ] All tasks have `<automated>` verify or Wave 0 dependencies
- [ ] Sampling continuity: no 3 consecutive tasks without automated verify
- [ ] Wave 0 covers all MISSING references
- [ ] No watch-mode flags
- [ ] Feedback latency < 45s
- [ ] `nyquist_compliant: true` set in frontmatter

**Approval:** pending
