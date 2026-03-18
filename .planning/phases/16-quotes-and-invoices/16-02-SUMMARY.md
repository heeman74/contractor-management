---
phase: 16-quotes-and-invoices
plan: "02"
subsystem: ui
tags: [react, nextjs, tanstack-query, tailwindcss, typescript]

# Dependency graph
requires:
  - phase: 16-01
    provides: Quote/Invoice TypeScript types, apiGet/apiPost/apiFetchRaw client helpers, StatusBadge with quote/invoice color map
  - phase: 13-web-foundation-and-auth
    provides: App Router layout, Redux store, setPageTitle action, DataTable patterns
  - phase: 14-job-management
    provides: DataTable + status tabs pattern (jobs/page.tsx), two-column detail layout (jobs/[id]/page.tsx)
provides:
  - /quotes list page with 7 status tabs, count badges, search, sort, pagination
  - /quotes/[id] detail page with line items table, activity log, status stepper, lifecycle actions, PDF download
  - Send Quote confirmation dialog
  - Extend Expiry dialog with date picker
  - Declined/expired alert banners
  - Generate Invoice button (approved + job complete)
  - Linked Invoice card
  - PDF download via apiFetchRaw blob URL pattern
affects: [16-03, 16-04, future-client-portal]

# Tech tracking
tech-stack:
  added: []
  patterns:
    - "Fetch all quotes once, derive per-status counts client-side (no separate count requests)"
    - "Jobs lookup map (jobsMap[job_id]) for client/job info in quotes list"
    - "apiFetchRaw blob download: fetch → blob() → createObjectURL → anchor click → revokeObjectURL"
    - "Status stepper component with STEPPER_STEPS array and indigo completed/current/future styling"
    - "Context-sensitive action buttons using if/else blocks per quote.status value"

key-files:
  created:
    - web/src/app/(dashboard)/quotes/page.tsx
    - web/src/app/(dashboard)/quotes/[id]/page.tsx
  modified: []

key-decisions:
  - "Fetch all quotes once + filter client-side (no per-status requests) — quotes list is small enough for single fetch"
  - "Jobs lookup map built from /api/v1/jobs/ to resolve client_name and description in quotes list"
  - "Generate Invoice button gated on job?.status === 'complete' per CONTEXT.md locked decision"
  - "Extend expiry uses POST /{id}/extend with { new_expiry_date } body field (verified from router.py)"
  - "Revised quotes excluded from All tab via client-side filter (backend hides via get_active_quotes)"

patterns-established:
  - "Quote list page: client-side filter/sort/paginate from single fetch (suitable for moderate dataset sizes)"
  - "Quote detail: StatusStepper component with STEPPER_STEPS array maps status index to indigo styling"
  - "PDF download: toast.loading → apiFetchRaw → blob → objectURL → anchor.click → revokeObjectURL → toast.dismiss"

requirements-completed: [QUOTE-01, QUOTE-03, QUOTE-04]

# Metrics
duration: 18min
completed: 2026-03-17
---

# Phase 16 Plan 02: Quotes List and Detail Pages Summary

**Quotes list page with 7 status tabs + counts, and quote detail with full lifecycle actions (Send, Revise, Extend Expiry, PDF download via apiFetchRaw, Generate Invoice) and declined/expired alert banners**

## Performance

- **Duration:** 18 min
- **Started:** 2026-03-17T09:36:32Z
- **Completed:** 2026-03-17T09:54:12Z
- **Tasks:** 2
- **Files modified:** 2

## Accomplishments
- Quotes list page at /quotes with 7 status tabs (All, Draft, Sent, Viewed, Approved, Declined, Expired), count badges derived from single fetch, 300ms debounced search, client-side sort + pagination
- Quote detail page at /quotes/[id] with two-column layout: line items table with financial summary footer, admin notes, activity log timeline on left; status stepper, context-sensitive action buttons, quote info, financial summary, linked invoice card on right
- Send Quote confirmation dialog, Extend Expiry date picker dialog, Generate Invoice mutation with redirect
- PDF download (QUOTE-04) using apiFetchRaw blob URL pattern with loading toast and error handling
- Declined alert (red left-border banner) with decline reason; Expired alert (amber) with Extend/Revise CTA buttons

## Task Commits

Each task was committed atomically:

1. **Task 1: Quotes list page** - `887dd99` (feat)
2. **Task 2: Quote detail page** - `b705a23` (feat)

**Plan metadata:** (included in final docs commit)

## Files Created/Modified
- `web/src/app/(dashboard)/quotes/page.tsx` — Quotes list: DataTable, 7 status tabs, count badges, search, sort, pagination (428 lines)
- `web/src/app/(dashboard)/quotes/[id]/page.tsx` — Quote detail: two-column layout, line items, activity log, lifecycle actions, PDF download (877 lines)

## Decisions Made
- Fetch all quotes once + filter client-side: no separate per-status count requests. Quotes are small enough for a single fetch and this avoids 6+ parallel requests on page load.
- Jobs lookup map via single `/api/v1/jobs/` fetch: resolves job description and client_name in the quotes table without N+1 requests.
- Generate Invoice button gated on `job?.status === "complete"` per CONTEXT.md locked decision (job must be finished before invoicing).
- Extend expiry POST endpoint is `/quotes/{id}/extend` with body `{ new_expiry_date }` — verified against router.py to avoid using incorrect `/extend_expiry` path.
- "Revised" quotes excluded from All tab client-side (backend `get_active_quotes` already filters them; defensive client filter ensures correctness even if API changes).

## Deviations from Plan

None — plan executed exactly as written.

## Issues Encountered

None — TypeScript compiled cleanly on first attempt for both files. Build succeeded without warnings.

## User Setup Required

None — no external service configuration required.

## Next Phase Readiness
- /quotes and /quotes/[id] are complete and ready for Plan 03 (quote builder/editor)
- The /quotes/[id]/edit route is referenced from action buttons but will be implemented in Plan 03
- Invoice generation redirects to /invoices/{id} which will be built in Plan 04

---
*Phase: 16-quotes-and-invoices*
*Completed: 2026-03-17*
