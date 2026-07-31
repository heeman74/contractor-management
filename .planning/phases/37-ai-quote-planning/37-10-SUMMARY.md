---
phase: 37-ai-quote-planning
plan: 10
subsystem: ui
tags: [react, tanstack-query, finance-permissions, nextjs, quotes, financials-dashboard]

# Dependency graph
requires:
  - phase: 37-04
    provides: "GET /projects/{projectId}/financials/quote-variance backend endpoint (finance.view-gated)"
  - phase: 37-08
    provides: "QuoteVarianceTrade type, exported LABOR_NOTE, quote-detail Quoted vs Actual card pattern to mirror"
provides:
  - ProjectQuoteVariance type, fetchProjectQuoteVariance fetcher (reuses the shared trade-row mapper), useProjectQuoteVariance hook (own query key, finance.view-gated)
  - QuoteVarianceTable module (quoteVarianceKpi, quoteVarianceCsvRows, QuoteVarianceTable) — the per-trade table with a hairline-separated Project total row
  - Fourth ChartCard on /financials/[projectId], mounted between the trend and the scope/category two-up grid, outside the page loading gate
affects: [37-11, 37-12]

tech-stack:
  added: []
  patterns:
    - "Fourth independent query on the drill-down: own key under the cost-entries prefix, own finance.view enabled gate, own in-card skeleton/error surface excluded from the page loading gate — extends the three-query pattern 36-04/37-08 established"
    - "A test file that mocks @/features/finance/hooks via jest.mock module factory and renders ProjectFinancialsDashboard must register every hook the component calls, including ones added by a later plan — a factory replaces the whole module, so an unmocked newly-imported hook returns undefined and every test using it fails with 'not a function'"

key-files:
  created:
    - web/src/app/(dashboard)/financials/[projectId]/_components/quote-variance-table.tsx
  modified:
    - web/src/features/finance/types.ts
    - web/src/features/finance/api.ts
    - web/src/features/finance/hooks.ts
    - web/src/app/(dashboard)/financials/[projectId]/_components/project-financials-dashboard.tsx
    - web/src/app/(dashboard)/financials/__tests__/project-financials.test.tsx
    - web/src/app/(dashboard)/financials/__tests__/profitability-finding.test.tsx
    - web/src/features/finance/__tests__/financials-hooks.test.tsx

key-decisions:
  - "scope-budget-bars.tsx's LABOR_NOTE was already exported by plan 37-08 (a wave early) — Task 1 made no change to that file; verified via git diff on the file returning empty rather than re-adding the export"
  - "quoteVarianceKpi/VarianceFigure/unsigned/isOverQuoted are re-implemented locally in quote-variance-table.tsx rather than imported from quote-variance-card.tsx (the quote-detail sibling) since none of those helpers are exported there — duplicating a small, well-tested pure-function shape across two route-scoped modules was preferred over widening quote-variance-card.tsx's public surface for a single reuse"
  - "The dashboard's docstring literal changed from 'Three queries, three keys, three failure surfaces' to 'Its docstring rule: four queries, four keys, four failure surfaces' (matching the plan's own interfaces-block phrasing) rather than capitalizing 'Four' — the acceptance grep is a case-sensitive literal match on the lowercase phrase"
  - "Extended the jest.mock('@/features/finance/hooks') factory with useProjectQuoteVariance in BOTH project-financials.test.tsx and profitability-finding.test.tsx — the second file was not listed in the plan's files_modified but also renders ProjectFinancialsDashboard behind the same module-factory mock, so it hit the identical 'not a function' trap 36-04 first documented"

# Metrics
duration: 30min
completed: 2026-07-31
---

# Phase 37 Plan 10: Project Quote Variance Drill-Down Summary

**Fourth independent query on `/financials/[projectId]` — a per-trade Quoted vs Actual table (with a hairline-separated Project total row, red-800-only overage ink, and an unrolled CSV export) mounted between the margin trend and the scope/category grid, outside the page loading gate.**

## Performance

- **Duration:** ~30 min
- **Tasks:** 3
- **Files modified:** 8 (1 created, 7 modified)

## Accomplishments
- `useProjectQuoteVariance` hook: its own query key (`quote-variance-project`, distinct from the quote-detail's `quote-variance` key), `finance.view`-gated, zero requests when unauthorized — the fetch-side half of the Trap 8 double lock, proven by hook tests that mock the HTTP layer directly (the 36-02 precedent)
- `QuoteVarianceTable` module mirroring `scope-budget-bars.tsx`'s shape: `quoteVarianceKpi` (over/under quoted percent, "Matched quoted" at zero, "No invoiced work yet" when the total has no figures), `quoteVarianceCsvRows` (true unrolled backend strings, the 35-03 rule), and the table itself (one row per trade plus a `border-t`-separated Project total row, `text-red-800` only on a positive/over-quoted figure, everything else `text-gray-900`, no green, no check glyph, no band chip)
- Mounted as the drill-down's fourth `ChartCard`, full width, between the margin trend and the scope/category two-up grid — the page loading gate stays `financials.isLoading || trend.isLoading`, so a slow or failing variance query renders its own two-bar skeleton or scoped in-card error line while every other card (tiles, finding, trend, scope bars, category mix) renders normally

## Task Commits

1. **Task 1: Export the scope-labor caption and add the project-variance query** - `78221f8` (feat)
2. **Task 2: The per-trade variance table module** - `8fb9b38` (feat)
3. **Task 3: Mount the card as a fourth independent query** - `88bebf8` (feat)

**Plan metadata:** (this commit)

## Files Created/Modified
- `web/src/app/(dashboard)/financials/[projectId]/_components/quote-variance-table.tsx` - new module: the table, KPI, CSV rows
- `web/src/features/finance/types.ts` - `ProjectQuoteVariance` type
- `web/src/features/finance/api.ts` - `fetchProjectQuoteVariance` + response mapper, reusing the shared trade-row mapper
- `web/src/features/finance/hooks.ts` - `useProjectQuoteVariance`
- `web/src/app/(dashboard)/financials/[projectId]/_components/project-financials-dashboard.tsx` - fourth hook, fourth `ChartCard`, skeleton/error body helper
- `web/src/app/(dashboard)/financials/__tests__/project-financials.test.tsx` - table unit tests, dashboard wiring tests, extended jest.mock factory
- `web/src/app/(dashboard)/financials/__tests__/profitability-finding.test.tsx` - extended jest.mock factory (deviation, see below)
- `web/src/features/finance/__tests__/financials-hooks.test.tsx` - `useProjectQuoteVariance` hook tests (HTTP-layer mocked)

## Decisions Made
See `key-decisions` in frontmatter.

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 3 - Blocking] Extended profitability-finding.test.tsx's hooks mock factory**
- **Found during:** Task 3 (mounting the fourth query)
- **Issue:** `profitability-finding.test.tsx` also `jest.mock`s `@/features/finance/hooks` with a module factory and renders `ProjectFinancialsDashboard`. Once the dashboard unconditionally called the new `useProjectQuoteVariance`, that file's mock factory returned `undefined` for it, and every test rendering the dashboard through that mock crashed with "not a function" — the exact 36-04 trap, now reproduced in a second file the plan's `files_modified` list didn't name.
- **Fix:** Added `useProjectQuoteVariance: jest.fn()` to the factory, a quiet default return value in `mockHealthyPageWithFinding`, and a `mockReset()` in `beforeEach`; one test that builds its mocks inline (not through the helper) also got the same quiet default.
- **Files modified:** `web/src/app/(dashboard)/financials/__tests__/profitability-finding.test.tsx`
- **Verification:** `npx jest "src/app/\(dashboard\)/financials"` — all 3 suites, 110 tests green; full `npm test` — 526/526 green.
- **Committed in:** `88bebf8` (Task 3 commit)

---

**Total deviations:** 1 auto-fixed (blocking)
**Impact on plan:** Necessary to keep the shipped test suite green; no scope creep — same fix pattern the plan's own `<action>` block anticipated for `project-financials.test.tsx`, applied to the one additional file that hit the identical trap.

## Issues Encountered
- Recharts injects a singleton `#recharts_measurement_span` into `document.body` outside the React tree, which is not removed by React Testing Library's auto-cleanup between tests. A new table test using `getByText("Plumbing")` collided with a stale measurement span left by an earlier `ScopeBudgetBars` test in the same file (both use "Plumbing"/"Electrical" as trade names). Fixed by scoping the query with `within(screen.getByTestId(QUOTE_VARIANCE_TEST_ID))` rather than querying the whole document.

## User Setup Required
None - no external service configuration required.

## Next Phase Readiness
The project drill-down now carries all four FINAI-05-relevant surfaces (quote-detail variance from 37-08, project-level per-trade variance from this plan). No blockers for 37-11/37-12.

---
*Phase: 37-ai-quote-planning*
*Completed: 2026-07-31*

## Self-Check: PASSED

All 9 created/modified files found on disk; all 3 task commits (78221f8, 8fb9b38, 88bebf8) found in git history.
