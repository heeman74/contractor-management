---
phase: 10
slug: ui-backend-wiring-gap-closure
status: complete
nyquist_compliant: true
wave_0_complete: true
created: 2026-03-14
audited: 2026-03-14
---

# Phase 10 — Validation Strategy

> Per-phase validation contract for feedback sampling during execution.

---

## Test Infrastructure

| Property | Value |
|----------|-------|
| **Framework (Flutter)** | flutter_test + mocktail |
| **Framework (Backend)** | pytest + httpx ASGI client |
| **Config file (Flutter)** | none -- flutter test discovers automatically |
| **Config file (Backend)** | backend/pyproject.toml (asyncio_mode=auto) |
| **Quick run (Flutter)** | `cd mobile && flutter test test/e2e/phase_10_ui_wiring_e2e_test.dart` |
| **Quick run (Backend)** | `cd backend && uv run python -m pytest tests/integration/test_phase_10_e2e.py -x -v` |
| **Full suite (Flutter)** | `cd mobile && flutter test test/` |
| **Full suite (Backend)** | `cd backend && uv run python -m pytest tests/ -x` |
| **Estimated runtime** | ~3 seconds (Flutter) + ~4 seconds (Backend) |

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
| 10-01-01 | 01 | 1 | SCHED-08 (overdue panel renders) | widget/E2E | `cd mobile && flutter test test/e2e/phase_10_ui_wiring_e2e_test.dart` | YES | green |
| 10-01-02 | 01 | 1 | SCHED-08 (empty state) | widget/E2E | same | YES | green |
| 10-01-03 | 01 | 1 | SCHED-08 (collapsed state) | widget/E2E | same | YES | green |
| 10-01-04 | 01 | 1 | BIZ-01 (Create Quote button for admin) | widget/E2E | same | YES | green |
| 10-01-05 | 01 | 1 | BIZ-01 (no button for non-admin) | widget/E2E | same | YES | green |
| 10-01-06 | 01 | 1 | BIZ-01 (no button for cancelled job) | widget/E2E | same | YES | green |
| 10-01-07 | 01 | 1 | BIZ-02 (View/Edit Quote button) | widget/E2E | same | YES | green |
| 10-01-08 | 01 | 1 | BIZ-02 (draft quote visible) | widget/E2E | same | YES | green |
| 10-01-09 | 01 | 1 | SCHED-06 (travel provider absent) | integration | `cd backend && uv run python -m pytest tests/integration/test_phase_10_e2e.py -x -v` | YES | green |
| 10-01-10 | 01 | 1 | SCHED-06 (travel provider injected) | integration | same | YES | green |
| 10-01-11 | 01 | 1 | SCHED-06 (availability endpoint smoke) | integration | same | YES | green |
| 10-01-12 | 01 | 1 | SCHED-06 (conflicts endpoint smoke) | integration | same | YES | green |

*Status: pending -- green -- red -- flaky*

---

## Requirement Coverage Summary

| Requirement | Tests | Coverage |
|-------------|-------|----------|
| SCHED-08 | 10-01-01, 10-01-02, 10-01-03 | COVERED (overdue panel renders, empty state, collapsed state) |
| BIZ-01 | 10-01-04, 10-01-05, 10-01-06 | COVERED (Create Quote for admin, hidden for non-admin, hidden for cancelled) |
| BIZ-02 | 10-01-07, 10-01-08 | COVERED (View/Edit Quote with existing quote, draft quote visible) |
| SCHED-06 | 10-01-09, 10-01-10, 10-01-11, 10-01-12 | COVERED (travel provider absent/injected, endpoint smoke tests) |

---

## Wave 0 Requirements

- [x] `mobile/test/e2e/phase_10_ui_wiring_e2e_test.dart` -- 8 tests covering SCHED-08, BIZ-01, BIZ-02
- [x] `backend/tests/integration/test_phase_10_e2e.py` -- 4 tests covering SCHED-06

*Existing infrastructure covers all phase requirements -- no new framework installs needed.*

---

## Manual-Only Verifications

| Behavior | Requirement | Why Manual | Test Instructions |
|----------|-------------|------------|-------------------|
| OverduePanel animation smoothness | SCHED-08 | AnimatedContainer visual quality | Open schedule screen, verify panel slides smoothly |
| Quote button visual alignment in JobDetail | BIZ-01 | Layout aesthetics | Open job detail, verify button placement looks correct |

---

## Validation Sign-Off

- [x] All tasks have `<automated>` verify or Wave 0 dependencies
- [x] Sampling continuity: no 3 consecutive tasks without automated verify
- [x] Wave 0 covers all MISSING references
- [x] No watch-mode flags
- [x] Feedback latency < 45s
- [x] `nyquist_compliant: true` set in frontmatter

**Approval:** APPROVED

---

## Nyquist Audit Trail

**Auditor:** gsd-nyquist-auditor
**Date:** 2026-03-14
**Phase requirements:** SCHED-08, BIZ-01, BIZ-02, SCHED-06

### Test Execution Results

| Test Suite | File | Tests | Result | Runner |
|------------|------|-------|--------|--------|
| Flutter E2E | `mobile/test/e2e/phase_10_ui_wiring_e2e_test.dart` | 8 | ALL PASSED | `cd mobile && flutter test test/e2e/phase_10_ui_wiring_e2e_test.dart` |
| Backend Integration | `backend/tests/integration/test_phase_10_e2e.py` | 4 | ALL PASSED | `cd backend && uv run python -m pytest tests/integration/test_phase_10_e2e.py -x -v` |

### Flutter E2E Test Details (8 passing)

1. `sched08: OverduePanel renders overdue job when panel is visible` -- SCHED-08
2. `sched08_empty: OverduePanel renders empty state when panel is visible with no jobs` -- SCHED-08
3. `sched08_collapsed: OverduePanel is hidden when showOverduePanelProvider is false` -- SCHED-08
4. `biz01_create: Admin sees Create Quote button when job has no quote` -- BIZ-01
5. `biz01_no_button: Non-admin (contractor) does NOT see Create Quote button` -- BIZ-01
6. `biz01_cancelled: Admin does NOT see Create Quote button for cancelled job` -- BIZ-01
7. `biz02_view: Admin sees View / Edit Quote button when quote exists` -- BIZ-02
8. `biz02_draft_visible: Admin sees View / Edit Quote for draft quote` -- BIZ-02

### Backend Integration Test Details (4 passing)

1. `test_travel_provider_absent_when_no_ors_key` -- SCHED-06
2. `test_travel_provider_injected_when_ors_key_set` -- SCHED-06
3. `test_scheduling_availability_endpoint_smoke` -- SCHED-06
4. `test_scheduling_conflicts_endpoint_smoke` -- SCHED-06

### Gap Analysis

No gaps found. All 4 requirements (SCHED-08, BIZ-01, BIZ-02, SCHED-06) have multiple automated tests covering their behavioral contracts across Flutter widget tests and backend integration tests.

### Compliance Determination

**nyquist_compliant: true** -- Every requirement has at least one automated behavioral test that was executed and passed during this audit.
