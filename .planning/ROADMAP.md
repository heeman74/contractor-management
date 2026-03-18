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

- [x] **Phase 13: Web Foundation and Auth** — Next.js scaffold, httpOnly cookie auth, session management, global navigation shell (completed 2026-03-16)
- [x] **Phase 14: Job Management** — Filterable jobs list, job detail, status transitions, job request review queue (completed 2026-03-16)
- [x] **Phase 15: Scheduling Calendar** — Weekly calendar with contractor lanes, drag-and-drop rescheduling, conflict detection (completed 2026-03-17)
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
**Plans:** 4/4 plans complete

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
**Plans:** 3/3 plans complete

Plans:
- [ ] 14-01-PLAN.md — Shared foundation (types, StatusBadge colors, ui-slice pageTitle, shadcn installs, Playwright stubs) + jobs list page with tabs, search, sort, pagination
- [ ] 14-02-PLAN.md — Job detail page with two-column layout, notes, activity history, status transitions with confirmation dialogs
- [ ] 14-03-PLAN.md — Job request detail page with approve/decline actions and redirect flows

### Phase 15: Scheduling Calendar
**Goal**: Admins can see the full team schedule at a glance and reschedule or reassign bookings by dragging them, with the system preventing conflicts before they are confirmed
**Depends on**: Phase 14
**Requirements**: SCHED-01, SCHED-02, SCHED-03
**Success Criteria** (what must be TRUE):
  1. Admin can view a weekly calendar where each contractor has a dedicated lane showing their bookings
  2. Admin can drag a booking to a different time or contractor lane and the change is saved
  3. Before a drag-and-drop is confirmed, any scheduling conflict is surfaced as a warning that the admin must acknowledge or cancel
**Plans:** 4/4 plans complete

Plans:
- [ ] 15-01-PLAN.md — Calendar infrastructure: types, hooks, Redux slice, react-big-calendar with resources prop, booking detail panel, toolbar navigation
- [ ] 15-02-PLAN.md — Drag-and-drop rescheduling: backend contractor_id support, optimistic update/rollback, conflict pre-check, conflict warning modal
- [ ] 15-03-PLAN.md — Booking creation from empty slots, multi-filter toolbar with chips, E2E test stubs
- [ ] 15-04-PLAN.md — Gap closure: add client_name to JobResponse and wire into calendar booking events

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
**Plans:** 1/4 plans executed

Plans:
- [ ] 16-01-PLAN.md — Backend list endpoints, amount_paid migration, TypeScript types, StatusBadge extensions, apiFetchRaw, dnd-kit install, E2E stubs
- [ ] 16-02-PLAN.md — Quotes list page (DataTable + status tabs) + Quote detail page (two-column layout, lifecycle actions, PDF download)
- [ ] 16-03-PLAN.md — Invoices list page (DataTable + payment tabs, overdue highlighting) + Invoice detail (payment recording, PDF download)
- [ ] 16-04-PLAN.md — Quote builder (react-hook-form + dnd-kit inline editing, template loading, preview mode) + Job detail integration (Create Quote, Generate Invoice buttons)

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
| 13. Web Foundation and Auth | 4/4 | Complete   | 2026-03-16 | - |
| 14. Job Management | 3/3 | Complete    | 2026-03-16 | - |
| 15. Scheduling Calendar | 4/4 | Complete    | 2026-03-17 | - |
| 16. Quotes and Invoices | 1/4 | In Progress|  | - |
| 17. CRM — Clients and Contractors | v2.0 | 0/5 | Not started | - |
| 18. Reporting Dashboard | v2.0 | 0/3 | Not started | - |
