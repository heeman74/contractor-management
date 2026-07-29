---
phase: 35-web-financial-dashboard
plan: 10
subsystem: ui
tags: [react, nextjs, recharts, typescript, jest, financial-dashboard]

# Dependency graph
requires:
  - phase: 35-03
    provides: chart-theme constants, financials-format helpers, ChartEmptyState, FinancialsSkeleton, FinanceGate
  - phase: 35-04
    provides: useProjectFinancials / useProjectMarginTrend hooks and the ProjectFinancials / MarginTrend types
  - phase: 35-09
    provides: BulletBarChart and FinanceSummaryTiles, consumed read-only
provides:
  - "/financials/[projectId] drill-down route behind the shared FinanceGate"
  - "MarginTrendChart — three series, labelled break-even line, real gaps for null margins"
  - "TrendWindowFilter — four windows on their own query key, with the cumulative caption"
  - "ScopeBudgetBars — the shared bullet-bar form with no click-through and the labor caption"
  - "CategoryMixChart — six-slice pie with an Other rollup whose CSV stays unrolled"
affects: [35-11, 36-ai-profitability]

# Tech tracking
tech-stack:
  added: []
  patterns:
    - "Drill-down container owns two queries on independent keys so a window change never restates lifetime tiles"
    - "Chart datum carries both the number geometry needs and the backend string every figure formats from"
    - "Pie fill assignment draws from a finite ramp pool so no hue can repeat inside one chart"

key-files:
  created:
    - "web/src/app/(dashboard)/financials/[projectId]/page.tsx"
    - "web/src/app/(dashboard)/financials/[projectId]/_components/project-financials-dashboard.tsx"
    - "web/src/app/(dashboard)/financials/[projectId]/_components/margin-trend-chart.tsx"
    - "web/src/app/(dashboard)/financials/[projectId]/_components/trend-window-filter.tsx"
    - "web/src/app/(dashboard)/financials/[projectId]/_components/scope-budget-bars.tsx"
    - "web/src/app/(dashboard)/financials/[projectId]/_components/category-mix-chart.tsx"
    - "web/src/app/(dashboard)/financials/__tests__/project-financials.test.tsx"
  modified:
    - "web/src/features/finance/financials-format.ts"

key-decisions:
  - "formatFullMonthLabel added beside formatMonthLabel in financials-format.ts rather than a second month table in the chart"
  - "isNotFoundError reads ApiError.status — no message matching, no bare cast"
  - "Custom category fills draw from a pool of the two reserved custom hues plus any unclaimed system hue, so the capped ramp is provably repeat-free"
  - "The trend query's error degrades to zero buckets (the empty state) instead of blanking the whole drill-down"

patterns-established:
  - "Window selectors live inside their chart card, never at page level, so they cannot be misread as page-wide filters"
  - "connectNulls is named only in a comment — the false default is the contract, an explicit prop would invite flipping it"

requirements-completed: [MARG-04]

# Metrics
duration: 11min
completed: 2026-07-29
---

# Phase 35 Plan 10: Project Financials Drill-Down Summary

**`/financials/[projectId]` with a three-series margin trend that renders real gaps for null months, a window selector on its own query key, per-trade-scope bullet bars carrying the labor-exclusion caption, and a six-slice category pie whose CSV export is never rolled up.**

## Performance

- **Duration:** 11 min
- **Started:** 2026-07-29T04:08:55Z
- **Completed:** 2026-07-29T04:19:55Z
- **Tasks:** 3
- **Files modified:** 8 (7 created, 1 modified)

## Accomplishments

- Drill-down route shell (`ssr: false` + project skeleton) whose container is the only hook owner, with a 404 panel distinct from the generic load error.
- Margin trend with Margin/Revenue/Cost on one dollar axis, a labelled `Break-even` reference line, `Mar 26` axis ticks built by string split, and `-$4k` value ticks. A null-margin month maps to `null`, breaks the line into two sub-paths (asserted in jest), and exports as an empty CSV cell.
- Window selector using the shipped `DateRangeFilter` preset recipe with `aria-pressed`; a switch refetches only the trend, keeps the previous chart at `opacity-60` with `aria-busy="true"`, and the Pitfall-2 caption sits directly beneath it.
- Scope bullet bars consume `BulletBarChart` read-only (no `onRowClick`, default cursor) and always show `Scope spend excludes labor — labor is tracked at job level.`
- Category pie caps at six slices through the shipped `rollUpCategories`, sorts `Other` last, names the rolled-up categories in its tooltip, suppresses on-slice labels under 5%, and exports one row per real category.

## Task Commits

1. **Task 1: Drill-down shell, container and header states** — `4dea754` (feat)
2. **Task 2: MarginTrendChart and the window selector** — `0d90cbf` (feat)
3. **Task 3: ScopeBudgetBars and CategoryMixChart** — `433d340` (feat)

_TDD: each task wrote its failing spec first (module-not-found RED), then the implementation._

## Files Created/Modified

- `web/src/app/(dashboard)/financials/[projectId]/page.tsx` — `ssr:false` shell reading the id via `useParams`
- `web/src/app/(dashboard)/financials/[projectId]/_components/project-financials-dashboard.tsx` — the only hook owner; header, tiles, three chart cards, `isNotFoundError`
- `web/src/app/(dashboard)/financials/[projectId]/_components/margin-trend-chart.tsx` — `toTrendData`, `trendCsvRows`, `trendMonthsKpi`, `trendTooltipLabel`, the LineChart
- `web/src/app/(dashboard)/financials/[projectId]/_components/trend-window-filter.tsx` — four window buttons plus `TREND_WINDOW_NOTE`
- `web/src/app/(dashboard)/financials/[projectId]/_components/scope-budget-bars.tsx` — `toScopeBarRows`, `scopeBarsCsvRows`, `budgetedScopesKpi`, the labor caption
- `web/src/app/(dashboard)/financials/[projectId]/_components/category-mix-chart.tsx` — `toCategorySlices`, `sliceFills`, `categoryTooltipDetail`, `categoryMixCsvRows`, `categoryMixKpi`
- `web/src/app/(dashboard)/financials/__tests__/project-financials.test.tsx` — 36 tests covering state-matrix rows 21–34
- `web/src/features/finance/financials-format.ts` — `MONTH_ABBREVIATIONS` replaced by `MONTH_NAMES` + a shared `monthParts` splitter; `formatFullMonthLabel` added

## Decisions Made

- **`formatFullMonthLabel` lives in `financials-format.ts`.** The trend tooltip needs `March 2026` while the axis needs `Mar 26`. Declaring a second month table inside the chart would fork the one module that owns the never-`new Date()` rule, so both formatters now share a single `monthParts` splitter and the abbreviation is derived from the full name.
- **`isNotFoundError` reads the status code.** `ApiError` carries `status`, so the 404 branch is a code comparison — no message matching, and no `as` cast (the plan's acceptance criterion and CLAUDE.md's type-safety rule agree here).
- **Custom category fills come from a pool, not an index into a two-entry array.** `CUSTOM_CATEGORY_FILLS` has two hues, but a company with six custom categories and no system ones would exhaust it. `customFillPool` appends any system hue no slice claimed, so with the six-slice cap the ramp can never run out or repeat.
- **A failing trend query degrades to the empty state.** The trend has its own key and its own card; blanking the whole drill-down because one of two queries failed would hide the tiles, scopes and category mix that did load.
- **`connectNulls` appears only in a comment.** The false default *is* the contract; writing `connectNulls={false}` would present it as a tunable knob.

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 3 - Blocking] `formatFullMonthLabel` added to `financials-format.ts`**
- **Found during:** Task 2 (MarginTrendChart)
- **Issue:** The UI-SPEC requires the trend tooltip label to be the full month (`March 2026`). No shipped formatter produced it, and `financials-format.ts` is not in this plan's `files_modified` list.
- **Fix:** Replaced `MONTH_ABBREVIATIONS` with `MONTH_NAMES` plus a shared `monthParts` splitter, kept `formatMonthLabel` byte-identical in behavior, and added `formatFullMonthLabel`. The alternative — a second month table inside the chart file — would have duplicated the one piece of knowledge that keeps month labels off `new Date()`.
- **Files modified:** `web/src/features/finance/financials-format.ts`
- **Verification:** 35-03's `financials-format.test.ts` still green; full web suite 380/380
- **Committed in:** `0d90cbf` (Task 2 commit)

**2. [Rule 3 - Blocking] Chart cards wired card-by-card rather than all in Task 1**
- **Found during:** Task 1 (drill-down shell)
- **Issue:** Task 1's action describes the full layout including the trend and half-width cards, but those components are authored by Tasks 2 and 3. Importing them in Task 1 would have required stub files (dead code, CLAUDE.md).
- **Fix:** Task 1 shipped the header and tiles; Task 2 added the trend card; Task 3 added the scope and category cards — which is exactly what those tasks' own actions prescribe.
- **Files modified:** `project-financials-dashboard.tsx`
- **Verification:** Final layout matches the UI-SPEC page diagram; card wiring asserted in jest
- **Committed in:** `4dea754`, `0d90cbf`, `433d340`

---

**Total deviations:** 2 auto-fixed (2 blocking)
**Impact on plan:** Both were sequencing/DRY concerns rather than scope changes. No new dependency, no new UI surface, no change to 35-09's shared components.

## Issues Encountered

None. Every task's spec went RED then GREEN on the first implementation pass; `npm run lint` and `npx tsc --noEmit` were clean at every commit.

## Known Stubs

None — every rendered figure is wired to real query data. The Jest suite mocks the hooks layer by design (the backend trend endpoint shipped in parallel as 35-07).

## Contract Compliance

- `BulletBarChart` and every other file under `financials/_components/` consumed read-only: `git diff --name-only "web/src/app/(dashboard)/financials/_components/"` is empty.
- `FinanceSummaryTiles` reused with `Revenue`/`Cost`/`Margin` and neither `quotedRevenue` nor `incompleteProjectCount`; a null margin renders `—` tiles while Cost still renders `grandTotal`.
- `grep -rn "?? 0" "web/src/app/(dashboard)/financials/"` returns nothing.
- `grep -n "new Date(" margin-trend-chart.tsx` returns nothing; `parseFloat` occurs twice, both inside `toTrendData`.

## User Setup Required

None — no external service configuration required.

## Next Phase Readiness

- The drill-down is complete and consumes `GET /financials/projects/{id}` plus `/trend?window=` exactly as 35-06/35-07 serve them.
- Ready for the phase's Playwright keystone plan: every element the spec names carries its `data-testid` (`margin-trend-chart`, `trend-window-{3m,6m,12m,all}`, `trend-window-note`, `trend-no-revenue-note`, `scope-budget-bars`, `scope-labor-note`, `category-mix-chart`, `project-financials-not-found`, `financials-error`, `financials-skeleton`).

---
*Phase: 35-web-financial-dashboard*
*Completed: 2026-07-29*

## Self-Check: PASSED

All 8 key files verified on disk; all 3 task commits verified in git history.
