---
phase: 35-web-financial-dashboard
plan: 09
subsystem: ui
tags: [nextjs, react, recharts, tanstack-query, jest, financial-dashboard]

# Dependency graph
requires:
  - phase: 35-03
    provides: FinanceGate + financials layout, chart-theme constants, ChartEmptyState, financials-format helpers, FinancialsSkeleton
  - phase: 35-04
    provides: useCompanyFinancials hook, CompanyFinancials/ProjectFinancialsRow/AttentionRow types, INACTIVE_PROJECT_STATUSES
  - phase: 35-05
    provides: GET /api/v1/financials/company (the endpoint the hook calls at runtime)
provides:
  - "/financials route shell (dynamic ssr:false) with the company skeleton fallback"
  - "CompanyFinancialsDashboard — the route's single hook owner and inline error surface"
  - "FinanceSummaryTiles — one tile trio for both financial routes, portfolio props optional"
  - "BulletBarChart — reusable, name-agnostic bullet-bar form (testId/label driven)"
  - "ProjectBudgetBars — company wrapper: row mapping, unbudgeted caption, KPI, CSV"
  - "AttentionList — server-ordered tier list with badges, anchors and CSV"
  - "ProjectsTable — full inventory grouped by activity below the honesty separator"
affects: [35-10, 35-11, 36]

# Tech tracking
tech-stack:
  added: []
  patterns:
    - "Presentational finance components take already-parsed props; one container owns the hook"
    - "Recharts in jest: ResponsiveContainer mocked to a fixed box exposing the computed plot height"
    - "Bar charts render with isAnimationActive={false} so geometry is deterministic on every refetch"

key-files:
  created:
    - "web/src/app/(dashboard)/financials/page.tsx"
    - "web/src/app/(dashboard)/financials/_components/company-financials-dashboard.tsx"
    - "web/src/app/(dashboard)/financials/_components/finance-summary-tiles.tsx"
    - "web/src/app/(dashboard)/financials/_components/bullet-bar-chart.tsx"
    - "web/src/app/(dashboard)/financials/_components/project-budget-bars.tsx"
    - "web/src/app/(dashboard)/financials/_components/attention-list.tsx"
    - "web/src/app/(dashboard)/financials/_components/projects-table.tsx"
    - "web/src/app/(dashboard)/financials/__tests__/company-financials.test.tsx"
  modified:
    - "web/src/components/shared/chart-theme.ts"
    - "web/src/features/finance/components/BudgetSummarySection.tsx"

key-decisions:
  - "BulletBarRow carries `remaining` alongside `percentUsed` so the shipped budgetTierFill decides the band — the chart never re-derives it"
  - "The incomplete-data chip IS the anchor element: one <a> carrying the shipped chip class, so the count and the rows it counts share one testid"
  - "Bars render with isAnimationActive={false}: deterministic in jsdom, and no zero-to-value replay on every cost-write invalidation"
  - "NEARING_BUDGET_CHIP_LABEL exported from BudgetSummarySection so the warning band cannot carry two names across finance surfaces"
  - "The clamp overflow fill and the bullet reference stroke live in chart-theme, not inline in the chart"

patterns-established:
  - "Generic chart + thin domain wrapper: the chart knows rows, the wrapper knows what a row names"
  - "CSV builders and KPI strings are exported pure functions from the component module the card renders"

requirements-completed: [MARG-04]

# Metrics
duration: 25min
completed: 2026-07-29
---

# Phase 35 Plan 09: Company Financials Overview Summary

**`/financials` renders portfolio tiles, sorted budget-vs-actual bullet bars with marked 200%+ overruns, the server-ordered attention list and the full projects table from a single `useCompanyFinancials` call — 38 jest tests covering the UI-SPEC honesty states.**

## Performance

- **Duration:** 25 min
- **Started:** 2026-07-29T03:41:00Z
- **Completed:** 2026-07-29T04:06:00Z
- **Tasks:** 3 (TDD: 6 commits)
- **Files modified:** 10 (8 created, 2 modified)

## Accomplishments

- The route ships end to end: `page.tsx` (dynamic `ssr:false`) → `CompanyFinancialsDashboard` (the only hook owner) → five pure presentational components.
- `BulletBarChart` is genuinely reusable: `data-testid={testId}`, `dataKey="label"`, `labelFormatter` via `rowLabelFor(value, rows)`, and a verified-empty `grep -in "project"` — 35-10 can pass `testId="scope-budget-bars"` unchanged.
- Extreme overruns clamp geometry only: a 340%-spent budget reaches the axis edge and carries `▸ 340%` (`budget-bar-overflow-{projectId}`), while the tooltip, table and CSV keep the true percent.
- Honesty surfaces are all wired: the incomplete-data chip anchors to `#attention-list`, the unbudgeted caption names what the chart omits, and inactive projects are dimmed (bars at 0.45 opacity, table rows below the separator) but never dropped from a total.

## Task Commits

1. **Task 1: Page shell, dashboard container and FinanceSummaryTiles** — `4ee75db` (test) → `765edd2` (feat)
2. **Task 2: Shared BulletBarChart + ProjectBudgetBars** — `e9a3998` (test) → `52be333` (feat)
3. **Task 3: AttentionList and the All Projects table** — `6955e68` (test) → `0edf9c4` (feat)

## Files Created/Modified

- `web/src/app/(dashboard)/financials/page.tsx` — Route shell, `dynamic(ssr:false)` with the company skeleton fallback
- `web/src/app/(dashboard)/financials/_components/company-financials-dashboard.tsx` — Single hook owner; loading → skeleton, error → inline panel, success → tiles + chart pair + table
- `web/src/app/(dashboard)/financials/_components/finance-summary-tiles.tsx` — Shared tile trio; `basisCaption` / `incompleteBadgeLabel` keep pluralisation and basis copy in one place
- `web/src/app/(dashboard)/financials/_components/bullet-bar-chart.tsx` — Generic bullet-bar form: tier fills, inactive opacity, 100% reference line, clamp overflow labels
- `web/src/app/(dashboard)/financials/_components/project-budget-bars.tsx` — `toBudgetBarRows` (the only `parseFloat` site), `budgetBarsCsvRows`, `budgetedProjectsKpi`, unbudgeted caption, row click → drill-down
- `web/src/app/(dashboard)/financials/_components/attention-list.tsx` — `TIER_BADGE` map, `attentionKpi`, `attentionCsvRows`; renders server order with no sort and no filter
- `web/src/app/(dashboard)/financials/_components/projects-table.tsx` — `groupProjectsByActivity`, the D-12 separator row, `text-red-800` negative cells, `No budget` / `—` cell rules
- `web/src/app/(dashboard)/financials/__tests__/company-financials.test.tsx` — 38 tests across UI-SPEC states 4–20
- `web/src/components/shared/chart-theme.ts` — Added `BULLET_REFERENCE_STROKE` and `OVERFLOW_LABEL_FILL`
- `web/src/features/finance/components/BudgetSummarySection.tsx` — Exported `NEARING_BUDGET_CHIP_LABEL`

## Decisions Made

- **`BulletBarRow.remaining` added to the plan's interface.** `budgetTierFill(row)` is typed on `Pick<BudgetVsActual, "percentUsed" | "remaining">`; without `remaining` the plan's own `fill={budgetTierFill(row)}` would not compile, and the alternative (a precomputed fill on the row) would move the band rule out of the shipped helper. The exactly-100% case is asserted.
- **The axis domain reads `percentUsedClamped`, never `parseFloat`.** `axisMaxDomain` clamps at 200 anyway, so the clamped numbers give an identical domain while keeping the chart free of money parsing (acceptance criterion).
- **`isAnimationActive={false}` on the bar.** Recharts renders no rectangle path until its animation starts, which makes tier fills untestable in jsdom; it also stops every cost-write invalidation replaying a grow-from-zero animation past the budget line.
- **The chip is the anchor.** `<a href="#attention-list">` carries `FINANCE_FLAG_CHIP_CLASS` directly instead of wrapping a `FinanceFlagChip`, so the badge has exactly one testid and one accessible name.
- **`grep`-literal strings where an acceptance criterion demands them** (`href="#attention-list"`, `id="attention-list"`), each used once at its single call site and commented.

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 3 - Blocking] `BulletBarRow` extended with `remaining`**
- **Found during:** Task 2 (BulletBarChart)
- **Issue:** The plan's `<Cell fill={budgetTierFill(row)} />` does not typecheck against the plan's own `BulletBarRow`, which carries no `remaining`.
- **Fix:** Added `remaining: string` to the interface and populated it in `toBudgetBarRow`, keeping the band decision inside the shipped `budgetTierFill`.
- **Files modified:** `bullet-bar-chart.tsx`, `project-budget-bars.tsx`
- **Verification:** `npx tsc --noEmit` clean; the "exactly 100% is not amber" test passes.
- **Committed in:** `52be333`

**2. [Rule 3 - Blocking] Two chart hexes added to `chart-theme.ts`**
- **Found during:** Task 2 (BulletBarChart)
- **Issue:** The plan inlines `stroke="#0e1726"` and the `#991b1b` overflow label colour, which contradicts CLAUDE.md's no-magic-values rule and chart-theme's stated role as the single home for chart colour.
- **Fix:** Exported `BULLET_REFERENCE_STROKE` and `OVERFLOW_LABEL_FILL` from `chart-theme.ts` and imported both. No value changed; both are already-shipped Job Ticket / Tailwind steps.
- **Files modified:** `web/src/components/shared/chart-theme.ts`, `bullet-bar-chart.tsx`
- **Verification:** `npm run lint` at `--max-warnings 0`, full jest suite green (344 tests).
- **Committed in:** `52be333`

**3. [Rule 2 - Missing Critical] `NEARING_BUDGET_CHIP_LABEL` exported**
- **Found during:** Task 3 (AttentionList)
- **Issue:** The UI-SPEC requires the `Nearing budget` badge to be byte-identical to the shipped Phase 34 chip, but the constant was module-private in `BudgetSummarySection.tsx`, so the plan's only option was to retype the string.
- **Fix:** Added `export` (one keyword, no behaviour change) and imported it into `TIER_BADGE`.
- **Files modified:** `web/src/features/finance/components/BudgetSummarySection.tsx`, `attention-list.tsx`
- **Verification:** `src/features/finance` jest suite green (134 tests); the tier-badge test asserts the label and the shipped chip class.
- **Committed in:** `0edf9c4`

---

**Total deviations:** 3 auto-fixed (2 blocking, 1 missing critical)
**Impact on plan:** All three are contract-preserving — two make the plan's own snippets compile/lint, one removes a copy-drift risk the UI-SPEC explicitly forbids. No scope added.

## Issues Encountered

- **Recharts renders nothing measurable in jsdom.** Solved by mocking `ResponsiveContainer` to a fixed 800px box that also exposes the computed plot height via `data-height` — which turned the 28px-row geometry contract into a real assertion (40 rows → 1156px) instead of an untested claim.
- **Recharts 3 renders axis tick text into a shared layer**, not inside the `.recharts-xAxis` / `.recharts-yAxis` groups, so descendant selectors returned nothing. Test helpers now split ticks by content (percentages vs names).

## User Setup Required

None - no external service configuration required.

## Next Phase Readiness

- `BulletBarChart` is ready for 35-10 to consume read-only with `testId="scope-budget-bars"`; `FinanceSummaryTiles` is ready for the drill-down with `margin` nullable and both portfolio props omitted (both paths are covered by tests here).
- Verification run: `npx jest` (344 passed, 33 suites), `npx tsc --noEmit` clean, `npm run lint` clean at `--max-warnings 0`, `npx playwright test tests/phase-18-reports.spec.ts` 18/18 passed — Reports untouched.
- No stubs: every rendered figure is wired to `useCompanyFinancials` data. `/financials/[projectId]` links resolve once 35-10 ships the drill-down route.

---
*Phase: 35-web-financial-dashboard*
*Completed: 2026-07-29*

## Self-Check: PASSED

All 8 created files exist on disk; all 6 task commits resolve in `git log`.
