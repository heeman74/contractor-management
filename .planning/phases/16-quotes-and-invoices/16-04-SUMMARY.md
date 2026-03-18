---
phase: 16-quotes-and-invoices
plan: "04"
subsystem: ui
tags: [react, nextjs, react-hook-form, dnd-kit, zod, tanstack-query]

# Dependency graph
requires:
  - phase: 16-01
    provides: Quote/Invoice types in api.ts, backend endpoints for quotes/invoices/templates
  - phase: 16-02
    provides: Quote detail page and status management, apiFetchRaw pattern

provides:
  - Quote builder page at /quotes/[id]/edit with inline editable table, drag-reorder, template loading, preview mode
  - Job detail page Documents card with Create Quote and Generate Invoice buttons
  - Route semantics: /quotes/new/edit?job_id= for new, /quotes/{id}/edit for edit, ?revise=true for revision

affects: [16-quotes-and-invoices]

# Tech tracking
tech-stack:
  added: []
  patterns:
    - "useFieldArray with DndContext/SortableContext for sortable inline table rows"
    - "Controller wrapper for base-ui Select with react-hook-form controlled values"
    - "enabled: !isNew guard on quote fetch to avoid /quotes/new 404"
    - "reset() with mapped existing data (not setValue) to avoid react-hook-form pitfall"

key-files:
  created:
    - web/src/app/(dashboard)/quotes/[id]/edit/page.tsx
  modified:
    - web/src/app/(dashboard)/jobs/[id]/page.tsx

key-decisions:
  - "Template loader uses onValueChange guard (if v) to handle null from base-ui Select"
  - "Select<string> generic annotation required for template loader to satisfy TypeScript onValueChange signature"
  - "Documents card in job detail shows for quote/complete/invoiced statuses — covers all document lifecycle states"
  - "quote-for-job query enabled for quote/complete/invoiced job statuses to support all three document card states"

patterns-established:
  - "SortableRow as separate component receives register/control/watch/errors from parent form to avoid excessive prop drilling alternatives"
  - "Sticky financial summary footer uses fixed bottom-0 with z-40 and pb-24 on page container to prevent overlap"

requirements-completed: [QUOTE-02]

# Metrics
duration: 25min
completed: 2026-03-18
---

# Phase 16 Plan 04: Quote Builder Summary

**Quote builder page with react-hook-form + dnd-kit sortable rows, template loading, Edit/Preview toggle, live financial footer, and job detail Documents card with Create Quote and Generate Invoice buttons**

## Performance

- **Duration:** 25 min
- **Started:** 2026-03-18T01:43:14Z
- **Completed:** 2026-03-18T02:08:00Z
- **Tasks:** 2
- **Files modified:** 2

## Accomplishments
- Quote builder at /quotes/[id]/edit with 1084 lines, handling new/edit/revise route semantics
- Inline editable table with drag-reorder via dnd-kit SortableContext and PointerSensor
- Template loading with replace-confirmation dialog, Edit/Preview tab toggle
- Live financial summary (subtotal, discount, tax, total) in sticky bottom footer
- Job detail page Documents card with conditional Create Quote / View Quote / Generate Invoice / View Invoice buttons

## Task Commits

Each task was committed atomically:

1. **Task 1: Quote builder page** - `7ffd35a` (feat)
2. **Task 2: Job detail integration buttons** - `5217922` (feat)

**Plan metadata:** (docs commit follows)

## Files Created/Modified
- `web/src/app/(dashboard)/quotes/[id]/edit/page.tsx` - Quote builder with react-hook-form, useFieldArray, dnd-kit, template loading, preview mode, create/update/revise mutations
- `web/src/app/(dashboard)/jobs/[id]/page.tsx` - Documents card with Create Quote, Generate Invoice buttons; quote-for-job and invoice-for-job queries

## Decisions Made
- `Select<string>` generic annotation required for the template loader — base-ui Select's `onValueChange` types `v` as `string | null` when no generic is specified, but our handler expects `string`
- Documents card shown for `quote`, `complete`, and `invoiced` job statuses to support the full document lifecycle without requiring multiple separate query enablement conditions
- `reset()` used to populate form from existing quote data (not `setValue` in useEffect) per RESEARCH.md pitfall #3 recommendation

## Deviations from Plan

None - plan executed exactly as written.

## Issues Encountered
- TypeScript error on template Select `onValueChange`: base-ui infers `v: string | null` when no generic is specified. Fixed with `Select<string>` annotation and `if (v)` guard.

## User Setup Required
None - no external service configuration required.

## Next Phase Readiness
- Quote builder is complete and integrated with job detail page
- Phase 16 (Quotes/Invoices) is now fully implemented across all 4 plans
- All quote and invoice CRUD, PDF download, status management, and builder UI are shipped

---
*Phase: 16-quotes-and-invoices*
*Completed: 2026-03-18*

## Self-Check: PASSED

- edit/page.tsx exists at expected path
- SUMMARY.md created
- Commit 7ffd35a (Task 1) confirmed in git log
- Commit 5217922 (Task 2) confirmed in git log
