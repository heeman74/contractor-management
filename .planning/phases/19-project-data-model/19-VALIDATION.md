---
phase: 19
slug: project-data-model
status: draft
nyquist_compliant: false
wave_0_complete: false
created: 2026-03-19
---

# Phase 19 — Validation Strategy

> Per-phase validation contract for feedback sampling during execution.

---

## Test Infrastructure

| Property | Value |
|----------|-------|
| **Framework (backend)** | pytest 7.x + ASGI client |
| **Framework (mobile)** | flutter_test + Drift in-memory DB |
| **Config file** | `backend/tests/conftest.py` (existing) |
| **Quick run (backend)** | `cd backend && uv run python -m pytest tests/test_phase_19_e2e.py -x` |
| **Quick run (mobile)** | `cd mobile && flutter test test/e2e/phase_19_project_data_model_e2e_test.dart` |
| **Full suite (backend)** | `cd backend && uv run python -m pytest` |
| **Full suite (mobile)** | `cd mobile && flutter test` |
| **Estimated runtime** | ~30 seconds (backend) / ~45 seconds (mobile) |

---

## Sampling Rate

- **After every task commit:** Run quick run command for the relevant stack
- **After every plan wave:** Run full suite for both stacks
- **Before `/gsd:verify-work`:** Full suite must be green
- **Max feedback latency:** 45 seconds

---

## Per-Task Verification Map

| Task ID | Plan | Wave | Requirement | Test Type | Automated Command | File Exists | Status |
|---------|------|------|-------------|-----------|-------------------|-------------|--------|
| 19-01-01 | 01 | 1 | PROJ-01 | integration | `uv run python -m pytest tests/test_phase_19_e2e.py::test_gc_creates_project -x` | ❌ W0 | ⬜ pending |
| 19-01-02 | 01 | 1 | PROJ-01 | integration | `uv run python -m pytest tests/test_phase_19_e2e.py::test_project_list_returns_created -x` | ❌ W0 | ⬜ pending |
| 19-01-03 | 01 | 1 | PROJ-01 | integration | `uv run python -m pytest tests/test_phase_19_e2e.py::test_rls_isolation -x` | ❌ W0 | ⬜ pending |
| 19-02-01 | 02 | 1 | PROJ-02 | integration | `uv run python -m pytest tests/test_phase_19_e2e.py::test_add_trade_scope_from_catalog -x` | ❌ W0 | ⬜ pending |
| 19-02-02 | 02 | 1 | PROJ-02 | integration | `uv run python -m pytest tests/test_phase_19_e2e.py::test_add_adhoc_trade_scope -x` | ❌ W0 | ⬜ pending |
| 19-02-03 | 02 | 1 | PROJ-02 | integration | `uv run python -m pytest tests/test_phase_19_e2e.py::test_contractor_assignment -x` | ❌ W0 | ⬜ pending |
| 19-02-04 | 02 | 1 | PROJ-02 | integration | `uv run python -m pytest tests/test_phase_19_e2e.py::test_status_auto_advance_planning -x` | ❌ W0 | ⬜ pending |
| 19-03-01 | 03 | 2 | PROJ-03 | E2E widget | `flutter test test/e2e/phase_19_project_data_model_e2e_test.dart -t "project_list"` | ❌ W0 | ⬜ pending |
| 19-03-02 | 03 | 2 | PROJ-03 | E2E widget | `flutter test test/e2e/phase_19_project_data_model_e2e_test.dart -t "project_detail"` | ❌ W0 | ⬜ pending |
| 19-03-03 | 03 | 2 | PROJ-03 | E2E widget | `flutter test test/e2e/phase_19_project_data_model_e2e_test.dart -t "scope_detail"` | ❌ W0 | ⬜ pending |
| 19-03-04 | 03 | 2 | PROJ-03 | unit/integration | `cd web && npm test -- projects` | ❌ W0 | ⬜ pending |
| 19-MIG-01 | 01 | 1 | All | integration | `uv run python -m pytest tests/test_phase_19_e2e.py::test_data_migration -x` | ❌ W0 | ⬜ pending |

*Status: ⬜ pending · ✅ green · ❌ red · ⚠️ flaky*

---

## Wave 0 Requirements

- [ ] `backend/tests/test_phase_19_e2e.py` — stubs for PROJ-01, PROJ-02 backend behaviors + RLS isolation + data migration
- [ ] `mobile/test/e2e/phase_19_project_data_model_e2e_test.dart` — stubs for PROJ-03 mobile tree view
- [ ] No new framework install needed — pytest and flutter_test already configured

*Existing infrastructure covers framework requirements.*

---

## Manual-Only Verifications

| Behavior | Requirement | Why Manual | Test Instructions |
|----------|-------------|------------|-------------------|
| Tree view visual hierarchy renders correctly | PROJ-03 | Visual layout/spacing check | Navigate Project → Scopes → Tasks, verify indentation and visual clarity |
| Trade scope color badges display correctly | PROJ-02 | Visual color rendering | Create scopes with different trades, verify color badges match catalog |

---

## Validation Sign-Off

- [ ] All tasks have `<automated>` verify or Wave 0 dependencies
- [ ] Sampling continuity: no 3 consecutive tasks without automated verify
- [ ] Wave 0 covers all MISSING references
- [ ] No watch-mode flags
- [ ] Feedback latency < 45s
- [ ] `nyquist_compliant: true` set in frontmatter

**Approval:** pending
