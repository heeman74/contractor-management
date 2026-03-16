# Roadmap: ContractorHub

## Milestones

- ✅ **v1.0 MVP** — Phases 1-12 (shipped 2026-03-15) — [archive](milestones/v1.0-ROADMAP.md)
- 🚧 **v2.0 Web Admin Dashboard** — Phases 13-18 (in progress)

## Phases

<details>
<summary>✅ v1.0 MVP (Phases 1-12) — SHIPPED 2026-03-15</summary>

- [x] Phase 1: Foundation (5/5 plans) — completed 2026-03-05
- [x] Phase 2: Offline Sync Engine (7/7 plans) — completed 2026-03-06
- [x] Phase 3: Scheduling Engine (4/4 plans) — completed 2026-03-07
- [x] Phase 4: Job Lifecycle (9/9 plans) — completed 2026-03-09
- [x] Phase 5: Calendar and Dispatch UI (6/6 plans) — completed 2026-03-09
- [x] Phase 6: Field Workflow (7/7 plans) — completed 2026-03-12
- [x] Phase 7: Client Portal and Notifications (4/4 plans) — completed 2026-03-13
- [x] Phase 8: Business Operations (7/7 plans) — completed 2026-03-14
- [x] Phase 9: Sync Engine Gap Closure (2/2 plans) — completed 2026-03-14
- [x] Phase 10: UI & Backend Wiring Gap Closure (1/1 plan) — completed 2026-03-15
- [x] Phase 11: Integration Polish (1/1 plan) — completed 2026-03-15
- [x] Phase 12: Client Profile Sync Fix (1/1 plan) — completed 2026-03-15

Full details: [milestones/v1.0-ROADMAP.md](milestones/v1.0-ROADMAP.md)

</details>

### 🚧 v2.0 Web Admin Dashboard (In Progress)

**Milestone Goal:** Give company admins a full-featured desktop web experience for managing their contracting business — quoting, contractor management, scheduling, jobs, clients, invoicing, and reporting — powered by the existing FastAPI backend.

- [ ] **Phase 13: Web Foundation and Auth** — Next.js scaffold, httpOnly cookie auth, session management, global navigation shell
- [ ] **Phase 14: Job Management** — Filterable jobs list, job detail, status transitions, job request review queue
- [ ] **Phase 15: Scheduling Calendar** — Weekly calendar with contractor lanes, drag-and-drop rescheduling, conflict detection
- [ ] **Phase 16: Quotes and Invoices** — Quote create/edit/send with line items, invoice payment recording, PDF downloads
- [ ] **Phase 17: CRM — Clients and Contractors** — Client list and job history, contractor profiles, weekly schedule editor, date overrides
- [ ] **Phase 18: Reporting Dashboard** — Revenue, utilization, and conversion charts with date range filtering

## Phase Details

### Phase 13: Web Foundation and Auth
**Goal**: Company admins can securely access the web dashboard and navigate to all modules without ever exposing tokens to JavaScript
**Depends on**: Nothing (first v2.0 phase)
**Requirements**: AUTH-01, AUTH-02, AUTH-03, AUTH-04, AUTH-05, AUTH-06
**Success Criteria** (what must be TRUE):
  1. Admin can log in with email and password and land on the dashboard home
  2. Refreshing the browser does not log the admin out — session persists via httpOnly cookie
  3. Navigating between modules does not trigger a login redirect — token refresh happens invisibly
  4. Admin can log out and immediately cannot access any protected page
  5. The global sidebar is visible and functional on every page, and user-friendly error messages appear for auth failures, validation errors, and server errors
**Plans:** 2/4 plans executed

Plans:
- [ ] 13-01-PLAN.md — Backend prep: dual-auth get_current_user (cookie + Bearer), client_type migration, CORS verification
- [ ] 13-02-PLAN.md — Next.js scaffold: App Router, TypeScript strict, Tailwind v4, shadcn/ui, Redux makeStore, TanStack Query provider
- [ ] 13-03-PLAN.md — Auth layer: Route Handlers (login/refresh/logout), API proxy, apiClient with 401 retry, proxy.ts route guard
- [ ] 13-04-PLAN.md — Login page, dashboard shell (sidebar + topbar), dashboard home with KPI cards, error pages, status badge

### Phase 14: Job Management
**Goal**: Admins can manage the full job lifecycle from a single, searchable web interface — reviewing requests, tracking progress, and driving jobs through every status stage
**Depends on**: Phase 13
**Requirements**: JOBS-01, JOBS-02, JOBS-03, JOBS-04
**Success Criteria** (what must be TRUE):
  1. Admin can view all jobs in a filterable list, switch between status tabs, and search by keyword
  2. Admin can open any job and see full detail — notes, contractor assignment, client info, current status, and time tracking
  3. Admin can advance or revert a job's status through the full lifecycle (Quote → Scheduled → In Progress → Complete → Invoiced)
  4. Admin can view inbound client-submitted job requests and approve or decline each one
**Plans**: TBD

Plans:
- [ ] 14-01: Jobs list page — Server Component initial fetch, Client DataTable with status filter tabs, column sort, server-side pagination
- [ ] 14-02: Job detail page — status display, notes, contractor/client info, time tracking; status transition actions
- [ ] 14-03: Job request review queue — pending requests list, approve/decline actions with confirmation dialog

### Phase 15: Scheduling Calendar
**Goal**: Admins can see the full team schedule at a glance and reschedule or reassign bookings by dragging them, with the system preventing conflicts before they are confirmed
**Depends on**: Phase 14
**Requirements**: SCHED-01, SCHED-02, SCHED-03
**Success Criteria** (what must be TRUE):
  1. Admin can view a weekly calendar where each contractor has a dedicated lane showing their bookings
  2. Admin can drag a booking to a different time or contractor lane and the change is saved
  3. Before a drag-and-drop is confirmed, any scheduling conflict is surfaced as a warning that the admin must acknowledge or cancel
**Plans**: TBD

Plans:
- [ ] 15-01: Calendar infrastructure — react-big-calendar with resources prop (contractor lanes), dateFnsLocalizer, dynamic import with ssr:false, TanStack Query data loading
- [ ] 15-02: Drag-and-drop rescheduling — onEventDrop handler, optimistic update with TanStack Query, 409 conflict rollback, week navigation
- [ ] 15-03: Conflict detection display — POST /scheduling/conflicts pre-check on drop, conflict warning modal with confirm/cancel

### Phase 16: Quotes and Invoices
**Goal**: Admins can create, edit, and send quotes from their desktop and record payments against invoices, with PDF downloads for both
**Depends on**: Phase 13
**Requirements**: QUOTE-01, QUOTE-02, QUOTE-03, QUOTE-04, INV-01, INV-02, INV-03
**Success Criteria** (what must be TRUE):
  1. Admin can view all quotes in a list filtered by status (draft, sent, approved, declined)
  2. Admin can create or edit a quote with line items, taxes, and descriptions, then send it to the client
  3. Admin can download any quote as a PDF
  4. Admin can view all invoices with payment status and record a full or partial payment on any invoice
  5. Admin can download any invoice as a PDF
**Plans**: TBD

Plans:
- [ ] 16-01: Quotes list page — DataTable with status filter tabs, status badge component
- [ ] 16-02: Quote create/edit form — react-hook-form with useFieldArray for line items, client search-select, send action, approval status tracking
- [ ] 16-03: Quote PDF download — fetch blob from backend, browser download trigger
- [ ] 16-04: Invoices list page — DataTable with payment status indicators
- [ ] 16-05: Invoice detail — payment recording form (full/partial), PDF download

### Phase 17: CRM — Clients and Contractors
**Goal**: Admins can look up any client or contractor, see their full history and schedule, and edit contractor availability directly from the web
**Depends on**: Phase 15
**Requirements**: CRM-01, CRM-02, CONTR-01, CONTR-02, CONTR-03, CONTR-04
**Success Criteria** (what must be TRUE):
  1. Admin can search and view a paginated list of all clients
  2. Admin can open a client's detail page and see all of their past and active jobs
  3. Admin can view all contractors with an availability summary, then open a contractor's profile to see assigned jobs and weekly schedule
  4. Admin can edit a contractor's weekly working hours and the change is reflected immediately
  5. Admin can set date-specific overrides (mark a date unavailable or assign custom hours) for any contractor
**Plans**: TBD

Plans:
- [ ] 17-01: Client list page — searchable DataTable with server-side pagination
- [ ] 17-02: Client detail page — job history list via GET /jobs?client_id=
- [ ] 17-03: Contractor list page — availability summary badges
- [ ] 17-04: Contractor profile page — assigned jobs, weekly schedule summary display
- [ ] 17-05: Weekly schedule editor — custom grid component, PUT /scheduling/schedules/{id}/weekly/{dow}, date overrides (POST /scheduling/overrides)

### Phase 18: Reporting Dashboard
**Goal**: Admins can review business performance at a glance with charts covering revenue, job status, contractor utilization, and quote conversion, filtered by any date range
**Depends on**: Phase 13
**Requirements**: RPT-01, RPT-02, RPT-03
**Success Criteria** (what must be TRUE):
  1. Admin can view a dashboard with four charts: revenue by month, jobs by status breakdown, contractor utilization, and quote conversion rate
  2. Admin can change the date range and all charts update to reflect the selected period
  3. Admin can view a contractor utilization heatmap showing which contractors are overloaded or underutilized
**Plans**: TBD

Plans:
- [ ] 18-01: Reporting page — four Recharts charts (AreaChart, BarChart, BarChart, PieChart) via shadcn/ui Chart wrappers, dynamic import with ssr:false
- [ ] 18-02: Date range filter — shadcn/ui DatePicker, TanStack Query-driven refetch on range change
- [ ] 18-03: Contractor utilization heatmap — custom heatmap grid component

## Progress

**Execution Order:**
v2.0 phases execute in numeric order: 13 → 14 → 15 → 16 → 17 → 18
Note: Phase 16 (Quotes/Invoices) depends only on Phase 13 and may be parallelized with Phase 14 and 15 if capacity allows.

| Phase | Milestone | Plans Complete | Status | Completed |
|-------|-----------|----------------|--------|-----------|
| 1. Foundation | v1.0 | 5/5 | Complete | 2026-03-05 |
| 2. Offline Sync Engine | v1.0 | 7/7 | Complete | 2026-03-06 |
| 3. Scheduling Engine | v1.0 | 4/4 | Complete | 2026-03-07 |
| 4. Job Lifecycle | v1.0 | 9/9 | Complete | 2026-03-09 |
| 5. Calendar and Dispatch UI | v1.0 | 6/6 | Complete | 2026-03-09 |
| 6. Field Workflow | v1.0 | 7/7 | Complete | 2026-03-12 |
| 7. Client Portal and Notifications | v1.0 | 4/4 | Complete | 2026-03-13 |
| 8. Business Operations | v1.0 | 7/7 | Complete | 2026-03-14 |
| 9. Sync Engine Gap Closure | v1.0 | 2/2 | Complete | 2026-03-14 |
| 10. UI & Backend Wiring Gap Closure | v1.0 | 1/1 | Complete | 2026-03-15 |
| 11. Integration Polish | v1.0 | 1/1 | Complete | 2026-03-15 |
| 12. Client Profile Sync Fix | v1.0 | 1/1 | Complete | 2026-03-15 |
| 13. Web Foundation and Auth | 2/4 | In Progress|  | - |
| 14. Job Management | v2.0 | 0/3 | Not started | - |
| 15. Scheduling Calendar | v2.0 | 0/3 | Not started | - |
| 16. Quotes and Invoices | v2.0 | 0/5 | Not started | - |
| 17. CRM — Clients and Contractors | v2.0 | 0/5 | Not started | - |
| 18. Reporting Dashboard | v2.0 | 0/3 | Not started | - |
