---
phase: 34-budgeting-and-overrun-alerts
verified: 2026-07-28T00:00:00Z
status: passed
score: 47/47 must-haves verified
requirements_status:
  BUDG-01: satisfied
  BUDG-02: satisfied
  BUDG-03: satisfied
  BUDG-04: satisfied
---

# Phase 34: Budgeting and Overrun Alerts Verification Report

**Phase Goal:** Owner/PM can set spending ceilings per project and trade scope and get warned before they're blown, with quote changes automatically kept in sync
**Verified:** 2026-07-28
**Status:** passed
**Re-verification:** No — initial verification

## Goal Achievement

### Observable Truths (aggregated across the 8 plans' must_haves)

All 47 truths across plans 34-01..34-08 verified. Highlights per success criterion:

| # | Success Criterion / Truth | Status | Evidence |
|---|---------------------------|--------|----------|
| 1 | Owner/PM sets a budget per project and independently per trade scope | ✓ VERIFIED | `POST/PATCH/DELETE /budgets` in `backend/app/features/finance/router.py:250-283`, each explicitly gated `require_permission("finance.manage")`; XOR anchor + 409 duplicate enforced in `BudgetService.create_budget` / `_reject_duplicate_anchor`; e2e `test_budget_crud_project_and_scope_budgets_coexist`, `..._duplicate_project_anchor_conflicts`, `..._duplicate_scope_anchor_conflicts` all pass |
| 2 | Budgeted vs spent vs remaining at project AND trade-scope level | ✓ VERIFIED | `budget_vs_actual_for_project/_trade_scope` in `budget_service.py:182-206` assemble `BudgetVsActual` (total/spent/remaining/percent_used); web `BudgetSummarySection.tsx` + mobile `budget_summary_section.dart` render the triad; job breakdown never carries budget (`test_budget_vs_actual_job_breakdown_never_carries_budget`) |
| 3 | 80%/100% alerts (dashboard + FCM), finance-permitted users only | ✓ VERIFIED | `evaluate_budget` + atomic `claim_threshold` (`UPDATE ... WHERE fired_at IS NULL RETURNING id`, `budget_repository.py:34-45,123-136`); `FINANCIAL_ALERT_TYPES = frozenset({budget_warning, budget_overrun})` (`alert_types.py:15-17`); dashboard filter drops financial alerts without finance.view (`dashboard/service.py:741-755`, router passes `has_finance_view="finance.view" in granted` at `dashboard/router.py:98`); FCM targets resolved via live RBAC `user_ids_with_permission` (`rbac/repository.py:68-85`) in the request session before scheduling |
| 4 | Approving a quote revision auto-adjusts the linked budget by the delta | ✓ VERIFIED | `approve_quote` calls `BudgetService.apply_quote_delta` in the same transaction (`quotes/service.py:316-317`); signed pre-tax delta via `previous_approved_in_chain` baseline + `adjusted_budget_total` clamp at `MINIMUM_BUDGET_TOTAL`; downward-below-spend fires overrun on the same request (`test_quote_delta_downward_revision_below_spend_fires_overrun`); failure rolls back the approval (`test_quote_delta_failure_rolls_back_the_approval`) |

**Score:** 47/47 truths verified

### Required Artifacts (gsd-tools verify artifacts, all 8 plans)

| Plan | Artifacts | Result |
|------|-----------|--------|
| 34-01 | migration 0035, alert_types.py, budget_math.py, unit test | 4/4 passed |
| 34-02 | budget_repository.py, budget_service.py, schemas.py, e2e test | 4/4 passed |
| 34-03 | budget_service.py, budget_repository.py, rbac/repository.py, notifications/service.py | 4/4 passed |
| 34-04 | BudgetSummarySection.tsx, types.ts, budget-section.test.tsx | 3/3 passed |
| 34-05 | cost_breakdown.dart, budget_summary_section.dart, phase_34_budgets_e2e_test.dart | 3/3 passed |
| 34-06 | budget_service.py (sweep_budgets), scheduler.py (BUDGET_SWEEP_HOUR_UTC) | 2/2 passed |
| 34-07 | SetBudgetDialog.tsx (313 lines), phase-34-budgets.spec.ts (331 lines) | 2/2 passed |
| 34-08 | quotes/service.py, quotes/repository.py, budget_service.py (apply_quote_delta) | 3/3 passed |

All substantive — no stubs, no placeholders, no TODO/FIXME in any phase file.

### Key Link Verification

| From | To | Status | Detail |
|------|----|--------|--------|
| dashboard/service.py | alert_types.py | ✓ WIRED | Module re-export; tests monkeypatch the module global |
| finance/models.py | budgets threshold columns | ✓ WIRED | `warning_fired_at` / `overrun_fired_at` mapped |
| budget_service.py | FinanceService spend | ✓ WIRED | `FinanceService(self.db)` at budget_service.py:214 (`_finance_service`) — gsd-tools reported FAIL due to regex escaping in the plan pattern; manually confirmed present and used by both `budget_vs_actual_for_*` and `_spend_for` |
| finance/router.py | BudgetService (finance.manage gates) | ✓ WIRED | All three budget endpoints |
| finance/service.py | BudgetVsActual (`budget=` block) | ✓ WIRED | Additive block on breakdown/rollup |
| budget_service.py | dashboard_alerts / budget_math / notifications | ✓ WIRED | 3/3 |
| web api.ts | backend budget block (`percent_used` mapper) | ✓ WIRED | snake→camel mapper |
| web CostBreakdownSummary → BudgetSummarySection | ✓ WIRED | Rendered between Total and Margin |
| mobile cost_breakdown_summary → BudgetSummarySection | ✓ WIRED | Same placement |
| mobile cost_breakdown.dart tolerant parser | ✓ WIRED | `percent_used`, absent-key tolerant |
| finance/service.py cost mutations → evaluate_for_* | ✓ WIRED | Post-flush hooks |
| scheduler.py → sweep_budgets | ✓ WIRED | CronTrigger(hour=5) via `_run_for_all_companies` |
| web hooks.ts → budget endpoints | ✓ WIRED | invalidateAllCostEntries |
| TradeScopeDetail / AlertPanel wiring | ✓ WIRED | SetBudgetDialog + "Alerts" header |
| quotes/service.py → apply_quote_delta | ✓ WIRED | In approve_quote, same transaction |
| budget_service.py → margin_math (quoted_revenue/DocumentAmounts) | ✓ WIRED | `_pre_tax_total_of` |

31/32 tool-verified; the single tool FAIL was a false negative (regex escaping), manually confirmed WIRED.

### Data-Flow Trace (Level 4)

| Artifact | Data Variable | Source | Real Data | Status |
|----------|---------------|--------|-----------|--------|
| BudgetSummarySection.tsx (web) | `budget.percentUsed` / spent / remaining | Backend `percent_used` via api.ts mapper — client never divides (`formatPercentUsed` only strips trailing `.0`) | Yes | ✓ FLOWING |
| budget_summary_section.dart (mobile) | BudgetVsActual from `tryFromJson` | Network breakdown/rollup responses; no Drift persistence | Yes | ✓ FLOWING |
| Budget block on breakdown/rollup | `spent` | Single spend definition (`FinanceService.project_spend` / `trade_scope_spend`); `spent == grand_total` pinned by `test_budget_vs_actual_scope_breakdown_spent_equals_grand_total` | Yes | ✓ FLOWING |
| Dashboard alert rows | `impact_text` | Locked copy templates in `budget_math.budget_alert_text`, verbatim-asserted in e2e | Yes | ✓ FLOWING |

### Behavioral Spot-Checks (test suites executed during this verification)

| Behavior | Command | Result | Status |
|----------|---------|--------|--------|
| Full phase backend e2e (CRUD, vs-actual, alerts, mutation hooks, sweep, quote delta) | `backend: .venv/bin/pytest tests/test_phase_34_e2e.py -q` | 67 passed in 86s | ✓ PASS |
| Threshold/percent/copy math + delta clamp | `pytest tests/unit/test_budget_evaluation.py tests/unit/test_finance_scrub.py -q` | 31 passed | ✓ PASS |
| Phase 30 leak-boundary regression (real budget types) | `pytest tests/test_phase_30_e2e.py -q` | 9 passed | ✓ PASS |
| Web unit suites (budget-section, set-budget-dialog among 28 suites) | `web: npm test -- --watchAll=false` | 268 passed / 28 suites | ✓ PASS |
| Mobile e2e + tolerant parse | `flutter test test/e2e/phase_34_budgets_e2e_test.dart test/features/finance/budget_summary_parse_test.dart` | 25 passed | ✓ PASS |
| Migration 0035 applied | Docker DB `SELECT version_num FROM alembic_version` | `0035_budget_alerts_quote_chain`; `warning_fired_at`/`overrun_fired_at`/`revised_from_quote_id` columns present; test DB migrated via conftest `alembic upgrade head` | ✓ PASS |
| Playwright phase spec | `web/tests/phase-34-budgets.spec.ts` (331 lines) | Executor-verified green per orchestrator; not re-run here (requires running stack) | ✓ PASS (executor-attested) |

### Deep-Claim Verification (orchestrator-flagged items)

| Claim | Status | Evidence |
|-------|--------|----------|
| Exactly-once under two-session race | ✓ VERIFIED | `test_alerts_concurrent_evaluations_fire_exactly_once` (e2e:877) runs two `_evaluate_in_own_session` calls via `asyncio.gather`, each in its own `async_session_factory()` session with its own commit; asserts `sum(results) == 1` and exactly one alert row. Mechanism: raw-SQL conditional UPDATE ... RETURNING claim (`budget_repository.py:34-45`) |
| FINANCIAL_ALERT_TYPES + permission filter | ✓ VERIFIED | `alert_types.py:15-17`; filter at `dashboard/service.py:753-755`; pin `test_finance_scrub.py:51` asserts the exact two-member frozenset; `test_phase_30_e2e.py` uses real `budget_warning` type |
| FCM targeting via live RBAC | ✓ VERIFIED | `_recipients_for` resolves `user_ids_with_permission(company_id, "finance.view")` in the current session before scheduling; e2e `test_alerts_push_targets_finance_view_holders_only` and `..._respects_live_matrix_revocation` pass |
| Two quote bug fixes + regressions | ✓ VERIFIED | (1) Anchors survive revision: `trade_scope_id`/`project_id` copied in `revise_quote` (quotes/service.py:453-457, commented as pre-existing-bug fix) — regressions `test_quote_delta_revision_keeps_{trade_scope,project,job}_anchor`; (2) approved quotes revisable (status set includes "approved", line 434) — `test_quote_delta_approved_quote_can_be_revised`, margin hand-off `test_quote_delta_margin_revenue_hands_off_to_new_approval` |
| Signed delta incl. downward + clamp | ✓ VERIFIED | `apply_quote_delta` applies signed delta; `adjusted_budget_total` clamps at `MINIMUM_BUDGET_TOTAL = 0.01`; unit tests at test_budget_evaluation.py:201-210 (up, down, zeroing clamp, negative-going clamp); e2e up/down/overrun-fire tests pass |
| scope_spends equivalence pin | ✓ VERIFIED | `test_sweep_scope_spends_equivalence_matches_trade_scope_spend` (e2e:1496) pins the batched sweep query to `FinanceService.trade_scope_spend` |
| Migration 0035 applied | ✓ VERIFIED | Docker DB at head `0035_budget_alerts_quote_chain`; new columns confirmed via information_schema |
| Phase 30 D-06 boundary intact | ✓ VERIFIED | Budget block only on finance.view-gated breakdown/rollup (403 tests pass); no `budget` fields in projects/dashboard/jobs schemas (pre-existing job-request `budget_min/max` is an unrelated Phase-8 field); job breakdown never carries budget |
| Mobile has no budget persistence | ✓ VERIFIED | No Phase-34 budget table/column in `mobile/lib/core/database/`; `BudgetVsActual` parsed from network responses only; no budget editing UI on mobile |

### Requirements Coverage

| Requirement | Source Plans | Description | Status | Evidence |
|-------------|-------------|-------------|--------|----------|
| BUDG-01 | 34-02, 34-07 | Set budget per project and per trade scope | ✓ SATISFIED | Gated CRUD endpoints + web dialog/affordances + 13 budget_crud e2e tests green |
| BUDG-02 | 34-02, 34-04, 34-05, 34-07 | View budgeted vs spent vs remaining at both levels | ✓ SATISFIED | Budget block on breakdown/rollup; web + mobile triad rendering; spent==grand_total pin |
| BUDG-03 | 34-01, 34-03, 34-06 | 80%/100% alerts via dashboard + FCM, finance-only | ✓ SATISFIED | Exactly-once claims, locked copy, permission filter, RBAC push targeting, mutation hooks, 05:00 UTC idempotent sweep |
| BUDG-04 | 34-01, 34-08 | Quote revision approval adjusts linked budget by delta | ✓ SATISFIED | Same-transaction hook, chain baseline, signed pre-tax delta, clamp, rollback safety |

No orphaned requirements: REQUIREMENTS.md maps exactly BUDG-01..04 to Phase 34, all claimed by plans.

### Anti-Patterns Found

None. Zero TODO/FIXME/placeholder/stub patterns across all phase 34 backend, web and mobile files. Code follows CLAUDE.md OOP architecture (TenantScopedService/Repository), named constants throughout (e.g. `MINIMUM_BUDGET_TOTAL`, `BUDGET_SWEEP_HOUR_UTC`, `WARNING_THRESHOLD_RATIO`), small single-purpose methods.

### Human Verification Required

None blocking. Per 34-VALIDATION.md, FCM is mocked at the messaging layer (project precedent) and visual chip/color polish is deferred to the UI-SPEC/UAT pass:

1. **Real-device FCM push delivery** — approve a threshold crossing with a real Firebase project configured; expected: finance.view holders receive the push with byte-identical body. Why human: requires live Firebase credentials + physical device.
2. **Visual polish of budget rows/chips** — amber "Nearing budget" chip and red negative Remaining match the UI-SPEC aesthetics. Why human: color/aesthetic judgment (presence/absence already asserted in widget/jest tests).

### Gaps Summary

No gaps. All 47 plan must-have truths verified against code, all 25 artifacts substantive and wired, all key links connected (one tool false-negative manually confirmed), all four requirements satisfied, and every automated suite executed green during this verification (backend 67+31+9, web 268, mobile 25).

---

_Verified: 2026-07-28_
_Verifier: Claude (gsd-verifier)_
