# Feature Research

**Domain:** Web Admin Dashboard — Contractor / Field Service Management (Next.js, desktop-first)
**Researched:** 2026-03-14
**Confidence:** HIGH — cross-referenced Jobber, ServiceTitan, Housecall Pro, BuildOps, Fieldpulse, mHelpDesk; existing backend API audited directly

---

## Context: What Already Exists

ContractorHub v1.0 shipped a complete Flutter mobile app with a FastAPI + PostgreSQL backend. All business logic and API endpoints are live. This web admin dashboard is a **new frontend only** — not a new product. Every feature below maps to existing backend endpoints.

### Existing API Surface (All Endpoints Available)

| Domain | Key Endpoints | Notes |
|--------|---------------|-------|
| Auth | POST /auth/login, /refresh, /logout | JWT + refresh rotation; works for web |
| Jobs | GET/POST/PATCH /jobs, /jobs/transition, /jobs/requests | Full lifecycle, search, notes, time tracking |
| Scheduling | GET/POST /scheduling/bookings, /availability, /conflicts | GIST conflict detection, multi-day, reschedule |
| Quotes | GET/POST/PATCH /quotes, /quotes/{id}/send,approve,decline,revise | Full approval flow + PDF |
| Invoices | GET/POST/PATCH /invoices, /invoices/{id}/finalize, /payment, /pdf | Payment tracking + PDF |
| Users | GET/POST /users, /users/{id}/roles | List and manage all users |
| Reports | GET /reports/dashboard, /reports/contractor | Jobs by status, revenue, utilization, conversion |
| Files | POST /files | Photo/document upload |
| Companies | (company context from JWT) | RLS scoping per company_id |

---

## Feature Landscape

### Table Stakes (Users Expect These)

Features that any admin web dashboard for field service must have. Missing any of these means the web app feels incomplete versus the mobile app or competitors.

| Feature | Why Expected | Complexity | Backend Dependency |
|---------|--------------|------------|--------------------|
| JWT login with session persistence | Every web app needs auth; admins expect to stay logged in across browser sessions | LOW | POST /auth/login, /refresh — token refresh via interceptor |
| Global navigation sidebar | Standard admin dashboard pattern; persistent access to all modules | LOW | None — UI only |
| Jobs list with status filter tabs | Admins need at-a-glance view of all jobs by lifecycle stage | LOW | GET /jobs (query params for status) |
| Job detail page with full lifecycle | View job info, status, notes, assigned contractor, client — all in one place | MEDIUM | GET /jobs/{id}, /jobs/{id}/notes |
| Job status transitions | Admin must be able to move jobs between lifecycle stages from web | LOW | PATCH /jobs/{id}/transition |
| Calendar scheduling view (week/month) | Drag-and-drop calendar is table stakes for any FSM platform — all 7 competitors have it | HIGH | GET /scheduling/bookings (date range filter) |
| Contractor column view on calendar | Side-by-side contractor lanes showing who is working when | HIGH | GET /scheduling/bookings + GET /users (contractors) |
| Drag-and-drop booking management | Reassign or reschedule bookings by dragging on calendar | HIGH | PATCH /scheduling/bookings/{id}/reschedule |
| Quotes list with status indicators | Admin needs to see which quotes are pending, sent, approved, declined | LOW | GET /quotes (list all) |
| Quote create/edit form | Write quotes with line items, taxes, descriptions from desktop (better than mobile for long-form entry) | MEDIUM | POST /quotes, PATCH /quotes/{id} |
| Send quote + track approval status | Admin sends to client, sees approval without leaving the platform | LOW | POST /quotes/{id}/send — status reflected in GET /quotes |
| Invoice list with payment status | Track outstanding vs paid invoices | LOW | GET /invoices — status field |
| Invoice detail + payment recording | View invoice, mark as paid, record partial payment | LOW | PATCH /invoices/{id}/payment |
| Invoice PDF download | Generate and download the PDF from web | LOW | GET /invoices/{id}/pdf |
| Client/CRM list with search | Search clients by name, see job history | LOW | GET /users (role=client filter) |
| Client detail with job history | See all past and active jobs for a client | MEDIUM | GET /jobs?client_id= or GET /users/{id} |
| Contractor list with availability summary | See all contractors and their current workload | LOW | GET /users (role=contractor) |
| Contractor profile view | See contractor details, assigned jobs, weekly schedule | MEDIUM | GET /scheduling/schedules/{id}/weekly |
| Reporting dashboard with charts | Revenue by month, jobs by status, utilization, quote conversion — all 4 exist in backend | MEDIUM | GET /reports/dashboard |
| Date range filter on reports | Slice reporting data by time period | LOW | GET /reports/dashboard?start_date=&end_date= |
| Loading states and empty states | Expected on every page — missing causes confusion | LOW | UI only — React Suspense + skeleton components |
| Error handling with user-friendly messages | 401, 403, 409, 422, 5xx all need meaningful messages | LOW | UI only — Axios/fetch interceptors |
| Responsive layout for large monitors | Admins use 1440px+ widescreen setups; layout must use the space | LOW | CSS/Tailwind layout — sidebar + content area |

### Differentiators (Competitive Advantage)

Features that go beyond competitor web dashboards and leverage ContractorHub's existing backend capabilities.

| Feature | Value Proposition | Complexity | Backend Dependency |
|---------|-------------------|------------|--------------------|
| Conflict detection during scheduling | Most web calendars let you double-book; ContractorHub can show conflicts before confirming | MEDIUM | POST /scheduling/conflicts (read-only pre-check) |
| Availability-aware date suggestions | When scheduling a multi-day job, suggest available date combinations automatically | MEDIUM | POST /scheduling/suggest-dates |
| Multi-day job booking UI | Book a contractor for multiple days atomically — rare in web FSM tools | HIGH | POST /scheduling/bookings/multi-day |
| Unassigned jobs queue panel | Sidebar or panel showing jobs without bookings — admins drag from queue onto calendar | MEDIUM | GET /jobs (no booking filter) + calendar drag |
| Quote-to-job conversion flow | Approve a quote and immediately schedule the resulting job without leaving the screen | MEDIUM | POST /quotes/{id}/approve → POST /jobs → POST /scheduling/bookings |
| Quote PDF preview inline | Preview the quote PDF in a browser panel before sending — no download needed | LOW | GET /quotes/{id}/pdf (rendered in iframe) |
| Job request review queue | Dedicated inbox for client-submitted job requests with approve/decline actions | LOW | GET /jobs/requests, POST /jobs/requests/{id}/review |
| Invoice generate from job | One-click invoice generation when job reaches "Complete" status | LOW | POST /invoices/generate/{job_id} |
| Contractor utilization heatmap | Visual chart showing which contractors are overloaded vs underutilized | MEDIUM | GET /reports/dashboard → contractor_utilization data |
| Revenue vs target comparison | Monthly revenue bar chart with paid vs unpaid breakdown — already in backend | LOW | GET /reports/dashboard → revenue_by_month |
| Quote conversion funnel visualization | Visual funnel showing approved/declined/pending ratios | LOW | GET /reports/dashboard → quote_conversion |
| Weekly schedule editor per contractor | Grid UI to set contractor working hours per day of week | MEDIUM | PUT /scheduling/schedules/{id}/weekly/{dow} |
| Date override management | Mark specific dates as unavailable or custom hours | MEDIUM | PUT /scheduling/schedules/{id}/overrides/{date} |

### Anti-Features (Commonly Requested, Often Problematic)

Features that appear valuable but create significant complexity or strategic risk for this milestone.

| Feature | Why Requested | Why Problematic | Alternative |
|---------|---------------|-----------------|-------------|
| Real-time push updates (WebSocket) | "Calendar should update live when contractor makes changes in mobile app" | Requires WebSocket server (not in current FastAPI setup), adds infra complexity, hard to test reliably; polling every 30-60s is invisible to users in practice | 30-second polling on schedule/jobs pages — users won't notice |
| Offline mode on web | "What if internet goes down?" | Web admin is always connected; offline-first architecture is for field contractors on job sites; web offline adds Service Worker complexity with no real value | Display a connection error banner; no offline cache |
| Inline PDF editor | "Edit the quote/invoice design from the browser" | WeasyPrint renders server-side from HTML templates; building a WYSIWYG PDF editor is a separate product | Offer template customization in settings (future v3) |
| In-app payment collection | "Process payments from the web dashboard" | PCI compliance, Stripe integration, webhook handling — a separate compliance domain; already deferred in PROJECT.md | Record manual payment via PATCH /invoices/{id}/payment — existing endpoint supports this |
| Multi-company admin console | "Super admin to manage all companies" | Different auth model, different RLS bypass logic, different UX context — a separate product (super admin panel) | Company admins only; super admin is an ops tool, not a product feature |
| GPS map view of contractors | "See where everyone is on a map" | No GPS tracking data in current backend; would require mobile changes; invasive to contractors | Calendar view + job status is sufficient for dispatch decisions |
| Chat / messaging | "Message contractors from web" | Push notifications to mobile exist; adding chat means building a messaging system; job notes cover most communication | Job notes already exist and sync to mobile; no chat needed |
| Dark mode | "Standard feature now" | Increases CSS complexity, testing surface doubles; adds no business value for an admin tool | Single light theme for v2.0; defer dark mode to v3 |
| CSV/Excel export for all tables | "I need to export my data" | Each table needs export logic; file format handling; accounting integration more useful | Invoice PDF covers the main export need; raw data export deferred |
| Bulk job status changes | "Select 20 jobs and mark complete" | Complex UI state, risk of accidental bulk transitions, hard to undo | Individual job management sufficient; bulk operations deferred |

---

## Feature Dependencies

```
[JWT Auth + Session]
    └──required-by──> [ALL web features]

[Jobs List]
    └──requires──> [JWT Auth]
    └──enhances──> [Job Status Transitions]
    └──enhances──> [Job Detail]

[Job Detail]
    └──requires──> [Jobs List]
    └──requires──> [Client CRM List] (show client info)
    └──enhances──> [Invoice Generate from Job]
    └──enhances──> [Quote-to-Job Flow]

[Calendar View]
    └──requires──> [JWT Auth]
    └──requires──> [Contractor List] (populate lanes)
    └──requires──> [Jobs List] (populate events)
    └──enhances──> [Conflict Detection During Scheduling]
    └──enhances──> [Unassigned Jobs Queue Panel]
    └──enhances──> [Multi-Day Booking UI]

[Conflict Detection During Scheduling]
    └──requires──> [Calendar View]
    └──requires──> POST /scheduling/conflicts API call

[Quote Create/Edit]
    └──requires──> [Client CRM List] (select client)
    └──enhances──> [Quote-to-Job Conversion]

[Quote-to-Job Conversion]
    └──requires──> [Quote Create/Edit]
    └──requires──> [Calendar View] (schedule the resulting job)

[Invoice Generate from Job]
    └──requires──> [Job Detail] (job must be Complete status)

[Reporting Dashboard]
    └──requires──> [JWT Auth]
    └──standalone (no dependency on other web pages)

[Weekly Schedule Editor]
    └──requires──> [Contractor Profile]
    └──enhances──> [Calendar View] (availability reflected on calendar)
```

### Dependency Notes

- **Auth is a hard prerequisite for everything.** The JWT interceptor must handle token refresh transparently before any data-fetching page is built.
- **Calendar view is the highest-complexity page** and depends on having both the contractor list and jobs list working. Build jobs list and contractor list first.
- **Quote-to-job conversion is a cross-cutting flow.** It spans quotes, jobs, and scheduling — build it after all three pages exist individually.
- **Reporting dashboard is fully standalone.** All 4 backend metrics exist. This is safe to build in parallel with other features.

---

## MVP Definition

### Launch With (v2.0 Web Dashboard)

Minimum viable web admin experience — parity with mobile admin capabilities on a desktop interface.

- [ ] JWT login + session management — without this, nothing else is accessible
- [ ] Dashboard home with 4 reporting charts — first page after login, signals product quality
- [ ] Jobs list with status filter + search — core admin daily workflow
- [ ] Job detail page with status transitions — admin acts on jobs from web
- [ ] Job request review queue — process inbound client requests
- [ ] Calendar view (week) with contractor lanes — scheduling is the product's core differentiator
- [ ] Drag-and-drop rescheduling — table stakes for any scheduling tool
- [ ] Conflict detection on booking — leverage the existing GIST constraint infrastructure
- [ ] Quotes list + create/edit/send — long-form data entry is better on desktop than mobile
- [ ] Quote approval tracking — admin sees client approval status
- [ ] Invoices list + payment recording — close the financial loop from web
- [ ] Invoice PDF download — standard business document workflow
- [ ] Client list with search + job history — CRM is foundational
- [ ] Contractor list with profile view + schedule editor — manage team from desktop
- [ ] Global sidebar navigation — expected structural pattern

### Add After Validation (v2.x)

- [ ] Unassigned jobs queue panel on calendar — improves dispatch UX; non-blocking for launch
- [ ] Multi-day booking UI — complex interaction; launch with single-day, add multi-day in v2.1
- [ ] Date override management for contractors — edge case; weekly schedule editor is sufficient for launch
- [ ] Quote-to-job conversion flow — cross-cutting; ship as polish after all three base pages are stable
- [ ] Inline quote PDF preview — nice UX enhancement; download is sufficient for launch
- [ ] Availability-aware date suggestions — leverages backend POST /suggest-dates; ship after calendar is stable

### Future Consideration (v3+)

- [ ] In-app payment processing — requires Stripe/PCI compliance work
- [ ] Bulk job operations — needed only at scale
- [ ] CSV export — needed when accounting integration is requested
- [ ] Dark mode — cosmetic; defer
- [ ] Super admin console — different product
- [ ] QuickBooks / Xero integration — deferred explicitly in PROJECT.md

---

## Feature Prioritization Matrix

| Feature | User Value | Implementation Cost | Priority |
|---------|------------|---------------------|----------|
| JWT login + session | HIGH | LOW | P1 |
| Reporting dashboard (4 charts) | HIGH | LOW | P1 |
| Jobs list + filters | HIGH | LOW | P1 |
| Job detail + transitions | HIGH | LOW | P1 |
| Job request review queue | HIGH | LOW | P1 |
| Calendar week view (contractor lanes) | HIGH | HIGH | P1 |
| Drag-and-drop reschedule | HIGH | HIGH | P1 |
| Conflict detection on schedule | HIGH | MEDIUM | P1 |
| Quotes list + create/edit/send | HIGH | MEDIUM | P1 |
| Quote approval status tracking | MEDIUM | LOW | P1 |
| Invoices list + payment recording | HIGH | LOW | P1 |
| Invoice PDF download | MEDIUM | LOW | P1 |
| Client list + search + history | HIGH | LOW | P1 |
| Contractor list + profile + schedule | HIGH | MEDIUM | P1 |
| Global sidebar navigation | HIGH | LOW | P1 |
| Unassigned jobs queue panel | MEDIUM | MEDIUM | P2 |
| Multi-day booking UI | MEDIUM | HIGH | P2 |
| Date override management | MEDIUM | MEDIUM | P2 |
| Quote-to-job conversion flow | MEDIUM | MEDIUM | P2 |
| Inline PDF preview | LOW | LOW | P2 |
| Date suggestion UI | LOW | MEDIUM | P2 |
| In-app payment | HIGH | HIGH | P3 |
| Bulk operations | MEDIUM | HIGH | P3 |
| CSV export | MEDIUM | MEDIUM | P3 |
| Dark mode | LOW | MEDIUM | P3 |

**Priority key:**
- P1: Must have for v2.0 launch — all exist in backend, new frontend only
- P2: Add in v2.1 after core is stable
- P3: Future milestone

---

## Competitor Web Dashboard Feature Analysis

| Feature | Jobber Web | ServiceTitan Web | Housecall Pro Web | ContractorHub Web Approach |
|---------|------------|-----------------|-------------------|---------------------------|
| Calendar view | Month/Week/Day/List/Map (5 views) | Dispatch board + month/week | Calendar + map view | Week + contractor lanes; map is deferred |
| Unassigned jobs queue | Yes — sidebar panel | Yes — dispatch queue | Partial | P2 for v2.1 |
| Drag-and-drop | Yes (all platforms) | Yes (advanced) | Yes | Yes — core requirement |
| Conflict detection | Basic (no travel time) | Advanced | Basic | Advanced — GIST constraint already live |
| Quoting from web | Yes — full form | Yes — complex configurator | Yes — templates | Yes — full form with line items |
| Invoice PDF | Yes | Yes | Yes | Yes — existing endpoint |
| Reporting | Basic (dashboard cards) | Advanced (30+ reports, custom) | Basic | 4 charts from existing backend; matches Jobber's level |
| Client CRM | Full history | Full history | Basic | Client list + job history; matches Jobber |
| Contractor availability editor | Admin-only, basic | Admin with dispatch view | Admin-only | Weekly schedule grid + date overrides |
| Multi-day booking | Not first-class | Yes (construction module) | No | Yes (API is ready; UI is P2) |
| Real-time updates | Polling | WebSocket dispatch board | Polling | Polling — sufficient, no infra change needed |
| Role-based views | Admin vs tech separate apps | Admin vs tech separate | Admin vs tech separate | Admin-only web; contractors use mobile |

---

## Web-Specific UX Patterns (Not on Mobile)

These patterns are expected on desktop web but do not exist on the Flutter mobile app.

| Pattern | Where It Applies | Why Important |
|---------|-----------------|---------------|
| Persistent sidebar navigation | All pages | Web users expect always-visible navigation; mobile uses bottom tabs |
| Server-side pagination for tables | Jobs list, invoices list, clients list | Mobile loads pages lazily; web shows sortable, filterable data tables |
| Column sort on data tables | All list pages | Standard desktop table UX — click header to sort ascending/descending |
| Status filter tabs above tables | Jobs list, quotes list, invoices list | Fast switching between Active/Pending/Complete without a dropdown |
| Inline status badges | All list pages | Color-coded chips showing lifecycle state at a glance |
| Split-pane detail view (optional) | Jobs list + job detail | Click row → detail slides in on right; avoids page navigation for quick reads |
| Keyboard shortcuts | Calendar (arrow keys to navigate weeks) | Power users expect keyboard navigation on desktop |
| Browser tab title with page name | All pages | Bookmarkable states; multi-tab workflows |
| Modal dialogs for destructive actions | Delete booking, cancel job | Web standard; mobile uses bottom sheets |
| Form validation inline (not on submit) | Quote create, job create | Desktop forms have more fields; inline validation improves UX |
| Breadcrumb navigation | Job detail, client detail | Desktop users navigate hierarchies differently than mobile |
| Copy-to-clipboard on IDs / links | Quote links, invoice links | Admin sharing links to quotes with clients |

---

## Sources

- [HouseCall Pro vs Jobber vs ServiceTitan Comparison — Contractor+](https://contractorplus.app/blog/housecall-pro-vs-jobber-vs-servicetitan)
- [Jobber Dashboard Help Center](https://help.getjobber.com/hc/en-us/articles/360033835353-Dashboard)
- [ServiceTitan Dispatch Software Features](https://www.servicetitan.com/features/dispatch-software)
- [Field Service Scheduling — mHelpDesk drag-and-drop calendar](https://www.mhelpdesk.com/features/drag-and-drop-calendar/)
- [Jobber vs Housecall Pro Comparison 2026 — FieldPulse](https://www.fieldpulse.com/resources/blog/housecall-pro-vs-jobber)
- [ServiceTitan Dashboard Overview](https://www-servicetitan.com/dashboard/)
- [Common Mistakes in React Admin Dashboards — DEV Community](https://dev.to/vaibhavg/common-mistakes-in-react-admin-dashboards-and-how-to-avoid-them-1i70)
- [Field Service Scheduling Multi-View UX — Dynamics 365](https://learn.microsoft.com/en-us/dynamics365/field-service/work-with-schedule-board)
- [Construction KPIs Dashboard — Bold BI](https://www.boldbi.com/dashboard-examples/construction/)
- Existing backend API audit: `/backend/app/features/*/router.py` (direct code review, HIGH confidence)

---

*Feature research for: Web Admin Dashboard — ContractorHub v2.0*
*Researched: 2026-03-14*
