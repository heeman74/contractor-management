---
phase: 14-job-management
plan: "01"
subsystem: ui
tags: [react, next.js, tanstack-query, redux, shadcn, typescript, playwright]

# Dependency graph
requires:
  - phase: 13-web-foundation-and-auth
    provides: "StatusBadge, apiClient, Redux store, dashboard shell, sidebar/topbar layout"

provides:
  - "Full Job, JobNote, JobRequest, JobRequestResponse, TimeEntryResponse type definitions in web/src/types/api.ts"
  - "StatusBadge extended with quote (indigo) and invoiced (teal) color entries"
  - "ui-slice pageTitle field with setPageTitle action for breadcrumb UUID override"
  - "Topbar reads pageTitle from Redux to override UUID-shaped breadcrumb segments"
  - "shadcn dialog, table, tabs, textarea, alert components installed"
  - "12 Playwright E2E test stubs for JOBS-01 through JOBS-04"
  - "Jobs list page at /jobs with 7 status tabs, search, sortable columns, pagination"

affects: [14-02, 14-03, 15-schedule, 16-quotes-invoices]

# Tech tracking
tech-stack:
  added: ["shadcn dialog", "shadcn table", "shadcn tabs", "shadcn textarea", "shadcn alert"]
  patterns:
    - "useQueries from TanStack Query to run parallel count queries without hooks-in-loop violation"
    - "Suspense boundary wrapping useSearchParams() consumer per Next.js App Router requirement"
    - "URL-driven UI state: tab/page/q/sort/dir params control all list state"
    - "Client-side sort after server fetch using plain array .sort()"

key-files:
  created:
    - "web/src/app/(dashboard)/jobs/page.tsx"
    - "web/tests/jobs.spec.ts"
    - "web/src/components/ui/dialog.tsx"
    - "web/src/components/ui/table.tsx"
    - "web/src/components/ui/tabs.tsx"
    - "web/src/components/ui/textarea.tsx"
    - "web/src/components/ui/alert.tsx"
  modified:
    - "web/src/types/api.ts"
    - "web/src/components/shared/status-badge.tsx"
    - "web/src/store/slices/ui-slice.ts"
    - "web/src/components/layout/topbar.tsx"
    - "web/src/app/(dashboard)/page.tsx"

key-decisions:
  - "useQueries used for parallel per-status count queries to avoid hooks-in-loop Rules of Hooks violation"
  - "Requests tab count filtered client-side by status === 'pending' (not total request count)"
  - "Suspense boundary required by Next.js around useSearchParams() consumer in App Router"
  - "Search endpoint /api/v1/jobs/search used when query non-empty; list endpoint used otherwise"

patterns-established:
  - "URL search params drive all list state (tab, page, q, sort, dir) — no useState for these"
  - "300ms debounce for search input using useRef + setTimeout pattern"
  - "JobsPage default export = Suspense wrapper; JobsPageContent is the actual component"

requirements-completed: [JOBS-01]

# Metrics
duration: 25min
completed: "2026-03-16"
---

# Phase 14 Plan 01: Jobs List Foundation Summary

**Jobs list page at /jobs with 7 status tabs, 300ms debounced search, sortable columns, URL-driven pagination, and full Job/Request type foundation for downstream plans**

## Performance

- **Duration:** ~25 min
- **Started:** 2026-03-16T22:45:00Z
- **Completed:** 2026-03-16T23:08:11Z
- **Tasks:** 2
- **Files modified:** 12

## Accomplishments
- Full Job schema replacing stub (description/status_history/priority/version/timestamps — no title field)
- StatusBadge colorMap extended with quote (indigo) and invoiced (teal) for job lifecycle colors
- Redux ui-slice gains pageTitle for breadcrumb UUID segment override; topbar wired to read it
- 5 new shadcn components installed (dialog, table, tabs, textarea, alert) for Plans 02 and 03
- Jobs list page with 7 tabs (All/Quote/Scheduled/In Progress/Complete/Invoiced/Requests), search, sortable table, pagination
- 12 Playwright test stubs for JOBS-01 through JOBS-04

## Task Commits

Each task was committed atomically:

1. **Task 1: Shared foundation** - `b087246` (feat)
2. **Task 2: Jobs list page** - `87a5bd4` (feat)

**Plan metadata:** (docs commit follows)

## Files Created/Modified
- `web/src/types/api.ts` - Full Job, JobStatus, StatusHistoryEntry, JobTransitionRequest, JobNoteResponse, JobRequestResponse, TimeEntryResponse types
- `web/src/components/shared/status-badge.tsx` - Added quote (indigo) and invoiced (teal) entries to colorMap
- `web/src/store/slices/ui-slice.ts` - Added pageTitle: string | null and setPageTitle reducer
- `web/src/components/layout/topbar.tsx` - Reads pageTitle from Redux, overrides UUID breadcrumb segments; adds requests to SEGMENT_LABELS
- `web/src/app/(dashboard)/jobs/page.tsx` - Full jobs list page (505 lines)
- `web/tests/jobs.spec.ts` - 12 test.skip stubs for JOBS-01 through JOBS-04
- `web/src/components/ui/dialog.tsx` - shadcn dialog (new)
- `web/src/components/ui/table.tsx` - shadcn table (new)
- `web/src/components/ui/tabs.tsx` - shadcn tabs (new)
- `web/src/components/ui/textarea.tsx` - shadcn textarea (new)
- `web/src/components/ui/alert.tsx` - shadcn alert (new)
- `web/src/app/(dashboard)/page.tsx` - Fixed job.description reference (was job.title — auto-fix)

## Decisions Made
- useQueries from TanStack Query used for parallel per-status count queries (avoids hooks-in-loop React violation)
- Requests tab count badge shows pending-only count via client-side `.filter(r => r.status === "pending")`
- Suspense boundary wraps useSearchParams() consumer (Next.js App Router requirement for build to pass)

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 1 - Bug] Fixed dashboard page using removed Job.title field**
- **Found during:** Task 1 (TypeScript check after types update)
- **Issue:** `web/src/app/(dashboard)/page.tsx` referenced `job.title` which no longer exists after replacing the Job stub with the full schema (field is `description`)
- **Fix:** Changed `job.title` to `job.description` in the recent activity list rendering
- **Files modified:** `web/src/app/(dashboard)/page.tsx`
- **Verification:** `npx tsc --noEmit` exits 0 after fix
- **Committed in:** `b087246` (Task 1 commit)

**2. [Rule 3 - Blocking] Wrapped useSearchParams() in Suspense boundary**
- **Found during:** Task 2 (npm run build)
- **Issue:** Next.js App Router requires `useSearchParams()` to be wrapped in a Suspense boundary; build failed with prerender error at /jobs
- **Fix:** Renamed inner component to `JobsPageContent`, added `JobsPage` default export that wraps it in `<Suspense>`
- **Files modified:** `web/src/app/(dashboard)/jobs/page.tsx`
- **Verification:** `npm run build` completes with 0 errors; /jobs shows as static route
- **Committed in:** `87a5bd4` (Task 2 commit)

---

**Total deviations:** 2 auto-fixed (1 bug, 1 blocking build issue)
**Impact on plan:** Both auto-fixes essential for correctness and build success. No scope creep.

## Issues Encountered
- None beyond the auto-fixed items above.

## User Setup Required
None - no external service configuration required.

## Next Phase Readiness
- All shared types and components needed by Plans 14-02 and 14-03 are in place
- shadcn dialog/table/tabs/textarea/alert ready for job detail and request review pages
- Jobs nav item already in sidebar (was present from Phase 13)
- `/jobs/[id]` and `/jobs/requests/[id]` routes need to be created in Plan 14-02 and 14-03

## Self-Check: PASSED

All key files found on disk:
- web/src/app/(dashboard)/jobs/page.tsx: FOUND
- web/tests/jobs.spec.ts: FOUND
- web/src/components/ui/dialog.tsx: FOUND
- web/src/components/ui/table.tsx: FOUND
- web/src/components/ui/tabs.tsx: FOUND
- web/src/components/ui/textarea.tsx: FOUND
- web/src/components/ui/alert.tsx: FOUND

All task commits verified:
- b087246: FOUND
- 87a5bd4: FOUND

---
*Phase: 14-job-management*
*Completed: 2026-03-16*
