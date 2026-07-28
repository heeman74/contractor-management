---
phase: 34-budgeting-and-overrun-alerts
plan: 06
subsystem: finance
tags: [sqlalchemy, fastapi, apscheduler, budgets, alerts, cron]

# Dependency graph
requires:
  - phase: 34-budgeting-and-overrun-alerts (34-02)
    provides: BudgetService CRUD, set_total D-03 re-arm, project_spend/trade_scope_spend single spend definition
  - phase: 34-budgeting-and-overrun-alerts (34-03)
    provides: evaluate_budget/evaluate_for_project/evaluate_for_trade_scope with atomic claims + FCM dispatch
  - phase: 26-ai-daily-checklists-and-monitoring-dashboard
    provides: _run_for_all_companies cron pattern with per-company sessions and tenant context
provides:
  - FinanceService._evaluate_budgets_for_entry post-flush hook on cost create/update/delete (D-02, D-04)
  - BudgetService.update_budget inline evaluation — a below-spend edit fires in the same request (D-10)
  - BudgetRepository.scope_spends — ONE grouped spend query for all scope budgets, pinned to trade_scope_spend by a named equivalence test
  - BudgetService.sweep_budgets(company_id=, target_date=) with the _run_for_all_companies-required signature
  - run_budget_sweep cron job at 05:00 UTC (BUDGET_SWEEP_HOUR_UTC) via the new _register_jobs extraction
affects: [34-07 web alerts panel, 34-08 quote-revision deltas, 35-financial-dashboard, 36-ai-profitability]

# Tech tracking
tech-stack:
  added: []
  patterns:
    - "Mutation hooks evaluate AFTER the flush so the check reads post-mutation spend (Pitfall 5); the hook shares the request transaction so a rollback un-does alert and claim together"
    - "Scheduler job registration extracted to _register_jobs(target_scheduler) — cron wiring testable without starting the app"
    - "Batched restatements of a spend definition must carry a named equivalence test referenced from the method docstring (Pitfall 6)"

key-files:
  created: []
  modified:
    - backend/app/features/finance/service.py
    - backend/app/features/finance/budget_service.py
    - backend/app/features/finance/budget_repository.py
    - backend/app/core/scheduler.py
    - backend/tests/test_phase_34_e2e.py

key-decisions:
  - "Kept the shipped module-level BudgetService import in service.py instead of the plan's lazy in-method import — the cycle was already broken from the budget_service side in 34-02, and a second (lazy) import of an already-imported name would be dead weight (CLAUDE.md no-dead-code)"
  - "Alerts tests now seed the cost entry BEFORE the budget so the new mutation hook stays inert during seeding and the manual-evaluation tests keep their meaning"
  - "scope_spends quantizes each grouped SUM to CENTS so its values match grand_total's quantized form exactly"

patterns-established:
  - "_evaluate_budgets_for_entry: scope entries evaluate scope budget + project budget; job entries reach the project budget via a column-only jobs.project_id lookup; NULL project is a clean no-op"

requirements-completed: [BUDG-03]

# Metrics
duration: 27min
completed: 2026-07-28
---

# Phase 34 Plan 06: Cost-Mutation Hooks and Nightly Budget Sweep Summary

**Budget evaluation now runs itself: every cost create/update/delete and every budget edit re-checks the affected budgets in the same transaction, and a 05:00 UTC sweep catches labor-only crossings with one grouped scope-spend query pinned to the displayed total**

## Performance

- **Duration:** 27 min
- **Started:** 2026-07-28T15:46:22Z
- **Completed:** 2026-07-28T16:14:07Z
- **Tasks:** 3 (2 TDD)
- **Files modified:** 5

## Accomplishments

- Recording a cost that pushes spend past 80% produces the warning alert with zero further user action — POST/PATCH/DELETE on cost entries all evaluate the affected budgets after their flush (Pitfall 5), scope and project budgets independently (D-04), at most two evaluations per mutation
- Editing a budget below current spend fires the crossed thresholds in the SAME request; raising it re-arms and stays silent until the new thresholds cross (D-03/D-10)
- `sweep_budgets` evaluates every active budget per company — proven to catch a purely labor-driven crossing (completed time entry + rate, no cost entry anywhere), to skip soft-deleted budgets and dead-project budgets without raising, and to fire nothing on a second run
- The sweep's batched scope spend is pinned: `scope_spends([scope])[scope] == trade_scope_spend(scope) == breakdown grand_total` asserted in one chained assertion over mixed categories plus a soft-deleted entry, and the repository docstring names that test
- `run_budget_sweep` registered at 05:00 UTC (before the 06:00 checklists so alerts await owners) via a new `_register_jobs` extraction that makes cron registration testable without app startup
- 19 new tests (10 mutation + 9 sweep); phase-34 file 52 green; full backend suite 798 passed, 1 skipped; ruff check + format clean

## Task Commits

Each task was committed atomically:

1. **Task 1: Evaluate on cost mutation and on budget edit** - `c8d7874` (test RED), `bbdd030` (feat GREEN)
2. **Task 2: Nightly sweep over every active budget** - `73a3270` (test RED), `77eb516` (feat GREEN)
3. **Task 3: Register the 05:00 UTC budget sweep cron job** - `14c5e29` (feat)

## Files Created/Modified

- `backend/app/features/finance/service.py` - `_evaluate_budgets_for_entry` hook + column-only `_project_id_for_trade_scope`/`_project_id_for_job` lookups; wired into create/update/delete_cost_entry after their flushes
- `backend/app/features/finance/budget_service.py` - `update_budget` inline evaluation; `sweep_budgets` + `_sweep_scope_budgets`/`_sweep_project_budgets` helpers
- `backend/app/features/finance/budget_repository.py` - `scope_spends` grouped SUM with the equivalence-test-naming docstring
- `backend/app/core/scheduler.py` - `run_budget_sweep`, `BUDGET_SWEEP_HOUR_UTC`/`BUDGET_SWEEP_MISFIRE_GRACE_SECONDS`, `_register_jobs` extraction, three-job module docstring
- `backend/tests/test_phase_34_e2e.py` - 10 `mutation` tests, 9 `sweep` tests (incl. the equivalence pin and cron-registration check), alerts-test seeding reordered for the now-live hook

## Decisions Made

- Used the existing module-level `BudgetService` import in `service.py` rather than adding the plan's lazy in-method import: the service↔budget_service cycle was already broken from the budget_service side in 34-02 (its lazy `FinanceService` import, the security.py convention), so a second import of an already-imported name would violate CLAUDE.md's no-dead-code rule; the hook docstring documents the convention instead
- Seed order in alerts tests flipped (entry before budget) so seeding never triggers the new hook — tests that exercise evaluation explicitly keep their original semantics
- `scope_spends` quantizes each SUM to CENTS to match `_build_breakdown`'s quantized `grand_total` form exactly

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 1 - Bug-prevention/CLAUDE.md precedence] Plan's lazy BudgetService import was already obsolete**
- **Found during:** Task 1 (implementation)
- **Issue:** The plan instructed importing `BudgetService` inside `_evaluate_budgets_for_entry` to break an import cycle, but `service.py` has imported `BudgetService` at module level since 34-02 (cycle broken from the other side) — an additional lazy import would be redundant dead code
- **Fix:** Used the existing import; documented the cycle convention in the hook's docstring
- **Files modified:** backend/app/features/finance/service.py
- **Verification:** import check + full suite green; ruff clean
- **Commit:** bbdd030

**2. [Rule 2 - Missing critical] Existing alerts tests updated for the now-automatic evaluation**
- **Found during:** Task 1 (GREEN phase)
- **Issue:** Four shipped 34-03 tests seeded budgets before cost entries and asserted manual-evaluation counts; once mutations evaluate automatically, seeding itself fired alerts and the counts inverted
- **Fix:** `_seed_scope_budget_with_spend` now adds the entry before the budget; `raising_budget_rearms`, `lowering_budget_below_spend`, and `push_project_budget` tests updated to reflect inline firing (manual re-evaluation now finds thresholds already claimed)
- **Files modified:** backend/tests/test_phase_34_e2e.py
- **Verification:** all 13 alerts tests green alongside the 10 new mutation tests
- **Commit:** bbdd030

---

**Total deviations:** 2 auto-fixed (1 plan-vs-codebase adjustment, 1 required test adaptation)
**Impact on plan:** None on scope or contracts — all planned behavior shipped exactly as specified.

## Issues Encountered

- Two RED-phase mutation tests (job-without-project no-op, anchor-without-budget no-op) passed trivially before implementation — they are negative-space guards; the 8 behavior-bearing RED tests failed as required in both TDD tasks.

## Known Stubs

None — hooks, sweep, and cron registration are wired to real evaluation and real spend data end to end. `target_date` on `sweep_budgets` is intentionally unused (cron-contract parameter, documented in the docstring), not a stub.

## User Setup Required

None - no external service configuration required.

## Next Phase Readiness

- 34-08 (quote-revision deltas) can call `set_total` then `evaluate_budget` — both re-arm and inline firing semantics are now proven under endpoints
- The sweep + mutation triggers complete BUDG-03's automatic path; Phase 35 dashboards and Phase 36 AI consume the same alert rows

---
*Phase: 34-budgeting-and-overrun-alerts*
*Completed: 2026-07-28*

## Self-Check: PASSED

All 5 modified files and the SUMMARY exist on disk; all five task commits (c8d7874, bbdd030, 73a3270, 77eb516, 14c5e29) present in git history. Full backend suite: 798 passed, 1 skipped; ruff check + format clean.
