---
phase: 35-web-financial-dashboard
plan: 07
subsystem: api
tags: [fastapi, sqlalchemy, postgres, margin-trend, pytest]

# Dependency graph
requires:
  - phase: 35-web-financial-dashboard (35-01)
    provides: trend_math — dense month keys, as-of replay, window_slice, DatedCost/DatedDocument/TrendInputs
  - phase: 35-web-financial-dashboard (35-05)
    provides: public finance query builders (invoice_amounts_query, approved_quote_amounts_query, to_anchored_amounts) + PortfolioRepository
  - phase: 35-web-financial-dashboard (35-06)
    provides: PortfolioService.project_financials, project_header 404 path, test_phase_35_e2e seeders
  - phase: 33-margin-visibility
    provides: D-01 revenue resolution (anchor_revenues / combined_anchor_revenue), summarize_margin, rollup_for_project
provides:
  - "GET /api/v1/projects/{project_id}/financials/trend?window=3m|6m|12m|all — dense monthly cumulative buckets, gated on finance.view"
  - "MarginTrendResponse + TrendBucketResponse wire schemas (month, cost, full MarginSummary block)"
  - "PortfolioService.margin_trend — six bounded reads then a pure trend_math replay"
  - "Dated invoice/approved-quote aggregates: Invoice.issued_at and COALESCE(approved_at, created_at) AS approved_on"
  - "PortfolioRepository.dated_invoices_for_project / dated_quotes_for_project / dated_project_level_quote"
  - "Six named trend e2e tests, led by the final-bucket reconciliation"
affects: [35-08 web margin trend chart, 36-ai-profitability-analysis]

# Tech tracking
tech-stack:
  added: []
  patterns:
    - "Shared query builders grow trailing columns; existing callers keep the row[:6] contract and new callers read the appendices BY LABEL"
    - "As-of replay over shipped pure math instead of delta accumulation, so the final bucket is a self-verifying reconciliation"
    - "Trend test fixtures dated relative to the current UTC month, never a fixed calendar year"

key-files:
  created: []
  modified:
    - backend/app/features/finance/repository.py
    - backend/app/features/finance/portfolio_repository.py
    - backend/app/features/finance/portfolio_service.py
    - backend/app/features/finance/schemas.py
    - backend/app/features/finance/router.py
    - backend/tests/test_phase_35_e2e.py

key-decisions:
  - "Dated document rows are read by label (row.issued_at / row.approved_on) through one _to_dated_document mapper, not by the plan's positional date_index — portfolio_repository's own documented row-access rule forbids positional reads past the shared six columns, and a label survives the next appended column"
  - "_to_dated_document takes the timestamp as an argument rather than a column name, so there is no getattr indirection and no column-name constants"
  - "The trend's dated-quote query keeps ORDER BY created_at DESC (not approved_on DESC) so the first row per anchor is still the one the shipped rollup resolves against — reordering would break the reconciliation the trend exists to prove"
  - "test_trend_quote_without_approved_at_uses_created_at backdates created_at via SQL so the fallback is proven at an EARLIER bucket, not merely at the final one where every quote lands anyway"
  - "margin_trend runs project_header BEFORE the six trend reads, reusing 35-06's single 404 path for missing, soft-deleted and cross-tenant ids"

patterns-established:
  - "Appending a column to a shared aggregate builder: add it to select AND group_by with a WHY comment, keep to_anchored_amounts' row[:6] contract, read the appendix by label"
  - "Trend orchestration: one _trend_inputs method holds every await; margin_trend itself is four lines of pure composition"

requirements-completed: [MARG-04]

# Metrics
duration: 24min
completed: 2026-07-29
---

# Phase 35 Plan 07: Project Margin Trend Summary

**`GET /projects/{id}/financials/trend?window=` serving dense monthly cumulative buckets from an as-of replay of the shipped Phase 33 margin pipeline, whose final bucket is provably bit-identical to `rollup_for_project`.**

## Performance

- **Duration:** 24 min
- **Started:** 2026-07-29T04:01:00Z
- **Completed:** 2026-07-29T04:25:00Z
- **Tasks:** 3
- **Files modified:** 6

## Accomplishments

- The two shared document aggregates now carry their effective dates: `Invoice.issued_at`, and `COALESCE(Quote.approved_at, Quote.created_at) AS approved_on` so an approved-but-undated quote still buckets instead of vanishing. Every shipped caller is untouched — `to_anchored_amounts` still reads `row[:6]`.
- `PortfolioRepository` gained three dated-document methods, all returning `trend_math.DatedDocument` value objects through one `_to_dated_document` mapper and one `_for_project` traversal helper (the shipped dual-outerjoin predicate, not a restatement).
- `PortfolioService.margin_trend` composes six bounded queries — the same profile as the shipped project rollup — then hands everything to `trend_buckets` / `window_slice`. No date arithmetic, no bucketing and no window filtering happens in SQL.
- The endpoint is mounted after `/projects/{id}/financials`, gated inline on `finance.view`, with `window` constrained by a `Literal` and defaulted from `DEFAULT_TREND_WINDOW` (no `"12m"` literal in the router).
- Six named e2e tests, led by the keystone: the final bucket's cost equals the rollup's `grand_total` and its margin block matches field-for-field, on a fixture whose resolved basis is `mixed` so both D-01 legs are exercised.

## Task Commits

1. **Task 1: Dated document queries for the trend inputs** — `bde2268` (feat)
2. **Task 2: PortfolioService.margin_trend, response schema and the windowed route** — `204c772` (feat)
3. **Task 3: Five named trend tests, led by the reconciliation guarantee** — `496b02e` (test)

## Files Created/Modified

- `backend/app/features/finance/repository.py` — `invoice_amounts_query` appends `Invoice.issued_at`; `approved_quote_amounts_query` appends the `approved_on` COALESCE. Both added to `group_by` as well as `select`, each with a WHY comment.
- `backend/app/features/finance/portfolio_repository.py` — `_for_project` traversal helper, `_to_dated_document` mapper, and the three dated-document methods; module docstring's row-access rule updated now that the trailing date columns have landed.
- `backend/app/features/finance/portfolio_service.py` — `margin_trend`, `_trend_inputs` (every await in one place) and the pure `_to_trend_response` mapper.
- `backend/app/features/finance/schemas.py` — `TrendBucketResponse` and `MarginTrendResponse`, each documenting that revenue is resolved (not accumulated) and that the window slices buckets (not records).
- `backend/app/features/finance/router.py` — `GET /projects/{project_id}/financials/trend`, gated on `finance.view`.
- `backend/tests/test_phase_35_e2e.py` — six trend tests plus their fixtures; `_add_cost_entry` gained an `incurred_date` argument and `_backdate_quote` was added.

## Decisions Made

- **Dated rows are read by label, not by positional index.** The plan specified `_to_dated_document(row, date_index)` with indices 6 and 7. `portfolio_repository.py`'s own module docstring forbids positional reads past the shared six columns precisely so appended columns cannot silently shift a value. The mapper instead takes the already-resolved timestamp (`_to_dated_document(row, row.issued_at)`), which removes the index, removes a `getattr` indirection and removes the need for column-name constants.
- **`ORDER BY Quote.created_at DESC` was deliberately left alone.** Ordering by the new `approved_on` would look more "correct" for a trend, but the first row per anchor is what D-01 resolves against; changing it would make the trend resolve a different quote than the rollup does and would break the reconciliation that is the trend's only self-check.
- **The undated-quote test backdates `created_at`.** Left alone, a NULL-`approved_at` quote's `created_at` is "now", so its revenue would appear only in the final bucket — where every quote appears anyway. Backdating it two months proves the fallback actually dates the quote, and the same test still asserts the final-bucket reconciliation.
- **The D-12 flag is coarser in the trend than in the rollup, and the fixture is built so they agree.** `trend_math._missing_cost_flag` applies the missing-cost rule to the project total (the trend carries no per-anchor cost split), while the rollup sweeps per anchor. The reconciliation fixture gives both revenue anchors real cost, so both sides report `incomplete: False` and the comparison stays honest rather than accidentally passing.
- **Trend fixtures are dated relative to the current UTC month.** The endpoint's last bucket is always the current month, so a hard-coded year (as `_seed_date` uses) would drift out of every window as time passes and quietly stop testing anything.

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 3 - Blocking] `_add_cost_entry` could not date a cost entry**

- **Found during:** Task 3 (trend fixtures)
- **Issue:** The shipped helper hard-coded `incurred_date=date(2026, 6, 1)`, so no fixture could spread spend across months — the trend has nothing to bucket without it.
- **Fix:** Added an `incurred_date: date = _DEFAULT_INCURRED_DATE` keyword argument; the literal became a named module constant so every existing caller keeps its exact behaviour.
- **Files modified:** `backend/tests/test_phase_35_e2e.py`
- **Verification:** All 20 Phase 35 tests pass, including the 14 that predate this plan.
- **Committed in:** `496b02e`

**2. [Rule 2 - Missing Critical] The undated-approval fallback needed a backdated `created_at`**

- **Found during:** Task 3 (`test_trend_quote_without_approved_at_uses_created_at`)
- **Issue:** With `approved_at` NULL and `created_at` set to insert time, the quote's revenue lands only in the final bucket, so the test would pass even if the COALESCE fallback were deleted and the quote were dated "today" by any other means.
- **Fix:** Added `_backdate_quote` (raw UPDATE, mirroring the file's existing `_approve_quote` convention) and asserted revenue is absent in the month before and present from the `created_at` month onward.
- **Files modified:** `backend/tests/test_phase_35_e2e.py`
- **Verification:** The test fails if the fallback is removed (the quote drops out of every bucket and the final-bucket reconciliation breaks).
- **Committed in:** `496b02e`

---

**Total deviations:** 2 auto-fixed (1 blocking, 1 missing critical)
**Impact on plan:** Both are test-side; neither changes the shipped API surface or the plan's architecture. Deviation 2 turns a test that would have passed vacuously into one that actually guards RESEARCH Pitfall 4.

## Issues Encountered

- One arithmetic slip in `test_trend_absent_revenue_is_null_not_zero`: the expected pre-revenue bucket count was off by one (buckets strictly before the invoice month are `first_months_back - invoice_months_back`, not `+ 1`). Caught by the test itself on first run and corrected before commit.

## Known Stubs

None — the endpoint is fully wired end to end (route → service → repository → SQL) and asserted against real data.

## Authentication Gates

None.

## User Setup Required

None — no external service configuration required.

## Next Phase Readiness

- The wire contract plan 35-08's `MarginTrend` web type expects is live and exercised: `{ project_id, window, buckets: [{ month, cost, margin }] }`, ascending and dense, with `margin.revenue` / `margin.margin` as literal JSON `null` before any revenue exists (Recharts `connectNulls` must stay at its `false` default).
- `?window=` accepts `3m | 6m | 12m | all`, defaults to `12m`, and 422s anything else — the web toggle can send the raw string with no client-side allow-list of its own.
- No blockers. The parallel-execution note in STATE.md still applies: the backend suites TRUNCATE all tables per test, so two concurrent pytest processes on `contractorhub_test` can deadlock.

## Self-Check: PASSED

All six modified files exist on disk; all three task commits (`bde2268`, `204c772`, `496b02e`) are reachable in the repository.

---
*Phase: 35-web-financial-dashboard*
*Completed: 2026-07-29*
