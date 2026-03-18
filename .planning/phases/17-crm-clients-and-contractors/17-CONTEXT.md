# Phase 17: CRM — Clients and Contractors - Context

**Gathered:** 2026-03-17
**Status:** Ready for planning

<domain>
## Phase Boundary

Admins can look up any client or contractor, see their full history and schedule, and edit contractor availability directly from the web. Delivers: client list with search and pagination, client detail with job history and properties, contractor list with availability badges, contractor profile with schedule summary and assigned jobs, weekly schedule editor with visual grid and date overrides. Also wires up the existing CrmService backend to a router and adds cross-page links from jobs, quotes, invoices, and the schedule calendar to the new CRM pages.

Requirements: CRM-01, CRM-02, CONTR-01, CONTR-02, CONTR-03, CONTR-04

</domain>

<decisions>
## Implementation Decisions

### Client list presentation
- Flat searchable list (no status tabs — clients don't have statuses)
- Server-side search and pagination via CrmService.list_clients() (already supports name/email search)
- Rich columns: Name, Email, Phone, Tags (as chips), Preferred Contractor, Jobs Count
- Sortable columns, default sort by name alphabetical
- Click row navigates to /clients/[id] detail page

### Client detail layout
- Full CRM profile with two-column layout (main ~65% + sidebar ~35%)
- Main content sections (top to bottom):
  - Job history table: reverse chronological, columns = Job #, Title, Status (StatusBadge), Contractor, Date. Click row → /jobs/[id]
  - Saved properties: compact address list with "Default" badge on primary property, click to expand full address details. Read-only
  - Admin notes: inline in sidebar, always visible, read-only
- Sidebar sections: contact card (name, email, phone), tags (as chips), average rating, referral source, preferred contractor (linked to /contractors/[id]), billing address
- Read-only for now — no editing of client profiles from web (CRM-01 and CRM-02 only require viewing)

### Contractor list presentation
- Flat searchable list with server-side pagination
- Columns: Name, Email, Phone, Trade Type (badge), Availability Status (badge), Active Jobs Count
- Availability badge: Green "Available" / Yellow "Partially booked" / Red "Fully booked" based on today's schedule
- Sortable columns, click row navigates to /contractors/[id]

### Contractor profile layout
- Two-column layout (main ~65% + sidebar ~35%) — consistent with client detail and job detail patterns
- Main content (top to bottom):
  - Weekly schedule summary: visual grid showing working hours per day (Mon–Sun). "Edit Schedule" button navigates to /contractors/[id]/schedule
  - Assigned jobs table: reverse chronological, columns = Job #, Title, Status (StatusBadge), Client, Date. Click row → /jobs/[id]
- Sidebar: contact info (name, email, phone), trade type badge, average rating, quick stats (active jobs count, hours this week)

### Weekly schedule editor
- Dedicated page at /contractors/[id]/schedule. Breadcrumb: Contractors > [Name] > Schedule
- Visual 7-column grid (Mon–Sun), rows = hours (6am–8pm). Click and drag to paint working hours. Existing blocks shown as colored fills
- Per-day auto-save: each day saves independently when changed (PUT /schedules/{id}/weekly/{dow}). Success toast per save
- Date overrides section below the weekly grid:
  - Calendar date picker to select the override date
  - Toggle: "Unavailable all day" or set custom hours with time pickers
  - Existing overrides shown as highlighted dates on the calendar picker
  - Save via PUT /schedules/{id}/overrides/{date}

### Cross-page linking
- Job detail page: client_name → /clients/[id], contractor name → /contractors/[id] (clickable links)
- Quote detail sidebar: client name → /clients/[id]
- Invoice detail sidebar: client name → /clients/[id]
- Contractor profile: assigned jobs table rows → /jobs/[id]
- Client detail: job history table rows → /jobs/[id], preferred contractor → /contractors/[id]
- Schedule calendar (Phase 15): contractor lane headers → /contractors/[id]

### Claude's Discretion
- Exact visual grid component implementation for schedule editor (custom canvas vs CSS grid vs third-party)
- Drag-to-paint interaction details for the schedule grid
- Availability badge calculation logic (how to determine Available/Partially/Fully booked thresholds)
- Exact skeleton loading shapes for all pages
- Tag chip styling and color assignments
- Property list expand/collapse animation
- Exact spacing, typography, and component sizing
- Empty state messages for clients/contractors with no results
- Pagination controls styling (reuse pattern from jobs list)

</decisions>

<canonical_refs>
## Canonical References

**Downstream agents MUST read these before planning or implementing.**

### Backend API — CRM (Already Built)
- `backend/app/features/jobs/crm_service.py` — CrmService: list_clients, get_client_with_job_history, manage_properties, add/remove_property (needs router to expose)
- `backend/app/features/jobs/crm_repository.py` — CrmRepository with joinedload patterns for ClientProfile + User + preferred_contractor
- `backend/app/features/jobs/models.py` — ClientProfile (tags JSONB, admin_notes, referral_source, preferred_contractor_id, average_rating, billing_address), ClientProperty (is_default)

### Backend API — Users
- `backend/app/features/users/router.py` — User list and role assignment endpoints
- `backend/app/features/users/service.py` — UserService with role-based queries
- `backend/app/features/users/schemas.py` — UserResponse with roles list

### Backend API — Scheduling
- `backend/app/features/scheduling/router.py` — Weekly schedule PUT, date override PUT, availability GET endpoints
- `backend/app/features/scheduling/schemas.py` — TimeBlock, WeeklyScheduleCreate, DateOverrideCreate, AvailabilityResponse (free_windows + blocked_intervals)
- `backend/app/features/scheduling/models.py` — ContractorWeeklySchedule (day_of_week, block_index), ContractorDateOverride (is_unavailable)

### Web Foundation (Phase 13)
- `web/src/lib/api-client.ts` — apiClient with 401 auto-refresh proxy pattern
- `web/src/components/shared/status-badge.tsx` — StatusBadge with semantic color map
- `web/src/components/layout/sidebar.tsx` — Sidebar navigation (Clients and Contractors items already present)
- `web/src/components/layout/topbar.tsx` — Topbar with breadcrumbs
- `web/src/store/slices/` — Redux slices for UI state

### Web Patterns (Phase 14, 16)
- `web/src/app/(dashboard)/jobs/page.tsx` — DataTable + status tabs + pagination + sorting pattern to replicate
- `web/src/app/(dashboard)/jobs/[id]/page.tsx` — Two-column detail layout pattern (main + sidebar)
- `web/src/app/(dashboard)/invoices/page.tsx` — List page with computed status tabs
- `web/src/app/(dashboard)/quotes/page.tsx` — List page pattern

### Schedule Calendar (Phase 15) — Cross-linking
- `web/src/app/(dashboard)/schedule/page.tsx` — Calendar with contractor lane headers (need to add links)

### UI Components
- `web/src/components/ui/` — shadcn/ui: Card, Badge, Button, Input, Table, Tabs, Dialog, Sheet, Skeleton, Sonner (toast), DropdownMenu

### Requirements
- `.planning/REQUIREMENTS.md` — CRM-01, CRM-02, CONTR-01, CONTR-02, CONTR-03, CONTR-04

</canonical_refs>

<code_context>
## Existing Code Insights

### Reusable Assets
- **CrmService** (`backend/app/features/jobs/crm_service.py`): Fully built with list_clients, get_client_with_job_history, manage_properties — needs a router endpoint to expose
- **StatusBadge** (`web/src/components/shared/status-badge.tsx`): Needs new availability-status mappings (available/partially_booked/fully_booked)
- **apiClient** (`web/src/lib/api-client.ts`): GET/POST/PATCH/DELETE with proxy and 401 refresh
- **DataTable + tabs pattern** from Phase 14 jobs list: directly replicable for client and contractor lists
- **Two-column detail layout** from Phase 14 job detail: directly replicable for client and contractor profiles
- **Sidebar nav**: Already has "Clients" (/clients) and "Contractors" (/contractors) items configured

### Established Patterns
- **TanStack Query for server state**: All API data via useQuery/useMutation
- **Redux for UI state only**: Filter state, sidebar collapse
- **httpOnly cookie auth**: All API calls through /api/proxy route handler
- **URL-driven state**: searchParams for bookmarkable views
- **Two-column detail**: 65/35 split established in Phase 14, reused in Phase 16

### Integration Points
- **CRM router**: Wire up CrmService to a new `/api/v1/crm/` router (GET /clients, GET /clients/{id})
- **Dashboard route group**: New pages at `web/src/app/(dashboard)/clients/` and `web/src/app/(dashboard)/contractors/`
- **Schedule editor**: New page at `web/src/app/(dashboard)/contractors/[id]/schedule/`
- **Cross-linking updates**: Job detail, quote detail, invoice detail sidebar links; schedule calendar lane headers
- **Scheduling endpoints**: Already exist — PUT weekly/{dow}, PUT overrides/{date}, GET availability

</code_context>

<specifics>
## Specific Ideas

- Schedule editor visual grid inspired by Google Calendar's working hours editor — click and drag to paint time blocks
- Availability badges should be immediately scannable — green/yellow/red traffic-light pattern
- Client detail should feel like a lightweight CRM contact page — not a full Salesforce, just the essentials a contractor admin needs
- Cross-page linking makes the app feel like an integrated system, not separate disconnected pages

</specifics>

<deferred>
## Deferred Ideas

None — discussion stayed within phase scope

</deferred>

---

*Phase: 17-crm-clients-and-contractors*
*Context gathered: 2026-03-17*
