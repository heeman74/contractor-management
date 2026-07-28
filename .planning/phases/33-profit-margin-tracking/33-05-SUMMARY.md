---
phase: 33-profit-margin-tracking
plan: 05
subsystem: ui
tags: [flutter, riverpod, dio, mocktail, margin, finance]

# Dependency graph
requires:
  - phase: 33-profit-margin-tracking (33-01)
    provides: Locked margin wire contract (revenue_basis enum, incomplete_reasons, Decimal-as-string amounts)
  - phase: 32-labor-rates-and-cost-rollup (32-05)
    provides: CostBreakdownSummary widget, breakdown providers, MockDio e2e harness, financePermissionProvider
provides:
  - Tolerant MarginSummary.tryFromJson parsing on CostBreakdown (all three surfaces via fromJson)
  - MarginSummarySection widget rendering every 33-UI-SPEC margin state
  - Shared BreakdownRow/BreakdownCaption/FinanceFlagChip primitives (one amber chip recipe)
  - Phase-33 mobile widget E2E covering states 1-7, 10, trade-scope variant, and gating
affects: [33-06, 33-verification, 35-financial-dashboard]

# Tech tracking
tech-stack:
  added: []
  patterns:
    - "tryFromJson tolerance idiom extended to MarginSummary — additive wire contract, null on absent/malformed"
    - "Shared finance row/caption/chip primitives in breakdown_row_widgets.dart so data-quality chips cannot visually drift"

key-files:
  created:
    - mobile/lib/features/finance/presentation/widgets/breakdown_row_widgets.dart
    - mobile/lib/features/finance/presentation/widgets/margin_summary_section.dart
    - mobile/test/features/finance/margin_summary_parse_test.dart
    - mobile/test/e2e/phase_33_margin_e2e_test.dart
  modified:
    - mobile/lib/features/finance/data/cost_breakdown.dart
    - mobile/lib/features/finance/presentation/widgets/cost_breakdown_summary.dart

key-decisions:
  - "MarginSummary nullable fields are optional constructor params (basis stays required) — reconciles the plan snippet with its own 'no required this.margin' acceptance criterion"
  - "Project-variant e2e test overrides projectCostBreakdownProvider directly — the real fetch path requires an authenticated session; parser path covered by unit suite"

patterns-established:
  - "FinanceFlagChip: single amber pill class for unrated-hours and incomplete-cost-data flags"
  - "Margin figure formatting via pure exported helpers (formatMarginPercent/Dollars/Figure), unit-tested without widget pumps"

requirements-completed: [MARG-01, MARG-02, MARG-03]

# Metrics
duration: 13min
completed: 2026-07-28
---

# Phase 33 Plan 05: Mobile Margin Section Summary

**Revenue/Margin rows on all three mobile Costs surfaces via tolerant MarginSummary parsing, a MarginSummarySection widget with the full UI-SPEC state matrix, and a shared amber flag-chip primitive**

## Performance

- **Duration:** ~13 min active (split across two sessions by a session-limit pause)
- **Started:** 2026-07-27T17:12:00Z
- **Completed:** 2026-07-28T00:14:23Z
- **Tasks:** 3
- **Files modified:** 6

## Accomplishments

- `MarginSummary.tryFromJson` parses the locked 33-01 wire contract tolerantly: absent key, malformed block, and wrong-typed fields all degrade to a null margin (no rows) instead of a `FormatException` — an older backend keeps working
- Margin block renders beneath the Total on job, trade-scope, and project Costs surfaces with zero screen-file edits (parsing lives in `CostBreakdown.fromJson`; the section mounts inside `CostBreakdownSummary`)
- Every verbatim UI-SPEC string ships as a named constant and is test-asserted: quoted/mixed basis captions, incomplete chip + caption, no-revenue note
- The unrated chip (Phase 32) and incomplete chip (Phase 33) are now the same `FinanceFlagChip` widget — one amber recipe, cannot drift
- Negative margins render numerals-only in `colorScheme.error`; flagged margins keep showing the figure (D-06: never suppressed, never unflagged)

## Task Commits

Each task was committed atomically:

1. **Task 1: Tolerant MarginSummary parsing (TDD)** - `42f318a` (test RED), `fa230f1` (feat GREEN)
2. **Task 2: Shared primitives + MarginSummarySection** - `ae3bc5c` (feat)
3. **Task 3: Phase 33 mobile widget E2E** - `e4b66c4` (test)

## Files Created/Modified

- `mobile/lib/features/finance/data/cost_breakdown.dart` - `MarginSummary` class + optional `margin` field on `CostBreakdown`, parsed in `fromJson` (covers rollup via `tryFromJson` delegation)
- `mobile/lib/features/finance/presentation/widgets/breakdown_row_widgets.dart` - `BreakdownRow`, `BreakdownCaption`, `FinanceFlagChip`, `financeSecondaryStyle` — shipped implementations extracted verbatim
- `mobile/lib/features/finance/presentation/widgets/margin_summary_section.dart` - `MarginSummarySection` + pure `formatMarginPercent`/`formatMarginDollars`/`formatMarginFigure` helpers
- `mobile/lib/features/finance/presentation/widgets/cost_breakdown_summary.dart` - consumes shared primitives (dead private helpers deleted), mounts `MarginSummarySection` after the Total row
- `mobile/test/features/finance/margin_summary_parse_test.dart` - 12 parser unit tests (tolerance matrix + breakdown integration)
- `mobile/test/e2e/phase_33_margin_e2e_test.dart` - 13 tests: UI-SPEC states 1-7 and 10, trade-scope variant, pure helpers, finance.view gating

## Decisions Made

- `MarginSummary` nullable fields became optional named constructor params with safe defaults (`incomplete = false`, `incompleteReasons = const []`); only `revenueBasis` is required — see deviation 1
- Project-variant e2e test overrides `projectCostBreakdownProvider` with the fixture parsed through `CostBreakdown.fromJson` rather than mocking the full fetch path, since `_projectRollupFetchProvider` requires an `AuthAuthenticated` state that the phase-32 harness never constructs; the Dio-level path is exercised by the job and trade-scope surface tests

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 1 - Bug] Plan-internal conflict: MarginSummary constructor snippet violated the plan's own acceptance criterion**
- **Found during:** Task 1 (acceptance criteria check)
- **Issue:** The plan's `MarginSummary` snippet specified `required this.margin`, but the acceptance criterion requires `grep "required this.margin"` to return nothing (intended to guard `CostBreakdown.margin` optionality, but it matches `MarginSummary`'s constructor too)
- **Fix:** Made nullable `MarginSummary` fields optional named params (`this.revenue`, `this.margin`, `this.marginPercent`, defaults for `incomplete`/`incompleteReasons`); `revenueBasis` stays required
- **Files modified:** mobile/lib/features/finance/data/cost_breakdown.dart
- **Verification:** Grep criterion passes; all 12 parser tests still green
- **Committed in:** fa230f1 (Task 1 GREEN commit)

---

**Total deviations:** 1 auto-fixed (1 bug/plan-conflict)
**Impact on plan:** Cosmetic constructor-shape change only; wire parsing and rendering unchanged. No scope creep.

## Issues Encountered

- Session-limit interruption between Task 2 implementation and its verification; resumed cleanly from coordinator-verified git state (Tasks 1 commits landed, Task 2 files present uncommitted). No rework needed.

## Known Stubs

None in this plan's files. Note (by design, not a stub): the live backend endpoints do not emit the `margin` block until 33-03 (Wave 3) ships — until then the mobile section renders nothing, which is exactly state 10 of the UI-SPEC contract and is test-asserted.

## User Setup Required

None - no external service configuration required.

## Next Phase Readiness

- Mobile is ready to display margins the moment 33-03's backend endpoints start emitting the `margin` block — no further mobile changes needed
- `FinanceFlagChip`/`BreakdownRow` primitives available for any future finance surface (Phase 34 budgets, Phase 35 dashboard)

---
*Phase: 33-profit-margin-tracking*
*Completed: 2026-07-28*

## Self-Check: PASSED

All 4 created files exist on disk; all 4 task commits (42f318a, fa230f1, ae3bc5c, e4b66c4) verified in git log.
