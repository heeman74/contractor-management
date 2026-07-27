---
phase: 32-labor-rates-and-cost-rollup
plan: 02
subsystem: finance
tags: [fastapi, sqlalchemy, decimal, labor-derivation, cost-breakdown, rls]

# Dependency graph
requires:
  - phase: 32-labor-rates-and-cost-rollup (plan 32-01)
    provides: labor_derivation pure module (WorkSession/LaborTotals/summarize_labor), LaborRateRepository.list_rates_for_users, _group_rates_by_user, /labor-rates endpoints
  - phase: 31-actual-cost-capture
    provides: CostEntry/CostCategory models, FinanceRepository/FinanceService/router, project rollup endpoint
provides:
  - CategoryTotal / LaborCostSummary / CostBreakdownResponse schemas (Decimal-as-string wire format)
  - ProjectCostRollupResponse extended additively with categories/labor/grand_total (total/entries untouched)
  - Column-only costable work-session queries (job + project) with shared D-03 predicates
  - One shared GROUP BY category-total repository helper for job and trade-scope anchors
  - Two-round-trip labor derivation in FinanceService (_derive_labor + summarize_labor)
  - GET /jobs/{id}/cost-breakdown and GET /trade-scopes/{id}/cost-breakdown gated finance.view
  - Reserved labor-category 422 guard on cost-entry create/update; legacy rows fold into the labor row
affects: [32-04, 32-05, 33-margin, 34-budgeting, 36-ai-profitability]

# Tech tracking
tech-stack:
  added: []
  patterns:
    - "Two bounded round trips for derivation: session columns query + rates-for-contractors query, matched in Python"
    - "Repository maps Row tuples to plain dataclasses (_to_work_sessions) so services never see SQLAlchemy rows"
    - "Frozen dataclass (ProjectCostRollup) as multi-value service return instead of tuples"
    - "Domain constants single-sourced in the pure module (LABOR_CATEGORY_NAME in labor_derivation)"

key-files:
  created: []
  modified:
    - backend/app/features/finance/schemas.py
    - backend/app/features/finance/repository.py
    - backend/app/features/finance/service.py
    - backend/app/features/finance/router.py
    - backend/app/features/finance/labor_derivation.py
    - backend/tests/unit/test_finance_schemas.py
    - backend/tests/test_phase_32_e2e.py

key-decisions:
  - "LABOR_CATEGORY_NAME lives in labor_derivation.py (plan's 'cleaner' option) — repository cannot import from service without a cycle, so the pure module is the single home"
  - "Legacy labor-category rows fold into the labor row only when derived labor exists (jobs/projects); on trade scopes (labor=None) they stay visible as an ordinary category row so no money hides"
  - "ProjectCostRollup.labor carries the folded labor total so project responses count legacy manual labor exactly once"

patterns-established:
  - "Breakdown assembly: one module-level _build_breakdown helper shared by job, trade-scope, and project paths"
  - "Costable-session predicates (status IN completed/adjusted, duration NOT NULL, not soft-deleted) stated once in _costable_sessions_query"

requirements-completed: [COST-05, COST-06]

# Metrics
duration: 29min
completed: 2026-07-27
---

# Phase 32 Plan 02: Labor Derivation and Cost Breakdown Summary

**Labor cost derived from tracked time x effective-dated rates in two bounded queries, plus itemized category breakdowns for jobs/trade scopes/projects with a reserved-labor-category 422 guard**

## Performance

- **Duration:** 29 min
- **Started:** 2026-07-27T04:34:03Z
- **Completed:** 2026-07-27T05:03:18Z
- **Tasks:** 3
- **Files modified:** 7

## Accomplishments

- COST-05: labor cost derives automatically from completed tracked seconds x the rate effective on the UTC work day of each clock-in — exactly two bounded round trips, unrated seconds surfaced explicitly (never $0)
- ROADMAP success criterion 2 proven by `test_derivation_later_rate_change_does_not_rewrite_history`: a new rate effective today leaves a past job's labor total byte-identical ("240.00" before and after)
- COST-06: `GET /jobs/{id}/cost-breakdown`, `GET /trade-scopes/{id}/cost-breakdown`, and the additively-extended project rollup expose per-category totals plus a grand total; trade scopes report `labor_tracked_at_job_level=true` with no labor figure
- Mobile back-compat preserved: `total` (cost-entry sum, JSON string) and `entries` unchanged in shape and meaning — verified by phase 31 e2e suite passing untouched
- RESEARCH Pitfall 1 closed: manual cost entries can no longer use the reserved `labor` category (422 with the exact UI-SPEC string on create and update); pre-guard legacy rows fold into the single labor row

## Task Commits

Each task was committed atomically:

1. **Task 1 (TDD RED): failing breakdown-schema tests** - `5579c10` (test)
2. **Task 1 (TDD GREEN): schemas, derivation queries, service aggregation** - `228bcab` (feat)
3. **Task 2: breakdown endpoints + COST-05/COST-06 integration tests** - `4f2fb4b` (feat)
4. **Task 3: reserved labor-category guard** - `a269b3d` (feat)

## Files Created/Modified

- `backend/app/features/finance/schemas.py` - CategoryTotal, LaborCostSummary (basis="unburdened" default), CostBreakdownResponse; ProjectCostRollupResponse extended additively
- `backend/app/features/finance/repository.py` - `completed_work_sessions_for_job/for_project` (column-only, three D-03 predicates), `category_totals_for_job/for_trade_scope` sharing one `_category_totals_where` GROUP BY helper, `is_reserved_labor_category`
- `backend/app/features/finance/service.py` - `_derive_labor` (two round trips), `job_cost_breakdown`, `trade_scope_cost_breakdown`, labor-aware `rollup_for_project` returning the `ProjectCostRollup` frozen dataclass, `_build_breakdown` fold logic, `_reject_reserved_labor_category` guard
- `backend/app/features/finance/router.py` - two new finance.view-gated breakdown endpoints; rollup handler populates additive fields
- `backend/app/features/finance/labor_derivation.py` - `LABOR_CATEGORY_NAME` constant (single home for the reserved name)
- `backend/tests/unit/test_finance_schemas.py` - 5 DB-free tests covering serialization, defaults, and rollup backward compatibility
- `backend/tests/test_phase_32_e2e.py` - 17 new integration tests (6 derivation, 6 breakdown, 5 labor_category) + `_seed_time_entry`/`_seed_cost_entry_directly` helpers

## Decisions Made

- `LABOR_CATEGORY_NAME` moved to `labor_derivation.py` (the plan's stated "cleaner" option) rather than exported from service.py — the repository cannot import from service without a circular import, so the pure module is the only home both can share. Task 3's "literal in exactly one file" criterion is satisfied with labor_derivation as that file; repository and service both import the constant, zero duplicated literals.
- Fold rule refinement: legacy labor-category rows fold into the labor row only when derived labor exists (job/project paths). On trade scopes (`labor=None`) a legacy labor row stays visible as an ordinary category row — folding it into a nonexistent labor row would hide money, and no double-count is possible where labor is never derived.
- `ProjectCostRollup.labor` carries the folded labor total (not the raw derived total) so a project with a legacy manual labor entry reports it once in `labor.total` and once in `grand_total`.

## Deviations from Plan

None - plan executed exactly as written (the two interpretation calls above are documented as decisions, not deviations; both follow options the plan itself offered).

## Issues Encountered

None. Note for reviewers: between the Task 1 and Task 2 commits the router still tuple-unpacked the service's new `ProjectCostRollup` return — the plan explicitly staged the router call-site update into Task 2, and Task 1's verification scope (unit tests + ruff) was green at its commit.

## Authentication Gates

None.

## Known Stubs

None — no placeholder values or unwired data paths were introduced.

## User Setup Required

None - no external service configuration required.

## Next Phase Readiness

- Breakdown API shape (`categories`, `labor.total/rated_seconds/unrated_seconds/basis`, `labor_tracked_at_job_level`, `grand_total`) is live for the 32-04 web UI and 32-05 mobile plans
- `unrated_seconds` is machine-readable (int) and ready as Phase 33's incomplete-data signal (MARG-03)
- Full backend suite green: 686 passed, 1 skipped; ruff check + format clean; no migration added

## Self-Check: PASSED

All 8 key files exist on disk; all 4 task commits (5579c10, 228bcab, 4f2fb4b, a269b3d) verified in git log.

---
*Phase: 32-labor-rates-and-cost-rollup*
*Completed: 2026-07-27*
