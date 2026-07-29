---
phase: 35-web-financial-dashboard
plan: 05
subsystem: api
tags: [fastapi, sqlalchemy, postgres, finance, aggregation, n+1, rls]

# Dependency graph
requires:
  - phase: 35-01
    provides: portfolio_math (tier ladder, portfolio totals) + margin_math anchor_revenues/combined_anchor_revenue/quoted_revenue
  - phase: 35-02
    provides: test_phase_35_e2e.py harness (_seed_company_portfolio, _count_sql_statements, dated revenue seeders)
  - phase: 34
    provides: BudgetRepository.list_active/scope_spends, budget_math thresholds, _to_budget_vs_actual
  - phase: 33
    provides: FinanceService.rollup_for_project margin block, RevenueRepository traversal
provides:
  - "GET /api/v1/financials/company — company overview's only data source, gated on finance.view"
  - "PortfolioRepository — 7 grouped, column-only, company-wide aggregates keyed by COALESCE(TradeScope.project_id, Job.project_id)"
  - "PortfolioService — batched per-project cost/margin/budget assembly with every await outside any loop"
  - "CompanyFinancialsResponse / PortfolioTotals / ProjectFinancialsRow / AttentionRow wire schemas"
  - "Public finance query builders (costable_sessions_query, invoice_amounts_query, approved_quote_amounts_query, to_anchored_amounts, to_work_sessions)"
affects: [35-06, 35-07, 35-08, 35-09, 35-11, 36-ai-profitability]

# Tech tracking
tech-stack:
  added: []
  patterns:
    - "Batched company-wide aggregate path pinned to the shipped per-project path by a named equivalence test (Phase 34 scope_spends precedent)"
    - "Project key read from result rows BY LABEL (row.project_id), never positionally, so later plans may append columns to the shared builders"
    - "Service holds every database await in one _fetch_portfolio_inputs; per-project assembly functions are pure"

key-files:
  created:
    - backend/app/features/finance/portfolio_repository.py
    - backend/app/features/finance/portfolio_service.py
  modified:
    - backend/app/features/finance/repository.py
    - backend/app/features/finance/schemas.py
    - backend/app/features/finance/router.py
    - backend/tests/test_phase_35_e2e.py

key-decisions:
  - "Five module-level finance query builders/mappers made public rather than duplicated in portfolio_repository — one definition of the traversal predicates"
  - "PROJECT_KEY split into a raw COALESCE expression (WHERE/GROUP BY) and a labelled column (SELECT) so PostgreSQL groups on the full expression, never on an output alias"
  - "PortfolioService reuses service.py's _build_breakdown / _labor_by_job / _any_anchor_missing_cost_data / ProjectMarginContext directly instead of restating the folding and D-12 rules"
  - "D-11 live-threshold test asserts BOTH directions (over-budget-but-never-alerted must be listed; stale claim after a soft-delete must not) because the plan's raise-below-spend route is unreachable under 34-06's inline PATCH evaluation"

patterns-established:
  - "Pattern: batched read path + named equivalence pin — the batched method's docstring names the test that holds it to the shipped path"
  - "Pattern: label-based row access as an explicit forward-compatibility contract for shared query builders"

requirements-completed: [MARG-04]

# Metrics
duration: 79min
completed: 2026-07-29
---

# Phase 35 Plan 05: Batched Company Financial Rollup Summary

**`GET /api/v1/financials/company` serving portfolio totals, every project's cost/margin/budget block and the ordered attention list from 7 grouped column-only queries that do not grow with project count — pinned figure-for-figure to `FinanceService.rollup_for_project`.**

## Performance

- **Duration:** 79 min (≈27 min of it backend suite runtime)
- **Started:** 2026-07-29T02:22:00Z
- **Completed:** 2026-07-29T03:41:14Z
- **Tasks:** 3
- **Files modified:** 6 (2 created, 4 modified)

## Accomplishments

- **PortfolioRepository** — company-wide aggregates in a fixed query count: projects, per-(project, anchor, category) cost sums, project-tagged work sessions, invoice and approved-quote amounts by project, D-14 project-level quotes, and trade-scope labels. Every keyed query carries `COALESCE(TradeScope.project_id, Job.project_id)` in both `SELECT` and `GROUP BY` (Pitfall 7), and every one states its soft-delete predicate at its own call site (Pitfall 8).
- **PortfolioService** — all database awaits live in `_fetch_portfolio_inputs`; the per-project assembly (`_margin_context`, `_project_revenue`, `_anchored_budgets`, `_project_figures`) is pure and reads only already-fetched rows. Tiers, ordering and totals come from `portfolio_math`; the service performs no threshold or margin arithmetic of its own.
- **Equivalence pin** — `test_company_rollup_matches_rollup_for_project` seeds one project holding every known drift trap (soft-deleted entry, legacy `labor`-category entry, unrated session, rated session, quoted-only scope, invoiced job) and asserts cost, all six margin fields and all four budget fields are exactly equal to the shipped rollup's, compared as `Decimal`.
- **No regression** — 120 Phase 31/32/33/34 tests pass unchanged after the five query-builder renames; 78 Phase 34+35 tests pass with the new endpoint mounted.

## Task Commits

1. **Task 1: PortfolioRepository — batched company-wide aggregates** — `96245cf` (feat)
2. **Task 2: PortfolioService, response schemas and the gated route** — `44d229f` (feat)
3. **Task 3: Six named backend tests for the company rollup** — `8ec755f` (test)

## Files Created/Modified

- `backend/app/features/finance/portfolio_repository.py` — batched company-wide aggregates; module docstring states the COALESCE key rule, the by-label row-access contract protecting plan 35-07's date columns, and the Pitfall-8 soft-delete rule.
- `backend/app/features/finance/portfolio_service.py` — company rollup orchestration; `PortfolioInputs` / `BudgetInputs` / `ProjectRevenue` frozen DTOs, pure per-project assembly, wire mapping.
- `backend/app/features/finance/repository.py` — five module-level helpers made public (`costable_sessions_query`, `to_work_sessions`, `invoice_amounts_query`, `approved_quote_amounts_query`, `to_anchored_amounts`); module docstring explains why they are public. `to_anchored_amounts`'s `row[:6]` contract untouched.
- `backend/app/features/finance/schemas.py` — additive `PortfolioTotals`, `ProjectFinancialsRow`, `AttentionRow`, `CompanyFinancialsResponse` (plain `BaseModel`, matching the shipped aggregate-block convention).
- `backend/app/features/finance/router.py` — one thin `GET /financials/company` handler with the inline `finance.view` gate.
- `backend/tests/test_phase_35_e2e.py` — six named tests plus their helpers (`_company_financials`, `_project_row`, `_attention_rows_for`, `_tier_percents`, `_delete_cost_entry`, `_delete_budget`, `_delete_project`, `_seed_legacy_labor_cost_entry`, `_overrun_fired_at`, `_seed_drift_trap_project`). The Wave-1 harness was extended, never rewritten.

## Decisions Made

- **Public query builders over duplication.** `portfolio_repository` composes `repository.py`'s builders rather than restating the traversal predicates, so the batched and per-project paths cannot define soft-delete or status filters differently.
- **`PROJECT_KEY` (raw COALESCE) vs `PROJECT_KEY_COLUMN` (labelled).** `WHERE` and `GROUP BY` use the raw expression so PostgreSQL groups on the full COALESCE and never on an output alias; `SELECT` uses the label so callers read `row.project_id`. Verified by compiling all five statements against the PostgreSQL dialect.
- **Reuse of `service.py`'s per-project assembly internals.** `_build_breakdown`, `_labor_by_job`, `_any_anchor_missing_cost_data` and `ProjectMarginContext` are imported directly (the plan's `<interfaces>` block lists them as pieces to compose). Restating the legacy-labor folding or the D-12 anchor flag would be exactly the Pitfall-1 drift the equivalence test exists to catch.
- **Scope budgets whose scope is gone are dropped.** A scope budget with no live `trade_scope_labels` entry has no name; labelling it wrongly would mislabel an attention row.
- **Deterministic scope-budget ordering.** Scope budgets are sorted by trade name so `worst_crossed_budget`'s `max()` is stable on exact percent ties.

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 1 - Bug] The plan's D-11 test construction is unreachable under shipped 34-06 behavior**

- **Found during:** Task 3 (`test_attention_tiers_use_live_threshold_state`)
- **Issue:** The plan specified: fire an overrun alert, then `PATCH /budgets/{id}` raising the total to a value still below spend, then assert `overrun_fired_at IS NULL` while the project remains in the overrun tier. That state is not reachable: `BudgetService.update_budget` calls `set_total` (which nulls both fired timestamps on a raise) and then **evaluates inline in the same request** (34-06, D-10). If the new total is still below spend, the evaluation immediately re-claims the overrun crossing, so `overrun_fired_at` is non-NULL when the request returns. The literal assertion would always fail. (Confirmed against the shipped `test_mutation_budget_edit_raise_rearms_without_firing`, which only leaves both columns NULL when the raise clears the thresholds.)
- **Fix:** Asserted the same D-11 invariant via two constructions that are reachable and that *both* fail under a fired-column implementation:
  - `live_over`: cost entries first, budget created afterwards (`POST /budgets/` performs no evaluation) → 140% over with `overrun_fired_at IS NULL` → **must** appear in the overrun tier.
  - `stale_claim`: budget first, a crossing entry fires the overrun, then the entry is soft-deleted → spend back under budget with `overrun_fired_at IS NOT NULL` → **must not** appear in attention.
- **Files modified:** `backend/tests/test_phase_35_e2e.py`
- **Verification:** `pytest tests/test_phase_35_e2e.py -k "attention" -q` → passes; the test docstring records why the plan's route was replaced.
- **Committed in:** `8ec755f`

---

**Total deviations:** 1 auto-fixed (1 bug — an unreachable test precondition in the plan).
**Impact on plan:** None on scope or shape. The replacement asserts strictly more than the original (both directions of the D-11 invariant instead of one). No scope creep.

## Issues Encountered

- The Phase 31–34 regression run takes ~22 minutes serially; it was launched early and the remaining tasks were written while it ran. All 120 tests passed, confirming the five renames are behaviour-neutral.
- No test-DB deadlocks occurred — this wave ran a single backend agent, as the Wave-1 STATE.md note anticipated.

## Verification Evidence

| Check | Result |
|---|---|
| `pytest tests/test_phase_31/32/33/34_e2e.py -q` | 120 passed (renames are behaviour-neutral) |
| `pytest tests/test_phase_34_e2e.py tests/test_phase_35_e2e.py -q` | 78 passed |
| `pytest tests/test_phase_35_e2e.py -k "company_rollup or portfolio or attention" -q` | 8 passed, 3 deselected (6 new + 2 harness) |
| `ruff check . && ruff format --check .` | clean, 308 files |
| Route mounted | `['/api/v1/financials/company']` |
| `grep -c PROJECT_KEY portfolio_repository.py` | 10 (≥ 8 required) |
| `grep -c "deleted_at.is_(None)" portfolio_repository.py` | 6 (≥ 5 required) |
| Old private builder names in `repository.py` | none |
| Positional `row[N]` reads in `portfolio_repository.py` | none |
| `row[:6]` contract in `repository.py` | still present |
| Awaits in `portfolio_service.py` | all in `company_financials` / `_fetch_portfolio_inputs`; none in a loop body |
| Threshold arithmetic in `portfolio_service.py` | none (`fired_at` / `>= 80` / `crossed_thresholds` absent) |
| `require_permission("finance.view")` in `router.py` | 8 (was 7) |

**One acceptance-criterion nuance:** `grep -n "rollup_for_project" portfolio_service.py` returns 2 matches, both in the module docstring — the sentence stating the shipped per-project path *is never called from here* and the name of the test that pins the two together. There is no call site.

## Known Stubs

None — every field of `CompanyFinancialsResponse` is wired to live data and asserted by a test.

## User Setup Required

None — no external service configuration required.

## Next Phase Readiness

- `GET /financials/company` is mounted, gated and pinned; plan 35-08's query-count invariant and latency budget can now measure it with the Wave-1 `_count_sql_statements` harness.
- Plan 35-06's drill-down can reuse `PortfolioRepository.trade_scope_labels` and the `_to_budget_vs_actual` composition pattern.
- Plan 35-07 must keep the by-label row-access contract when it appends `issued_at` / `approved_on` at indices 6/7 of the shared builders; `to_anchored_amounts`'s `row[:6]` slice and `PortfolioRepository`'s `row.project_id` reads are both already safe under that change.
- Plan 35-04's web types must match the shipped wire contract exactly: `portfolio{cost, quoted_revenue|null, incomplete_project_count, margin}`, `projects[]{project_id, name, status, cost, margin, budget|null}`, `attention[]{project_id, project_name, project_status, tier, anchor_label, spent|null, budget_total|null, percent_used|null}`.

---
*Phase: 35-web-financial-dashboard*
*Completed: 2026-07-29*

## Self-Check: PASSED

All created files exist on disk; all three task commits are present in `git log`.
