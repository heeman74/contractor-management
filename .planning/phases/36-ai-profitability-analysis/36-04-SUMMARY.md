---
phase: 36-ai-profitability-analysis
plan: 04
subsystem: ui
tags: [react, nextjs, tailwind, jest, testing-library, finance, ai]

# Dependency graph
requires:
  - phase: 36-ai-profitability-analysis (plan 02)
    provides: ProfitabilityFinding type, fetcher, permission-gated useProjectProfitabilityFinding hook, formatFindingDate, FINANCE_ALERT_CHIP_CLASS, and the promoted QUOTED_BASIS_CAPTION / UNBURDENED_TITLE / UNBURDENED_BODY exports
  - phase: 35-web-financial-dashboard
    provides: the /financials/[projectId] drill-down, FinanceSummaryTiles, ChartEmptyState, the two-query loading gate convention
provides:
  - ProfitabilityFindingCard — presentational card rendering the latest open AI finding with all 11 UI-SPEC test ids
  - Three pure exported helpers — findingDateLine, revenueBasisCaption, emptyStateCopy
  - The card mounted full-width between the summary tiles and the Margin Trend chart
  - A 21-test state-matrix suite covering UI-SPEC states 3-16, 19 and 21
  - The findings-outage keystone: a failed finding query never blanks the money dashboard
affects: [36-05, 36-09, 36-10, ai-profitability-analysis, playwright-e2e]

# Tech tracking
tech-stack:
  added: []
  patterns:
    - "Presentational card owns no hook and no permission branch — the 22-row state matrix is testable by props alone"
    - "One SEVERITY_CHIP map holds a band's copy and its color together, mirroring attention-list.tsx's TIER_BADGE"
    - "AI-authored prose asserted through the prop variable, never byte-for-byte; frame strings asserted byte-for-byte"
    - "Third query excluded from the page loading gate: three keys, three failure surfaces"

key-files:
  created:
    - "web/src/app/(dashboard)/financials/[projectId]/_components/profitability-finding-card.tsx"
    - "web/src/app/(dashboard)/financials/__tests__/profitability-finding.test.tsx"
  modified:
    - "web/src/app/(dashboard)/financials/[projectId]/_components/project-financials-dashboard.tsx"
    - "web/src/app/(dashboard)/financials/__tests__/project-financials.test.tsx"

key-decisions:
  - "incompleteCostData reads breakdown.margin?.incomplete ?? false — CostBreakdown.margin is MarginSummary | null, so the plan's non-optional access would not compile and would crash the shipped null-margin drill-down test"
  - "The shipped drill-down test's hooks mock was extended with useProjectProfitabilityFinding rather than the dashboard importing the hook lazily — a module-factory mock that omits a newly imported hook fails as 'not a function', and hiding that behind an import-time guard would put test scaffolding in production code"
  - "The finding-in-flight keystone test is what mutation-catches a widened loading gate; the finding-error keystone alone cannot, because isError implies isLoading false"

patterns-established:
  - "Card chrome never changes with severity — only the chip does — so a warning finding can never be mistaken for the page-level error panel"
  - "Shipped copy strings are imported, never retyped, so one caveat can never carry two texts"

requirements-completed: [FINAI-02]

# Metrics
duration: 8min
completed: 2026-07-29
---

# Phase 36 Plan 04: Profitability Finding Card Summary

**Presentational `ProfitabilityFindingCard` with all 11 UI-SPEC test ids, mounted full-width between the summary tiles and the Margin Trend chart, plus a 21-test state-matrix suite whose keystone proves a findings outage never blanks the money dashboard.**

## Performance

- **Duration:** 8 min
- **Started:** 2026-07-29T18:52:00Z
- **Completed:** 2026-07-29T18:59:38Z
- **Tasks:** 3
- **Files modified:** 4 (2 created, 2 modified)

## Accomplishments

- `ProfitabilityFindingCard` renders every locked frame string byte-for-byte — card title and `aria-label`, both severity chip labels, the `SUGGESTED ACTION` eyebrow at `text-gray-700`, both date-line templates, both revenue-basis captions, the composed unburdened-labor caveat, the always-last AI disclosure line, both empty-state variants and the in-card error line.
- The card is purely presentational: no hook, no permission branch, no state, no interactive element. That is what makes the state matrix testable by props alone.
- Three pure exported helpers (`findingDateLine`, `revenueBasisCaption`, `emptyStateCopy`) are unit-tested without React.
- The drill-down now owns three queries with three keys and three failure surfaces; the page loading gate still reads exactly `financials.isLoading || trend.isLoading`, mutation-verified.
- Shipped strings are **imported**, never retyped: `QUOTED_BASIS_CAPTION`, `UNBURDENED_TITLE`, `UNBURDENED_BODY`, `FINANCE_FLAG_CHIP_CLASS`, `FINANCE_ALERT_CHIP_CLASS`. The literals `"Based on approved quotes"` and `"Unburdened labor"` appear nowhere in the card.
- 235 tests green across `src/app/(dashboard)/financials` and `src/features/finance`; `tsc --noEmit` and `eslint --max-warnings 0` both clean.

## Task Commits

1. **Task 1: ProfitabilityFindingCard** — `7460e7e` (feat)
2. **Task 2: Mount on the drill-down without widening the loading gate** — `0fa5d36` (feat)
3. **Task 3: Jest state-matrix suite** — `d20cf9f` (test)

## Files Created/Modified

- `web/src/app/(dashboard)/financials/[projectId]/_components/profitability-finding-card.tsx` — the card, its named copy constants, the `SEVERITY_CHIP` map and the three pure helpers (222 lines)
- `web/src/app/(dashboard)/financials/[projectId]/_components/project-financials-dashboard.tsx` — third hook, card mount between the tiles and the trend chart, docstring updated to three queries
- `web/src/app/(dashboard)/financials/__tests__/profitability-finding.test.tsx` — 21 tests: states 3-16, 19, 21 plus the dashboard failure surface (446 lines)
- `web/src/app/(dashboard)/financials/__tests__/project-financials.test.tsx` — hooks mock extended with the new hook so the shipped drill-down suite keeps compiling

## Decisions Made

- **`breakdown.margin?.incomplete ?? false`, not `breakdown.margin.incomplete`.** `CostBreakdown.margin` is `MarginSummary | null`. The plan's literal would fail `tsc --noEmit` and would throw at runtime on the shipped "a null margin renders em dash tiles" path. The optional read preserves the acceptance criterion's intent (the project's own incomplete flag drives the honesty empty state) while a project with no revenue — and therefore no margin block — falls into the plain empty state, exactly the variant bound the UI-SPEC states.
- **The shipped drill-down test's hooks mock was extended rather than worked around.** `jest.mock("@/features/finance/hooks", factory)` replaces the whole module, so a newly imported hook arrives as `undefined`. The default return is `{ data: undefined, isLoading: false, isError: false }` with an in-file comment saying why: those tests assert the money dashboard, so the finding stays quiet.
- **Two keystone tests, not one.** The finding-error test proves the error line renders beside intact tiles/trend/scope-bars/category-mix. The finding-in-flight test is the one that mutation-catches a widened loading gate — an errored query has `isLoading: false`, so the error test alone would still pass if `finding.isLoading` joined the gate.

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 1 - Bug] `breakdown.margin.incomplete` dereferences a nullable field**
- **Found during:** Task 2 (Mount the card on the drill-down)
- **Issue:** The plan's JSX snippet and its acceptance grep specify `incompleteCostData={breakdown.margin.incomplete}`, but `CostBreakdown.margin` is typed `MarginSummary | null`. Under strict TypeScript this fails `tsc --noEmit`, and at runtime it throws on the shipped drill-down path where a project has no revenue and therefore no margin block.
- **Fix:** `incompleteCostData={breakdown.margin?.incomplete ?? false}`. The acceptance grep was relaxed to `incompleteCostData={breakdown.margin` — the prop and its source are unchanged; only the null guard was added.
- **Files modified:** `web/src/app/(dashboard)/financials/[projectId]/_components/project-financials-dashboard.tsx`
- **Verification:** `npx tsc --noEmit` clean; the shipped "a null margin renders em dash tiles while cost still renders the grand total" test passes.
- **Committed in:** `0fa5d36`

**2. [Rule 3 - Blocking] Shipped drill-down test's hooks mock omitted the new hook**
- **Found during:** Task 2 (Mount the card on the drill-down)
- **Issue:** `project-financials.test.tsx` mocks `@/features/finance/hooks` with a factory listing only `useProjectFinancials` and `useProjectMarginTrend`. Once the dashboard imported `useProjectProfitabilityFinding`, 19 of 74 shipped tests failed with `(0, hooks_1.useProjectProfitabilityFinding) is not a function` — Task 2's verification gate could not pass.
- **Fix:** Added `useProjectProfitabilityFinding: jest.fn()` to the mock factory, a default healthy-and-empty return value inside the existing `mockQueries` helper, and a `mockReset()` in `beforeEach` alongside the other two.
- **Files modified:** `web/src/app/(dashboard)/financials/__tests__/project-financials.test.tsx`
- **Verification:** `npx jest "src/app/\(dashboard\)/financials"` — 74/74 shipped tests green again, then 95/95 with the new suite.
- **Committed in:** `0fa5d36`

---

**Total deviations:** 2 auto-fixed (1 bug, 1 blocking)
**Impact on plan:** Both were required for the plan to compile and for its own verification gate to run. No scope creep — no file outside `files_modified` plus the one shipped test whose mock had to learn about the new hook. `financials-skeleton.tsx` and `AlertPanel.tsx` are untouched, as the plan requires.

## Issues Encountered

- **`npx jest "src/app/(dashboard)/financials"` matches nothing.** The plan's verification command passes the path as a regex, and the route group's literal parentheses are capture groups. The escaped form `npx jest "src/app/\(dashboard\)/financials"` is what actually runs the suite. Worth carrying into 36-05/36-09 verification commands.

## Verification Performed

- `npx tsc --noEmit` — clean
- `npm run lint` (eslint `--max-warnings 0`) — clean
- `npx jest "src/app/\(dashboard\)/financials" "src/features/finance"` — 12 suites, 235 tests, all green
- **Mutation check:** widening the page loading gate to `financials.isLoading || trend.isLoading || finding.isLoading` fails exactly one test (the finding-in-flight keystone) and no others; the gate was then restored and re-verified byte-identical to the committed file.
- All 22 Task-1 acceptance greps confirmed, including the negative ones (`! grep "Based on approved quotes"`, `! grep "Unburdened labor"`, no `parseFloat`/`formatCurrency`/`new Date`, no `<button`/`<Button`/`onClick`).
- Placement confirmed by line number and by a DOM-order assertion: the card sits after `FinanceSummaryTiles` and before the `TREND_TITLE` `ChartCard`.

## Known Stubs

None. Every branch of the card renders real content from real props; no placeholder text, no hardcoded empty data, no unwired component.

## User Setup Required

None — no external service configuration required.

## Next Phase Readiness

- The card and its mount are ready for 36-09's `AlertPanel` verification-by-test and for the Playwright suite, which can target `data-testid="profitability-finding"` and the accessible name `"Profitability Finding card"`.
- Playwright must log in through the UI then SPA-navigate rather than `page.goto` the drill-down (the shipped 32-04 / 35-11 lesson) — a hard navigation resets Redux `isAuthenticated`, disables `usePermissions`, and the finance surfaces are correctly denied.
- No blockers.

## Self-Check: PASSED

All 5 claimed files exist on disk; all 3 task commit hashes resolve in git history.

---
*Phase: 36-ai-profitability-analysis*
*Completed: 2026-07-29*
