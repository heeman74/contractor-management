---
phase: 10
slug: ui-backend-wiring-gap-closure
status: draft
nyquist_compliant: false
wave_0_complete: false
created: 2026-03-14
---

# Phase 10 — Validation Strategy

> Per-phase validation contract for feedback sampling during execution.

---

## Test Infrastructure

| Property | Value |
|----------|-------|
| **Framework (Flutter)** | flutter_test + mocktail |
| **Framework (Backend)** | pytest + httpx ASGI client |
| **Config file (Flutter)** | none — flutter test discovers automatically |
| **Config file (Backend)** | backend/pyproject.toml (asyncio_mode=auto) |
| **Quick run (Flutter)** | `flutter test mobile/test/e2e/phase_10_ui_wiring_e2e_test.dart` |
| **Quick run (Backend)** | `uv run python -m pytest backend/tests/integration/test_phase_10_e2e.py -x` |
| **Full suite (Flutter)** | `flutter test mobile/test/` |
| **Full suite (Backend)** | `uv run python -m pytest backend/tests/ -x` |
| **Estimated runtime** | ~30 seconds (Flutter) + ~15 seconds (Backend) |

---

## Sampling Rate

- **After every task commit:** Run `flutter test mobile/test/e2e/phase_10_ui_wiring_e2e_test.dart` and `uv run python -m pytest backend/tests/integration/test_phase_10_e2e.py -x`
- **After every plan wave:** Run full suite for both Flutter and Backend
- **Before `/gsd:verify-work`:** Full suite must be green
- **Max feedback latency:** ~45 seconds

---

## Per-Task Verification Map

| Task ID | Plan | Wave | Requirement | Test Type | Automated Command | File Exists | Status |
|---------|------|------|-------------|-----------|-------------------|-------------|--------|
| 10-01-01 | 01 | 1 | SCHED-08 | widget/E2E | `flutter test mobile/test/e2e/phase_10_ui_wiring_e2e_test.dart -N sched08` | ❌ W0 | ⬜ pending |
| 10-01-02 | 01 | 1 | SCHED-08 | widget/E2E | `flutter test mobile/test/e2e/phase_10_ui_wiring_e2e_test.dart -N sched08_empty` | ❌ W0 | ⬜ pending |
| 10-01-03 | 01 | 1 | SCHED-08 | widget/E2E | `flutter test mobile/test/e2e/phase_10_ui_wiring_e2e_test.dart -N sched08_nav` | ❌ W0 | ⬜ pending |
| 10-01-04 | 01 | 1 | BIZ-01 | widget/E2E | `flutter test mobile/test/e2e/phase_10_ui_wiring_e2e_test.dart -N biz01_create` | ❌ W0 | ⬜ pending |
| 10-01-05 | 01 | 1 | BIZ-01 | widget/E2E | `flutter test mobile/test/e2e/phase_10_ui_wiring_e2e_test.dart -N biz01_no_button` | ❌ W0 | ⬜ pending |
| 10-01-06 | 01 | 1 | BIZ-02 | widget/E2E | `flutter test mobile/test/e2e/phase_10_ui_wiring_e2e_test.dart -N biz02_view` | ❌ W0 | ⬜ pending |
| 10-01-07 | 01 | 1 | BIZ-02 | widget/E2E | `flutter test mobile/test/e2e/phase_10_ui_wiring_e2e_test.dart -N biz02_nav` | ❌ W0 | ⬜ pending |
| 10-01-08 | 01 | 1 | SCHED-06 | integration | `uv run python -m pytest backend/tests/integration/test_phase_10_e2e.py::test_travel_provider_injected -x` | ❌ W0 | ⬜ pending |
| 10-01-09 | 01 | 1 | SCHED-06 | integration | `uv run python -m pytest backend/tests/integration/test_phase_10_e2e.py::test_travel_provider_absent -x` | ❌ W0 | ⬜ pending |

*Status: ⬜ pending · ✅ green · ❌ red · ⚠️ flaky*

---

## Wave 0 Requirements

- [ ] `mobile/test/e2e/phase_10_ui_wiring_e2e_test.dart` — stubs for SCHED-08, BIZ-01, BIZ-02
- [ ] `backend/tests/integration/test_phase_10_e2e.py` — stubs for SCHED-06

*Existing infrastructure covers all phase requirements — no new framework installs needed.*

---

## Manual-Only Verifications

| Behavior | Requirement | Why Manual | Test Instructions |
|----------|-------------|------------|-------------------|
| OverduePanel animation smoothness | SCHED-08 | AnimatedContainer visual quality | Open schedule screen, verify panel slides smoothly |
| Quote button visual alignment in JobDetail | BIZ-01 | Layout aesthetics | Open job detail, verify button placement looks correct |

---

## Validation Sign-Off

- [ ] All tasks have `<automated>` verify or Wave 0 dependencies
- [ ] Sampling continuity: no 3 consecutive tasks without automated verify
- [ ] Wave 0 covers all MISSING references
- [ ] No watch-mode flags
- [ ] Feedback latency < 45s
- [ ] `nyquist_compliant: true` set in frontmatter

**Approval:** pending
