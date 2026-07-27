---
phase: 33-profit-margin-tracking
plan: 01
subsystem: finance
tags: [python, decimal, margin, revenue, tdd, pure-math]

# Dependency graph
requires:
  - phase: 32-labor-rates-and-cost-rollup
    provides: labor_derivation.py CENTS/ZERO_MONEY constants and the DB-free pure-math module posture
  - phase: 25-per-trade-billing
    provides: invoice/quote schemas whose duplicated discount/tax math this plan extracts
provides:
  - backend/app/features/finance/margin_math.py — DB-free document totals, revenue resolution (D-01/D-03/D-13), margin/flag math (D-05/D-06/D-07)
  - Wire-string constants for revenue_basis (invoiced/quoted/mixed/none) and incomplete_reasons (unrated_labor/no_cost_data)
  - RevenueAnchor hashable dataclass for 33-02 query grouping
  - Invoice/quote response totals delegated to the shared helpers (single implementation of discount/tax math)
affects: [33-02, 33-03, 33-04, 33-05, 35-financial-dashboard, 36-ai-profitability]

# Tech tracking
tech-stack:
  added: []
  patterns:
    - "DB-free pure-math module with frozen dataclasses (mirrors labor_derivation.py)"
    - "Wire strings single-sourced as module constants, never re-literaled downstream"

key-files:
  created:
    - backend/app/features/finance/margin_math.py
    - backend/tests/unit/test_margin_math.py
  modified:
    - backend/app/features/invoices/schemas.py
    - backend/app/features/quotes/schemas.py

key-decisions:
  - "discount_for/tax_for keep default (banker's) quantize rounding — bit-for-bit identical to shipped schema math so existing invoice/quote totals never change"
  - "ROUND_HALF_UP applies only in margin_percent_for (one-decimal percent), matching the plan's rounding policy"
  - "summarize_margin forces basis to none whenever revenue.total is None, keeping the D-07 absent-margin shape self-consistent"

patterns-established:
  - "Margin wire contract: revenue_basis in {invoiced, quoted, mixed, none}; incomplete_reasons subset of (unrated_labor, no_cost_data) in fixed order"
  - "Document math flows through DocumentAmounts — schemas map ORM/Pydantic fields, margin_math owns the arithmetic"

requirements-completed: [MARG-01, MARG-03]

# Metrics
duration: 7min
completed: 2026-07-27
---

# Phase 33 Plan 01: Margin Math Core Summary

**DB-free margin math module: pre-tax revenue resolution (invoices win outright over approved quotes), margin dollars/percent with honest incomplete-data flags, and invoice/quote totals delegated to the shared discount/tax helpers**

## Performance

- **Duration:** 7 min
- **Started:** 2026-07-27T17:02:47Z
- **Completed:** 2026-07-27T17:09:22Z
- **Tasks:** 3
- **Files modified:** 4

## Accomplishments

- `margin_math.py` ships the whole Phase 33 arithmetic surface: document totals, `resolve_anchor_revenue` (D-01/D-03), `combine_revenue_bases`, `missing_cost_data`, `margin_percent_for`, and `summarize_margin` (D-05/D-06/D-07) — all pure, no DB/FastAPI imports
- 28-test pure unit suite, including the Pitfall-9 keystone: revenue 2000.00 with zero cost yields margin "2000.00" / "100.0" but flagged `incomplete` with `no_cost_data` — never a clean 100%
- Invoice and quote `from_orm_with_totals` now compute discount/tax/total through the shared helpers, eliminating the byte-identical duplicated math and guaranteeing displayed totals can never diverge from the margin revenue leg (34 existing invoice/quote e2e tests pass unchanged)

## Task Commits

Each task was committed atomically:

1. **Task 1: Write the failing pure-math unit suite** - `ad1e656` (test — TDD RED)
2. **Task 2: Implement margin_math.py until the suite is green** - `a0be948` (feat — TDD GREEN)
3. **Task 3: Delegate invoice and quote response totals to the shared helpers** - `5f174e2` (refactor)

No REFACTOR-step commit was needed for the TDD pair — the GREEN implementation already followed the module conventions.

## Files Created/Modified

- `backend/app/features/finance/margin_math.py` - DB-free margin math: constants (wire strings), frozen dataclasses (RevenueAnchor, DocumentAmounts, AnchorRevenue, ResolvedRevenue, MarginInputs, MarginFigures), and the ten pure functions of the plan's API contract
- `backend/tests/unit/test_margin_math.py` - 28 pure unit tests (no DB, no async) with string assertions on serialized Decimals to catch quantization regressions
- `backend/app/features/invoices/schemas.py` - `InvoiceResponse.from_orm_with_totals` delegates to `discount_for`/`tax_for`/`document_total`
- `backend/app/features/quotes/schemas.py` - `QuoteResponse.from_orm_with_totals` delegates identically

## Decisions Made

- Kept `.quantize(CENTS)` with no explicit rounding argument in `discount_for`/`tax_for` (default ROUND_HALF_EVEN) — bit-for-bit identical to the shipped schema math, so existing invoice/quote totals cannot shift
- `ROUND_HALF_UP` appears only inside `margin_percent_for`, per the plan's one-decimal percent policy
- `summarize_margin` returns `revenue_basis="none"` for absent revenue regardless of the input basis, keeping the D-07 all-None figure set internally consistent

## Deviations from Plan

None - plan executed exactly as written.

## Known Stubs

None. `RevenueAnchor` is intentionally unexercised by this plan's unit tests — plan 33-02 imports it as a dict key at wave 2, per the plan's own acceptance criteria.

## Issues Encountered

None.

## User Setup Required

None - no external service configuration required.

## Next Phase Readiness

- Wave 2 plans (33-02 onward) can import the wire strings, dataclasses, and `summarize_margin` directly — remaining phase work is queries and assembly, not arithmetic
- The keystone honesty rule (Pitfall 9) and the D-01 invoices-win-outright rule are locked by named tests

---
*Phase: 33-profit-margin-tracking*
*Completed: 2026-07-27*

## Self-Check: PASSED

- backend/app/features/finance/margin_math.py: FOUND
- backend/tests/unit/test_margin_math.py: FOUND
- Commits ad1e656, a0be948, 5f174e2: FOUND
