---
phase: 34-budgeting-and-overrun-alerts
plan: 05
subsystem: ui
tags: [flutter, riverpod, dio, mocktail, budget, finance]

# Dependency graph
requires:
  - phase: 34-budgeting-and-overrun-alerts (34-02)
    provides: additive budget block (budget_id/total/spent/remaining/percent_used) on trade-scope breakdown and project rollup responses
  - phase: 33-margin-visibility (33-05)
    provides: MarginSummarySection tolerant-parse pattern, BreakdownRow/FinanceFlagChip primitives, MockDio E2E harness
provides:
  - BudgetVsActual tolerant parser + optional budget field on CostBreakdown (both fetch paths)
  - finance_formatters.dart — single home for formatMarginPercent/formatMarginDollars/formatPercentUsed and financeFigureSeparator
  - BudgetSummarySection widget rendering the Budget/Spent/Remaining triad per the 34-UI-SPEC state matrix
  - Wiring into CostBreakdownSummary between Total and MarginSummarySection on project/tradeScope variants only
  - Phase 34 mobile E2E suite (widget states + mocked-Dio fetch path)
affects: [35-financial-dashboard, verify-work phase 34]

# Tech tracking
tech-stack:
  added: []
  patterns: [tolerant additive-block tryFromJson parsing, band classification from backend strings only (no client percent math), shared formatter module re-exported for backward compatibility]

key-files:
  created:
    - mobile/lib/features/finance/presentation/widgets/finance_formatters.dart
    - mobile/lib/features/finance/presentation/widgets/budget_summary_section.dart
    - mobile/test/features/finance/budget_summary_parse_test.dart
    - mobile/test/e2e/phase_34_budgets_e2e_test.dart
  modified:
    - mobile/lib/features/finance/data/cost_breakdown.dart
    - mobile/lib/features/finance/presentation/widgets/margin_summary_section.dart
    - mobile/lib/features/finance/presentation/widgets/cost_breakdown_summary.dart

key-decisions:
  - "Nearing budget chip condition uses remaining > 0 (not the plan snippet's bare percent >= 80) so exactly-at-budget renders $0.00 plain per UI-SPEC state 5"
  - "figure separator promoted to public financeFigureSeparator in finance_formatters.dart; formatMarginFigure and the Spent figure share it"
  - "Project-surface E2E overrides projectCostBreakdownProvider directly (Phase 33 precedent — real path requires AuthAuthenticated); Dio-level path proven via trade-scope surface + repository-level rollup test"

patterns-established:
  - "Budget band classification: parse backend remaining/percent_used strings with double.tryParse for comparison only — display always uses the verbatim string"

requirements-completed: [BUDG-02]

# Metrics
duration: 18min
completed: 2026-07-28
---

# Phase 34 Plan 05: Mobile Budget View Summary

**View-only Budget/Spent/Remaining triad on mobile project and trade-scope Costs sections, parsed tolerantly from the additive backend budget block with the amber chip/red-numeral band matrix**

## Performance

- **Duration:** 18 min
- **Started:** 2026-07-28T06:02:52Z
- **Completed:** 2026-07-28T06:20:51Z
- **Tasks:** 3 (all TDD)
- **Files modified:** 7

## Accomplishments

- `BudgetVsActual.tryFromJson` — tolerant of an absent/malformed/null budget key (older backend renders exactly what it renders today), strict `is String` shape checks on every field, no bare casts; carried through both `CostBreakdown.fromJson` (trade-scope path) and the lenient rollup `tryFromJson`
- `finance_formatters.dart` — one home for money/percent formatting; `formatPercentUsed` delegates to `formatMarginPercent` (single trailing-".0" implementation); `margin_summary_section.dart` re-exports the moved helpers so the shipped Phase 33 E2E imports keep compiling
- `BudgetSummarySection` — composed from shared `BreakdownRow`/`FinanceFlagChip` primitives; Spent shows the backend `percent_used` verbatim (client never divides); chip (80–100% band) and red over-budget numerals are mutually exclusive; job variant never renders the group
- 12-test Phase 34 mobile E2E file: 7 widget-state tests (UI-SPEC states 1/3/4/5/6/9/10 + typography) and 5 network-driven tests through MockDio → FinanceRepository → provider → widget, asserting the real `/trade-scopes/{id}/cost-breakdown` and `/projects/{id}/cost-entries` paths
- Full mobile suite green (1222 tests), `dart analyze` clean, no Drift schema change, no budget persistence, no editing affordance (D-13)

## Task Commits

Each task was committed atomically (TDD: test → feat):

1. **Task 1: BudgetVsActual parser + shared finance formatters** - `b2979f4` (test), `491b66f` (feat)
2. **Task 2: BudgetSummarySection widget + wiring** - `79cf718` (test), `8d9e07b` (feat)
3. **Task 3: Phase 34 mobile E2E through the real fetch path** - `a6f11da` (test)

## Files Created/Modified

- `mobile/lib/features/finance/data/cost_breakdown.dart` - BudgetVsActual class + optional budget field on CostBreakdown
- `mobile/lib/features/finance/presentation/widgets/finance_formatters.dart` - shared formatters + financeFigureSeparator (new)
- `mobile/lib/features/finance/presentation/widgets/margin_summary_section.dart` - imports/re-exports the moved formatters
- `mobile/lib/features/finance/presentation/widgets/budget_summary_section.dart` - the triad widget (new)
- `mobile/lib/features/finance/presentation/widgets/cost_breakdown_summary.dart` - renders BudgetSummarySection on non-job variants
- `mobile/test/features/finance/budget_summary_parse_test.dart` - 13 parser/formatter unit tests (new)
- `mobile/test/e2e/phase_34_budgets_e2e_test.dart` - 12 E2E tests, widget + mocked-Dio halves (new)

## Decisions Made

- Chip band condition uses `remaining > 0` rather than the plan snippet's `!isOverBudget && percent >= 80` — the snippet contradicted the plan's own behavior list and UI-SPEC state 5 (exactly at budget: $0.00 plain, no chip). See deviation below.
- `_figureSeparator` moved to `finance_formatters.dart` as public `financeFigureSeparator` so the Spent figure imports it instead of retyping the middle dot (plan's stated intent).
- Project-surface widget test overrides `projectCostBreakdownProvider` directly with a comment explaining why (real fetch path requires `AuthAuthenticated`) — the Phase 33 precedent; the Dio-level project path is proven by a repository-level `fetchProjectRollup` test asserting the exact request path.

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 1 - Bug] Corrected the Nearing-budget band condition at exactly 100%**
- **Found during:** Task 2 (BudgetSummarySection widget)
- **Issue:** The plan's code snippet classified `isNearingBudget = !isOverBudget && percentUsed >= 80`, which renders the chip at exactly 100% (remaining 0.00) — contradicting the plan's own `<behavior>` bullet ("remaining '0.00' at 100% renders '$0.00' plain with no chip"), the must_haves truth ("chip shows only between 80% and 100%"), and UI-SPEC states 4/5 (`80 ≤ percent_used ∧ spent < total`)
- **Fix:** Chip requires `remainingAmount > 0` in addition to the 80% threshold; over-budget and at-budget states never show it
- **Files modified:** mobile/lib/features/finance/presentation/widgets/budget_summary_section.dart
- **Verification:** state-5 widget test passes ($0.00 plain, no chip); states 4/6 confirm chip and red numerals never co-render
- **Committed in:** 8d9e07b (Task 2 feat commit)

---

**Total deviations:** 1 auto-fixed (1 bug)
**Impact on plan:** Fix required for correctness against the plan's own behavior spec and the locked UI contract. No scope creep.

## Issues Encountered

None.

## User Setup Required

None - no external service configuration required.

## Next Phase Readiness

- BUDG-02's mobile half complete: the budget triad renders from the API on project and trade-scope Costs sections, tolerant of pre-Phase-34 backends
- No Drift schema change, no budget editing, no client-side percent math — verify-work can assert the D-13 view-only posture
- Web half (34-04) and FCM push (34-03) ship in parallel waves; nothing here blocks them

---
*Phase: 34-budgeting-and-overrun-alerts*
*Completed: 2026-07-28*

## Self-Check: PASSED

All 5 created files exist on disk; all 5 task commits (b2979f4, 491b66f, 79cf718, 8d9e07b, a6f11da) present in git log.
