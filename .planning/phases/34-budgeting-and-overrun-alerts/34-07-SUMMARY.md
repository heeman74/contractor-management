---
phase: 34-budgeting-and-overrun-alerts
plan: 07
subsystem: ui
tags: [react, tanstack-query, base-ui, playwright, budgets, finance]

# Dependency graph
requires:
  - phase: 34-02
    provides: /budgets CRUD endpoints (POST/PATCH/DELETE, 409 on duplicate anchor) and the budget response block
  - phase: 34-04
    provides: Read-only BudgetSummarySection, budget types (BudgetVsActual), formatPercentUsed, breakdown/rollup budget mapping
provides:
  - useSetBudget/useUpdateBudget/useDeleteBudget mutation hooks invalidating the cost-entries prefix
  - SetBudgetDialog (create/edit/remove with UI-SPEC copy verbatim)
  - Manage affordances (states 2 and 11) on project and trade-scope Costs surfaces, gated finance.manage
  - Monitoring AlertPanel header renamed "AI Alerts" -> "Alerts"; budget alerts render via existing severity path
  - phase-34-budgets.spec.ts Playwright coverage of the full web budget flow
affects: [35-financial-dashboard, 36-ai-profitability]

# Tech tracking
tech-stack:
  added: []
  patterns:
    - "Dialog form reset via onOpenChange wrapper with a null 'untouched' sentinel (amount = editedAmount ?? budget?.total ?? \"\") — prefill stays correct after data refetch, no useEffect"
    - "Stateful Playwright proxy mocks: mutation routes update the state the GET responses are built from, proving invalidation-driven row refresh"

key-files:
  created:
    - web/src/features/finance/components/SetBudgetDialog.tsx
    - web/src/features/finance/__tests__/set-budget-dialog.test.tsx
    - web/tests/phase-34-budgets.spec.ts
  modified:
    - web/src/features/finance/api.ts
    - web/src/features/finance/hooks.ts
    - web/src/features/finance/components/BudgetSummarySection.tsx
    - web/src/features/finance/components/CostBreakdownSummary.tsx
    - web/src/features/finance/components/ProjectCostsCard.tsx
    - web/src/app/(dashboard)/projects/components/ProjectDetail.tsx
    - web/src/app/(dashboard)/projects/components/TradeScopeDetail.tsx
    - web/src/app/(dashboard)/monitoring/_components/AlertPanel.tsx
    - web/src/features/finance/__tests__/budget-section.test.tsx
    - web/src/app/(dashboard)/projects/components/__tests__/trade-scope-detail.test.tsx

key-decisions:
  - "Budget API functions return Promise<void> — the dialog only needs success/failure; refreshed rows come from query invalidation, so no unused response mapper was added"
  - "409 duplicate detection via ApiError.status in a named isDuplicateBudgetError helper; jest mocks ApiError with a status-carrying class so instanceof works"
  - "Edit-button aria-label uses a named constant (CLAUDE.md no-magic-strings) instead of an inline literal; the rendered aria-label=\"Edit budget\" attribute is asserted in jest"
  - "SetBudgetDialog amount state uses a null sentinel so prefill tracks the latest budget prop across close/reopen without effects or remount keys"

patterns-established:
  - "onOpenChange-wrapper reset with untouched sentinel: the reliable no-useEffect dialog prefill recipe when the prefill source can change while closed"

requirements-completed: [BUDG-01, BUDG-02]

# Metrics
duration: 13min
completed: 2026-07-28
---

# Phase 34 Plan 07: Web Budget Management UI Summary

**SetBudgetDialog with create/edit/remove budget flows wired into both Costs surfaces via three cost-entries-invalidating mutation hooks, plus the AlertPanel "Alerts" rename and end-to-end Playwright proof**

## Performance

- **Duration:** 13 min (resumed session; a prior session was cut off during context reading with no commits made)
- **Started:** 2026-07-28T15:46:22Z
- **Completed:** 2026-07-28T16:00:02Z
- **Tasks:** 3 (all TDD)
- **Files modified:** 13

## Accomplishments

- `useSetBudget`/`useUpdateBudget`/`useDeleteBudget` hooks call POST/PATCH/DELETE `/api/v1/budgets/` and invalidate the `["cost-entries"]` prefix, so every budget row (scope breakdown + project rollup) refreshes without a reload
- `SetBudgetDialog` implements UI-SPEC § 3 exactly: create/edit titles, "CURRENT BUDGET" eyebrow + spend caption, non-blocking below-spend note, both validation messages, 409 duplicate toast, and a destructive remove confirmation with initial focus on Cancel
- UI-SPEC states 2 and 11 shipped: "Set budget" ghost row when no budget exists and an "Edit" (aria-label "Edit budget") button on the Budget row — both only for `finance.manage` holders; view-only users see figures with no affordances
- Monitoring panel header renamed to "Alerts" (rule-based budget alerts are not AI); `budget_warning`/`budget_overrun` flow through the existing severity path with no special-casing
- 18 new dialog unit tests, 10 new affordance tests, and a 5-test Playwright spec covering set → edit → remove, warning-chip vs over-budget rendering, and the alert panel

## Task Commits

Each task was committed atomically (TDD: test → feat):

1. **Task 1: Budget mutation hooks + SetBudgetDialog** - `fac6a2f` (test), `9b78736` (feat)
2. **Task 2: Manage affordances on both Costs surfaces** - `f6057e6` (test), `79aa63a` (feat)
3. **Task 3: AlertPanel header fix + phase-34 Playwright spec** - `149bd8a` (test), `372ed3f` (feat), `b0d4efd` (fix, deviation)

## Files Created/Modified

- `web/src/features/finance/components/SetBudgetDialog.tsx` - Create/edit/remove budget dialog (BudgetAmountField, CurrentBudgetHeadline, RemoveBudgetConfirmation sub-components)
- `web/src/features/finance/api.ts` - setBudget/updateBudget/deleteBudget endpoint calls (snake_case bodies, no unused response types)
- `web/src/features/finance/hooks.ts` - Three budget mutations invalidating the cost-entries prefix
- `web/src/features/finance/components/BudgetSummarySection.tsx` - canManage/onManageBudget props, Set budget affordance row (state 2), Edit button (state 11)
- `web/src/features/finance/components/CostBreakdownSummary.tsx` - canManageBudget/onManageBudget pass-through
- `web/src/features/finance/components/ProjectCostsCard.tsx` - projectName prop, finance.manage gating, hosts SetBudgetDialog with project anchor
- `web/src/app/(dashboard)/projects/components/ProjectDetail.tsx` - passes projectName={project.name}
- `web/src/app/(dashboard)/projects/components/TradeScopeDetail.tsx` - hosts SetBudgetDialog with "{trade name} scope" anchor
- `web/src/app/(dashboard)/monitoring/_components/AlertPanel.tsx` - header "AI Alerts" → "Alerts"
- `web/tests/phase-34-budgets.spec.ts` - Playwright spec (login through UI, SPA-navigate, stateful mutation mocks)

## Decisions Made

- Budget API functions return `Promise<void>`: the dialog only needs success/failure and rows refresh via invalidation, so no dead response mapper was added (plan's "prefer not adding unused types")
- The edit-button aria-label is a named constant (`EDIT_BUDGET_ARIA_LABEL`) per CLAUDE.md no-magic-strings; the acceptance criterion's literal grep is satisfied semantically — jest asserts the rendered `aria-label="Edit budget"` attribute
- Amount prefill uses a null "untouched" sentinel instead of copying `budget.total` into state, so reopening after a refetch always shows the current total without effects
- Playwright DELETE mock fulfills `200 { json: null }` because `apiDelete` unconditionally parses JSON (a 204 empty body would reject)

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 3 - Blocking] Existing TradeScopeDetail tests broke on the new dialog mount**
- **Found during:** Task 3 (full-suite verification)
- **Issue:** `trade-scope-detail.test.tsx` mocks `@/features/finance/hooks` with an explicit factory; mounting SetBudgetDialog inside TradeScopeDetail made the three new budget hooks resolve to `undefined` → 4 tests failed
- **Fix:** Added `useSetBudget`/`useUpdateBudget`/`useDeleteBudget` stubs to that test's hooks mock
- **Files modified:** web/src/app/(dashboard)/projects/components/__tests__/trade-scope-detail.test.tsx
- **Verification:** Full suite 268/268 passing
- **Committed in:** b0d4efd

---

**Total deviations:** 1 auto-fixed (1 blocking)
**Impact on plan:** Test-infrastructure fix only, required by the planned dialog mount. No scope creep.

## Known Stubs

None — all affordances are wired to live mutation hooks against the shipped 34-02 endpoints; no placeholder data or unwired components.

## Issues Encountered

None beyond the documented deviation. Note for future planners: a trade scope with zero cost entries and no budget renders no breakdown at all (`isBreakdownEmpty`), so the "Set budget" affordance is unreachable there — consistent with UI-SPEC state 2's "breakdown loaded" condition and the shipped 34-04 behavior, but worth revisiting if empty-scope budgeting becomes a need.

## User Setup Required

None - no external service configuration required.

## Next Phase Readiness

- BUDG-01's web half is complete: budgets set/edit/remove from both Costs surfaces, gated finance.manage, with UI-SPEC states 2 and 11 closing the state matrix
- The monitoring panel honestly labels rule-based alerts; Phase 35's financial dashboard can build on the budget rows and alert rendering shipped here
- Phase-34 web verification can lean on `tests/phase-34-budgets.spec.ts` + `phase-33-margin.spec.ts` (both green together)

## Self-Check: PASSED

All key created files exist on disk and all seven task commits are present in git history.

---
*Phase: 34-budgeting-and-overrun-alerts*
*Completed: 2026-07-28*
