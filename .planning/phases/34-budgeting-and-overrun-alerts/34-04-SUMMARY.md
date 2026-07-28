---
phase: 34-budgeting-and-overrun-alerts
plan: 04
subsystem: ui
tags: [react, nextjs, jest, testing-library, finance, budgets]

# Dependency graph
requires:
  - phase: 34-budgeting-and-overrun-alerts (34-02)
    provides: backend budget block (total/spent/remaining/percent_used) on trade-scope breakdown + project rollup responses
  - phase: 33-profit-margin-tracking
    provides: CostBreakdownSummary/MarginSummarySection row rhythm, FinanceFlagChip amber recipe, formatMarginDollars sign-before-symbol convention
provides:
  - BudgetVsActual type + null-tolerant snake_case parser on both finance responses
  - formatSignedCurrency shared helper in web/src/lib/format.ts (formatMarginDollars now delegates)
  - BudgetSummarySection pure display component (Budget/Spent/Remaining triad, states 1, 3-10)
  - Budget rows wired into project and trade-scope Costs surfaces; job variant provably excluded
affects: [34-05, 34-06, 34-07, 34-08, 35-financial-dashboard]

# Tech tracking
tech-stack:
  added: []
  patterns:
    - "Band classification from backend strings only: isOverBudget = remaining < 0; nearing = remaining > 0 && percentUsed >= WARNING_PERCENT — client never divides"
    - "showsBudget = variant !== 'job' && !isLoading gate keeps budget rows off job breakdowns and loading states"

key-files:
  created:
    - web/src/features/finance/components/BudgetSummarySection.tsx
    - web/src/features/finance/__tests__/budget-section.test.tsx
  modified:
    - web/src/features/finance/types.ts
    - web/src/features/finance/api.ts
    - web/src/lib/format.ts
    - web/src/features/finance/components/MarginSummarySection.tsx
    - web/src/features/finance/components/CostBreakdownSummary.tsx
    - web/src/features/finance/components/ProjectCostsCard.tsx
    - web/src/features/finance/__tests__/cost-breakdown-summary.test.tsx

key-decisions:
  - "Nearing-budget band requires remaining > 0 (not just percent >= 80) so state 5 (exactly at budget) shows no chip — matches UI-SPEC state-4 condition spent < total"
  - "Spent/Budget figures use shipped formatCurrency output (no thousands separators, e.g. $4200.00) — consistent with every shipped finance test; UI-SPEC comma examples are illustrative"
  - "budget field is required (non-optional) on CostBreakdown/ProjectCostRollup so the compiler forces every construction site to decide, with null meaning no budget/older backend"

patterns-established:
  - "isBreakdownEmpty gains hasBudget: a present budget keeps an otherwise-empty breakdown visible so a freshly-set budget is never invisible"

requirements-completed: [BUDG-02]

# Metrics
duration: 28min
completed: 2026-07-28
---

# Phase 34 Plan 04: Web Budget-vs-Actual Display Summary

**Budget/Spent/Remaining triad on project and trade-scope Costs surfaces, rendered verbatim from the backend budget block with amber nearing chip and red overrun numerals, covered by 19 jest tests**

## Performance

- **Duration:** ~28 min
- **Started:** 2026-07-28T06:02:51Z
- **Completed:** 2026-07-28T06:30:30Z
- **Tasks:** 3
- **Files modified:** 9

## Accomplishments
- `BudgetVsActual` typed and parsed (null-tolerant `toBudgetVsActual`) on both the cost-breakdown and project-rollup mappers — older backends without the block render nothing
- `formatSignedCurrency` extracted to `web/src/lib/format.ts` as the one negative-money formatter; `formatMarginDollars` is now a one-line delegate (shipped tests unchanged)
- `BudgetSummarySection` pure display component implements UI-SPEC read-only states 1, 3-10: backend percent displayed verbatim (trailing ".0" dropped), amber "Nearing budget" chip only in the 80-100% band, red signed negative Remaining when over budget, chip and red never co-render
- Budget rows render between the Total row and the margin section on project/trade-scope variants; job variant and loading states provably render none
- Full web suite green: 27 suites, 241 tests, tsc clean, eslint --max-warnings 0 clean, no changes under web/src/components/ui/

## Task Commits

Each task was committed atomically:

1. **Task 1: Budget types, response parsing, shared signed-currency helper** - `3d40ae8` (feat)
2. **Task 2: BudgetSummarySection display component** - `76a8fb1` (test, RED) → `c622df6` (feat, GREEN)
3. **Task 3: Wire budget rows into project and trade-scope Costs surfaces** - `1a813bb` (test, RED) → `42e7abb` (feat, GREEN)

## Files Created/Modified
- `web/src/features/finance/components/BudgetSummarySection.tsx` - Pure display triad; exports `formatPercentUsed`
- `web/src/features/finance/__tests__/budget-section.test.tsx` - 19 tests: state matrix + formatPercentUsed unit block + wiring tests
- `web/src/features/finance/types.ts` - `BudgetVsActual` + required `budget: BudgetVsActual | null` on `CostBreakdown`/`ProjectCostRollup`
- `web/src/features/finance/api.ts` - `BudgetVsActualApiResponse` + `toBudgetVsActual` mapper called from both response mappers
- `web/src/lib/format.ts` - `formatSignedCurrency` (moved from `formatMarginDollars` body)
- `web/src/features/finance/components/MarginSummarySection.tsx` - `formatMarginDollars` delegates to the shared helper
- `web/src/features/finance/components/CostBreakdownSummary.tsx` - `showsBudget` gate + `hasBudget` in `isBreakdownEmpty`
- `web/src/features/finance/components/ProjectCostsCard.tsx` - forwards `rollup.budget` into the breakdown object
- `web/src/features/finance/__tests__/cost-breakdown-summary.test.tsx` - fixtures gain `budget: null` (assertions unchanged)

## Decisions Made
- Nearing band classified as `remaining > 0 && percentUsed >= 80` — the plan's `!isOverBudget && percent >= 80` draft would have shown the chip at exactly 100% (state 5 forbids it); UI-SPEC state 4's `spent < total` condition is authoritative
- Test amounts assert shipped `formatCurrency` output (`$4200.00 · 42%`, no thousands separator) rather than the UI-SPEC's comma-formatted illustrations — matching every shipped finance test (`$20000.00` in margin tests); changing `formatCurrency` would ripple across all Phase 32/33 surfaces and is out of scope

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 3 - Blocking] Required `budget` field broke existing fixtures and ProjectCostsCard compile**
- **Found during:** Task 1 (types/parsing)
- **Issue:** Making `budget` non-optional on `CostBreakdown` failed tsc in `cost-breakdown-summary.test.tsx` (5 fixture literals) and `ProjectCostsCard.tsx` (breakdown object literal)
- **Fix:** Added `budget: null` to the test fixtures; added `budget: rollup.budget` to ProjectCostsCard (pulling forward Task 3's one-line change so Task 1 could compile — Task 3's acceptance criterion satisfied early)
- **Files modified:** web/src/features/finance/__tests__/cost-breakdown-summary.test.tsx, web/src/features/finance/components/ProjectCostsCard.tsx
- **Verification:** tsc clean, all 47 pre-existing tests in the two touched suites pass unchanged
- **Committed in:** 3d40ae8 (Task 1 commit)

---

**Total deviations:** 1 auto-fixed (Rule 3 blocking)
**Impact on plan:** Mechanical compile fix; no scope creep. The chip-band correction (remaining > 0) surfaced via TDD and is documented as a decision, not a deviation — the plan's own behavior spec (state 5) demanded it.

## Issues Encountered
None beyond the above.

## User Setup Required
None - no external service configuration required.

## Next Phase Readiness
- Display contract for read-only budget states is settled and test-locked; 34-07 can layer the SetBudgetDialog/"Set budget"/"Edit" affordances (states 2, 11) on top of `BudgetSummarySection` without touching the triad
- `formatSignedCurrency` is available for any future negative-money surface (dashboard charts in Phase 35)

## Self-Check: PASSED

All claimed files exist on disk and all five task commits (3d40ae8, 76a8fb1, c622df6, 1a813bb, 42e7abb) are present in git history.

---
*Phase: 34-budgeting-and-overrun-alerts*
*Completed: 2026-07-28*
