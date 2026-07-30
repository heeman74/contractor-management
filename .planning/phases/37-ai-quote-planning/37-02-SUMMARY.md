---
phase: 37-ai-quote-planning
plan: 02
subsystem: api
tags: [python, decimal, grounding, quotes, finance-math]

# Dependency graph
requires:
  - phase: 36-ai-profitability-analysis
    provides: ai_grounding validator (validate_grounding/collect_allowed_values), the shipped closed-set grounding discipline
  - phase: 33-profit-margin-tracking
    provides: margin_math (pre_tax_total, margin_percent_for, DocumentAmounts)
provides:
  - AllowedFigures + validate_typed_grounding, additive typed money/percent grounding sibling
  - quote_history_math.py — variance_for/variance_percent_for, prorated_pre_tax_totals, confidence_band + its two independent axes (band_by_count, band_by_spread), spread_ratio_for, median_of
affects: [37-04, 37-05, 37-06, 37-09 (comparable-matching, suggestion service, confidence-chip UI, variance surfacing)]

# Tech tracking
tech-stack:
  added: []
  patterns:
    - "Typed grounding sibling: separately-typed money/percent frozensets (AllowedFigures) beside the untouched flat-set validator, so a percent can never satisfy a dollar citation"
    - "Confidence band = max(band_by_count, band_by_spread) over a fixed BAND_ORDER tuple — the worse axis always wins"
    - "Variance derived from margin_percent_for via negation, never a second percent formula"

key-files:
  created:
    - backend/app/features/quotes/quote_history_math.py
    - backend/tests/unit/test_quote_history_math.py
  modified:
    - backend/app/core/ai_grounding.py
    - backend/tests/unit/test_ai_grounding.py

key-decisions:
  - "AllowedFigures/validate_typed_grounding appended additively to ai_grounding.py — validate_grounding/collect_allowed_values remain byte-identical (only the module docstring's closing paragraph grew to name both validators)"
  - "variance_percent_for special-cases margin_percent==0 to avoid returning Decimal(-0.0), which would render as -0%"
  - "confidence_band always yields the WORSE of band_by_count and band_by_spread, via max() over BAND_ORDER — a high count can never overrule a wide spread"
  - "spread_ratio_for returns None (not a degenerate ratio) for fewer than two values or a zero p10 — an unknowable spread reads as the weakest evidence, not an all-clear"

patterns-established:
  - "MIN_COMPARABLES_FOR_SUGGESTION (D-09 refusal floor), HIGH/MEDIUM_CONFIDENCE_MIN_SAMPLES and *_MAX_SPREAD_RATIO are the single home for every quote-suggestion confidence threshold; later plans (37-09) import these constants rather than re-literal them"

requirements-completed: [FINAI-04, FINAI-05]

# Metrics
duration: 25min
completed: 2026-07-30
---

# Phase 37 Plan 02: Typed Grounding and Quote History Math Summary

**Additive `AllowedFigures`/`validate_typed_grounding` sibling closing the percent-vs-money grounding gap, plus a DB-free `quote_history_math.py` with quoted-vs-actual variance (derived from the shipped margin percent) and two-axis, code-computed confidence bands.**

## Performance

- **Duration:** 25 min
- **Started:** 2026-07-30T18:52:00Z
- **Completed:** 2026-07-30T19:00:47Z
- **Tasks:** 3
- **Files modified:** 4

## Accomplishments
- A percent value in an AI payload can no longer satisfy a dollar citation and vice versa, while the shipped Phase 36 grounding path (`validate_grounding`/`collect_allowed_values`) is proven byte-unchanged by a dedicated regression test
- Quoted-vs-actual variance is defined exactly once, as the negation of the shipped `margin_percent_for`, with an explicit zero-branch guard against Decimal negative-zero
- Confidence bands are computed in code on two independent axes (sample count, agreement spread) and reported as the worse of the two — a self-reported AI confidence is structurally impossible since the module carries no AI call at all
- `prorated_pre_tax_totals` allocates one quote's discounted pre-tax total across per-trade groups by subtotal share, with the rounding remainder assigned to the largest group so rows always sum exactly to the quote total

## Task Commits

Each task was committed atomically:

1. **Task 1: Typed money/percent grounding, additive to the shipped validator** - `1f2099c` (feat)
2. **Task 2: Quoted-vs-actual variance math** - `be018b9` (feat)
3. **Task 3: Confidence bands on two independent axes** - `59a249c` (feat)

**Plan metadata:** (this commit)

## Files Created/Modified
- `backend/app/core/ai_grounding.py` - Added `AllowedFigures`, `matches_typed`, `validate_typed_grounding`; only the module docstring's closing paragraph was reworded, no existing function/constant touched
- `backend/tests/unit/test_ai_grounding.py` - Added `TestTypedGrounding` covering all seven typed-grounding behaviors plus the untyped-path regression test
- `backend/app/features/quotes/quote_history_math.py` - New DB-free module: `VarianceFigures`, `variance_for`, `variance_percent_for`, `prorated_pre_tax_totals`, `band_by_count`, `band_by_spread`, `confidence_band`, `spread_ratio_for`, `median_of`, plus all named threshold constants
- `backend/tests/unit/test_quote_history_math.py` - 20 tests covering variance sign/zero-guard/negation-equivalence, proration sum/remainder/zero-input, both confidence axes independently and combined, spread-ratio nearest-rank and none-cases, median even/empty

## Decisions Made
- Kept `validate_grounding`/`collect_allowed_values` completely untouched; the new typed pair is a pure sibling so Phase 36's shipped path and its 30+ existing tests stay green (verified: 40 tests pass in `test_ai_grounding.py`, up from the shipped 33)
- `quote_history_math.py` has zero session/model/repository imports, matching the `margin_math`/`budget_math`/`profitability_math` precedent for DB-free math modules — verified by grep in the acceptance criteria
- Bands are returned only through the named `BAND_HIGH`/`BAND_MEDIUM`/`BAND_LOW` constants — no bare string literals in any `return` statement (grep-verified)

## Deviations from Plan

None - plan executed exactly as written.

## Issues Encountered

None.

## User Setup Required

None - no external service configuration required.

## Next Phase Readiness

- `AllowedFigures`/`validate_typed_grounding` and `quote_history_math.py` are ready for the suggestion service (37-04+) to consume: structured `unit_price`/`quantity` fields validate via `AllowedFigures` membership, the basis string via `validate_typed_grounding`, and comparable aggregation reduces through `confidence_band`/`variance_for`.
- `MIN_COMPARABLES_FOR_SUGGESTION` is defined once here so the D-09 cold-start refusal (37-05/37-09) and its `required_count` UI field share one source.
- Backend unit suite: 256 tests passed (up from the pre-plan baseline); `ruff check`/`ruff format --check` clean on all touched files.

---
*Phase: 37-ai-quote-planning*
*Completed: 2026-07-30*

## Self-Check: PASSED

All created/modified files found on disk; all task commit hashes (1f2099c, be018b9, 59a249c) found in git log.
