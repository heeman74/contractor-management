---
phase: 32-labor-rates-and-cost-rollup
plan: 04
subsystem: ui
tags: [react, nextjs, tanstack-query, playwright, jest, finance, cost-breakdown]

# Dependency graph
requires:
  - phase: 32-02
    provides: "GET /jobs/{id}/cost-breakdown and GET /trade-scopes/{id}/cost-breakdown endpoints; additively-extended project rollup (categories/labor/grand_total)"
  - phase: 32-03
    provides: "web/tests/phase-32-labor-rates.spec.ts login/proxy conventions; useAddLaborRate invalidating the cost-entries prefix"
  - phase: 31-03
    provides: "AddCostDialog, CostEntryList, ProjectCostsCard, and the three finance.view-gated Costs surfaces"
provides:
  - "Shared CostBreakdownSummary component (job / trade-scope / project variants) with fixed row order, hours-visible unrated badge, unburdened popover, and loading/error/empty states"
  - "CategoryTotal, LaborCostSummary, CostBreakdown types plus additively-extended ProjectCostRollup"
  - "fetchJobCostBreakdown / fetchTradeScopeCostBreakdown mappers and useJobCostBreakdown / useTradeScopeCostBreakdown hooks keyed under the cost-entries invalidation prefix"
  - "AddCostDialog labor-category filter (UI half of the Pitfall 1 guard)"
  - "Project Total Spent prefers grand_total (all-in) with cost-entry fallback"
affects: [33-margin, 34-budgeting, 35-dashboard, 36-ai-profitability]

# Tech tracking
tech-stack:
  added: []
  patterns:
    - "Breakdown queries keyed [\"cost-entries\", \"breakdown\", ...] so invalidateAllCostEntries refreshes them after cost writes and rate appends"
    - "Info affordance via base-ui popover.tsx (no tooltip component exists; PopoverTrigger renders the button itself, no asChild)"
    - "Playwright job-detail navigation: login through UI, then SPA-navigate Jobs list row click (direct goto leaves Redux isAuthenticated false, so permission-gated cards never render)"

key-files:
  created:
    - web/src/features/finance/components/CostBreakdownSummary.tsx
    - web/src/features/finance/__tests__/cost-breakdown-summary.test.tsx
  modified:
    - web/src/features/finance/types.ts
    - web/src/features/finance/api.ts
    - web/src/features/finance/hooks.ts
    - web/src/features/finance/components/ProjectCostsCard.tsx
    - web/src/features/finance/components/AddCostDialog.tsx
    - web/src/app/(dashboard)/jobs/[id]/page.tsx
    - web/src/app/(dashboard)/projects/components/TradeScopeDetail.tsx
    - web/src/app/(dashboard)/projects/components/__tests__/trade-scope-detail.test.tsx
    - web/tests/phase-32-labor-rates.spec.ts

key-decisions:
  - "Playwright job-detail tests log in through the UI and SPA-navigate via the Jobs list row (not direct page.goto) — Redux isAuthenticated is set only by the login page, so direct navigation leaves usePermissions disabled and finance-gated cards hidden"
  - "Playwright picker mock uses Title Case category names (Labor/Materials/...) so option-text assertions are exact; AddCostDialog filter matches case-insensitively"
  - "orderedCategories filters the reserved labor name so a legacy labor-categorized API row can never render a second Labor row"

patterns-established:
  - "CostBreakdownSummary variants: job/project render the labor row always; trade-scope renders the Tracked-at-job-level note with no amount, no badge, no popover"
  - "Empty suppression: no categories + zero grand total + zero unrated seconds renders nothing (existing empty state below covers it)"

requirements-completed: [COST-06]

# Metrics
duration: 45min
completed: 2026-07-27
---

# Phase 32 Plan 04: Web Cost Breakdown Surfaces Summary

**Shared CostBreakdownSummary mounted on job, trade-scope, and project Costs surfaces with hours-visible unrated badge, unburdened-labor popover, all-in project Total Spent, and the Labor category removed from the add-cost picker**

## Performance

- **Duration:** ~45 min active (split across two sessions by a session-limit pause; started 2026-07-27T05:06:13Z, completed 2026-07-27T15:40:11Z wall clock)
- **Tasks:** 2 (Task 1 TDD: RED + GREEN)
- **Files modified:** 11

## Accomplishments

- COST-06 on web: category totals (Labor, Materials, Subcontractor, Other, customs) plus a Total row now render inside all three existing finance.view-gated Costs surfaces
- D-05 honored: unrated time renders as "{H} hrs unrated" (singular/decimal rules covered by unit tests) — never a silent $0
- D-06 honored: every labor figure carries the Info popover disclosing "Wage cost only — excludes payroll tax, insurance, overhead."
- D-08 honored: trade-scope labor row reads "Tracked at job level" — no $0, no omitted row
- Pitfall 1 UI half closed: the reserved Labor category is filtered from AddCostDialog, so the backend 422 guard is unreachable from the UI
- Project "Total Spent" now shows the all-in grand total when available, falling back to the cost-entry total for older backends

## Task Commits

1. **Task 1 (RED): failing Jest tests** - `038a903` (test)
2. **Task 1 (GREEN): types/api/hooks + CostBreakdownSummary** - `f52f296` (feat) — 19 Jest tests green
3. **Task 2: three mount points, picker filter, Playwright coverage** - `3c32820` (feat)

## Files Created/Modified

- `web/src/features/finance/components/CostBreakdownSummary.tsx` - Shared component + exported pure helpers (formatUnratedHours, orderedCategories, isBreakdownEmpty, displayCategoryName)
- `web/src/features/finance/__tests__/cost-breakdown-summary.test.tsx` - 19 tests over rendering behaviors and helper units
- `web/src/features/finance/types.ts` - CategoryTotal/LaborCostSummary/CostBreakdown; ProjectCostRollup extended additively
- `web/src/features/finance/api.ts` - Breakdown response shapes, mappers, fetchers; rollup mapping carries the new optional fields
- `web/src/features/finance/hooks.ts` - useJobCostBreakdown/useTradeScopeCostBreakdown under the cost-entries prefix
- `web/src/features/finance/components/ProjectCostsCard.tsx` - Breakdown block + grand-total-preferring Total Spent (data-testid preserved)
- `web/src/features/finance/components/AddCostDialog.tsx` - selectableCategories filter (labor removed)
- `web/src/app/(dashboard)/jobs/[id]/page.tsx` - Breakdown above CostEntryList in the Costs card
- `web/src/app/(dashboard)/projects/components/TradeScopeDetail.tsx` - trade-scope variant above the entry list
- `web/tests/phase-32-labor-rates.spec.ts` - 5 new cost-breakdown E2E tests (10 total in the file, all green)

## Decisions Made

- Playwright job-detail tests must log in through the UI then SPA-navigate (Jobs list row click): Redux `isAuthenticated` is only set by the login page dispatch, so `page.goto("/jobs/{id}")` leaves `usePermissions` disabled and the gated Costs card never renders
- Picker mock categories use Title Case names, matching Phase 31 conventions, so the "Labor option absent" assertion is exact while the filter matches case-insensitively

## Deviations from Plan

None - plan executed exactly as written.

## Issues Encountered

- Full Playwright suite has 2 pre-existing failures (`ai-intake.spec.ts`, `ai-interview.spec.ts`) asserting the old `/projects/{id}` URL; the project-preselect refactor (`413804d`) moved navigation to `/projects?project={id}` before this plan. Out of scope — logged in `deferred-items.md`. All 151 other tests pass, including all Phase 31 cost-capture and Phase 32 specs.

## Known Stubs

None — all three surfaces are wired to live breakdown endpoints (project variant reads the extended rollup; older backends fall back to the unchanged cost-entry total).

## User Setup Required

None - no external service configuration required.

## Next Phase Readiness

- Web COST-06 complete; 32-05 (mobile breakdown widget) is the remaining plan for Phase 32
- Breakdown query keys sit under the cost-entries prefix, so Phase 33 margin work can reuse the same invalidation path

## Self-Check: PASSED

All key files exist on disk and all three task commits (`038a903`, `f52f296`, `3c32820`) are in history.

---
*Phase: 32-labor-rates-and-cost-rollup*
*Completed: 2026-07-27*
