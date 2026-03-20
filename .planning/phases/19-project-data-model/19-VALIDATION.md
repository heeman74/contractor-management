---
phase: 19
slug: project-data-model
status: draft
nyquist_compliant: true
wave_0_complete: true
created: 2026-03-19
---

# Phase 19 -- Validation Strategy

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

## Wave 0 Assessment

Plans 01 and 02 (Wave 1) verify via model imports and code generation -- they do NOT reference test files. Test files are created within the plans that need them:
- `backend/tests/test_phase_19_e2e.py` -- created in Plan 03 Task 2 (Wave 2)
- `mobile/test/e2e/phase_19_project_data_model_e2e_test.dart` -- created in Plan 04 Task 2 (Wave 2)
- `web/e2e/projects.spec.ts` -- created in Plan 05 Task 3 (Wave 3)

No separate Wave 0 plan is needed. Each test file is created in the same plan that runs it.

---

## Per-Task Verification Map

| Task ID | Plan | Wave | Requirement | Test Type | Automated Command | Status |
|---------|------|------|-------------|-----------|-------------------|--------|
| 19-01-01 | 01 | 1 | PROJ-01 | import check | `uv run python -c "from app.features.projects.models import Project, ..."` | pending |
| 19-01-02 | 01 | 1 | PROJ-01 | migration + RLS | `uv run alembic upgrade head && uv run python -c "... pg_policies ..."` | pending |
| 19-02-01 | 02 | 1 | PROJ-01 | code generation | `dart run build_runner build --delete-conflicting-outputs` | pending |
| 19-02-02 | 02 | 1 | PROJ-02 | static analysis | `dart analyze lib/features/projects/data/` | pending |
| 19-03-01 | 03 | 2 | PROJ-01 | integration | `uv run python -m pytest tests/test_phase_19_e2e.py -x -v` | pending |
| 19-04-01 | 04 | 2 | PROJ-03 | static analysis | `dart analyze lib/features/projects/` | pending |
| 19-04-02 | 04 | 2 | PROJ-03 | E2E widget | `flutter test test/e2e/phase_19_project_data_model_e2e_test.dart` | pending |
| 19-05-01 | 05 | 3 | PROJ-03 | typecheck | `cd web && npx tsc --noEmit` | pending |
| 19-05-02 | 05 | 3 | PROJ-03 | E2E playwright | `cd web && npx playwright test e2e/projects.spec.ts --reporter=line` | pending |

*Status: pending / green / red / flaky*

---

## Manual-Only Verifications

| Behavior | Requirement | Why Manual | Test Instructions |
|----------|-------------|------------|-------------------|
| Tree view visual hierarchy renders correctly | PROJ-03 | Visual layout/spacing check | Navigate Project -> Scopes -> Tasks, verify indentation and visual clarity |
| Trade scope color badges display correctly | PROJ-02 | Visual color rendering | Create scopes with different trades, verify color badges match catalog |

---

## Validation Sign-Off

- [x] All tasks have `<automated>` verify commands
- [x] Sampling continuity: no 3 consecutive tasks without automated verify
- [x] Test files are created within the same plan that references them
- [x] No watch-mode flags
- [x] Feedback latency < 45s
- [x] `nyquist_compliant: true` set in frontmatter

**Approval:** ready
