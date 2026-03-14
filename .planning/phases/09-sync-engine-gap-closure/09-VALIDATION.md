---
phase: 9
slug: sync-engine-gap-closure
status: draft
nyquist_compliant: false
wave_0_complete: false
created: 2026-03-14
---

# Phase 9 — Validation Strategy

> Per-phase validation contract for feedback sampling during execution.

---

## Test Infrastructure

| Property | Value |
|----------|-------|
| **Framework** | flutter_test + mocktail (Flutter), pytest + httpx (Backend) |
| **Config file** | `mobile/` and `backend/` directories |
| **Quick run command** | `flutter test test/e2e/phase_9_sync_gap_closure_e2e_test.dart` |
| **Full suite command** | `flutter test test/ && uv run python -m pytest backend/tests/` |
| **Estimated runtime** | ~30 seconds |

---

## Sampling Rate

- **After every task commit:** Run `flutter test test/e2e/phase_9_sync_gap_closure_e2e_test.dart`
- **After every plan wave:** Run `flutter test test/ && uv run python -m pytest backend/tests/`
- **Before `/gsd:verify-work`:** Full suite must be green
- **Max feedback latency:** 30 seconds

---

## Per-Task Verification Map

| Task ID | Plan | Wave | Requirement | Test Type | Automated Command | File Exists | Status |
|---------|------|------|-------------|-----------|-------------------|-------------|--------|
| 09-01-01 | 01 | 1 | INFRA-04 | unit | `flutter test test/e2e/phase_9_sync_gap_closure_e2e_test.dart` | ❌ W0 | ⬜ pending |
| 09-01-02 | 01 | 1 | INFRA-04 | unit | same | ❌ W0 | ⬜ pending |
| 09-01-03 | 01 | 1 | FIELD-02 | unit | same | ❌ W0 | ⬜ pending |
| 09-01-04 | 01 | 1 | BIZ-01 | unit | same | ❌ W0 | ⬜ pending |
| 09-01-05 | 01 | 1 | BIZ-03 | unit | same | ❌ W0 | ⬜ pending |
| 09-01-06 | 01 | 1 | SCHED-03 | integration | same | ❌ W0 | ⬜ pending |
| 09-01-07 | 01 | 1 | BIZ-01, BIZ-03 | integration | same | ❌ W0 | ⬜ pending |
| 09-01-08 | 01 | 1 | INFRA-04 | backend integration | `uv run python -m pytest backend/tests/integration/test_phase_9_sync_e2e.py -x` | ❌ W0 | ⬜ pending |

*Status: ⬜ pending · ✅ green · ❌ red · ⚠️ flaky*

---

## Wave 0 Requirements

- [ ] `mobile/test/e2e/phase_9_sync_gap_closure_e2e_test.dart` — stubs for INFRA-04, FIELD-02, BIZ-01, BIZ-03, SCHED-03
- [ ] `backend/tests/integration/test_phase_9_sync_e2e.py` — backend endpoint verification (14 keys, line items as flat arrays)

*Existing `conftest.py` fixtures cover shared test infrastructure.*

---

## Manual-Only Verifications

*All phase behaviors have automated verification.*

---

## Validation Sign-Off

- [ ] All tasks have `<automated>` verify or Wave 0 dependencies
- [ ] Sampling continuity: no 3 consecutive tasks without automated verify
- [ ] Wave 0 covers all MISSING references
- [ ] No watch-mode flags
- [ ] Feedback latency < 30s
- [ ] `nyquist_compliant: true` set in frontmatter

**Approval:** pending
