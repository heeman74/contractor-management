---
phase: 31
slug: actual-cost-capture
status: planned
nyquist_compliant: true
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
| COST-01 | Create materials cost entry on a job (amount/category/date/vendor/note) | backend E2E | `pytest tests/test_phase_31_e2e.py::test_create_materials_cost_entry_on_job -x` | 31-01 |
| COST-01 | Create materials cost entry on a trade scope | backend E2E | `pytest tests/test_phase_31_e2e.py::test_create_materials_cost_entry_on_trade_scope -x` | 31-01 |
| COST-01 | XOR anchor rejected (both / neither job_id & trade_scope_id) | backend | `pytest tests/test_phase_31_e2e.py::test_cost_entry_rejects_both_or_neither_anchor -x` | 31-01 |
| COST-02 | Create subcontractor cost entry | backend E2E | `pytest tests/test_phase_31_e2e.py::test_create_subcontractor_cost_entry -x` | 31-01 |
| COST-02 | Create "other" category cost entry | backend E2E | `pytest tests/test_phase_31_e2e.py::test_create_other_category_cost_entry -x` | 31-01 |
| COST-03 | Attach receipt, retrievable via `/files/cost-receipts/...` | backend E2E | `pytest tests/test_phase_31_e2e.py::test_upload_and_fetch_cost_receipt -x` | 31-02 |
| COST-03 | Multiple receipts on one entry | backend E2E | `pytest tests/test_phase_31_e2e.py::test_multiple_receipts_per_cost_entry -x` | 31-02 |
| COST-03 | Cross-tenant receipt fetch → 404 | backend E2E | `pytest tests/test_phase_31_e2e.py::test_other_tenant_cannot_fetch_cost_receipt -x` | 31-02 |
| Criterion 4 | Non-finance role → 403 on every cost + receipt endpoint | backend E2E | `pytest tests/test_phase_31_e2e.py::test_non_finance_role_403_on_every_cost_endpoint -x` | 31-01 (entries) / 31-02 (receipts) |
| D-05 | Soft-deleted entry drops from list + rollup | backend E2E | `pytest tests/test_phase_31_e2e.py::test_soft_deleted_cost_entry_excluded_from_lists_and_rollup -x` | 31-01 |
| D-02/D-05 | Project rollup = trade-scope costs + job costs (job.project_id = project) | backend E2E | `pytest tests/test_phase_31_e2e.py::test_project_rollup_combines_scope_and_job_costs -x` | 31-01 |
| D-06 | API-level RLS isolation (tenant B cannot read tenant A costs via endpoints) | backend E2E | `pytest tests/test_phase_31_e2e.py::test_cost_entry_api_rls_isolation -x` | 31-01 |
| D-06 (web) | "Add cost"/list hidden without finance.view/manage, visible with it | web Playwright | `npx playwright test tests/cost-capture.spec.ts` | 31-03 |
| D-01/D-04 (mobile) | Offline: create entry + local receipt, drain queue + upload on reconnect | mobile E2E | `flutter test test/e2e/phase_31_cost_capture_e2e_test.dart` | 31-05 |

---

## Per-Task Verification Map

*Every task maps to a test row above or is a scaffold/data task whose own automated verify gates it.*

| Task ID | Plan | Wave | Requirement | Test Type | Automated Command | Status |
|---------|------|------|-------------|-----------|-------------------|--------|
| 31-01-T1 | 31-01 | 1 | COST-01/03 (schema) | import smoke | `python -c "from app.features.finance.models import CostReceipt; from app.features.finance.schemas import CostEntryResponse..."` | ⬜ pending |
| 31-01-T2 | 31-01 | 1 | COST-01/02 (repo/service) | import + source assert | `python -c "from app.features.finance.repository import FinanceRepository..."` | ⬜ pending |
| 31-01-T3 | 31-01 | 1 | COST-01/02, Criterion 4, D-02/05, D-06 | backend E2E | `pytest tests/test_phase_31_e2e.py -q -k "cost_entry or materials or subcontractor or rollup or non_finance or rls"` | ⬜ pending |
| 31-02-T1 | 31-02 | 2 | COST-03 | route inspect + E2E | `pytest tests/test_phase_31_e2e.py -q -k "receipt"` | ⬜ pending |
| 31-02-T2 | 31-02 | 2 | COST-03 (serve) | source assert + E2E | `pytest tests/test_phase_31_e2e.py -q -k "receipt"` | ⬜ pending |
| 31-02-T3 | 31-02 | 2 | COST-03, Criterion 4 | backend E2E | `pytest tests/test_phase_31_e2e.py -q -k "receipt"` | ⬜ pending |
| 31-03-T1 | 31-03 | 3 | COST-01/02/03 (web client) | typecheck | `cd web && npx tsc --noEmit` | ⬜ pending |
| 31-03-T2 | 31-03 | 3 | COST-01/02/03, D-02, D-06 | typecheck + lint | `npx tsc --noEmit && npx eslint web/src/features/finance --max-warnings 0` | ⬜ pending |
| 31-03-T3 | 31-03 | 3 | COST-01/02/03, D-06 (web) | web Playwright + Jest | `npx jest src/features/finance && npx playwright test tests/cost-capture.spec.ts` | ⬜ pending |
| 31-04-T1 | 31-04 | 3 | COST-01/02/03 (Drift v16) | analyze + build_runner | `dart run build_runner build --delete-conflicting-outputs && dart analyze lib/features/finance/data` | ⬜ pending |
| 31-04-T2 | 31-04 | 3 | COST-01/02/03 (sync/upload) | analyze | `dart analyze lib/core/sync lib/features/finance` | ⬜ pending |
| 31-04-T3 | 31-04 | 3 | COST-01/03 (offline/upload) | mobile unit | `flutter test test/unit/features/finance` | ⬜ pending |
| 31-05-T1 | 31-05 | 4 | COST-01/02/03 (UI) | analyze | `dart analyze lib/features/finance/presentation` | ⬜ pending |
| 31-05-T2 | 31-05 | 4 | COST-01/02/03, D-06 | analyze | `dart analyze lib/features/jobs/.../job_detail_screen.dart ...` | ⬜ pending |
| 31-05-T3 | 31-05 | 4 | D-01/D-04 (mobile E2E) | mobile E2E | `flutter test test/e2e/phase_31_cost_capture_e2e_test.dart` | ⬜ pending |

---

## Wave 0 Requirements

Note: this phase has no separate "Wave 0" plan — each layer's E2E ships inside the plan that
builds that layer (CLAUDE.md: E2E ships WITH the feature in the same change). The four test
files below are created/extended by their owning plans:

- [ ] `backend/tests/test_phase_31_e2e.py` — created in 31-01 (cost-entry: COST-01/02 + criterion 4 (403) + D-05 soft-delete + D-02/D-05 rollup + API-level RLS isolation); extended in 31-02 (COST-03 receipts + cross-tenant 404 + receipt 403). Reuse the `_token(company_id, roles)` helper from `test_phase_30_e2e.py`.
- [ ] `web/tests/cost-capture.spec.ts` + `web/src/features/finance/__tests__/cost-entry-form.test.tsx` — created in 31-03; mock `/api/proxy` for `/me/permissions` (with/without finance.*), `/cost-entries` CRUD, and receipt upload; log in through the UI first (permission-gated flow).
- [ ] `mobile/test/unit/features/finance/*` — created in 31-04 (DAO + receipt upload retry/backoff, mirroring `attachment_upload_service_test.dart`).
- [ ] `mobile/test/e2e/phase_31_cost_capture_e2e_test.dart` — created in 31-05 (offline create + drain + receipt upload on reconnect + gating).
- [ ] Framework install: none — pytest/Jest/Playwright/flutter_test all already configured.

---

## Manual-Only Verifications

| Behavior | Requirement | Why Manual | Test Instructions |
|----------|-------------|------------|-------------------|
| Receipt photo renders correctly on a physical device / emulator | COST-03 | Widget tests assert the NetworkImage is configured (url + auth header), not that pixels paint | On emulator, log in as owner, add a cost with a receipt, reopen the entry, confirm the receipt thumbnail loads |

---

## Validation Sign-Off

- [x] All tasks have `<automated>` verify or Wave 0 dependencies
- [x] Sampling continuity: no 3 consecutive tasks without automated verify
- [x] Wave 0 covers all MISSING references
- [x] No watch-mode flags
- [x] Feedback latency < 30s
- [x] `nyquist_compliant: true` set in frontmatter

**Approval:** approved (planner, 2026-07-25)
