---
phase: 33-profit-margin-tracking
plan: 03
subsystem: api
tags: [fastapi, sqlalchemy, pydantic, decimal, margin, finance]

# Dependency graph
requires:
  - phase: 33-01
    provides: margin_math pure functions (summarize_margin, resolve_anchor_revenue, combine_revenue_bases, missing_cost_data)
  - phase: 33-02
    provides: RevenueRepository bounded revenue queries, WorkSession.job_id, 13-test RED integration contract
  - phase: 32-labor-rates-and-cost-rollup
    provides: cost breakdown endpoints, labor derivation, unrated-seconds signal
provides:
  - MarginSummary wire schema with revenue/revenue_basis/margin/margin_percent/incomplete/incomplete_reasons
  - Additive margin field on CostBreakdownResponse and ProjectCostRollupResponse
  - FinanceService._anchor_margin (job/scope) and _project_margin (D-12 traversal, D-14 fallback)
  - All 13 Phase 33 integration tests green
affects: [33-04, 33-05, 34-budgeting, 35-dashboard, 36-ai-profitability]

# Tech tracking
tech-stack:
  added: []
  patterns:
    - "Margin assembled on shipped finance.view-gated responses via model_copy(update=...) — no new endpoints, URLs, or permission surface"
    - "Per-anchor D-01 resolution in Python from two bounded project-wide queries; quotes at invoiced anchors discarded"

key-files:
  created: []
  modified:
    - backend/app/features/finance/schemas.py
    - backend/app/features/finance/service.py
    - backend/app/features/finance/router.py
    - backend/app/features/invoices/service.py
    - backend/tests/test_phase_33_e2e.py

key-decisions:
  - "Quoted revenue leg quantized to cents (_quoted_revenue) so quote-backed figures match the invoice leg's revenue_from precision"
  - "Project margin always fetches BOTH revenue legs (two bounded queries); _anchor_revenues discards quotes at invoiced anchors instead of conditionally skipping the quote query"
  - "D-14 project-level quote is the anchor of last resort — counted only when no anchor resolved any revenue, preventing double-count with per-scope quotes"
  - "generate_manual now honors the Phase 25 trade_scope_id anchor: scope-anchored manual invoices validate the scope and skip the job status machine"

patterns-established:
  - "MarginCostSide / ProjectMarginContext frozen dataclasses carry the cost half so margin helpers take 2 args max"
  - "Test fixtures force job status transitions via raw SQL (SET LOCAL + UPDATE), mirroring the 33-02 quote-approval pattern"

requirements-completed: [MARG-01, MARG-02, MARG-03]

# Metrics
duration: 27min
completed: 2026-07-28
---

# Phase 33 Plan 03: Margin Assembly on Cost Responses Summary

**Margin block (revenue, $/% margin, revenue basis, honesty flags) wired onto the three shipped finance.view-gated cost responses via invoices-else-approved-quote resolution — all 13 Phase 33 integration tests green**

## Performance

- **Duration:** 27 min
- **Started:** 2026-07-28T00:17:21Z
- **Completed:** 2026-07-28T00:44:14Z
- **Tasks:** 2
- **Files modified:** 5

## Accomplishments

- `GET /jobs/{id}/cost-breakdown` and `GET /trade-scopes/{id}/cost-breakdown` now carry a `margin` block resolved from anchor-level revenue (invoices win outright, else latest approved quote, else honestly absent per D-07)
- `GET /projects/{id}/cost-entries` carries a project margin whose revenue and cost resolve through the identical dual-outerjoin traversal (D-12), with per-anchor D-01 resolution and the D-14 project-quote fallback
- The keystone honesty case holds: a legacy job with revenue and zero cost data reports its number AND the `no_cost_data` flag — never an unflagged 100% margin
- Full backend suite: 727 passed, 1 skipped — no endpoint, URL, or permission gate added or changed

## Task Commits

Each task was committed atomically:

1. **Task 1: MarginSummary schema and anchor-level margin assembly** - `5274412` (feat)
2. **Task 2: Project margin rollup with per-anchor resolution and router wiring** - `b7d647a` (feat)

## Files Created/Modified

- `backend/app/features/finance/schemas.py` - MarginSummary schema; additive `margin` field on both breakdown responses
- `backend/app/features/finance/service.py` - `_anchor_margin`, `_project_margin`, `_anchor_revenues`, `_labor_by_job`, `_anchor_costs_from_entries`, `_rates_by_contractor` refactor, `MarginCostSide`/`ProjectMarginContext` dataclasses
- `backend/app/features/finance/router.py` - `margin=rollup.margin` on the project rollup response constructor
- `backend/app/features/invoices/service.py` - `generate_manual` scope-anchor fix (Rule 1 deviation)
- `backend/tests/test_phase_33_e2e.py` - fixture corrections: `_mark_job_complete` SQL helper, `_post_invoice` completes job-anchored jobs first

## Decisions Made

- Quoted revenue quantized to cents in one `_quoted_revenue` helper shared by the anchor and project paths — quote subtotals arrive as `SUM(quantity * unit_price)` with 5 decimal places and would otherwise serialize as `"1500.00000"`
- Both project revenue legs are always fetched (the plan checker's final instruction): a quote at an uninvoiced anchor must count even when a sibling anchor is invoiced; `_anchor_revenues` discards quotes at invoiced anchors (test 8 mixed-basis proves it)
- Project-level approved quote counts only when NO anchor resolved revenue (D-14 without double-count)

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 1 - Bug] generate_manual ignored the trade_scope_id anchor**
- **Found during:** Task 1 (anchor margin tests)
- **Issue:** `InvoiceCreate` has advertised `trade_scope_id` since Phase 25 and its validator accepts scope-only payloads, but `InvoiceService.generate_manual` always loaded a job (404 "Job not found" for scope-anchored requests) and never set `trade_scope_id` on the Invoice
- **Fix:** Job branch unchanged; scope branch validates the TradeScope exists (entity_or_404) and skips the job status machine; `trade_scope_id` now set on the created invoice; `_mark_job_invoiced` only runs for job anchors
- **Files modified:** backend/app/features/invoices/service.py
- **Verification:** Scope-anchored margin tests pass; full backend suite (incl. phase 16/25 invoice suites) green
- **Committed in:** 5274412 (Task 1 commit)

**2. [Rule 1 - Bug] Test fixtures posted invoices on jobs in 'quote' status**
- **Found during:** Task 1 (job margin tests failed 409 "Job must be in 'complete' status")
- **Issue:** `_create_job` leaves jobs in `quote` status; manual invoices require `complete`, while quotes require `quote` — a blanket status change would break the quote-posting tests
- **Fix:** Added `_mark_job_complete` raw-SQL helper; `_post_invoice` takes `company_id` and completes job-anchored jobs immediately before invoicing (fixture correction only — no assertion weakened)
- **Files modified:** backend/tests/test_phase_33_e2e.py
- **Verification:** All 13 tests pass with original assertions intact
- **Committed in:** 5274412 (Task 1 commit)

**3. [Rule 1 - Bug] Unquantized quoted revenue leg**
- **Found during:** Task 1 (quote fallback test: `'1500.00000' != '1500.00'`)
- **Issue:** `pre_tax_total` on a quote aggregate returns the raw 5-decimal subtotal; the invoice leg quantizes via `revenue_from`
- **Fix:** `_quoted_revenue` helper quantizes to CENTS, used at the anchor path, the project per-anchor path, and the D-14 fallback
- **Files modified:** backend/app/features/finance/service.py
- **Verification:** `test_job_margin_falls_back_to_latest_approved_quote_basis` passes
- **Committed in:** 5274412 (Task 1 commit)

**4. [Deviation - Verification command] Task 1's `-k "anchor or basis or forbidden or legacy or incomplete"` filter over-matched**
- **Found during:** Task 1 verification
- **Issue:** The plan's filter substring-matches ALL 13 test names (e.g. "anchors", "mixed_basis", project "incomplete" tests), so it cannot exit 0 before Task 2 exists
- **Fix:** Verified Task 1 with the precise filter `-k "job_margin or trade_scope_margin or forbidden or legacy or unrated or no_revenue"` (exactly the 8 intended tests: 1,2,3,4,5,10,11,12) — all green
- **Files modified:** none
- **Verification:** 8 passed, 5 deselected; full file 13 passed after Task 2

---

**Total deviations:** 4 auto-fixed (3 Rule 1 bugs, 1 verification-command correction)
**Impact on plan:** All fixes necessary for correctness; no scope creep. The invoices-service fix repairs a real Phase 25 API gap the margin tests exposed.

## Issues Encountered

None beyond the documented deviations.

## User Setup Required

None - no external service configuration required.

## Next Phase Readiness

- Backend margin contract is now live and green; web (33-04) and mobile (33-05) UI plans that encoded this wire shape are already complete — Phase 33 is fully executed (5/5 plans)
- Phase 34 budgets can consume `grand_total`; Phase 36 AI receives `revenue_basis` and `incomplete_reasons` as designed

---
*Phase: 33-profit-margin-tracking*
*Completed: 2026-07-28*

## Self-Check: PASSED

All 5 modified files and SUMMARY exist on disk; commits 5274412 and b7d647a verified in git log.
