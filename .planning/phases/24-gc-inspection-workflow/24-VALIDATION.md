---
phase: 24
slug: gc-inspection-workflow
status: draft
nyquist_compliant: false
wave_0_complete: false
created: 2026-03-25
---

# Phase 24 — Validation Strategy

> Per-phase validation contract for feedback sampling during execution.

---

## Test Infrastructure

| Property | Value |
|----------|-------|
| **Framework** | pytest 7.x (backend) / flutter_test (mobile) |
| **Config file** | `backend/pyproject.toml` / `mobile/pubspec.yaml` |
| **Quick run command** | `cd backend && uv run python -m pytest tests/ -x -q --timeout=30` / `cd mobile && flutter test --no-pub` |
| **Full suite command** | `cd backend && uv run python -m pytest tests/ -v` / `cd mobile && flutter test` |
| **Estimated runtime** | ~60 seconds (backend) / ~90 seconds (mobile) |

---

## Sampling Rate

- **After every task commit:** Run quick test command for changed area
- **After every plan wave:** Run full suite command
- **Before `/gsd:verify-work`:** Full suite must be green
- **Max feedback latency:** 60 seconds

---

## Per-Task Verification Map

| Task ID | Plan | Wave | Requirement | Test Type | Automated Command | File Exists | Status |
|---------|------|------|-------------|-----------|-------------------|-------------|--------|
| 24-01-01 | 01 | 1 | INSP-01 | integration | `uv run python -m pytest tests/test_phase_24_inspection.py -x` | ❌ W0 | ⬜ pending |
| 24-01-02 | 01 | 1 | INSP-01 | widget | `flutter test test/e2e/phase_24_inspection_e2e_test.dart` | ❌ W0 | ⬜ pending |
| 24-02-01 | 02 | 1 | INSP-02 | integration | `uv run python -m pytest tests/test_phase_24_site_walk.py -x` | ❌ W0 | ⬜ pending |
| 24-02-02 | 02 | 1 | INSP-02 | widget | `flutter test test/e2e/phase_24_site_walk_e2e_test.dart` | ❌ W0 | ⬜ pending |
| 24-03-01 | 03 | 1 | INSP-03 | integration | `uv run python -m pytest tests/test_phase_24_punch_list.py -x` | ❌ W0 | ⬜ pending |
| 24-03-02 | 03 | 1 | INSP-03 | widget | `flutter test test/e2e/phase_24_punch_list_e2e_test.dart` | ❌ W0 | ⬜ pending |
| 24-04-01 | 04 | 2 | INSP-04 | integration | `uv run python -m pytest tests/test_phase_24_fcm_rejection.py -x` | ❌ W0 | ⬜ pending |
| 24-04-02 | 04 | 2 | INSP-04 | widget | `flutter test test/e2e/phase_24_notification_e2e_test.dart` | ❌ W0 | ⬜ pending |

*Status: ⬜ pending · ✅ green · ❌ red · ⚠️ flaky*

---

## Wave 0 Requirements

- [ ] `backend/tests/test_phase_24_inspection.py` — stubs for INSP-01 (task approve/reject)
- [ ] `backend/tests/test_phase_24_site_walk.py` — stubs for INSP-02 (site walk flags)
- [ ] `backend/tests/test_phase_24_punch_list.py` — stubs for INSP-03 (punch list items)
- [ ] `backend/tests/test_phase_24_fcm_rejection.py` — stubs for INSP-04 (FCM rejection notification)
- [ ] `mobile/test/e2e/phase_24_inspection_e2e_test.dart` — stubs for INSP-01 mobile flow
- [ ] `mobile/test/e2e/phase_24_site_walk_e2e_test.dart` — stubs for INSP-02 mobile flow
- [ ] `mobile/test/e2e/phase_24_punch_list_e2e_test.dart` — stubs for INSP-03 mobile flow
- [ ] `mobile/test/e2e/phase_24_notification_e2e_test.dart` — stubs for INSP-04 mobile flow

---

## Manual-Only Verifications

| Behavior | Requirement | Why Manual | Test Instructions |
|----------|-------------|------------|-------------------|
| Photo annotation UX for rejection evidence | INSP-01 | Visual annotation quality check | Open task detail → Reject → take photo → annotate → verify overlay renders correctly on device |
| Camera-first flag creation UX | INSP-02 | Camera hardware interaction | Tap Flag Issue → verify camera opens → take photo → verify form fallback works |
| Punch badge visual styling | INSP-03 | Visual appearance check | Open contractor task view → verify punch items show distinct badge |
| FCM push notification timing | INSP-04 | Real device push delivery | Reject a task → verify contractor receives push within 30 seconds on physical device |

---

## Validation Sign-Off

- [ ] All tasks have `<automated>` verify or Wave 0 dependencies
- [ ] Sampling continuity: no 3 consecutive tasks without automated verify
- [ ] Wave 0 covers all MISSING references
- [ ] No watch-mode flags
- [ ] Feedback latency < 60s
- [ ] `nyquist_compliant: true` set in frontmatter

**Approval:** pending
