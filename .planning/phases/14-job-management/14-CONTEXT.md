# Phase 14: Job Management - Context

**Gathered:** 2026-03-16
**Status:** Ready for planning

<domain>
## Phase Boundary

Admins can manage the full job lifecycle from a single, searchable web interface — reviewing client-submitted requests, tracking job progress, and driving jobs through every status stage (Quote → Scheduled → In Progress → Complete → Invoiced). No job creation from web (mobile only), no scheduling calendar (Phase 15), no quote/invoice editing (Phase 16).

</domain>

<decisions>
## Implementation Decisions

### Jobs list presentation
- Horizontal status tab bar: All | Quote | Scheduled | In Progress | Complete | Invoiced | Requests
- Each tab shows count badge (e.g., "In Progress (12)")
- Requests tab separated at the end for client-submitted job requests with pending count
- Compact columns: Job #, Title, Client, Status (StatusBadge), Assigned Contractor, Date
- Always-visible search bar, right-aligned next to tabs
- Click row navigates to detail page at /jobs/[id] (full page navigation, breadcrumb: Dashboard > Jobs > Job #1042)
- Server-side pagination with page controls at bottom (prev/next + page numbers)
- Sortable columns — click header to toggle asc/desc, arrow indicator, default sort: newest first by date
- No inline row actions — all status transitions happen on the detail page only

### Job detail layout
- Two-column layout: main content (~65%) + right sidebar (~35%)
- Main content order (top to bottom): Description → Notes → Activity/History
- Notes section: read + add new text notes from web; photo notes from mobile display as thumbnail grid with lightbox on click
- Right sidebar sections: Status badge, Contractor (linked to /contractors/[id]), Client (linked to /clients/[id]), Scheduled date/time, Address, Time tracking (total + expandable individual clock-in/out entries)
- Linked quote/invoice: summary card in sidebar if exists (e.g., "Quote #Q-1042 — $4,500 — Approved") with link to detail (Phase 16 pages — 404 until built)
- Navigation: breadcrumbs only (no explicit back button) — clicking "Jobs" in breadcrumb or sidebar navigates back

### Status transition UX
- Primary action button in sidebar under status badge showing next logical status (e.g., "Mark In Progress")
- Dropdown arrow reveals all valid transitions: forward (primary), revert (secondary), cancel (destructive/red)
- Forward transitions execute immediately with success toast: "Job #1042 marked In Progress"
- Destructive actions (revert, cancel) show confirmation dialog before executing
- Cancel Job requires a reason (text field in confirmation dialog, required) — saved as job note for audit trail
- Transition errors display as inline red alert banner below the status button, clears on next action
- After successful transition: stay on detail page, update status badge and action button in place

### Job request review flow
- Requests live as a tab on the jobs page (not a separate page or nav item)
- Click request row navigates to request detail page showing: client info, description, preferred dates, property, type
- Approve and Decline buttons at top of request detail
- Declining requires a reason (text field in confirmation dialog, required)
- After approve: navigate to the newly created job's detail page (in Quote status)
- After decline: navigate back to requests tab with success toast

### Claude's Discretion
- Exact DataTable component choice (shadcn/ui table vs TanStack Table)
- Pagination controls styling
- Skeleton loading shapes for list and detail pages
- Lightbox/modal implementation for photo notes
- Exact spacing, typography, and card styling within the two-column layout
- Search debounce timing
- Empty state illustrations/messages for zero-results and zero-requests

</decisions>

<canonical_refs>
## Canonical References

**Downstream agents MUST read these before planning or implementing.**

### Backend API — Jobs
- `backend/app/features/jobs/router.py` — All job endpoints: CRUD, transitions, notes, requests, search, time entries
- `backend/app/features/jobs/request_service.py` — Job request review logic (approve/decline)

### Web Foundation (Phase 13)
- `web/src/lib/api-client.ts` — apiClient with 401 auto-refresh proxy pattern
- `web/src/components/shared/status-badge.tsx` — StatusBadge with semantic color map (reuse for all job statuses)
- `web/src/components/shared/kpi-card.tsx` — KPI card component pattern
- `web/src/components/layout/sidebar.tsx` — Sidebar navigation (add Jobs route)
- `web/src/components/layout/topbar.tsx` — Topbar with breadcrumbs
- `web/src/components/layout/dashboard-shell.tsx` — Dashboard shell wrapper
- `web/src/store/slices/` — Redux slices (auth-slice.ts, ui-slice.ts)

### UI Components
- `web/src/components/ui/` — shadcn/ui primitives: Card, Badge, Button, Input, Skeleton, Sheet, DropdownMenu, Sonner (toast)

### Requirements
- `.planning/REQUIREMENTS.md` — JOBS-01 through JOBS-04

</canonical_refs>

<code_context>
## Existing Code Insights

### Reusable Assets
- **StatusBadge** (`web/src/components/shared/status-badge.tsx`): Already maps all job statuses (scheduled, in_progress, complete, etc.) to semantic colors — direct reuse
- **apiClient** (`web/src/lib/api-client.ts`): GET/POST/PATCH/DELETE helpers with proxy and 401 refresh — use for all job API calls
- **Card, Button, Input, DropdownMenu** (`web/src/components/ui/`): shadcn/ui primitives ready for DataTable, forms, and action menus
- **Sonner toast** (`web/src/components/ui/sonner.tsx`): Toast notifications for success/error — error toasts use `duration: Infinity` per Phase 13 decision

### Established Patterns
- **TanStack Query for server state**: All API data fetched/cached via TanStack Query (decided in Phase 13)
- **Redux for UI state only**: Sidebar collapse, filter state, active tab — NOT for server data
- **httpOnly cookie auth**: All API calls go through `/api/proxy` route handler — tokens never in JS
- **App Router with (dashboard) group**: Protected pages under `(dashboard)` layout group
- **Breadcrumb in topbar**: Already wired — needs dynamic segments for job detail pages

### Integration Points
- **Sidebar nav**: Add "Jobs" route to sidebar items array in `sidebar.tsx` (module order already decided: Dashboard > Jobs > Schedule > ...)
- **Dashboard route group**: New pages at `web/src/app/(dashboard)/jobs/` for list and `jobs/[id]/` for detail
- **Backend endpoints**: `GET /jobs/`, `GET /jobs/{id}`, `PATCH /jobs/{id}/transition`, `GET /jobs/requests`, `POST /jobs/requests/{id}/review`, `GET /jobs/{id}/notes`, `POST /jobs/{id}/notes`

</code_context>

<specifics>
## Specific Ideas

- Jobs list tabs should feel like the Stripe payments list — clean horizontal tabs with counts, instant status switching
- Job detail two-column layout inspired by GitHub issue pages — main content left, metadata sidebar right
- Status transition button similar to Jira's "In Progress" button — prominent primary action with dropdown for alternatives
- Photo note thumbnails should open in a proper lightbox, not navigate away from the page

</specifics>

<deferred>
## Deferred Ideas

None — discussion stayed within phase scope

</deferred>

---

*Phase: 14-job-management*
*Context gathered: 2026-03-16*
