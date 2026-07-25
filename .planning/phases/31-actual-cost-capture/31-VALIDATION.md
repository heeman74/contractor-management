---
phase: 31
slug: actual-cost-capture
status: draft
nyquist_compliant: false
wave_0_complete: false
created: 2026-07-25
---

# Phase 31 — Validation Strategy

> Per-phase validation contract for feedback sampling during execution.
> Seeded from 31-RESEARCH.md § Validation Architecture. The per-task map is
> completed by the planner (task IDs assigned at plan time).

---

## Test Infrastructure

| Property | Value |
|----------|-------|
| **Backend framework** | pytest + pytest-asyncio, `contractorhub_test` DB via `conftest.py` |
| **Backend quick run** | `cd backend && source .venv/bin/activate && python -m pytest tests/test_phase_31_e2e.py -q` |
| **Backend full suite** | `cd backend && source .venv/bin/activate && python -m pytest -q` |
| **Web framework** | Jest (component/unit) + Playwright (E2E, mocked `/api/proxy`) |
| **Web quick run** | `cd web && npx jest src/features/finance && npx playwright test tests/cost-capture.spec.ts` |
| **Web full suite** | `cd web && npm run test-e2e` |
| **Mobile framework** | `flutter_test` — unit (mocktail), widget (ProviderScope overrides), DAO (in-memory Drift) |
| **Mobile quick run** | `cd mobile && flutter test test/e2e/phase_31_cost_capture_e2e_test.dart` |
| **Mobile full suite** | `cd mobile && flutter test` |

---

## Sampling Rate

- **After every task commit:** run the single new/changed test file for the task (backend `pytest tests/test_phase_31_e2e.py -q`; web `npx jest` + the one Playwright spec; mobile the one E2E file).
- **After every plan wave:** backend full `pytest -q`; web `npm run test-e2e`; mobile `flutter test`.
- **Before `/gsd:verify-work`:** all three full suites green.
- **Max feedback latency:** ~30s for per-task quick runs.

---

## Phase Requirements → Test Map

| Req / Criterion | Behavior | Test Type | Automated Command | File |
|---|---|---|---|---|
| COST-01 | Create materials cost entry on a job (amount/category/date/vendor/note) | backend E2E | `pytest tests/test_phase_31_e2e.py::test_create_materials_cost_entry_on_job -x` | ❌ W0 |
| COST-01 | Create materials cost entry on a trade scope | backend E2E | `pytest tests/test_phase_31_e2e.py::test_create_materials_cost_entry_on_trade_scope -x` | ❌ W0 |
| COST-01 | XOR anchor rejected (both / neither job_id & trade_scope_id) | backend | `pytest tests/test_phase_31_e2e.py::test_cost_entry_rejects_both_or_neither_anchor -x` | ❌ W0 |
| COST-02 | Create subcontractor cost entry | backend E2E | `pytest tests/test_phase_31_e2e.py::test_create_subcontractor_cost_entry -x` | ❌ W0 |
| COST-02 | Create "other" category cost entry | backend E2E | `pytest tests/test_phase_31_e2e.py::test_create_other_category_cost_entry -x` | ❌ W0 |
| COST-03 | Attach receipt, retrievable via `/files/cost-receipts/...` | backend E2E | `pytest tests/test_phase_31_e2e.py::test_upload_and_fetch_cost_receipt -x` | ❌ W0 |
| COST-03 | Multiple receipts on one entry | backend E2E | `pytest tests/test_phase_31_e2e.py::test_multiple_receipts_per_cost_entry -x` | ❌ W0 |
| COST-03 | Cross-tenant receipt fetch → 404 | backend E2E | `pytest tests/test_phase_31_e2e.py::test_other_tenant_cannot_fetch_cost_receipt -x` | ❌ W0 |
| Criterion 4 | Non-finance role → 403 on every cost + receipt endpoint | backend E2E | `pytest tests/test_phase_31_e2e.py::test_non_finance_role_403_on_every_cost_endpoint -x` | ❌ W0 |
| D-05 | Soft-deleted entry drops from list + rollup | backend E2E | `pytest tests/test_phase_31_e2e.py::test_soft_deleted_cost_entry_excluded_from_lists_and_rollup -x` | ❌ W0 |
| D-02/D-05 | Project rollup = trade-scope costs + job costs (job.project_id = project) | backend E2E | `pytest tests/test_phase_31_e2e.py::test_project_rollup_combines_scope_and_job_costs -x` | ❌ W0 |
| D-06 | API-level RLS isolation (tenant B cannot read tenant A costs via endpoints) | backend E2E | `pytest tests/test_phase_31_e2e.py::test_cost_entry_api_rls_isolation -x` | ❌ W0 |
| D-06 (web) | "Add cost"/list hidden without finance.view/manage, visible with it | web Playwright | `npx playwright test tests/cost-capture.spec.ts` | ❌ W0 |
| D-01/D-04 (mobile) | Offline: create entry + local receipt, drain queue + upload on reconnect | mobile E2E | `flutter test test/e2e/phase_31_cost_capture_e2e_test.dart` | ❌ W0 |

---

## Per-Task Verification Map

*Filled by the planner once task IDs are assigned. Every task must map to a row above or declare a Wave 0 dependency.*

| Task ID | Plan | Wave | Requirement | Test Type | Automated Command | Status |
|---------|------|------|-------------|-----------|-------------------|--------|
| _TBD by planner_ | | | | | | ⬜ pending |

---

## Wave 0 Requirements

- [ ] `backend/tests/test_phase_31_e2e.py` — new file; COST-01/02/03 + criterion 4 (403) + D-05 soft-delete + D-02/D-05 rollup + API-level RLS isolation. Reuse the `_token(company_id, roles)` helper from `test_phase_30_e2e.py` (import or copy the ~3-line `create_access_token` helper).
- [ ] `web/tests/cost-capture.spec.ts` — new Playwright spec; mock `/api/proxy` for `/me/permissions` (with/without finance.*), `/cost-entries` CRUD, and receipt upload; log in through the UI first (permission-gated flow).
- [ ] `web/src/features/finance/__tests__/*.test.tsx` — Jest tests for cost-entry form/validation logic.
- [ ] `mobile/test/e2e/phase_31_cost_capture_e2e_test.dart` — new file; seed Drift, drive "Add cost" via fake CostEntryDao/provider, assert MockDioClient captured request + payload, and verify the receipt upload service's retry/backoff against a mocked Dio failure-then-success (mirror `mobile/test/unit/features/jobs/attachment_upload_service_test.dart`).
- [ ] Framework install: none — pytest/Jest/Playwright/flutter_test all already configured.

---

## Manual-Only Verifications

| Behavior | Requirement | Why Manual | Test Instructions |
|----------|-------------|------------|-------------------|
| Receipt photo renders correctly on a physical device / emulator | COST-03 | Widget tests assert the NetworkImage is configured (url + auth header), not that pixels paint | On emulator, log in as owner, add a cost with a receipt, reopen the entry, confirm the receipt thumbnail loads |

---

## Validation Sign-Off

- [ ] All tasks have `<automated>` verify or Wave 0 dependencies
- [ ] Sampling continuity: no 3 consecutive tasks without automated verify
- [ ] Wave 0 covers all MISSING references
- [ ] No watch-mode flags
- [ ] Feedback latency < 30s
- [ ] `nyquist_compliant: true` set in frontmatter

**Approval:** pending
