---
phase: 34
slug: budgeting-and-overrun-alerts
status: planned
nyquist_compliant: true
wave_0_complete: false
created: 2026-07-28
task_map_completed: 2026-07-28
---

# Phase 34 — Validation Strategy

> Per-phase validation contract for feedback sampling during execution.
> Seeded from 34-RESEARCH.md § Validation Architecture. The per-task map below
> was completed at plan time (8 plans, 5 waves).

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

| Req ID | Behavior | Test Type | Automated Command | Owning task | File Exists? |
|--------|----------|-----------|-------------------|-------------|-------------|
| BUDG-01 | Budget CRUD (XOR anchor, finance.manage gate, soft-delete, 409 duplicate, 403s) | integration | `pytest tests/test_phase_34_e2e.py -k budget_crud -x` | **34-02 T2** | ❌ created by 34-02 T2 |
| BUDG-01 | Set/edit/remove budget dialog + affordance gating (UI-SPEC states 2, 11) | unit + E2E | `npm test -- set-budget-dialog` · `npx playwright test tests/phase-34-budgets.spec.ts` | **34-07 T1, T2, T3** | ❌ created by 34-07 |
| BUDG-02 | budget-vs-actual embedded in breakdown/rollup; `spent == grand_total` consistency | integration | `pytest tests/test_phase_34_e2e.py -k budget_vs_actual -x` | **34-02 T3** | ❌ created by 34-02 T3 |
| BUDG-02 | Web budget rows, state matrix 1/3–10 | unit | `npm test -- budget-section` | **34-04 T2, T3** | ❌ created by 34-04 T2 |
| BUDG-02 | Mobile budget rows + tolerant parsing of an absent `budget` key | unit + E2E | `flutter test test/features/finance/budget_summary_parse_test.dart` · `flutter test test/e2e/phase_34_budgets_e2e_test.dart` | **34-05 T1, T2, T3** | ❌ created by 34-05 |
| BUDG-03 | Threshold/percent/copy math (pure) | unit | `pytest tests/unit/test_budget_evaluation.py -x` | **34-01 T3** | ❌ created by 34-01 T3 |
| BUDG-03 | 80/100 fire exactly once; re-arm on increase; concurrent-eval race fires once; non-finance sees nothing + no FCM (keystone tests 1 & 3) | integration | `pytest tests/test_phase_34_e2e.py -k alerts -x` | **34-03 T2, T3** | ❌ created by 34-03 T2 |
| BUDG-03 | Alert types registered; the two shipped empty-set pins updated in the same commit | unit + integration | `pytest tests/unit/test_finance_scrub.py tests/test_phase_30_e2e.py -x` | **34-01 T2** | ✅ exists (updated in place) |
| BUDG-03 | Evaluation fires automatically on cost create/update/delete and on budget edit | integration | `pytest tests/test_phase_34_e2e.py -k mutation -x` | **34-06 T1** | ❌ created by 34-06 T1 |
| BUDG-03 | Nightly sweep evaluates all budgets idempotently, incl. labor-only crossings; cron job registered at 05:00 UTC | integration | `pytest tests/test_phase_34_e2e.py -k sweep -x` | **34-06 T2, T3** | ❌ created by 34-06 T2 |
| BUDG-04 | Anchors carried through revise_quote; approved quotes revisable; chain link set | integration | `pytest tests/test_phase_34_e2e.py -k quote_delta -x` | **34-08 T1** | ❌ created by 34-08 T1 |
| BUDG-04 | Pre-tax delta math + minimum-total clamp (pure) | unit | `pytest tests/unit/test_budget_evaluation.py -x` | **34-08 T2** | ✅ file exists (34-01 T3), section added |
| BUDG-04 | Signed delta on approved revision (up + down, keystone test 2); no-op without budget; baseline on first approval | integration | `pytest tests/test_phase_34_e2e.py -k quote_delta -x` | **34-08 T3** | ❌ created by 34-08 T3 |

Manual-only: none — FCM is mocked at the messaging layer (precedent: `test_phase_24_fcm_rejection.py`); visual chip/color checks fall to the UI-SPEC/UAT pass.

**Test-fixture note (Phase 33-02 lesson):** BUDG-04 delta tests must exercise the REAL `approve_quote` endpoint for the hook — drive the status machine through endpoints (send → approve), or set pre-approval status via SQL then call approve. Do not approve via raw SQL alone.

*Status: ⬜ pending · ✅ green · ❌ red · ⚠️ flaky*

---

## Wave 0 Requirements

Every test file below is created by the task that first needs it, inside the plan
that produces the behaviour — no test file is deferred past the code it covers.

- [ ] `backend/tests/unit/test_budget_evaluation.py` — threshold/percent/copy math → **34-01 T3** (delta section added by 34-08 T2)
- [ ] Update `backend/tests/unit/test_finance_scrub.py` (FINANCIAL_ALERT_TYPES empty-set pin at line 51) and `test_phase_30_e2e.py` leak test (stand-in type → real budget types) → **34-01 T2, SAME commit as registration**
- [ ] `backend/tests/test_phase_34_e2e.py` — created by **34-02 T2** (`budget_crud`), extended by 34-02 T3 (`budget_vs_actual`), 34-03 T2/T3 (`alerts`), 34-06 T1/T2/T3 (`mutation`, `sweep`), 34-08 T1/T3 (`quote_delta`)
- [ ] `web/src/features/finance/__tests__/budget-section.test.tsx` → **34-04 T2** (extended by 34-04 T3 and 34-07 T2)
- [ ] `web/src/features/finance/__tests__/set-budget-dialog.test.tsx` → **34-07 T1**
- [ ] `web/tests/phase-34-budgets.spec.ts` — Set-budget dialog + budget rows + alert panel (login through UI + SPA-navigate, 32-04 lesson) → **34-07 T3**
- [ ] `mobile/test/features/finance/budget_summary_parse_test.dart` → **34-05 T1**
- [ ] `mobile/test/e2e/phase_34_budgets_e2e_test.dart` — budget rows from mocked Dio breakdown; tolerant parsing of absent `budget` key → **34-05 T2** (network half added by 34-05 T3)
- Framework install: none — all harnesses configured and in use.

---

## Sampling Continuity Check

| Plan | Tasks | Tasks with an `<automated>` verify |
|------|-------|-----------------------------------|
| 34-01 | 3 | 3 |
| 34-02 | 3 | 3 |
| 34-03 | 3 | 3 |
| 34-04 | 3 | 3 |
| 34-05 | 3 | 3 |
| 34-06 | 3 | 3 |
| 34-07 | 3 | 3 |
| 34-08 | 3 | 3 |

No task ships without an automated command; no `MISSING` references remain.

---

## Manual-Only Verifications

None — FCM mocked at messaging layer; visual polish deferred to UI-SPEC checker/UAT.

---

## Validation Sign-Off

- [x] All tasks have `<automated>` verify or Wave 0 dependencies
- [x] Sampling continuity: no 3 consecutive tasks without automated verify
- [x] Wave 0 covers all MISSING references
- [x] No watch-mode flags
- [x] Feedback latency < 30s
- [x] `nyquist_compliant: true` set in frontmatter
- [x] Per-task map completed with assigned task IDs (2026-07-28)

**Approval:** pending
