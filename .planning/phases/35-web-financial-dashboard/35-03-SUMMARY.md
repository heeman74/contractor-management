---
phase: 35-web-financial-dashboard
plan: 03
subsystem: ui
tags: [react, nextjs, recharts, typescript, finance, rbac, jest]

# Dependency graph
requires:
  - phase: 35-web-financial-dashboard
    provides: FINANCE_VIEW_PERMISSION and the finance response types (plan 35-04)
  - phase: 30-financial-foundation
    provides: finance.view RBAC key and usePermissions().can()
  - phase: 33-margin-visibility
    provides: INCOMPLETE_CHIP_LABEL / INCOMPLETE_CAPTION / NO_REVENUE_NOTE honesty copy
  - phase: 34-budgeting-and-alerts
    provides: BudgetVsActual (percentUsed / remaining band inputs)
provides:
  - FinanceGate + FINANCE_DENY_MESSAGE, mounted once at financials/layout.tsx for both routes
  - chart-theme.ts — tooltip style, tier fills, category ramp, trend series, bullet/axis geometry
  - ChartEmptyState shared two-line empty state
  - financials-format.ts — formatMonthLabel, formatAxisThousands, truncateLabel,
    clampPercentForAxis, axisMaxDomain, budgetTierFill, rollUpCategories, bulletChartHeight
  - FinancialsSkeleton (company and drill-down variants)
  - finance.view-gated Financials sidebar entry
  - INCOMPLETE_CHIP_LABEL / INCOMPLETE_CAPTION / NO_REVENUE_NOTE exported from MarginSummarySection
affects: [35-05, 35-06, 35-07, 35-08, 35-09, 35-10, 35-11]

# Tech tracking
tech-stack:
  added: []
  patterns:
    - "Chart chrome lives in one module: no chart file re-types a hex, a row height or an axis bound"
    - "Permission gate mounted at the route-group layout, not repeated per page"
    - "Chart geometry is pure and unit-tested without React; rendered figures still format from backend strings"

key-files:
  created:
    - web/src/components/shared/chart-theme.ts
    - web/src/components/shared/chart-empty-state.tsx
    - web/src/features/finance/financials-format.ts
    - web/src/features/finance/components/FinanceGate.tsx
    - web/src/app/(dashboard)/financials/layout.tsx
    - web/src/app/(dashboard)/financials/_components/financials-skeleton.tsx
    - web/src/features/finance/__tests__/financials-format.test.ts
    - web/src/features/finance/__tests__/finance-gate.test.tsx
  modified:
    - web/src/components/layout/sidebar.tsx
    - web/src/features/finance/components/MarginSummarySection.tsx

key-decisions:
  - "FinanceGate imports FINANCE_VIEW_PERMISSION from types.ts and never inlines the key, so the render branch and the hooks' enabled branch fail closed on exactly the same string"
  - "truncateLabel returns a string of total length LABEL_TRUNCATE_LENGTH (21 chars + ellipsis), following the UI-SPEC formula rather than the plan prose's 22+ellipsis reading"
  - "bulletChartHeight's 36px axis allowance is a named constant (BULLET_CHART_AXIS_PADDING) in chart-theme.ts — no magic literal survives at the call site"
  - "rollUpCategories takes numeric amounts because the Other bucket is a genuine sum; every unrolled category still exports its own backend string row"
  - "The skeleton's chart-card body is one local helper with per-block test ids, so variant card counts are assertable without duplicating JSX"

patterns-established:
  - "Route-group layout as the single permission mount: one gate component guards every route beneath it"
  - "Named test ids on skeleton blocks (tile / chart-card / table) so loading layout differences are unit-testable"

requirements-completed: [MARG-04]

# Metrics
duration: 27 min
completed: 2026-07-29
---

# Phase 35 Plan 03: Financial Dashboard Foundation Summary

**One `FinanceGate` mounted at `financials/layout.tsx` guards both financial routes with the shipped deny recipe, backed by a single-source `chart-theme.ts` (tooltip style, three-band tier fills, nominal category ramp, bullet geometry) and eight pure, unit-tested formatters that clamp percent axes, roll a pie down to six slices and label months without ever constructing a `Date`.**

## Performance

- **Duration:** 27 min
- **Started:** 2026-07-29T03:05:46Z
- **Completed:** 2026-07-29T03:33:25Z
- **Tasks:** 3 (two TDD)
- **Files modified:** 10 (8 created, 2 modified)

## Accomplishments

- **`FinanceGate` extracted and mounted once.** The loading-pulse → deny-panel → children recipe existed twice already (`contracts/page.tsx`, `settings/roles/page.tsx`); this is the third occurrence, extracted per CLAUDE.md DRY with the deny panel's classes reproduced byte-for-byte. Mounting it at `app/(dashboard)/financials/layout.tsx` means `/financials` and `/financials/[projectId]` share one guard — neither page plan can ship its own.
- **`chart-theme.ts` is the only place a chart constant is spelled.** 21 exported constants cover the tooltip `contentStyle` (which the three shipped Reports charts each carry a copy of — there is now no fourth copy), the `BUDGET_TIER_FILL` three-band map, the six-hue `CATEGORY_FILL` ramp plus the two custom fills, `TREND_SERIES` stroke/width/dash, and every geometry value (`BULLET_ROW_HEIGHT`, `BULLET_BAR_SIZE`, `BULLET_AXIS_WIDTH`, `CHART_HEIGHT`, `PERCENT_AXIS_CLAMP`, `PERCENT_AXIS_FLOOR`, `MAX_PIE_SLICES`, `LABEL_TRUNCATE_LENGTH`).
- **`financials-format.ts` — eight pure functions, 20 unit tests.** `formatMonthLabel` splits `"YYYY-MM"` against a local abbreviation table so a date-only string can never shift a month across timezones (the 32-03 lesson); `formatAxisThousands` puts the sign before the symbol (`-$4k`, not `$-4k`); `budgetTierFill` requires `remaining > 0` for the amber band so a budget spent to exactly 100% is not painted as "nearing"; `bulletChartHeight` has no ceiling, so 40 projects grow the plot rather than compressing rows.
- **`rollUpCategories` caps the pie at six slices** by folding the smallest categories into the existing `Other` entry, recording their names on it for the tooltip, and sorting it last however large it grows.
- **Gated `Financials` nav entry** sits immediately after Reports with `permission: "finance.view"`; the shipped filter hides it, and `can()` is false while loading so it never flashes in.
- **Phase 33 honesty copy is now importable** — the dashboard reuses `INCOMPLETE_CHIP_LABEL`, `INCOMPLETE_CAPTION` and `NO_REVENUE_NOTE` byte-for-byte instead of forking a second wording for the same condition.

## Task Commits

1. **Task 1: chart theme, empty state and formatters** — `69f8657` (test, RED) → `e79a29f` (feat, GREEN)
2. **Task 2: FinanceGate, layout mount, FinancialsSkeleton** — `c125a99` (test, RED) → `1382df9` (feat, GREEN)
3. **Task 3: gated nav item and exported honesty copy** — `5cd6024` (feat)

_No refactor commits were needed: both GREEN implementations landed within the clean-code budget (every function under 20 lines, one responsibility each)._

## Files Created/Modified

- `web/src/components/shared/chart-theme.ts` — 21 chart constants; the single home for chrome, colour bands and geometry
- `web/src/components/shared/chart-empty-state.tsx` — `ChartEmptyState({ heading, body })`, `role="status"`, markup identical to the Reports local `EmptyState`
- `web/src/features/finance/financials-format.ts` — the eight pure formatters/geometry helpers plus `CategoryAmount` / `CategorySlice`
- `web/src/features/finance/components/FinanceGate.tsx` — the permission gate and `FINANCE_DENY_MESSAGE`
- `web/src/app/(dashboard)/financials/layout.tsx` — mounts the gate for both financial routes
- `web/src/app/(dashboard)/financials/_components/financials-skeleton.tsx` — `FinancialsSkeleton({ variant })`, company vs drill-down card counts
- `web/src/features/finance/__tests__/financials-format.test.ts` — 20 tests, one per behavior contract plus edges
- `web/src/features/finance/__tests__/finance-gate.test.tsx` — 6 tests: three gate branches, the permission-key assertion, both skeleton variants
- `web/src/components/layout/sidebar.tsx` — `Wallet` import + the gated `Financials` entry after Reports
- `web/src/features/finance/components/MarginSummarySection.tsx` — three copy constants exported (6 changed lines, component body untouched)

## Decisions Made

- **`truncateLabel` follows the UI-SPEC formula, not the plan prose.** The plan's behavior line reads "caps at 22 characters plus `…`" while 35-UI-SPEC § Chart 1 locks `name.slice(0, 21) + "…"`. The UI-SPEC formula wins (it is the sized-against-`width={160}` contract), so the returned string is exactly `LABEL_TRUNCATE_LENGTH` characters including the ellipsis. Both readings agree that a 22-character name is returned unchanged, which is the case the test pins.
- **`BULLET_CHART_AXIS_PADDING = 36` was added to `chart-theme.ts`** rather than left as a literal `+ 36` inside `bulletChartHeight`. The plan's constant list omitted it, but leaving it inline would have been the one magic number in a module whose whole purpose is that there are none.
- **`rollUpCategories` operates on numbers, not decimal strings.** The `Other` bucket is a real sum, so it cannot be a verbatim backend string; every other slice keeps its own amount and the CSV (a later plan) still exports one unrolled row per category, per the UI-SPEC honesty requirement.
- **Skeleton blocks carry test ids** (`financials-skeleton-tile` / `-chart-card` / `-table`) so the two variants' card counts are assertable. The wrapper id `financials-skeleton` is the contract from § Test Hooks; the block-level ids are additive.

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 3 - Blocking] Two acceptance-criteria greps matched their own explanatory comments**

- **Found during:** Tasks 1 and 2 (acceptance verification)
- **Issue:** `grep -n "new Date(" financials-format.ts` matched a docstring that said "Never `new Date("2026-03")`", and `grep -n "ReportsSkeleton" financials-skeleton.tsx` matched the comment explaining why it is not imported. Both criteria demand zero matches — a grep-based criterion cannot distinguish a comment from a call site, so the criteria would have failed on prose alone.
- **Fix:** Reworded both comments to state the same WHY without naming the forbidden symbol ("A Date is never constructed…", "The Reports page's own skeleton is deliberately not reused…").
- **Files modified:** `web/src/features/finance/financials-format.ts`, `web/src/app/(dashboard)/financials/_components/financials-skeleton.tsx`
- **Verification:** Both greps now exit 1 (no matches); jest still green on both suites.
- **Committed in:** `e79a29f`, `1382df9` (part of the task commits)

**2. [Rule 3 - Blocking] Honesty-copy WHY comment moved onto an existing line**

- **Found during:** Task 3
- **Issue:** The action asks for a one-line WHY comment on the exported constants, but the acceptance criterion caps the file's diff at 6 changed lines — and three `export` keywords already consume exactly 6 (3 insertions + 3 deletions). A standalone comment line would have made it 7.
- **Fix:** Attached the WHY as a trailing comment on the first exported constant. Both requirements hold: the comment exists, the diff is exactly `3 insertions(+), 3 deletions(-)`, and the component body is untouched.
- **Files modified:** `web/src/features/finance/components/MarginSummarySection.tsx`
- **Verification:** `git diff --stat` reported 6 changed lines; `npx jest src/features/finance` all green including the shipped `margin-summary-section.test.tsx`.
- **Committed in:** `5cd6024`

---

**Total deviations:** 2 auto-fixed (2 blocking)
**Impact on plan:** Both were criterion-vs-prose conflicts, resolved without changing any behavior. No scope creep; no functional code differs from the plan.

## Issues Encountered

- **One Reports Playwright test flaked under parallel workers.** `phase-18-reports.spec.ts` reported 17/18 with "preset buttons toggle aria-pressed and refetch" timing out on `[aria-label="Revenue by Month chart"]`. Re-run in isolation it passes in 18.1s — the failure is the Next dev server's cold compile of `/reports` racing the 5s visibility timeout while other workers compile the same route, not a regression. This plan touches no Reports source (the D-06 boundary holds: `ChartEmptyState` was created alongside, never folded into `reports-dashboard.tsx`).
- **Backend files appear modified in `git status`** (`backend/app/features/finance/*`) — those belong to the concurrent parallel executor and were never staged here. Every commit in this plan staged only its own `web/` paths.

## Known Stubs

None. Every file this plan ships is fully wired: the gate reads live permissions, the formatters are pure and exercised by 26 unit tests, and the nav entry is filtered by the shipped permission logic. The `/financials` route directory currently holds only `layout.tsx` and the skeleton — the pages themselves are plans 35-05 and 35-06, which is the planned wave order, not a stub.

## User Setup Required

None - no external service configuration required.

## Next Phase Readiness

- **Ready for 35-05 / 35-06** (the company overview and drill-down pages): the gate, layout mount, skeleton, chart constants, empty state and formatters they compose all exist and are tested.
- **Contract for downstream plans:** import chart values from `@/components/shared/chart-theme`, geometry/format helpers from `@/features/finance/financials-format`, and the honesty strings from `MarginSummarySection` — no chart hex, tooltip style, row height, axis bound, slice cap or honesty string may be re-typed at a call site.
- **No blockers.** The Reports Playwright flake is environmental (dev-server cold compile) and unrelated to this plan's surface.

## Self-Check: PASSED

All 8 created files verified present on disk; all 5 task commits (`69f8657`, `e79a29f`, `c125a99`, `1382df9`, `5cd6024`) verified in the git log.

---
*Phase: 35-web-financial-dashboard*
*Completed: 2026-07-29*
