---
phase: 17-crm-clients-and-contractors
plan: 02
subsystem: ui
tags: [next.js, react, tanstack-query, typescript, shadcn, tailwind]

# Dependency graph
requires:
  - phase: 17-01
    provides: ClientListItem, ClientDetail, ClientProperty types in api.ts; CRM backend endpoints /api/v1/crm/clients

provides:
  - /clients page: searchable, sortable, paginated client list with DataTable
  - /clients/[id] page: two-column client detail with job history, saved properties, and sidebar cards

affects:
  - 17-03 (contractor pages — same layout patterns apply)
  - 17-04 (schedule editor — reuses two-column structure)
  - 17-05 (navigation links — sidebar must link to /clients)

# Tech tracking
tech-stack:
  added: []
  patterns:
    - Client list page with 300ms debounce search + client-side sort after server fetch
    - Two-column detail layout grid-cols-1 lg:grid-cols-[1fr_360px] gap-8
    - PropertyRow with per-row useState expand/collapse using ChevronDown/ChevronRight
    - InfoRow sidebar label/value helper component pattern

key-files:
  created:
    - web/src/app/(dashboard)/clients/page.tsx
    - web/src/app/(dashboard)/clients/[id]/page.tsx
  modified: []

key-decisions:
  - "Client list sorts client-side after server fetch — backend sorts by last_name by default; jobs_count sort is client-side only"
  - "Row click navigates to /clients/{user_id} (not profile id) — user_id is the stable public identifier per plan spec"
  - "Property expand/collapse uses per-row useState — no global state needed for read-only properties list"

patterns-established:
  - "Tag chips: bg-indigo-50 text-indigo-700 text-xs rounded-full px-2 py-0.5 — consistent across client list and detail"
  - "Sidebar InfoRow pattern: label (uppercase xs) + value (sm) — reusable for contractor profile sidebar"
  - "Loading skeleton uses two-column grid shape to match actual layout — no jarring layout shift"

requirements-completed:
  - CRM-01
  - CRM-02

# Metrics
duration: 5min
completed: 2026-03-19
---

# Phase 17 Plan 02: CRM Client Pages Summary

**Next.js client list (/clients) and detail (/clients/[id]) pages with searchable DataTable, two-column layout, job history, saved properties, and sidebar contact/metadata cards**

## Performance

- **Duration:** 5 min
- **Started:** 2026-03-19T06:53:15Z
- **Completed:** 2026-03-19T06:58:30Z
- **Tasks:** 2
- **Files modified:** 2

## Accomplishments
- Client list page at /clients: debounced search, sortable Name/Jobs columns, pagination, 10-skeleton loading state, empty + error states per UI-SPEC copy
- Client detail page at /clients/[id]: two-column grid with job history table (clickable to /jobs/[id]), saved properties with expand/collapse, and full sidebar (contact, tags, rating, referral, preferred contractor linked to /contractors/[id], billing, admin notes)
- TypeScript compiles without errors across both files

## Task Commits

Each task was committed atomically:

1. **Task 1: Client list page** - `73d1433` (feat)
2. **Task 2: Client detail page** - `0c8d4f5` (feat)

**Plan metadata:** (pending — created in this step)

## Files Created/Modified
- `web/src/app/(dashboard)/clients/page.tsx` - Client list with search, sort, pagination, DataTable
- `web/src/app/(dashboard)/clients/[id]/page.tsx` - Client detail two-column layout with all sidebar cards

## Decisions Made
- Client-side sort after server fetch for Name and Jobs columns — backend default sort (last_name) covers most cases; jobs_count sort not supported server-side
- Row click uses `client.user_id` (not `client.id`) as URL segment — per plan spec, matches backend `/api/v1/crm/clients/{user_id}` route
- Per-property expand/collapse useState — lightweight and sufficient for read-only list; no accordion library needed

## Deviations from Plan

None - plan executed exactly as written.

## Issues Encountered

None.

## User Setup Required

None - no external service configuration required.

## Next Phase Readiness
- /clients and /clients/[id] pages are complete and TypeScript-clean
- Two-column detail layout pattern established; contractor profile pages (Plan 03) can reuse the same grid and InfoRow/PropertyRow patterns
- Tag chip styling (bg-indigo-50 text-indigo-700) and sidebar card structure are consistent — ready for contractor pages

---
*Phase: 17-crm-clients-and-contractors*
*Completed: 2026-03-19*
