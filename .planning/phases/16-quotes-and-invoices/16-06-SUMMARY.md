---
phase: 16-quotes-and-invoices
plan: 06
subsystem: testing
tags: [playwright, e2e, invoices, api-mocking, page-route]

# Dependency graph
requires:
  - phase: 16-quotes-and-invoices
    provides: invoices list page, invoice detail page, payment mutations, PDF download
provides:
  - 8 passing Playwright E2E tests covering invoices list and detail flows
affects: []

# Tech tracking
tech-stack:
  added: []
  patterns: [page.route proxy interception for API mocking, setupListRoutes/setupDetailRoutes helpers]

key-files:
  created: []
  modified:
    - web/tests/phase-16-invoices.spec.ts

key-decisions:
  - "Payment summary assertions use raw toFixed(2) values without comma formatting (matching actual page output)"
  - "Detail page wait-for-load uses getByRole heading to avoid breadcrumb+h1 strict mode violation"
  - "Unpaid tab count includes overdue invoices since overdue is a computed display state, not a backend status"

patterns-established:
  - "setupListRoutes/setupDetailRoutes helpers for DRY API mocking in invoice Playwright tests"
  - "patchHandler callback pattern for capturing and validating mutation request bodies"

requirements-completed: [INV-01, INV-02, INV-03]

# Metrics
duration: 5min
completed: 2026-03-18
---

# Phase 16 Plan 06: Invoice E2E Tests Summary

**8 Playwright E2E tests for invoices: list tabs/filtering/overdue styling/navigation, detail payment summary/record payment/mark paid, PDF download -- all using page.route() API mocking**

## Performance

- **Duration:** 5 min
- **Started:** 2026-03-18T04:31:50Z
- **Completed:** 2026-03-18T04:37:28Z
- **Tasks:** 1
- **Files modified:** 1

## Accomplishments
- Replaced 8 test.skip stubs with fully implemented passing Playwright E2E tests
- Tests cover invoices list (payment status tabs with counts, overdue row red border styling, status tab filtering, row click navigation)
- Tests cover invoice detail (payment summary Total/Paid/Balance, record partial payment with body verification, mark fully paid with body verification)
- Tests cover PDF download trigger via file save event
- All tests use page.route() proxy interception -- no live backend needed

## Task Commits

Each task was committed atomically:

1. **Task 1: Implement 8 Playwright E2E tests for invoices** - `1f13fc0` (test)

## Files Created/Modified
- `web/tests/phase-16-invoices.spec.ts` - 8 Playwright E2E tests for invoice list and detail pages (391 lines)

## Decisions Made
- Used `getByRole("heading")` instead of `getByText()` for invoice number assertions on detail pages to avoid strict mode violations from breadcrumb + h1 duplicate text
- Dollar amounts asserted without comma formatting (e.g., "$1650.00" not "$1,650.00") matching actual `Number.toFixed(2)` output
- Unpaid tab count is 2 (includes overdue invoice) since overdue is computed client-side from status + due_date, not a separate backend status

## Deviations from Plan

None - plan executed exactly as written.

## Issues Encountered
- `getByText('INV-0001')` resolved to 2 elements (breadcrumb span + h1 heading) causing strict mode violation -- resolved by using `getByRole("heading")` for detail page load checks
- `getByRole("button", { name: /Paid/ })` matched both "Partially Paid" and "Paid" tabs -- resolved with `^` anchored regex patterns
- Dollar sign `$` in getByText was problematic -- resolved by using plain string match without commas since the page uses `toFixed(2)` without locale formatting

## User Setup Required

None - no external service configuration required.

## Next Phase Readiness
- All invoice E2E tests passing, covering INV-01 (list), INV-02 (payments), INV-03 (PDF)
- Quote E2E tests (phase-16-quotes.spec.ts) still have test.skip stubs

---
*Phase: 16-quotes-and-invoices*
*Completed: 2026-03-18*

## Self-Check: PASSED
