---
phase: 36-ai-profitability-analysis
plan: 02
subsystem: ui
tags: [react, tanstack-query, typescript, jest, rbac, finance]

# Dependency graph
requires:
  - phase: 35-web-financial-dashboard
    provides: "financials hooks/api/types, FinanceGate, FINANCE_VIEW_PERMISSION, financials-format month splitters, FinanceFlagChip"
  - phase: 33-margin-and-honesty-flags
    provides: "FinanceFlagChip amber recipe, CostBreakdownSummary unburdened-labor caption"
provides:
  - "ProfitabilityFinding + FindingSeverity types matching the 36-UI-SPEC response contract"
  - "fetchProjectProfitabilityFinding with snake_case mapper, null = no open finding"
  - "useProjectProfitabilityFinding, permission-gated via enabled, keyed under the cost-entries prefix"
  - "formatFindingDate — YYYY-MM-DD to 'Jul 29, 2026' with no Date construction"
  - "FINANCE_ALERT_CHIP_CLASS exported once, consumed by attention-list"
  - "QUOTED_BASIS_CAPTION / UNBURDENED_TITLE / UNBURDENED_BODY promoted to exports"
affects: [36-04 profitability-finding-card, 36-05 dashboard mount, 36-06 playwright SC2]

# Tech tracking
tech-stack:
  added: []
  patterns:
    - "Hook-level enabled gate as the fetch-side half of a permission gate, proven by a zero-request test"
    - "Date-only strings formatted by string splitting, never by constructing a Date"
    - "Shipped class strings and copy promoted to exports rather than retyped at a second call site"

key-files:
  created: []
  modified:
    - web/src/features/finance/types.ts
    - web/src/features/finance/api.ts
    - web/src/features/finance/hooks.ts
    - web/src/features/finance/financials-format.ts
    - web/src/features/finance/components/FinanceFlagChip.tsx
    - web/src/features/finance/components/CostBreakdownSummary.tsx
    - web/src/app/(dashboard)/financials/_components/attention-list.tsx
    - web/src/app/(dashboard)/financials/_components/finance-summary-tiles.tsx
    - web/src/features/finance/__tests__/financials-hooks.test.tsx

key-decisions:
  - "Finding hook tests mock apiGet (the HTTP layer) instead of the api module fetcher, because the plan's own behavior contract demands asserting the request path and the snake_case mapping — neither is observable through a module-boundary mock"
  - "The zero-request assertion was verified load-bearing by mutation: deleting the enabled gate makes it fail with exactly one request to the finding path"
  - "dayParts validates the day as an integer in 1..31 so a malformed triple returns the input unchanged rather than a wrong date"

patterns-established:
  - "Mutation-verified permission gates: a zero-request test is only trusted after the gate is removed and the test observed to fail"

requirements-completed: [FINAI-02]

# Metrics
duration: 15min
completed: 2026-07-29
---

# Phase 36 Plan 02: Finding Data Layer Summary

**Permission-gated `useProjectProfitabilityFinding` over a snake_case-mapping fetcher, plus `formatFindingDate` and the three shipped-string extractions the finding card composes from.**

## Performance

- **Duration:** 15 min
- **Started:** 2026-07-29T18:30:30Z
- **Completed:** 2026-07-29T18:45:11Z
- **Tasks:** 3
- **Files modified:** 9

## Accomplishments

- `ProfitabilityFinding` / `FindingSeverity` match the 36-UI-SPEC response contract exactly, with `alertSummary` deliberately absent (nothing renders it).
- `fetchProjectProfitabilityFinding` reuses the shipped `projectFinancialsPath` helper and returns `null` for "no open finding" — its own key, its own failure surface, never folded into `fetchProjectFinancials`.
- `useProjectProfitabilityFinding` carries `enabled: can(FINANCE_VIEW_PERMISSION) && !!projectId` — the fetch-side half of the SC2 keystone — under the shared `["cost-entries", …]` prefix so `invalidateAllCostEntries` refreshes it for free.
- `formatFindingDate` ships in the one never-`new Date()` module, beside the shipped month splitters.
- `FINANCE_ALERT_CHIP_CLASS` now exists in exactly one module; `attention-list.tsx` imports it and both `OVER_BUDGET_BADGE_CLASS` and the orphaned `BADGE_BASE_CLASS` are gone.
- The 134 shipped Phase 35 / finance tests stayed green through the chip extraction — confirmed by running the suite, not by assuming byte equality.

## Task Commits

1. **Task 1: ProfitabilityFinding type, fetcher + mapper, permission-gated hook** — `9feb04c` (feat)
2. **Task 2: formatFindingDate + the three shipped-string extractions** — `8847269` (feat)
3. **Task 3: Hook + formatter unit tests** — `0d764f1` (test)

## Files Created/Modified

- `web/src/features/finance/types.ts` — `FindingSeverity`, `ProfitabilityFinding`
- `web/src/features/finance/api.ts` — `ProfitabilityFindingApiResponse`, `mapProfitabilityFinding`, `fetchProjectProfitabilityFinding`
- `web/src/features/finance/hooks.ts` — `useProjectProfitabilityFinding` with the `enabled` gate and its why-docstring
- `web/src/features/finance/financials-format.ts` — `dayParts` splitter + `formatFindingDate`
- `web/src/features/finance/components/FinanceFlagChip.tsx` — `FINANCE_ALERT_CHIP_CLASS` beside the amber recipe
- `web/src/features/finance/components/CostBreakdownSummary.tsx` — `UNBURDENED_TITLE` / `UNBURDENED_BODY` promoted to exports, values unchanged
- `web/src/app/(dashboard)/financials/_components/attention-list.tsx` — imports the shared red chip; two private constants deleted
- `web/src/app/(dashboard)/financials/_components/finance-summary-tiles.tsx` — `QUOTED_BASIS_CAPTION` promoted to export, value unchanged
- `web/src/features/finance/__tests__/financials-hooks.test.tsx` — 6 new tests (3 hook, 3 formatter)

## Decisions Made

- **The finding hook tests mock `apiGet`, not the api-module fetcher.** The plan's action text suggested mocking at the `@/features/finance/api` boundary, but its own `<behavior>` block requires asserting the request path (`/projects/{id}/financials/finding`) and the four snake_case→camelCase mappings. A module-boundary mock replaces the very code that builds the path and does the mapping, so neither is observable through it. Driving the real fetcher against a mocked HTTP layer proves the gate, the path and the mapper in one test. `fetchProjectProfitabilityFinding` is therefore deliberately left out of the file's existing api mock factory, with an in-file comment saying why.
- **The zero-request test was verified by mutation, not by inspection.** With `enabled` reduced to `!!projectId`, the suite failed with `Received number of calls: 1` against the finding path; restoring the gate returned all 140 to green. The gate is provably load-bearing rather than merely spelled correctly.
- **`dayParts` bounds the day to 1..31** so `"2026-07-99"` returns unchanged instead of rendering "Jul 99, 2026", matching the defensive shape `formatMonthLabel` already uses.

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 3 - Blocking] Test mock boundary moved from the api module to the HTTP layer**

- **Found during:** Task 3 (Hook + formatter unit tests)
- **Issue:** The plan's action text prescribed mocking the fetcher at the `@/features/finance/api` module boundary, but two of the plan's six required behaviors — "issues exactly one fetch to `/projects/{id}/financials/finding`" and "maps `corrective_action` → `correctiveAction`, `labor_included` → `laborIncluded`, `found_on` → `foundOn`, `last_confirmed_on` → `lastConfirmedOn`" — are implemented *inside* that fetcher. Mocking it out makes both unobservable, so the prescribed boundary could not satisfy the plan's own behavior contract.
- **Fix:** Left `fetchProjectProfitabilityFinding` real and mocked `apiGet` from `@/lib/api-client` instead (matching the executor brief's "your fetcher/hook tests mock the HTTP layer"). All six behaviors are now asserted, and the zero-request assertion became strictly stronger: it proves nothing reaches the wire, not merely that a wrapper went uncalled.
- **Files modified:** `web/src/features/finance/__tests__/financials-hooks.test.tsx`
- **Verification:** 140/140 green; mutation check (gate removed) fails exactly the intended assertion.
- **Committed in:** `0d764f1`

**2. [Rule 2 - Missing Critical] Named constants for the day-of-month bounds**

- **Found during:** Task 2 (formatFindingDate)
- **Issue:** Validating the day triple needs the literals `1` and `31`; CLAUDE.md forbids magic numbers and the shipped module has no such constants.
- **Fix:** Added `FIRST_DAY_OF_MONTH` / `LAST_POSSIBLE_DAY_OF_MONTH` beside the existing `ABBREVIATION_LENGTH` / `YEAR_SUFFIX_START`.
- **Files modified:** `web/src/features/finance/financials-format.ts`
- **Verification:** `npm run lint` clean at `--max-warnings 0`.
- **Committed in:** `8847269`

---

**Total deviations:** 2 auto-fixed (1 blocking, 1 missing critical)
**Impact on plan:** Both keep the plan's stated contracts intact — one makes the plan's own behavior list actually assertable, the other satisfies a CLAUDE.md hard rule. No scope creep; every acceptance criterion in all three tasks passes as written.

## Issues Encountered

None. The one risk the plan flagged — that the `FINANCE_ALERT_CHIP_CLASS` extraction changes the class *token order* on the Over-budget badge and might break shipped Phase 35 assertions — was checked by running `npx jest "src/app/(dashboard)/financials"`, which stayed green. The assertions are per-token `toHaveClass` checks, as the UI-SPEC predicted.

## Known Stubs

None. Every export in this plan is fully implemented and exercised by a test. The backend `GET /projects/{id}/financials/finding` endpoint does not exist yet (wave 7) by design — this plan's tests mock the HTTP layer, and no UI mounts the hook until 36-05.

## User Setup Required

None - no external service configuration required.

## Next Phase Readiness

- 36-04 can build `ProfitabilityFindingCard` as a purely presentational component: the type, the date formatter, the red chip class and the three composed caption strings are all importable now.
- 36-05 can mount the card and own the third hook on `project-financials-dashboard.tsx` without touching the page-level loading gate.
- 36-06's Playwright SC2 zero-request assertion has its fetch-side half in place and mutation-verified.
- No blockers.

## Self-Check: PASSED

All 9 modified files verified present on disk; all 3 task commits verified in `git log`.

---
*Phase: 36-ai-profitability-analysis*
*Completed: 2026-07-29*
