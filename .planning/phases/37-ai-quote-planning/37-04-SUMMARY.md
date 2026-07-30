---
phase: 37-ai-quote-planning
plan: 04
subsystem: api
tags: [python, decimal, finance, quotes, variance, fastapi]

# Dependency graph
requires:
  - phase: 37-02
    provides: quote_history_math (variance_for, prorated_pre_tax_totals)
  - phase: 37-01
    provides: review-state columns and the D-07 send gate on quotes
  - phase: 33-profit-margin-tracking
    provides: margin_math (quoted_revenue), finance/repository.py's invoice_amounts_query / approved_quote_amounts_query / to_anchored_amounts
provides:
  - "FinanceService.anchor_cost_context(project_id) — a public batched per-anchor cost context, so no caller loops rollup_for_project"
  - "QuoteVarianceService — quoted-vs-actual for one quote (job/scope/project-level D-14) and for one project's drill-down (per-anchor rows + total)"
  - "GET /api/v1/quotes/{quote_id}/variance and GET /api/v1/projects/{project_id}/financials/quote-variance, both finance.view-gated"
affects: [37-07, 37-08, 37-09, 37-10, 37-11, 37-12 (any surface reading quoted-vs-actual)]

# Tech tracking
tech-stack:
  added: []
  patterns:
    - "anchor_cost_context/rollup_for_project share one private _build_margin_context builder — ProjectMarginContext is constructed in exactly one place, verified by a grep-count-1 acceptance criterion"
    - "D-14 project-level quote variance: group line items by normalised field (strip().casefold(), empty/NULL dropped), allocate the quoted leg with the shipped prorated_pre_tax_totals, match each group to the project's job by normalised trade_type in ONE batched query"
    - "D-02 comparable gate: an anchor's actual is null (never zero) until at least one non-deleted invoice exists at that anchor — invoice existence IS the gate, invoice amount is never the compared value"

key-files:
  created:
    - backend/app/features/quotes/variance_service.py
  modified:
    - backend/app/features/finance/service.py
    - backend/app/features/quotes/schemas.py
    - backend/app/features/quotes/router.py
    - backend/app/main.py
    - backend/tests/test_phase_37_e2e.py

key-decisions:
  - "anchor_cost_context and rollup_for_project both call a new private _build_margin_context(cost_side) so ProjectMarginContext has exactly one construction site (acceptance-grep-verified), without changing rollup_for_project's query count or await order"
  - "A job/scope-anchored quote's WHOLE comparison (quoted, actual, variance, variance_percent) nulls together when the anchor has no invoice — a missing comparison is not a partial one; a project-level quote's per-field trades instead keep `quoted` (always known from the document) and null only actual/variance/variance_percent per group"
  - "The project-level quote's top-level actual/variance is reported only when every field group is comparable; a partial sum across a mix of invoiced/uninvoiced groups would misrepresent completeness"
  - "project_quote_variance's project-existence check (active_entity_or_404) runs before any aggregate query, mirroring PortfolioService.project_financials — a missing/soft-deleted/cross-tenant project 404s on one cheap lookup"
  - "project_variance_router declared in quotes/router.py (not finance/router.py) — every definition it composes is quote-domain, and quotes -> finance is the codebase's established one-way import direction"

patterns-established:
  - "PROJECT_TOTAL_LABEL = 'Project total' is the one place the drill-down's summary row name lives"

requirements-completed: [FINAI-05]

# Metrics
duration: 35min
completed: 2026-07-30
---

# Phase 37 Plan 04: Quote Variance — Quoted-vs-Actual Read Side Summary

**QuoteVarianceService composes the shipped quoted-revenue and per-anchor-cost owners into one quote's quoted-vs-actual (including a D-14 per-field breakdown for project-level quotes) and a project-wide drill-down table, both served by two new `finance.view`-gated endpoints.**

## Performance

- **Duration:** 35 min
- **Started:** 2026-07-30T19:05:00Z
- **Completed:** 2026-07-30T19:40:00Z
- **Tasks:** 3
- **Files modified:** 5 (1 created)

## Accomplishments
- `FinanceService.anchor_cost_context(project_id)` is now the one public, batched entry point for per-anchor cost — pinned equal to `rollup_for_project`, `job_cost_breakdown` and `trade_scope_spend` by three equivalence tests, with `ProjectMarginContext` constructed in exactly one private builder shared by both callers
- `QuoteVarianceService.quote_variance` reads one quote's quoted-vs-actual for all three anchor shapes (job, trade scope, project-level D-14 per-field group), composing `quoted_revenue`, `variance_for`, `prorated_pre_tax_totals` and `contributing_anchor_cost` — never a restated cost sum, discount formula, or percentage
- The D-02 "comparable" gate is enforced the same way everywhere: an anchor's `actual` is `None` (never `0`) until it has at least one non-deleted invoice, determined by the shipped `invoice_amounts_query()`
- `QuoteVarianceService.project_quote_variance` builds the financials drill-down's per-anchor table (one row per invoiced, approved-quote anchor, plus a summed `Project total` row), using two bounded label lookups and the same batched `anchor_cost_context`
- Two new endpoints — `GET /quotes/{quote_id}/variance` and `GET /projects/{project_id}/financials/quote-variance` — both gated by `require_permission("finance.view")`, the backend half of the Trap 8 double lock and the half that actually holds (the quote detail page has no UI gate today)

## Task Commits

Each task was committed atomically. Two of the three landed inside another concurrently-running executor's broad commit (see Deviations) rather than a standalone commit of their own; content and attribution are noted below.

1. **Task 1: A public batched anchor-cost context on FinanceService** - swept into `0a04c6f` ("feat(37-05): wire the Line Items table...") — the finance/service.py extraction and its three equivalence tests are present in that commit's diff
2. **Task 2: QuoteVarianceService — one quote's quoted-vs-actual, including D-14** - swept into `556848a` ("docs(37-05): complete AI quote suggestions editor surface plan") — variance_service.py, schemas.py additions and the six quote_variance tests are present in that commit's diff
3. **Task 3: The two variance endpoints, finance-gated** - `071163b` (feat) — committed standalone as intended

**Plan metadata:** (this commit)

## Files Created/Modified
- `backend/app/features/finance/service.py` - `anchor_cost_context` extracted as a public method; `_build_margin_context` is the single `ProjectMarginContext` construction site, called by both `anchor_cost_context` and `rollup_for_project`
- `backend/app/features/quotes/variance_service.py` - New: `QuoteVarianceService` (`quote_variance`, `project_quote_variance`), `QuoteVarianceTrade`/`QuoteVarianceResult`/`ProjectQuoteVarianceResult` frozen dataclasses, D-14 field-grouping helpers
- `backend/app/features/quotes/schemas.py` - `QuoteVarianceTradeResponse`, `QuoteVarianceResponse`, `ProjectQuoteVarianceResponse` and their `to_*` mappers from the service's pure-math results
- `backend/app/features/quotes/router.py` - `GET /{quote_id}/variance`; new `project_variance_router` with `GET /projects/{project_id}/financials/quote-variance`
- `backend/app/main.py` - Registers `project_variance_router` beside `scope_quote_router`
- `backend/tests/test_phase_37_e2e.py` - 3 equivalence tests (Task 1), 6 `QuoteVarianceService` tests including all three D-14 behaviors (Task 2), 5 endpoint tests covering both 403 denials, the drill-down table, its empty state, and tenant isolation (Task 3) — 14 new tests total, plus shared fixture helpers (project/trade-scope/cost-entry/invoice creation, quote approval via SQL, PM/admin token headers) copied in per the self-contained-test-file convention

## Decisions Made
- The project-level quote's per-field grouping deliberately does NOT reuse Phase 33's D-14 last-resort revenue rule — that rule answers a different question (whole-project revenue resolution) and a blended number would defeat the per-trade feedback loop this plan exists to close (stated in the plan and preserved verbatim in the module docstring)
- A project-level quote's top-level `actual`/`variance` is reported only when every field group resolved a comparable actual; a partial sum across a mix of invoiced/uninvoiced groups would misrepresent completeness as certainty
- `project_quote_variance` checks project existence (`active_entity_or_404`) before running any aggregate query, mirroring the `PortfolioService.project_financials` precedent — cheap failure path for missing/soft-deleted/cross-tenant ids

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 2 - Missing critical functionality] Project-existence 404 on the drill-down endpoint**
- **Found during:** Task 3 (writing the tenant-isolation test)
- **Issue:** The plan's behavior list requires "a project in another tenant: 404, never a leaked row." Without an explicit project lookup, RLS alone makes cross-tenant/missing/soft-deleted project ids resolve to an empty (200) result — no anchors, null total — rather than a 404, which both leaks the existence of a valid-but-inaccessible id path and contradicts the plan's own acceptance list.
- **Fix:** Added `active_entity_or_404(await self.db.get(Project, project_id), ...)` as the first statement in `project_quote_variance`, before any aggregate query — same ordering rationale as the shipped `PortfolioService.project_financials`.
- **Files modified:** `backend/app/features/quotes/variance_service.py`
- **Verification:** `test_project_quote_variance_is_tenant_isolated` asserts 404 for a cross-tenant project id.
- **Committed in:** `071163b` (Task 3 commit)

---

**Total deviations:** 1 auto-fixed (missing critical functionality — the D-02 style honest-absence contract was already followed for anchors; the plan's own tenant-isolation criterion needed the explicit guard to hold)
**Impact on plan:** Necessary for correctness against the plan's own must_haves. No scope creep.

### Parallel-execution note (not a plan deviation)

Two concurrently-running executors (plans 37-05, 37-06) were active in the shared working tree per the orchestrator's wave assignment. Twice during this plan's execution, a broad commit from one of those agents' final "complete plan" step swept up this plan's already-`git add`-staged Task 1 and Task 2 changes before this executor's own `git commit` ran (visible as `backend/app/features/finance/service.py`, `backend/app/features/quotes/variance_service.py`, `backend/app/features/quotes/schemas.py`, and the corresponding `test_phase_37_e2e.py` hunks inside commits `0a04c6f` and `556848a`, whose messages reference plan 37-05). The content is verified correct and present in the git history (see Self-Check); only the commit attribution for Tasks 1–2 is not a clean standalone commit as the protocol intends. Task 3 landed in its own commit (`071163b`) as expected. No user action needed; documented here for traceability.

## Issues Encountered

None beyond the parallel-execution commit interleaving noted above.

## User Setup Required

None - no external service configuration required.

## Next Phase Readiness

- `QuoteVarianceService.quote_variance` and `.project_quote_variance`, plus their response schemas, are ready for the web surfaces (37-07+) that render "Quoted vs Actual" on the quote detail page and the project financials drill-down.
- `FinanceService.anchor_cost_context` is now the shipped composition point for any future per-anchor cost need — a later plan needing per-anchor cost must call this, never loop `rollup_for_project`.
- Backend suite: `tests/test_phase_37_e2e.py` (26 tests) + `tests/unit` all green (282 total); `tests/test_phase_35_e2e.py` (24 tests, the rollup query-count/latency pins) still green after the `anchor_cost_context` extraction; `tests/test_phase_16_e2e.py`, `tests/test_project_quotes_e2e.py`, `tests/test_quote_validity.py` unaffected (12 tests green); `ruff check .` and `ruff format --check .` clean repo-wide.

---
*Phase: 37-ai-quote-planning*
*Completed: 2026-07-30*

## Self-Check: PASSED

All created/modified files found on disk (finance/service.py, quotes/variance_service.py,
quotes/schemas.py, quotes/router.py, main.py, tests/test_phase_37_e2e.py); all three
referenced commit hashes (0a04c6f, 556848a, 071163b) found in git log.
