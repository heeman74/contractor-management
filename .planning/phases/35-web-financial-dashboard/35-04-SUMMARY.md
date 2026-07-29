---
phase: 35-web-financial-dashboard
plan: 04
subsystem: ui
tags: [react, tanstack-query, typescript, finance, rbac, jest]

# Dependency graph
requires:
  - phase: 30-financial-foundation
    provides: finance.view RBAC permission key and usePermissions().can()
  - phase: 33-margin-visibility
    provides: MarginSummary type, mapMarginSummary, mapCostBreakdown
  - phase: 34-budgeting-and-alerts
    provides: BudgetVsActual type, toBudgetVsActual mapper
provides:
  - CompanyFinancials / ProjectFinancials / MarginTrend camelCase response types
  - FINANCE_VIEW_PERMISSION constant (single source for gate and hooks)
  - AttentionTier, TrendWindow, TREND_WINDOWS, DEFAULT_TREND_WINDOW, INACTIVE_PROJECT_STATUSES
  - fetchCompanyFinancials, fetchProjectFinancials, fetchProjectMarginTrend
  - useCompanyFinancials, useProjectFinancials, useProjectMarginTrend (permission-gated)
affects: [35-01, 35-02, 35-03, 35-05, 35-06, 35-07]

# Tech tracking
tech-stack:
  added: []
  patterns:
    - "Enum-ish wire values validated via toKnownValue(), never bare `as` casts"
    - "requireMarginSummary() fails loudly on a malformed block instead of casting away null"
    - "enabled: can(FINANCE_VIEW_PERMISSION) as the fetch-side half of the permission gate"

key-files:
  created:
    - web/src/features/finance/__tests__/financials-api.test.ts
    - web/src/features/finance/__tests__/financials-hooks.test.tsx
  modified:
    - web/src/features/finance/types.ts
    - web/src/features/finance/api.ts
    - web/src/features/finance/hooks.ts

key-decisions:
  - "FINANCE_VIEW_PERMISSION lives in types.ts, not a component, so FinanceGate's render branch and the hooks' enabled branch can never drift on the permission key"
  - "Wire enums (attention tier, trend window) go through a shared toKnownValue() validator rather than a cast, so a malformed payload throws at the boundary instead of surfacing as an impossible UI state"
  - "Financial query keys sit under the shipped cost-entries prefix so invalidateAllCostEntries refreshes the dashboard after any cost/budget/rate write with no new invalidation code"

patterns-established:
  - "Boundary validation: every new financials mapper reuses the shipped margin/budget/breakdown mappers and never writes a second null coalescer for money"
  - "Gate proof: a render test asserting zero fetcher calls when denied accompanies every permission-gated query family"

requirements-completed: [MARG-04]

# Metrics
duration: 9 min
completed: 2026-07-29
---

# Phase 35 Plan 04: Financial Data Layer Summary

**Typed, permission-gated TanStack Query data layer for the three financial endpoints — camelCase mappers that keep null money null, and `enabled: can(FINANCE_VIEW_PERMISSION)` on every query so an unauthorized visit issues zero `/api/v1/financials/*` requests.**

## Performance

- **Duration:** 9 min
- **Started:** 2026-07-29T01:56:25Z
- **Completed:** 2026-07-29T02:05:02Z
- **Tasks:** 3 (one TDD)
- **Files modified:** 5 (3 modified, 2 created)

## Accomplishments

- Response types for the company rollup, project drill-down and margin trend, reusing the shipped `MarginSummary` / `BudgetVsActual` / `CostBreakdown` interfaces rather than re-declaring their fields; `incompleteProjectCount` is the only new numeric field, every money and percent stays a string.
- `FINANCE_VIEW_PERMISSION` declared once in `types.ts` — plan 35-03's `FinanceGate` imports it from there, and neither file carries a `"finance.view"` literal.
- Three fetchers with snake_case→camelCase mappers that route every margin through `mapMarginSummary`, every budget through `toBudgetVsActual`, and the project breakdown through `mapCostBreakdown`. A null revenue, margin or budget survives the mapping layer unchanged — there is no `?? "0.00"` anywhere in the new code, and no `parseFloat` in the data layer at all.
- Three permission-gated hooks keyed under the `cost-entries` prefix, with the trend window in its own key segment and `placeholderData: (previous) => previous` so a window switch keeps the old chart on screen.
- 12 new jest tests (7 mapping, 5 hook) — including the load-bearing SC3 half: denied and still-loading permission states call the fetchers zero times.

## Task Commits

1. **Task 1: Response types for the three financial endpoints** - `6d9c485` (feat)
2. **Task 2: Typed fetchers and snake_case mappers** - `d1aadfc` (test, RED) → `a2c30f8` (feat, GREEN)
3. **Task 3: Permission-gated query hooks under the cost-entries prefix** - `654067b` (feat)

_No REFACTOR commit for Task 2 — the GREEN implementation needed no cleanup._

## Files Created/Modified

- `web/src/features/finance/types.ts` - Added the financial-dashboard type block: `PortfolioTotals`, `ProjectFinancialsRow`, `AttentionRow`, `CompanyFinancials`, `ScopeBudgetRow`, `ProjectFinancials`, `TrendBucket`, `MarginTrend`, plus `FINANCE_VIEW_PERMISSION`, `AttentionTier`, `TrendWindow`, `TREND_WINDOWS`, `DEFAULT_TREND_WINDOW`, `INACTIVE_PROJECT_STATUSES`.
- `web/src/features/finance/api.ts` - Added raw `*ApiResponse` interfaces, private mappers, `requireMarginSummary` / `toKnownValue` boundary guards, path constants, and the three exported fetchers.
- `web/src/features/finance/hooks.ts` - Added `useCompanyFinancials`, `useProjectFinancials`, `useProjectMarginTrend` (purely additive — zero removed lines).
- `web/src/features/finance/__tests__/financials-api.test.ts` - 7 mapping tests: null survival, absent budget block, attention rows, breakdown reuse, trend query param, bucket order, malformed-margin throw.
- `web/src/features/finance/__tests__/financials-hooks.test.tsx` - 5 hook tests: zero fetches when denied, zero fetches while permissions load, exactly-once when permitted, distinct trend keys per window, all keys under the `cost-entries` prefix.

## Decisions Made

- **Permission key home:** `types.ts` rather than a component module, so the render gate (35-03) and the fetch gate (this plan) resolve the identical string.
- **No casts on wire enums:** `raw.tier` and `raw.window` pass through a shared `toKnownValue()` validator that throws on an unknown value. The shipped `revenue_basis as RevenueBasis` cast was not copied — CLAUDE.md forbids bare casts on API data, and a validator costs six lines.
- **Missing margin is an error, not a null:** `mapMarginSummary` legitimately returns null for older breakdown payloads, but every new dashboard block always carries a margin, so `requireMarginSummary` throws rather than letting an impossible null reach the UI.
- **Trend query string written literally** (`?window=${window}`) instead of behind a param-name constant, matching the shipped fetchers' inline query style and keeping the path greppable.

## Deviations from Plan

None - plan executed exactly as written.

The plan's Task 2 note about a `FormatException`-style guard was implemented as `requireMarginSummary`; the extra `toKnownValue` validator for the tier and window enums is the same principle applied to the two enum fields the plan's mapper list implies (it replaced what would otherwise have been two bare casts).

## Issues Encountered

- `renderHook` with an inline `as const` initial prop narrowed the props type to the literal `"3m"`, so the `rerender({ window: "12m" })` call failed `tsc` while jest passed. Fixed by declaring an explicit `TrendWindowProps` type for both the callback parameter and the initial props object. Caught by the plan's mandatory `npx tsc --noEmit` gate.

## Known Stubs

None. The three fetchers target backend endpoints that do not exist yet (plans 35-05/06/07 build them); the mapping and gating tests mock the HTTP layer, which is the intended wave-1 boundary, not a stub in the delivered code.

## User Setup Required

None - no external service configuration required.

## Next Phase Readiness

- Plan 35-03 (`FinanceGate`) can import `FINANCE_VIEW_PERMISSION` from `@/features/finance/types` now.
- Plans 35-01/02 (dashboard pages) can consume the three hooks; display components receive already-parsed props with money as strings.
- Plans 35-05/06/07 must serialize exactly the `<interfaces>` wire contract — the mapper tests encode it, so a backend shape drift will fail these jest specs.
- Verification run at plan close: `npx jest src/features/finance` 108/108 passing across 7 suites, `npm run lint` clean at `--max-warnings 0`, `npx tsc --noEmit` exit 0, no `parseFloat` in `api.ts`.

## Self-Check: PASSED

All 5 claimed source files and the SUMMARY exist on disk; all 4 task commits (`6d9c485`, `d1aadfc`, `a2c30f8`, `654067b`) are present in the git log.

---
*Phase: 35-web-financial-dashboard*
*Completed: 2026-07-29*
