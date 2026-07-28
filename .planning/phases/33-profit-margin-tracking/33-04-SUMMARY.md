---
phase: 33-profit-margin-tracking
plan: 04
subsystem: ui
tags: [react, nextjs, jest, playwright, margin, finance, tailwind]

# Dependency graph
requires:
  - phase: 33-profit-margin-tracking (33-01)
    provides: locked margin wire contract (revenue_basis, incomplete_reasons, Decimal-as-string)
  - phase: 32-labor-rates-and-cost-rollup
    provides: CostBreakdownSummary on job/scope/project surfaces, unrated chip recipe, formatCurrency
provides:
  - MarginSummarySection pure display component rendering all 12 UI-SPEC states
  - FinanceFlagChip shared amber chip (unrated hours + incomplete data, one recipe)
  - Additive MarginSummary/RevenueBasis types with mapMarginSummary null-tolerant mapper
  - isBreakdownEmpty state-12 contract change (revenue keeps the honesty flag visible)
  - Playwright coverage of margin on job/scope/project surfaces + finance.view gating
affects: [33-03 backend margin endpoints, 33-05 mobile margin section, 35-financial-dashboard]

# Tech tracking
tech-stack:
  added: []
  patterns:
    - "Additive nullable API contract: margin? key absent on old backends yields null, section renders nothing"
    - "Shared chip recipe component (FinanceFlagChip) so honesty flags cannot visually drift"
    - "Sign-before-symbol negative money formatting (-$350.00) via formatMarginDollars"

key-files:
  created:
    - web/src/features/finance/components/MarginSummarySection.tsx
    - web/src/features/finance/components/FinanceFlagChip.tsx
    - web/src/features/finance/__tests__/margin-summary-section.test.tsx
    - web/tests/phase-33-margin.spec.ts
  modified:
    - web/src/features/finance/types.ts
    - web/src/features/finance/api.ts
    - web/src/features/finance/components/CostBreakdownSummary.tsx
    - web/src/features/finance/components/ProjectCostsCard.tsx
    - web/src/features/finance/__tests__/cost-breakdown-summary.test.tsx

key-decisions:
  - "FinanceFlagChip uses imported ReactNode type (not React.ReactNode UMD global) matching codebase convention"
  - "Job-surface Playwright mock keeps the 32-04 catch-all [] fallback (job page pulls many side endpoints); project-surface mock keeps the strict 404 fallback from the cost-capture recipe"
  - "Gating E2E asserts on the job surface with jobs.view+projects.view (no finance.view) — Costs card and margin-section both absent"

patterns-established:
  - "MarginSummarySection: pure display, no hooks, exported formatMarginPercent/formatMarginDollars pure helpers"
  - "isBreakdownEmpty treats present margin with revenueBasis !== none as non-empty (state 12)"

requirements-completed: [MARG-01, MARG-02, MARG-03]

# Metrics
duration: 30min
completed: 2026-07-28
---

# Phase 33 Plan 04: Web Margin Section Summary

**Revenue + Margin rows rendered inside CostBreakdownSummary on all three web Costs surfaces, with quoted/mixed captions, the shared amber incomplete chip, destructive negatives, and the state-12 legacy-job honesty guarantee — proven by 47 Jest tests and 5 Playwright E2E tests**

## Performance

- **Duration:** ~30 min active (wall clock spanned a session-limit pause: started 2026-07-27T17:11:57Z, completed 2026-07-28T00:14:21Z)
- **Tasks:** 3 (Task 2 executed as TDD RED→GREEN)
- **Files modified:** 9

## Accomplishments

- Margin data flows additively into every web Costs surface (job, trade-scope, project) as typed camelCase with zero mount-point edits — an old backend omitting the `margin` key renders nothing
- `MarginSummarySection` implements all 12 UI-SPEC states with every copywriting-contract string as a named constant, asserted verbatim by tests
- The Pitfall-9 legacy job (revenue, zero costs) can no longer hide: `isBreakdownEmpty` treats a present margin with revenue as non-empty, so the "Incomplete cost data" flag always renders
- The unrated-hours chip and the incomplete-data chip now share one implementation (`FinanceFlagChip`) — byte-identical rendered output, existing assertions untouched
- Negative margins render `-$350.00 · -8.3%` in `text-destructive` (sign carries meaning; color is reinforcement)

## Task Commits

Each task was committed atomically:

1. **Task 1: Margin types, API mapping, shared flag chip** - `eed66a2` (feat)
2. **Task 2 RED: Failing margin state coverage** - `f822f36` (test)
3. **Task 2 GREEN: MarginSummarySection implementation** - `230559e` (feat)
4. **Task 3: Playwright E2E for all three surfaces** - `a9a6255` (test)

_No REFACTOR commit — the GREEN implementation already satisfied SRP (RevenueRow/MarginRow/basisCaptionFor extraction) with named constants._

## Files Created/Modified

- `web/src/features/finance/components/MarginSummarySection.tsx` - Pure display component (12 states) + `formatMarginPercent`/`formatMarginDollars` exported helpers
- `web/src/features/finance/components/FinanceFlagChip.tsx` - The one amber data-quality chip recipe (`FINANCE_FLAG_CHIP_CLASS`)
- `web/src/features/finance/types.ts` - `RevenueBasis`, `MarginSummary`; `margin` field on `CostBreakdown` and `ProjectCostRollup`
- `web/src/features/finance/api.ts` - `MarginSummaryApiResponse` + `mapMarginSummary` wired into both breakdown and rollup mappers
- `web/src/features/finance/components/CostBreakdownSummary.tsx` - Renders the section after the Total row; state-12 `isBreakdownEmpty`; LaborRow uses FinanceFlagChip
- `web/src/features/finance/components/ProjectCostsCard.tsx` - Passes `rollup.margin` through the synthetic breakdown
- `web/src/features/finance/__tests__/margin-summary-section.test.tsx` - One test per behavior bullet (19 tests incl. helper cases)
- `web/src/features/finance/__tests__/cost-breakdown-summary.test.tsx` - Extended: section-after-total on all variants, state 11/12, loading
- `web/tests/phase-33-margin.spec.ts` - 5 E2E tests: invoiced job, quoted scope, mixed project + no-revenue scope, KEYSTONE legacy flag, gating

## Decisions Made

- `FinanceFlagChip` imports `ReactNode` from react rather than referencing the `React.ReactNode` UMD global from the plan snippet — matches existing file convention and avoids TS UMD-global errors
- Job-surface Playwright mock uses the 32-04 catch-all `[]` fallback (job detail pulls notes/time-entries/quotes/etc.); the project-surface mock keeps the strict cost-capture 404 fallback
- Gating test grants `jobs.view` + `projects.view` (plan suggested `projects.view` alone) so the Jobs list renders and the assertion isolates the finance gate rather than a navigation failure

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 3 - Blocking] Existing breakdown test literals missing the new required `margin` field**
- **Found during:** Task 1 (additive types)
- **Issue:** Making `margin` a required (nullable) field on `CostBreakdown` broke `tsc --noEmit` in `cost-breakdown-summary.test.tsx` (factory + 3 inline literals) — Task 1's acceptance gate requires tsc exit 0, but the plan scheduled the factory update in Task 2
- **Fix:** Added `margin: null` to the `breakdownWith()` factory default and the three inline `CostBreakdown` literals during Task 1
- **Files modified:** web/src/features/finance/__tests__/cost-breakdown-summary.test.tsx
- **Verification:** `npx tsc --noEmit` exits 0; all 19 pre-existing tests pass unchanged
- **Committed in:** eed66a2 (Task 1 commit)

---

**Total deviations:** 1 auto-fixed (1 blocking)
**Impact on plan:** Sequencing-only adjustment; the change was already planned for Task 2. No scope creep.

## Issues Encountered

- Session-limit interruption after the Task 2 GREEN edits were written but before commit — resumed, verified git state (eed66a2, f822f36 present), completed GREEN verification and committed. No work lost.

## Known Stubs

None — the section renders live data from the breakdown/rollup responses; the null-margin no-render path is the contracted state-10 behavior for pre-33-03 backends, not a stub.

## User Setup Required

None - no external service configuration required.

## Next Phase Readiness

- Web surfaces render margin the moment 33-03 ships the backend `margin` key — no further web changes needed
- `FinanceFlagChip` + verbatim strings available for 33-05 mobile parity (mobile locks the same copy via `find.text`)
- Full verification green: 222 Jest tests / 26 suites, 5/5 Playwright, `tsc --noEmit` clean, ESLint `--max-warnings 0` clean

---
*Phase: 33-profit-margin-tracking*
*Completed: 2026-07-28*

## Self-Check: PASSED

All 5 key files exist on disk; all 4 task commits (eed66a2, f822f36, 230559e, a9a6255) present in git history.
