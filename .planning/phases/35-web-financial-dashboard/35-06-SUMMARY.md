---
phase: 35-web-financial-dashboard
plan: 06
subsystem: api
tags: [fastapi, sqlalchemy, pydantic, finance, budgets, rls, marg-04]

# Dependency graph
requires:
  - phase: 35-web-financial-dashboard (35-05)
    provides: PortfolioRepository/PortfolioService, the public finance query builders, the row.project_id label rule
  - phase: 34-budgeting-and-alerts
    provides: BudgetRepository.scope_spends, _to_budget_vs_actual, BudgetVsActual
  - phase: 33-margin-visibility
    provides: MarginSummary and FinanceService.rollup_for_project's margin block
  - phase: 32-labor-rates-and-cost-rollup
    provides: _build_breakdown labor folding, LaborTotals
provides:
  - "GET /api/v1/projects/{project_id}/financials — window-independent drill-down aggregate (MARG-04)"
  - "ProjectFinancialsResponse + ProjectScopeBudgetRow wire schemas (aggregates only, never entries[])"
  - "PortfolioService.project_financials — shipped rollup for the project half, 3 queries for the scope half"
  - "PortfolioRepository.project_header / trade_scopes_for_project — column-only live-row lookups"
  - "to_labor_cost_summary — the single LaborTotals -> LaborCostSummary mapper"
affects: [35-07 margin trend endpoint, 35-08 finance gating tests, 35-10 web drill-down page]

# Tech tracking
tech-stack:
  added: []
  patterns:
    - "Drill-down composes the shipped rollup rather than restating spend/margin/budget definitions"
    - "Batched grouped scope_spends pinned to the per-scope definition by a named equivalence test"
    - "active_entity_or_404 on a column-only header row gives one 404 for missing, soft-deleted and cross-tenant ids"

key-files:
  created: []
  modified:
    - backend/app/features/finance/schemas.py
    - backend/app/features/finance/portfolio_repository.py
    - backend/app/features/finance/portfolio_service.py
    - backend/app/features/finance/router.py
    - backend/tests/test_phase_35_e2e.py

key-decisions:
  - "Drill-down reuses FinanceService.rollup_for_project verbatim for the project half — no second definition of spend, margin or the project budget"
  - "Scope half costs exactly three queries (scopes, active budgets, one grouped scope_spends); the per-scope trade_scope_spend call survives only inside the test as the reference"
  - "The header lookup runs BEFORE the rollup, so a cross-tenant or soft-deleted id 404s without paying for an aggregate"
  - "to_labor_cost_summary extracted so the shipped project rollup route and the drill-down cannot drift on the D-06 basis field"

patterns-established:
  - "Aggregate-only drill-down: the response carries no entries[] at any depth, asserted recursively"
  - "Every live trade scope gets a row even at spend 0.00 with budget null — a scope never disappears for having no money"

requirements-completed: [MARG-04]

# Metrics
duration: 11 min
completed: 2026-07-29
---

# Phase 35 Plan 06: Project Drill-Down Financials Summary

**`GET /api/v1/projects/{id}/financials` returns the window-independent drill-down aggregate — the shipped rollup's category mix, folded labor, margin and project budget plus per-trade-scope budget-vs-actual from one grouped spend query, with no itemized rows.**

## Performance

- **Duration:** 11 min
- **Started:** 2026-07-29T03:44:08Z
- **Completed:** 2026-07-29T03:55:25Z
- **Tasks:** 3
- **Files modified:** 5

## Accomplishments

- `ProjectFinancialsResponse` embeds `CostBreakdownResponse` verbatim, so the web's existing `mapCostBreakdown` parses the drill-down unchanged and the D-06 `basis` field rides along untouched.
- `PortfolioService.project_financials` composes the shipped `rollup_for_project` for the project half and spends exactly three queries on the scope half — scopes, active budgets, and ONE grouped `BudgetRepository.scope_spends`. No `await` sits inside any loop.
- Per-scope `spent` is pinned by test to the shipped `FinanceService.trade_scope_spend`, including a soft-deleted entry both definitions must exclude — the Pitfall 6 drift guard.
- Cross-tenant and soft-deleted project ids both 404 with `"Project not found"`, decided by a column-only header lookup that runs before any aggregate work.
- An empty scope still gets a row (`spent` `"0.00"`, `budget` `null`): a trade scope never vanishes from the drill-down for having no money.

## Task Commits

1. **Task 1: ProjectFinancialsResponse schema and the scope-budget query** - `e22570b` (feat)
2. **Task 2: PortfolioService.project_financials and the gated route** - `c48ece3` (feat)
3. **Task 3: Drill-down tests — scope spend equivalence, no entries, 404 paths** - `230768c` (test)

## Files Created/Modified

- `backend/app/features/finance/schemas.py` — `ProjectScopeBudgetRow`, `ProjectFinancialsResponse`, and the extracted `to_labor_cost_summary` mapper
- `backend/app/features/finance/portfolio_repository.py` — `project_header` and `trade_scopes_for_project`, both column-only with their own `deleted_at IS NULL` predicate
- `backend/app/features/finance/portfolio_service.py` — `project_financials` plus the pure `_rollup_breakdown` / `_budgets_by_scope` / `_scope_budget_row(s)` helpers
- `backend/app/features/finance/router.py` — `GET /projects/{project_id}/financials` gated on `finance.view`; the project rollup handler now shares the labor mapper
- `backend/tests/test_phase_35_e2e.py` — drill-down seeder plus the three named tests

## Decisions Made

- **Reuse over restatement.** The project half of the response is `rollup_for_project`'s output mapped straight onto the wire. Restating the labor folding, the D-12 anchor flag or the budget block is exactly the drift the 35-05 equivalence test already guards against, so the drill-down inherits that guarantee instead of needing its own.
- **Header first, aggregate second.** `active_entity_or_404(await project_header(...))` runs before the rollup. RLS makes another tenant's row invisible, soft-delete is filtered in the query, and a forged uuid is simply absent — one code path, one 404 message, and no wasted aggregate for an id that will 404 anyway.
- **`to_labor_cost_summary` extracted.** The `LaborTotals -> LaborCostSummary` mapping already existed inline in the project rollup route; a second copy in the drill-down would have been two places to forget the `basis` field. One mapper, both call sites (CLAUDE.md DRY).
- **The N+1 lives only in the test.** `trade_scope_spend` is called once per scope inside `_shipped_scope_spends` — deliberately the access pattern the endpoint replaces, kept as the reference the batched query is compared against.

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 2 - Missing Critical] Extracted `to_labor_cost_summary` instead of duplicating the labor mapping**
- **Found during:** Task 2 (PortfolioService.project_financials and the gated route)
- **Issue:** The plan's flow builds `CostBreakdownResponse` from `rollup.labor`, but `rollup.labor` is a `LaborTotals` dataclass, not the `LaborCostSummary` wire schema. The only existing conversion was inline in `router.get_project_cost_rollup`. Copying it would have created a second place where the D-06 `basis` field could be forgotten or diverge — a DRY violation CLAUDE.md lists as a hard constraint.
- **Fix:** Added `to_labor_cost_summary(labor: LaborTotals) -> LaborCostSummary` beside the existing `to_margin_summary` in `schemas.py` and routed both the shipped project-rollup handler and the new drill-down through it. Behaviour is byte-identical (both relied on the schema default for `basis`).
- **Files modified:** `backend/app/features/finance/schemas.py`, `backend/app/features/finance/router.py`, `backend/app/features/finance/portfolio_service.py`
- **Verification:** `pytest tests/test_phase_34_e2e.py` (67 passed) and `tests/test_phase_33_e2e.py` + `tests/unit` (166 passed) — every suite that asserts the shipped rollup's labor block is green.
- **Committed in:** `c48ece3` (Task 2 commit)

**2. [Rule 1 - Bug] Reworded a docstring so the plan's own acceptance grep can pass**
- **Found during:** Task 2 (PortfolioService.project_financials and the gated route)
- **Issue:** The plan's action text mandates a docstring containing the phrase "never a loop of trade_scope_spend", while its acceptance criterion requires `grep -n "trade_scope_spend" portfolio_service.py` to return **no** matches. The two instructions contradict each other; the criterion's intent is plainly "no call site".
- **Fix:** Kept the WHY intact but phrased it as "never a per-scope spend call in a loop", so the file contains zero occurrences of the identifier and the criterion's intent (no N+1 call) is provable by the grep it specifies.
- **Files modified:** `backend/app/features/finance/portfolio_service.py`
- **Verification:** `grep -c trade_scope_spend app/features/finance/portfolio_service.py` → 0; docstring still names the batched alternative and the pitfall.
- **Committed in:** `c48ece3` (Task 2 commit)

---

**Total deviations:** 2 auto-fixed (1 missing critical, 1 bug)
**Impact on plan:** Both were mechanical corrections to plan text that could not be followed literally. No scope creep; every must_have and acceptance criterion is satisfied.

## Issues Encountered

None. All three named tests passed on first run; no regressions in phase 33, 34 or unit suites.

## User Setup Required

None - no external service configuration required.

## Next Phase Readiness

- Ready for **35-07** (margin trend endpoint). The drill-down deliberately owns the window-independent figures (D-10), so the trend endpoint can append `issued_at` / `approved_on` columns to the shared query builders without any risk of restating the headline numbers.
- `_seed_drill_down_project` and `_project_financials` in `test_phase_35_e2e.py` are reusable by 35-07 and the 35-08 gating tests; 35-08 still needs to add `test_financial_endpoints_forbidden_without_finance_view` covering this endpoint's 403 branch.
- Web plan 35-10 can consume the endpoint as specified: `breakdown` is a byte-compatible `CostBreakdownResponse`, and `scopes[].spent` legitimately excludes labor (D-08), so the UI must render the "Scope spend excludes labor" caption.

---
*Phase: 35-web-financial-dashboard*
*Completed: 2026-07-29*

## Self-Check: PASSED

All 5 modified files and the SUMMARY exist on disk; all 3 task commits (`e22570b`, `c48ece3`, `230768c`) are present in git history.
