---
phase: 32-labor-rates-and-cost-rollup
plan: 05
subsystem: finance
tags: [flutter, riverpod, dio, cost-breakdown, labor-cost, mobile]

# Dependency graph
requires:
  - phase: 32-labor-rates-and-cost-rollup (plan 32-02)
    provides: GET /jobs/{id}/cost-breakdown, GET /trade-scopes/{id}/cost-breakdown, additively-extended project rollup (categories/labor/grand_total)
  - phase: 31-actual-cost-capture (plan 31-05)
    provides: financePermissionProvider, FinanceRepository, CostListSection, AddCostSheet, project rollup providers
provides:
  - Typed CostBreakdown/CategoryTotal/LaborCostSummary models (is-check parsing, FormatException on breach)
  - fetchJobCostBreakdown/fetchTradeScopeCostBreakdown online-only repository reads
  - ProjectCostRollupFetch.breakdown tolerant additive field (strict total/entries unchanged)
  - jobCostBreakdownProvider/tradeScopeCostBreakdownProvider/projectCostBreakdownProvider (no Drift persistence)
  - CostBreakdownSummary widget (unrated chip, unburdened caption, job-level note, offline state)
  - Labor-free add-cost category picker
  - phase_32_labor_cost_e2e_test.dart phase-completion suite
affects: [33-margin, 34-budgeting, 36-ai-profitability]

# Tech tracking
tech-stack:
  added: []
  patterns:
    - "Breakdown data is online-fetched and never persisted to Drift — labor requires server-side rate resolution"
    - "One shared _projectRollupFetchProvider feeds both the rollup total and the project breakdown (one network call, two consumers)"
    - "Amounts are backend Decimal-as-Strings displayed verbatim — no double.parse anywhere in the breakdown path"

key-files:
  created:
    - mobile/lib/features/finance/data/cost_breakdown.dart
    - mobile/lib/features/finance/presentation/widgets/cost_breakdown_summary.dart
    - mobile/test/unit/features/finance/cost_breakdown_parsing_test.dart
    - mobile/test/e2e/phase_32_labor_cost_e2e_test.dart
  modified:
    - mobile/lib/features/finance/data/finance_repository.dart
    - mobile/lib/features/finance/presentation/providers/cost_providers.dart
    - mobile/lib/features/finance/presentation/widgets/add_cost_sheet.dart
    - mobile/lib/features/jobs/presentation/screens/job_detail_screen.dart
    - mobile/lib/features/projects/presentation/screens/trade_scope_detail_screen.dart
    - mobile/lib/features/projects/presentation/screens/project_detail_screen.dart

key-decisions:
  - "costRollupTotalProvider kept its public FutureProvider.autoDispose.family<String?, String> signature — refactored internally onto a shared _projectRollupFetchProvider so the total and breakdown share one fetch"
  - "formatUnratedHours(0) returns an empty string — callers never render a chip when every hour is rated, so zero has no display form"
  - "Riverpod 3 Override type must be imported via flutter_riverpod/misc.dart show Override (existing codebase convention)"
  - "Test files that build widgets import drift as `show Value` to avoid the drift Column vs Flutter Column name clash"

patterns-established:
  - "CostBreakdownSummary is a data-down StatelessWidget: callers pass AsyncValue fields (value/isLoading/hasError), it never fetches"
  - "Exported pure helpers (formatUnratedHours, orderedCategories, displayCategoryName) unit-asserted directly by the phase E2E"

requirements-completed: [COST-06]

# Metrics
duration: 50min
completed: 2026-07-27
---

# Phase 32 Plan 05: Mobile Cost Breakdown Summary

**Itemized cost breakdown on all three mobile Costs surfaces — backend-string amounts, hours-visible unrated chip, unburdened-labor caption, trade-scope job-level note, offline honesty state — plus a labor-free add-cost picker and the phase E2E suite**

## Performance

- **Duration:** ~50 min active (split across two sessions by a session limit; wall clock 2026-07-27T05:06:28Z → 2026-07-27T15:41:01Z)
- **Started:** 2026-07-27T05:06:28Z
- **Completed:** 2026-07-27T15:41:01Z
- **Tasks:** 3
- **Files modified:** 10

## Accomplishments

- COST-06 on mobile: job detail, trade-scope detail, and project detail each render category totals, a labor row, and a grand total above their existing cost lists, inside the existing `financePermissionProvider.canView` gates (no new gating)
- D-05 honored: unrated tracked time renders as "{H} hrs unrated" (amber chip, never destructive red, never icon-only); a failed fetch shows "Breakdown unavailable offline" while the cached cost list below still renders — never a fabricated $0
- D-06 honored: the static caption "Wage cost only — excludes payroll tax, insurance, overhead." sits under every mobile labor figure (caption, not tooltip — mobile has no hover)
- D-08 honored: trade scopes show "Tracked at job level" in place of a labor amount — no chip, no caption, no $0
- D-11 honored: labor figures arrive as backend Decimal-as-Strings displayed verbatim; zero `double.parse`/`toDouble()` in the breakdown path; no labor-rate data on the device; no Drift schema change; zero new dependencies
- The reserved Labor category is filtered out of the mobile add-cost picker, so the backend 422 guard can never be triggered from the UI
- `fetchProjectRollup` extended tolerantly: an older backend still yields the same total/jobIds with a null breakdown; the strict `total`/`entries` parsing is byte-for-byte unchanged
- Phase E2E suite (10 tests) plus 9 parsing unit tests; full mobile suite green at 1172 tests; `dart analyze lib test` clean

## Task Commits

Each task was committed atomically:

1. **Task 1 (TDD RED): failing parsing/tolerance tests** - `b843061` (test)
2. **Task 1 (TDD GREEN): CostBreakdown model + repository fetches** - `35c4a85` (feat)
3. **Task 2: providers, CostBreakdownSummary, three mounts, picker filter** - `28935fb` (feat)
4. **Task 3: phase 32 mobile E2E suite** - `21f8c89` (test)

## Files Created/Modified

- `mobile/lib/features/finance/data/cost_breakdown.dart` - CategoryTotal/LaborCostSummary/CostBreakdown with is-check parsing, tryFromJson leniency for the rollup, FormatException on missing categories/grand_total
- `mobile/lib/features/finance/data/finance_repository.dart` - fetchJobCostBreakdown/fetchTradeScopeCostBreakdown via one shared `_fetchCostBreakdown` helper; ProjectCostRollupFetch.breakdown optional field
- `mobile/lib/features/finance/presentation/providers/cost_providers.dart` - jobCostBreakdownProvider, tradeScopeCostBreakdownProvider, projectCostBreakdownProvider; `_projectRollupFetchProvider` single-fetch refactor
- `mobile/lib/features/finance/presentation/widgets/cost_breakdown_summary.dart` - CostBreakdownVariant enum, exported pure helpers, chip/caption/note/offline states, shared `_breakdownRow` layout
- `mobile/lib/features/finance/presentation/widgets/add_cost_sheet.dart` - `_selectableCategories` filter dropping the reserved labor category
- `mobile/lib/features/jobs/presentation/screens/job_detail_screen.dart` - summary mounted above CostListSection inside the Costs card
- `mobile/lib/features/projects/presentation/screens/trade_scope_detail_screen.dart` - summary passed through `_TaskList` above CostListSection
- `mobile/lib/features/projects/presentation/screens/project_detail_screen.dart` - summary between the Costs header row and the entry list; header total untouched
- `mobile/test/unit/features/finance/cost_breakdown_parsing_test.dart` - 9 tests: parse shapes, strictness, malformed-row skip, rollup tolerance
- `mobile/test/e2e/phase_32_labor_cost_e2e_test.dart` - 10 tests: breakdown render, chip presence/absence, caption, job-level note, offline + cached list, gating, picker filter, pure helpers

## Decisions Made

- Kept `costRollupTotalProvider`'s public signature and refactored internally onto `_projectRollupFetchProvider` (the plan's preferred "smaller change") — one network call now feeds both the header total and the project breakdown
- `formatUnratedHours(0)` returns `''` (documented in-code): the chip is only rendered when unrated seconds exist, so zero needs no display form
- Job/project labor amount renders `—` when the payload's labor block is absent rather than fabricating `$0.00`

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 1 - Bug] Plan-suggested doc comment tripped the plan's own rate-leak audit**
- **Found during:** Task 1 (acceptance criteria check)
- **Issue:** The plan's suggested repository doc comment contained the literal `labor_rates`, which the plan's own acceptance criterion (`grep -rq "labor_rates\|hourly_cost" mobile/lib` must return nothing) flags
- **Fix:** Reworded to "labor rate data never reaches the device" — same meaning, audit passes
- **Files modified:** mobile/lib/features/finance/data/finance_repository.dart
- **Verification:** rate-leak grep returns nothing; dart analyze clean
- **Committed in:** 35c4a85 (Task 1 GREEN commit)

---

**Total deviations:** 1 auto-fixed (1 bug)
**Impact on plan:** Cosmetic comment wording only. No scope creep.

## Issues Encountered

- Riverpod 3.2 does not export the `Override` type from `flutter_riverpod.dart` — resolved with the existing codebase convention `import 'package:flutter_riverpod/misc.dart' show Override;`
- `drift/drift.dart`'s `Column` clashes with Flutter's in widget-bearing test files — imported drift as `show Value`
- The trade-scope E2E stub's category total and grand total are both "150.00" (a categories-only scope), so the assertion expects two matching text widgets

## Authentication Gates

None.

## Known Stubs

None — no placeholder values or unwired data paths were introduced. (Pre-existing note: `orderedCategories` drops any labor-named category row on all variants per the plan's helper contract; on trade scopes the backend may emit a legacy labor category row, which the total still includes — display-only nuance inherited from the shared-helper contract, mirrored on web.)

## User Setup Required

None - no external service configuration required.

## Next Phase Readiness

- COST-06 is now complete on both platforms (32-04 web, 32-05 mobile); Phase 32's phase-completion E2E gate for mobile is satisfied
- `unratedSeconds` is surfaced end-to-end (API → model → chip) and ready as Phase 33's incomplete-data signal (MARG-03)
- Full mobile suite green: 1172 passed; `dart analyze lib test` clean; zero dependencies added; no Drift schema change

## Self-Check: PASSED

All 4 created files exist on disk; all 4 task commits (b843061, 35c4a85, 28935fb, 21f8c89) verified in git log.

---
*Phase: 32-labor-rates-and-cost-rollup*
*Completed: 2026-07-27*
