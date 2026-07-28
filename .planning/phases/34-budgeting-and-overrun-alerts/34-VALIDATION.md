---
phase: 34
slug: budgeting-and-overrun-alerts
status: planned
nyquist_compliant: true
wave_0_complete: false
created: 2026-07-28
---

# Phase 34 — Validation Strategy

> Per-phase validation contract for feedback sampling during execution.
> Seeded from 34-RESEARCH.md § Validation Architecture. The per-task map is
> completed by the planner (task IDs assigned at plan time).

---

## Test Infrastructure

| Property | Value |
|----------|-------|
| **Backend framework** | pytest 8.3.4, `asyncio_mode=auto`, `testpaths=["tests"]` (`backend/pyproject.toml`); ASGI client + JWT-bearer fixtures in `conftest.py` |
| **Backend quick run** | `cd backend && .venv/bin/pytest tests/test_phase_34_e2e.py -x -q` |
| **Backend full suite** | `cd backend && .venv/bin/pytest` |
| **Web framework** | Jest (`npm run test`, `web/jest.config.ts`) + Playwright (`npm run test-e2e`, specs in `web/tests/phase-34-*.spec.ts`; precedent `phase-33-margin.spec.ts`) |
| **Web quick run** | `cd web && npm test -- budget && npx playwright test tests/phase-34-budgets.spec.ts --project=chromium` |
| **Web full suite** | `cd web && npm run lint && npx tsc --noEmit && npm run test` |
| **Mobile framework** | flutter_test; E2E in `mobile/test/e2e/phase_34_*_e2e_test.dart` |
| **Mobile quick run** | `cd mobile && flutter test test/e2e/phase_34_budgets_e2e_test.dart` |
| **Mobile full suite** | `cd mobile && flutter test` |
| **Estimated runtime** | ~30s per-task quick runs |

---

## Sampling Rate

- **After every task commit:** `pytest tests/test_phase_34_e2e.py -x` (plus `ruff check`, `dart analyze`/`npm run lint` for touched platforms).
- **After every plan wave:** full backend `pytest` + `flutter test` + web `lint`/`tsc`/`jest`.
- **Before `/gsd:verify-work`:** all suites green + Playwright `phase-34` spec.
- **Max feedback latency:** ~30 seconds.

---

## Phase Requirements → Test Map

| Req ID | Behavior | Test Type | Automated Command | File Exists? |
|--------|----------|-----------|-------------------|-------------|
| BUDG-01 | Budget CRUD (XOR anchor, finance.manage gate, soft-delete, 403s) | integration | `pytest tests/test_phase_34_e2e.py -k budget_crud -x` | ❌ Wave 0 |
| BUDG-02 | budget-vs-actual embedded in breakdown/rollup; `spent == grand_total` consistency | integration | `pytest tests/test_phase_34_e2e.py -k budget_vs_actual -x` | ❌ Wave 0 |
| BUDG-02 | Web/mobile budget rows render (incl. over-budget state) | unit/widget + E2E | `npm run test -- budget` · `flutter test test/e2e/phase_34_budgets_e2e_test.dart` · `npx playwright test tests/phase-34-budgets.spec.ts` | ❌ Wave 0 |
| BUDG-03 | 80/100 fire exactly once; re-arm on increase; concurrent-eval race fires once; non-finance sees nothing + no FCM (keystone tests 1 & 3) | unit + integration | `pytest tests/unit/test_budget_evaluation.py -x` · `pytest tests/test_phase_34_e2e.py -k alerts -x` | ❌ Wave 0 |
| BUDG-03 | Nightly sweep evaluates all budgets idempotently | integration | `pytest tests/test_phase_34_e2e.py -k sweep -x` | ❌ Wave 0 |
| BUDG-04 | Signed delta on approved revision (up + down, keystone test 2); anchors carried through revise_quote; no-op without budget; baseline on first approval | integration | `pytest tests/test_phase_34_e2e.py -k quote_delta -x` | ❌ Wave 0 |

Manual-only: none — FCM is mocked at the messaging layer (precedent: `test_phase_24_fcm_rejection.py`); visual chip/color checks fall to the UI-SPEC/UAT pass.

**Test-fixture note (Phase 33-02 lesson):** BUDG-04 delta tests must exercise the REAL `approve_quote` endpoint for the hook — drive the status machine through endpoints (send → approve), or set pre-approval status via SQL then call approve. Do not approve via raw SQL alone.

*Status: ⬜ pending · ✅ green · ❌ red · ⚠️ flaky*

---

## Wave 0 Requirements

- [ ] `backend/tests/test_phase_34_e2e.py` — BUDG-01..04 integration coverage
- [ ] `backend/tests/unit/test_budget_evaluation.py` — threshold math, dedup/claim, re-arm, delta math (pure/unit)
- [ ] Update `backend/tests/unit/test_finance_scrub.py` (FINANCIAL_ALERT_TYPES empty-set pin at line 51) and `test_phase_30_e2e.py` leak test (stand-in type → real budget types) — SAME commit that registers `budget_warning`/`budget_overrun`
- [ ] `web/tests/phase-34-budgets.spec.ts` — Set-budget dialog + budget rows + alert panel (login through UI + SPA-navigate, 32-04 lesson)
- [ ] `web/src/features/finance/__tests__/budget-section.test.tsx` (+ SetBudgetDialog test)
- [ ] `mobile/test/e2e/phase_34_budgets_e2e_test.dart` — budget rows from mocked Dio breakdown; tolerant parsing of absent `budget` key
- Framework install: none — all harnesses configured and in use.

---

## Manual-Only Verifications

None — FCM mocked at messaging layer; visual polish deferred to UI-SPEC checker/UAT.

---

## Validation Sign-Off

- [ ] All tasks have `<automated>` verify or Wave 0 dependencies
- [ ] Sampling continuity: no 3 consecutive tasks without automated verify
- [ ] Wave 0 covers all MISSING references
- [ ] No watch-mode flags
- [ ] Feedback latency < 30s
- [x] `nyquist_compliant: true` set in frontmatter

**Approval:** pending
