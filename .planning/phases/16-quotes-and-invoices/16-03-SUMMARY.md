---
phase: 16-quotes-and-invoices
plan: "03"
subsystem: ui
tags: [nextjs, react, tanstack-query, typescript, invoices, payments, pdf]

# Dependency graph
requires:
  - phase: 16-01
    provides: Invoice/InvoiceLineItem types in api.ts, apiGet/apiPatch/apiFetchRaw in api-client.ts, StatusBadge component with overdue/unpaid/partially_paid/paid colors

provides:
  - Invoices list page at /invoices with 6 payment status tabs, overdue row highlighting, search, sort, pagination
  - Invoice detail page at /invoices/[id] with payment recording inline form, Mark Fully Paid, PDF download, overdue alert banner

affects:
  - phase-17-onwards: invoice navigation from any job detail link to /invoices/${id}

# Tech tracking
tech-stack:
  added: []
  patterns:
    - Client-side overdue computation from unpaid/partially_paid + past due_date (not a backend status)
    - Inline collapsible payment form with amount validation (max = remaining balance)
    - apiFetchRaw blob download pattern for PDF generation
    - border-l-2 border-red-400 overdue row highlight in DataTable
    - Conditional text-red-700 for overdue balance, text-green-700 for paid amount

key-files:
  created:
    - web/src/app/(dashboard)/invoices/page.tsx
    - web/src/app/(dashboard)/invoices/[id]/page.tsx
  modified: []

key-decisions:
  - "Draft tab maps to finalized_at === null invoices since InvoiceStatus has no draft backend value"
  - "Jobs fetched separately at /invoices list to resolve client_name and description (no join on invoices endpoint)"
  - "Mark Fully Paid fires without confirmation dialog per CONTEXT.md spec"
  - "Payment form shows in both main column and sidebar Record Payment button scrolls to inline form"

patterns-established:
  - "Overdue = client-side: (status unpaid OR partially_paid) AND due_date < now — never stored as backend status"
  - "isOverdue display priority: StatusBadge shows overdue even when status=unpaid or partially_paid"
  - "Record Payment inline form collapses via showPaymentForm state; amount validated client-side before mutation"

requirements-completed: [INV-01, INV-02, INV-03]

# Metrics
duration: 15min
completed: 2026-03-18
---

# Phase 16 Plan 03: Invoices Summary

**Invoices list with 6 payment-status tabs + computed Overdue tab (client-side), DataTable with overdue red border rows, and invoice detail with inline payment recording form, Mark Fully Paid, and apiFetchRaw PDF download**

## Performance

- **Duration:** ~15 min
- **Started:** 2026-03-18T01:25:00Z
- **Completed:** 2026-03-18T01:40:34Z
- **Tasks:** 2
- **Files modified:** 2

## Accomplishments

- Invoices list page at /invoices with 6 tabs (All, Unpaid, Partially Paid, Paid, Overdue, Draft), count badges, overdue rows highlighted with border-l-2 border-red-400, font-mono financial columns
- Invoice detail page with two-column layout, editable vs read-only line items based on finalized_at, inline collapsible payment form with validation, Mark Fully Paid button, PDF blob download
- Both routes verified with npx tsc --noEmit (0 errors) and npm run build

## Task Commits

1. **Task 1: Invoices list page** - `d2c09b1` (feat)
2. **Task 2: Invoice detail page** - `756384e` (feat)

**Plan metadata:** (docs commit follows)

## Files Created/Modified

- `web/src/app/(dashboard)/invoices/page.tsx` - 481 lines. Invoices list with DataTable, 6 payment status tabs, isOverdue computation, overdue row styling, client-side search/sort/pagination, jobs-map for client_name lookups
- `web/src/app/(dashboard)/invoices/[id]/page.tsx` - 785 lines. Invoice detail with two-column layout, line items (editable if not finalized), payment recording inline form, Mark Fully Paid, PDF download via apiFetchRaw, overdue alert banner, payment summary sidebar

## Decisions Made

- Draft tab maps to `finalized_at === null` invoices since `InvoiceStatus` only has `unpaid | partially_paid | paid` — no backend draft value
- Jobs fetched separately at list page to resolve `client_name` and `description` (no join endpoint on invoices)
- Mark Fully Paid fires immediately without confirmation dialog per CONTEXT.md spec
- Payment inline form duplicated in both main column and sidebar for discoverability; both trigger the same `showPaymentForm` state

## Deviations from Plan

None - plan executed exactly as written.

## Issues Encountered

None.

## User Setup Required

None - no external service configuration required.

## Next Phase Readiness

- /invoices and /invoices/[id] routes are live and build cleanly
- All INV requirements (INV-01, INV-02, INV-03) are complete
- Phase 16 Plan 04 (E2E tests and verification) can proceed

---
*Phase: 16-quotes-and-invoices*
*Completed: 2026-03-18*
