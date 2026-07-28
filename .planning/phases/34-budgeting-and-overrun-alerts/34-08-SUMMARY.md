---
phase: 34-budgeting-and-overrun-alerts
plan: 08
subsystem: finance
tags: [sqlalchemy, fastapi, quotes, budgets, revision-chain, pre-tax-delta]

# Dependency graph
requires:
  - phase: 34-budgeting-and-overrun-alerts (34-01)
    provides: quotes.revised_from_quote_id column (migration 0035)
  - phase: 34-budgeting-and-overrun-alerts (34-03)
    provides: evaluate_budget with atomic threshold claims + FCM dispatch
  - phase: 34-budgeting-and-overrun-alerts (34-06)
    provides: set_total D-03 re-arm + inline evaluation semantics proven under endpoints
  - phase: 33-profit-margin-tracking
    provides: margin_math pre_tax_total / DocumentAmounts single discount math
provides:
  - Anchor-preserving revise_quote (trade_scope_id/project_id carried, revised_from_quote_id chain link, approved quotes revisable)
  - QuoteRepository.previous_approved_in_chain — exact baseline lookup bounded by MAX_REVISION_CHAIN_DEPTH
  - quoted_revenue (public, was _quoted_revenue) — the single quantized pre-tax quote leg
  - BudgetService.apply_quote_delta — signed pre-tax adjustment + D-03 re-arm + same-request evaluation, clamped at MINIMUM_BUDGET_TOTAL
  - approve_quote budget-delta hook (same transaction, atomic with the status change)
affects: [35-financial-dashboard, 36-ai-profitability, 37-ai-quote-planning]

# Tech tracking
tech-stack:
  added: []
  patterns:
    - "Revision chains are explicit (revised_from_quote_id), never inferred from revision_number + shared anchor — multiple independent chains per anchor are normal"
    - "Bounded parent-pointer walks document why they are not the N+1 pattern: bounded by chain depth (MAX_REVISION_CHAIN_DEPTH), one PK lookup per step"
    - "BUDG-04-only clamp: adjusted_budget_total floors at MINIMUM_BUDGET_TOTAL (0.01); user edits keep the full no-floor D-10 behavior"

key-files:
  created: []
  modified:
    - backend/app/features/quotes/service.py
    - backend/app/features/quotes/repository.py
    - backend/app/features/finance/service.py
    - backend/app/features/finance/budget_service.py
    - backend/tests/unit/test_budget_evaluation.py
    - backend/tests/test_phase_34_e2e.py

key-decisions:
  - "quoted_revenue stays in finance/service.py (rename only, per plan); budget_service reaches it via a lazy in-method import following the 34-02 cycle convention (_finance_service)"
  - "apply_quote_delta resolves a job quote's project via a column-only jobs.project_id lookup instead of relying on the ORM-loaded quote.job, decoupling it from the caller's loading strategy"
  - "The phase test contract is the six VALIDATION selectors (incl. 34-06's `mutation`), not the plan text's five — verified the six-selector union collects all 67 tests"

patterns-established:
  - "Delta tests drive the REAL approve endpoint (send → approve through the status machine); approval is never simulated by raw SQL because the hook is what is under test"

requirements-completed: [BUDG-04]

# Metrics
duration: 34min
completed: 2026-07-28
---

# Phase 34 Plan 08: Quote-Revision Budget Delta Summary

**Approving a quote revision now adjusts its linked budget by the signed pre-tax delta — after fixing the two shipped quote bugs (dropped anchors, unrevisable approved quotes) that made BUDG-04 unreachable and silently broke Phase 33's revenue leg for revised scope quotes**

## Performance

- **Duration:** 34 min
- **Started:** 2026-07-28T16:17:04Z
- **Completed:** 2026-07-28T16:51:00Z
- **Tasks:** 3 (3 TDD)
- **Files modified:** 6

## Accomplishments

- `revise_quote` carries `trade_scope_id` and `project_id` into the new revision and links it via `revised_from_quote_id`; "approved" joined the revisable status set, so a chain can contain a second approval — margin hands off automatically (old row drops out of the approved-quote revenue leg, proven by a 1000→None→1500 revenue assertion)
- `QuoteRepository.previous_approved_in_chain` walks the explicit chain link to the nearest approved ancestor, skipping never-approved revisions, hard-capped at `MAX_REVISION_CHAIN_DEPTH = 50` so a cyclic/corrupt chain terminates instead of looping
- `_quoted_revenue` became public `quoted_revenue`; the delta computes both legs through the exact shipped quantized pre-tax math — no second discount implementation exists (unit-pinned: `quoted_revenue == pre_tax_total(...).quantize(CENTS)`)
- `BudgetService.apply_quote_delta`: D-06 anchor resolution (scope → scope budget; job → jobs.project_id; project-level → quote.project_id), D-08 no-budget no-op, D-09 baseline no-op, signed delta through `set_total` (re-arms on increase), inline `evaluate_budget` so a downward revision below spend fires warning + overrun in the SAME request (keystone 2, asserted through the alert rows)
- Zeroing-or-below deltas clamp at `MINIMUM_BUDGET_TOTAL = Decimal("0.01")` — a storable, immediately-overrun budget instead of a constraint error; the clamp applies only to quote deltas, user edits keep D-10's no-floor behavior
- Approval is atomic: a simulated failure inside the delta application returns 500 and rolls the status change back to `sent`
- 15 `quote_delta` integration tests + 7 delta unit tests; phase-34 file 67 green under the six VALIDATION selectors; full backend suite 820 passed, 1 skipped; ruff check + format clean

## Task Commits

Each task was committed atomically (TDD: RED then GREEN):

1. **Task 1: Fix revise_quote — anchors, approved revisable, chain link** - `ab5a517` (test RED), `fd690c8` (fix GREEN)
2. **Task 2: Chain-walk baseline + signed pre-tax delta application** - `2ba7c30` (test RED), `83254cc` (feat GREEN)
3. **Task 3: Hook the delta into quote approval + BUDG-04 coverage** - `5837118` (test RED), `e200076` (feat GREEN)

## Files Created/Modified

- `backend/app/features/quotes/service.py` - revise_quote carries anchors + chain link + "approved" revisable; approve_quote ends in `_apply_budget_delta` (reuses the single get_with_line_items load, same transaction)
- `backend/app/features/quotes/repository.py` - `previous_approved_in_chain` + `MAX_REVISION_CHAIN_DEPTH` with the bounded-walk N+1 justification
- `backend/app/features/finance/service.py` - `_quoted_revenue` renamed to public `quoted_revenue` (4 call sites, math unchanged)
- `backend/app/features/finance/budget_service.py` - `MINIMUM_BUDGET_TOTAL`, pure `adjusted_budget_total`, `apply_quote_delta` + `_budget_for_quote`/`_project_id_of_job`/`_pre_tax_total_of` helpers
- `backend/tests/unit/test_budget_evaluation.py` - `# --- quote revision delta ---` section: pre-tax parity, signed delta up/down, minimum-total clamp
- `backend/tests/test_phase_34_e2e.py` - 15 `quote_delta` tests: anchor regressions, chain link, approved-revisable, margin hand-off, baseline/no-budget/no-project no-ops, up/down deltas on all three anchor kinds, below-spend overrun keystone, re-arm-then-realert, atomic rollback

## Decisions Made

- `quoted_revenue` is imported lazily inside `_pre_tax_total_of` — finance/service.py imports BudgetService at module level (the 34-02 cycle, broken from the budget_service side), so a module-level import back into service.py would recreate the cycle; the helper docstring documents the convention
- `_budget_for_quote` looks up a job quote's project with a column-only `select(Job.project_id)` rather than touching `quote.job` (lazy="raise" coupling to the caller's load), mirroring 34-06's `_project_id_for_job` pattern
- The atomicity test asserts through the ExceptionHandlerMiddleware's clean 500 response, then reads the quote row via SQL to prove the rollback

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 3 - Blocking] Plan's "five VALIDATION selectors" is actually six**
- **Found during:** Task 3 (phase test contract check)
- **Issue:** The plan's finishing instruction lists five selectors (`budget_crud`, `budget_vs_actual`, `alerts`, `sweep`, `quote_delta`), but 34-VALIDATION.md also defines `mutation` for the ten 34-06 hook tests — the five-selector union misses those 10 tests
- **Fix:** Verified against the authoritative VALIDATION table: the six-selector union collects all 67 tests in the file and all pass; no shipped 34-06 test names were changed
- **Files modified:** none
- **Verification:** `pytest tests/test_phase_34_e2e.py -k "budget_crud or budget_vs_actual or alerts or mutation or sweep or quote_delta" --collect-only` → 67 collected; full file 67 passed
- **Commit:** n/a (verification-only)

---

**Total deviations:** 1 (documentation discrepancy between plan text and VALIDATION; VALIDATION honored)
**Impact on plan:** None — all planned behavior shipped exactly as specified.

## Issues Encountered

- Three RED-phase tests passed trivially before implementation (draft-revise 409 guard in Task 1; baseline and no-op guards in Task 3) — they are negative-space regression guards; every behavior-bearing RED test failed as required
- The pre-commit ruff hook auto-fixed two cosmetic items in the RED test commits (a long signature wrap, a comparison reorder); restaged and committed the hook's output

## Known Stubs

None — the chain walk, delta math, and approval hook operate on real quote/budget data end to end; every figure asserted in tests is read back through the API surface a user sees (scope breakdown / project rollup `budget.total`).

## User Setup Required

None - no external service configuration required.

## Next Phase Readiness

- BUDG-04 completes Phase 34's requirement set (BUDG-01..04 all shipped); the phase backend test contract is closed at 67 green tests across six selectors
- The repaired anchor carry restores Phase 33 margin correctness for revised scope quotes — Phase 35 dashboards and Phase 36 AI profitability consume budgets that now track quote revisions automatically

---
*Phase: 34-budgeting-and-overrun-alerts*
*Completed: 2026-07-28*

## Self-Check: PASSED

All 6 modified files and the SUMMARY exist on disk; all six task commits (ab5a517, fd690c8, 2ba7c30, 83254cc, 5837118, e200076) present in git history. Full backend suite: 820 passed, 1 skipped; ruff check + format clean.
