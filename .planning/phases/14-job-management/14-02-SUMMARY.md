---
phase: 14-job-management
plan: "02"
subsystem: ui
tags: [react, next.js, tanstack-query, redux, shadcn, typescript, status-transitions]

# Dependency graph
requires:
  - phase: 14-job-management
    plan: "01"
    provides: "Job types, StatusBadge, setPageTitle, shadcn dialog/textarea/alert, api-client"

provides:
  - "Job detail page at /jobs/[id] with two-column layout"
  - "Status transition controls: primary forward button + dropdown for revert/cancel"
  - "Confirmation dialogs for revert (Revert job status?) and cancel (Cancel this job?)"
  - "Cancel reason saved as job note via POST /api/v1/jobs/{id}/notes"
  - "409 version conflict handling: refetch + inline error banner"
  - "Photo note lightbox via shadcn Dialog max-w-3xl"
  - "Time tracking card with total duration and expandable entries"
  - "Breadcrumb override: Job #XXXXXXXX via Redux setPageTitle"

affects: [14-03]

# Tech tracking
tech-stack:
  added: []
  patterns:
    - "Three parallel TanStack queries (job, notes, time-entries) with independent error handling"
    - "time-entries query uses retry:false for graceful 404 fallback"
    - "Cancel flow: transition mutation onSuccess callback fires second apiPost for note creation"
    - "queryClient.setQueryData() for immediate optimistic cache update after successful transition"
    - "React 19 use(params) for async Next.js App Router params"

key-files:
  created:
    - "web/src/app/(dashboard)/jobs/[id]/page.tsx"
  modified: []

key-decisions:
  - "DropdownMenuTrigger from base-ui does not support asChild prop — styled inline with Tailwind classes matching Button outline/sm variant"
  - "Cancel mutation uses onSuccess callback pattern (not two separate mutations) to sequence: transition first, then note creation on success"
  - "time-entries query has retry:false since /time-entries endpoint may not exist for all jobs — empty array on error"

patterns-established:
  - "Inline cancel note pattern: fire note POST inside transitionMutation onSuccess to ensure atomicity order"
  - "split button pattern: primary Button + DropdownMenuTrigger sibling in flex row"

requirements-completed: [JOBS-02, JOBS-03]

# Metrics
duration: 12min
completed: "2026-03-16"
---

# Phase 14 Plan 02: Job Detail Page Summary

**Job detail page at /jobs/[id] with two-column layout, status lifecycle transitions (forward/revert/cancel with dialogs), notes with photo lightbox, time tracking, and breadcrumb override**

## Performance

- **Duration:** ~12 min
- **Started:** 2026-03-16T23:10:55Z
- **Completed:** 2026-03-16T23:22:00Z
- **Tasks:** 1
- **Files modified:** 1

## Accomplishments

- Full job detail page with two-column layout (description/notes/activity on left; status+actions/metadata/time on right)
- Three parallel TanStack queries: job detail, notes, time-entries (graceful 404 fallback on time-entries)
- Breadcrumb override via Redux `setPageTitle` shows "Job #XXXXXXXX" (first 8 chars uppercased)
- Status transition controls: primary button for forward, ChevronDown dropdown for revert and cancel options
- Forward transitions execute immediately with `toast.success`; revert/cancel use confirmation dialogs
- Cancel dialog requires a reason which is saved as a job note via `POST /api/v1/jobs/{id}/notes`
- 409 version conflict shows inline `Alert` banner and triggers `invalidateQueries` refetch
- Photo attachment thumbnails in notes section open in a `max-w-3xl` lightbox Dialog
- Time tracking card shows total formatted duration and expandable per-entry list
- Quote/Invoice stub card renders only when `purchase_order_number` or `external_reference` is present

## Task Commits

| Task | Name | Commit | Files |
| ---- | ---- | ------ | ----- |
| 1 | Job detail page layout, notes, transitions | 2accb7e | web/src/app/(dashboard)/jobs/[id]/page.tsx |

## Files Created/Modified

- `web/src/app/(dashboard)/jobs/[id]/page.tsx` — 540+ line "use client" page component (created)

## Decisions Made

- **base-ui DropdownMenuTrigger has no asChild prop** — styled directly with Tailwind classes to match Button outline/sm appearance without wrapping in Button component (which would require asChild support)
- **Cancel note saved in onSuccess callback** — ensures note is only created if transition succeeds; non-fatal if note POST fails (error is caught and swallowed silently after transition completes)
- **time-entries query uses `retry: false`** — endpoint may return 404 for jobs without time tracking; treat as empty array rather than error state

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 1 - Bug] DropdownMenuTrigger does not accept asChild**
- **Found during:** Task 1 (TypeScript check)
- **Issue:** Plan specified `<DropdownMenuTrigger asChild><Button ...>` but the base-ui MenuPrimitive.Trigger component has no `asChild` prop, causing TS2322 type error
- **Fix:** Replaced with bare `<DropdownMenuTrigger>` with inline Tailwind classes matching Button outline/sm variant styling
- **Files modified:** `web/src/app/(dashboard)/jobs/[id]/page.tsx`
- **Verification:** `npx tsc --noEmit` exits 0 after fix
- **Committed in:** `2accb7e` (Task 1 commit)

---

**Total deviations:** 1 auto-fixed (TypeScript/API compatibility)
**Impact on plan:** Minimal — visual result is identical to `asChild` pattern, all acceptance criteria pass.

## Issues Encountered

None beyond the auto-fixed item above.

## User Setup Required

None — no external service configuration required.

## Next Phase Readiness

- `/jobs/requests/[id]` route needed in Plan 14-03 for job request review
- All shared components (StatusBadge, Dialog, Textarea, Alert, apiGet/apiPost/apiPatch) available for Plan 14-03

## Self-Check: PASSED

Files on disk:
- web/src/app/(dashboard)/jobs/[id]/page.tsx: FOUND

Commits verified:
- 2accb7e: FOUND

TypeScript: `npx tsc --noEmit` exits 0
Acceptance criteria: 31/31 passed

---
*Phase: 14-job-management*
*Completed: 2026-03-16*
