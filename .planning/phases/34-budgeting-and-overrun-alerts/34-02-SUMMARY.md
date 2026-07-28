---
phase: 34-budgeting-and-overrun-alerts
plan: 02
subsystem: api
tags: [fastapi, sqlalchemy, pydantic, budgets, finance, rbac]

# Dependency graph
requires:
  - phase: 34-budgeting-and-overrun-alerts (34-01)
    provides: migration 0035 (threshold-state columns, partial unique indexes, total>0 check), budget_math.percent_used, alert_types registration
  - phase: 33-profit-margin-tracking
    provides: breakdown/rollup assembly (_build_breakdown, rollup_for_project) that defines spend
  - phase: 30-financial-schema-foundation
    provides: Budget model, BudgetCreate schema, finance.* RBAC keys
provides:
  - POST/PATCH/DELETE /budgets endpoints gated finance.manage with 409 duplicate-anchor refusal
  - BudgetRepository with active-anchor lookups, list_active (nightly sweep feed), set_total as the single D-03 re-arm write path
  - BudgetService CRUD + budget_vs_actual_for_project/trade_scope assembly
  - FinanceService.project_spend / trade_scope_spend — the single spend definition alert evaluation reuses
  - Additive budget block (BudgetVsActual) on trade-scope breakdown and project rollup with spent == grand_total by construction
  - Shared e2e seed helpers (_create_project/_create_trade_scope/_create_budget/_add_cost_entry) in test_phase_34_e2e.py
affects: [34-03 alert evaluation, 34-04 nightly sweep, 34-05 web budgets UI, 34-06 web breakdown budget section, 34-07 mobile, 35-financial-dashboard]

# Tech tracking
tech-stack:
  added: []
  patterns:
    - "Single spend definition: every spend figure routes through _project_cost_side / _build_breakdown grand_total — never a second SUM"
    - "D-03 re-arm expressed once in BudgetRepository.set_total (raise nulls fired timestamps; decrease keeps them)"
    - "Lazy FinanceService import in BudgetService breaks the service<->budget_service module cycle (security.py convention)"

key-files:
  created:
    - backend/app/features/finance/budget_repository.py
    - backend/app/features/finance/budget_service.py
    - backend/tests/test_phase_34_e2e.py
  modified:
    - backend/app/features/finance/schemas.py
    - backend/app/features/finance/router.py
    - backend/app/features/finance/service.py

key-decisions:
  - "Added `from __future__ import annotations` to finance/schemas.py so the additive budget field on CostBreakdownResponse/ProjectCostRollupResponse can forward-reference BudgetVsActual defined later in the module (Pydantic v2 resolves from module globals)"
  - "Cycle broken from the budget_service side: service.py imports BudgetService normally; budget_service lazily imports FinanceService inside _finance_service() with a TYPE_CHECKING import for the annotation"
  - "BudgetRepository.set_total refreshes after flush so server-updated timestamps never lazy-load during response serialization (MissingGreenlet fix)"
  - "Anchor lookup queries inlined per method (not a shared helper) to keep every query's deleted_at filter explicit, matching FinanceRepository style"

patterns-established:
  - "Budget-vs-actual assembly: callers that already computed grand_total pass it as spent= so the block equals the displayed total by construction (Pitfall 6)"
  - "Dormant D-11 feature input (category_breakdowns) rejected loudly with 422, never silently dropped"

requirements-completed: [BUDG-01, BUDG-02]

# Metrics
duration: 34min
completed: 2026-07-28
---

# Phase 34 Plan 02: Budget CRUD and Budget-vs-Actual Block Summary

**Permission-gated /budgets CRUD (409 on duplicate active anchor, D-03 re-arm on raise) plus an additive BudgetVsActual block on the scope breakdown and project rollup whose spent is provably the response's own grand_total**

## Performance

- **Duration:** 34 min
- **Started:** 2026-07-28T05:25:26Z
- **Completed:** 2026-07-28T05:59:49Z
- **Tasks:** 3 (2 TDD)
- **Files modified:** 6

## Accomplishments

- Owners/PMs can create, edit (any positive amount, D-10) and soft-delete project and trade-scope budgets through three finance.manage-gated endpoints; non-finance roles 403
- One spend definition: `project_spend`/`trade_scope_spend` route through the shipped breakdown assembly (`_project_cost_side` extraction) — no new SUM query exists anywhere
- The trade-scope breakdown and project rollup now carry `budget` (total/spent/remaining/percent_used at one decimal) with `spent == grand_total` asserted on both surfaces; job breakdowns never carry it
- 20 integration tests (13 budget_crud + 7 budget_vs_actual) green; full backend suite 766 passed, phases 32/33 unchanged

## Task Commits

Each task was committed atomically:

1. **Task 1: Budget schemas + BudgetRepository** - `7b283f0` (feat)
2. **Task 2: BudgetService CRUD + /budgets endpoints** - `6d58af1` (test RED), `28dc931` (feat GREEN)
3. **Task 3: Single spend definition + embedded budget block** - `b8255c4` (test RED), `2a8cdc0` (feat GREEN)

## Files Created/Modified

- `backend/app/features/finance/budget_repository.py` - Active-anchor lookups, 404 helper, list_active, set_total (single D-03 re-arm write path)
- `backend/app/features/finance/budget_service.py` - CRUD with friendly 409/422 errors + budget_vs_actual assembly via budget_math.percent_used
- `backend/app/features/finance/schemas.py` - BudgetUpdate/BudgetResponse/BudgetVsActual; BudgetCreate.total tightened to gt=0; additive budget field on both response models
- `backend/app/features/finance/router.py` - POST/PATCH/DELETE /budgets handlers, endpoint table, rollup passes budget through
- `backend/app/features/finance/service.py` - ProjectCostSide extraction, project_spend/trade_scope_spend, budget wired into scope breakdown and rollup
- `backend/tests/test_phase_34_e2e.py` - 20 tests + shared seed helpers for later Phase 34 plans

## Decisions Made

- `from __future__ import annotations` added to schemas.py so the budget field can forward-reference BudgetVsActual (defined later, in the Budget schemas section per plan layout); ruff then auto-removed the now-redundant quoted validator annotations
- Module cycle broken from the budget_service side (lazy `FinanceService` import inside `_finance_service()`, TYPE_CHECKING import for the annotation) — service.py imports BudgetService normally, matching the plan's primary path
- Anchor queries inlined per repository method rather than a shared filter helper, keeping `deleted_at.is_(None)` visible at each query site (FinanceRepository convention)

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 1 - Bug] PATCH /budgets/{id} 500 — MissingGreenlet during response serialization**
- **Found during:** Task 2 (BudgetService CRUD, GREEN phase)
- **Issue:** `set_total` flushed but did not refresh; the server-updated `updated_at` was expired, so `BudgetResponse.model_validate` triggered a lazy load outside greenlet context → 500
- **Fix:** `await self.db.refresh(budget)` after flush in `set_total`, mirroring `BaseRepository.create`
- **Files modified:** backend/app/features/finance/budget_repository.py
- **Verification:** test_budget_crud_raising_total_rearms_fired_thresholds (and all PATCH tests) pass
- **Committed in:** 28dc931 (Task 2 commit)

---

**Total deviations:** 1 auto-fixed (1 bug)
**Impact on plan:** Fix necessary for correctness; no scope creep.

## Issues Encountered

- One RED-phase budget_crud test (unknown-id 404) passed trivially before implementation because FastAPI 404s unknown routes; it became meaningful once /budgets routes existed. All behavior-bearing RED tests failed as required.

## Known Stubs

None — the budget block is wired to real spend data end to end. `category_breakdowns` remains dormant by design (D-11) and is rejected with 422, not stubbed.

## User Setup Required

None - no external service configuration required.

## Next Phase Readiness

- 34-03 (alert evaluation) can consume `FinanceService.project_spend`/`trade_scope_spend`, `BudgetRepository.list_active`, and the `set_total` re-arm semantics directly
- Web/mobile plans (34-05/06/07) have their API contract: `budget` present-and-null distinguishes "no budget" from "old backend"; `percent_used` is backend-supplied at one decimal
- Shared e2e seed helpers in test_phase_34_e2e.py ready for reuse by later plans

---
*Phase: 34-budgeting-and-overrun-alerts*
*Completed: 2026-07-28*

## Self-Check: PASSED

All key files exist on disk; all five task commits present in git history.
