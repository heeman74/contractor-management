# Roadmap: ContractorHub

## Milestones

- ✅ **v1.0 MVP** — Phases 1-12 (shipped 2026-03-15) — [archive](milestones/v1.0-ROADMAP.md)
- ✅ **v2.0 Web Admin Dashboard** — Phases 13-18 (shipped 2026-03-19)
- ✅ **v3.0 AI-Driven Construction Management** — Phases 19-26 (completed 2026-03-26)
- 🚧 **v4.0 Financial Intelligence** — Phases 30-37 (in progress)

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

<details>
<summary>✅ v2.0 Web Admin Dashboard (Phases 13-18) — SHIPPED 2026-03-19</summary>

- [x] Phase 13: Web Foundation and Auth (4/4 plans) — completed 2026-03-16
- [x] Phase 14: Job Management (3/3 plans) — completed 2026-03-16
- [x] Phase 15: Scheduling Calendar (4/4 plans) — completed 2026-03-17
- [x] Phase 16: Quotes and Invoices (6/6 plans) — completed 2026-03-18
- [x] Phase 17: CRM — Clients and Contractors (5/5 plans) — completed 2026-03-19
- [x] Phase 18: Reporting Dashboard (3/3 plans) — completed 2026-03-19

</details>

### v3.0 AI-Driven Construction Management (Complete)

**Milestone Goal:** Transform ContractorHub from single-contractor job tracking into an AI-driven multi-trade project management platform where AI plans projects by trade, generates daily checklists, GCs coordinate all trades through chat and inspection tools, and the full quoting/invoicing lifecycle works per trade.

- [x] **Phase 19: Project Data Model** — Project -> Trade Scope -> Task hierarchy with RLS, Drift schema, and sync handlers (completed 2026-03-20)
- [x] **Phase 20: Dependency Engine** — Cross-trade dependency graph with cycle detection, topological sort, and Gantt timeline view (gap closure in progress) (completed 2026-03-22)
- [x] **Phase 21: AI Project Intake and Contractor Interview** — Claude API integration: GC describes project, AI structures by trade, AI interviews each contractor (completed 2026-03-24)
- [x] **Phase 22: Task Execution and Photo Annotation** — Contractor daily checklists, task progress on mobile, non-destructive photo annotation on mobile and web (completed 2026-03-24)
- [x] **Phase 23: Real-Time Chat** — Bidirectional GC-contractor chat with WebSocket, Redis pub/sub, file sharing, and FCM offline delivery
- [x] **Phase 24: GC Inspection Workflow** — Approve/reject/flag tasks, punch list, annotated photo evidence, FCM notifications to contractors (completed 2026-03-25)
- [x] **Phase 25: Per-Trade Billing** — Trade-scoped quotes and invoices, project-level aggregation, progress billing at milestones (completed 2026-03-26)
- [x] **Phase 26: AI Daily Checklists and Monitoring Dashboard** — Morning checklist push, AI schedule adaptation, cross-trade monitoring dashboard with AI alerts (completed 2026-03-26)

### v4.0 Financial Intelligence (In Progress)

**Milestone Goal:** Give owners and project managers real profit visibility and AI-assisted financial management — every project's margin, budget, and quote grounded in actual cost data, invisible to everyone else.

- [x] **Phase 30: Financial Schema Foundation and RBAC Audit** — Cost/labor-rate/budget schema, finance.* permission catalog (owner + project_manager default, admin explicitly excluded), audit of pre-existing money-adjacent surfaces (completed 2026-07-25)
- [x] **Phase 31: Actual Cost Capture** — Materials and subcontractor/other cost entries with receipt photos, scoped to job or trade scope (completed 2026-07-26)
- [ ] **Phase 32: Labor Rates and Cost Rollup** — Effective-dated hourly cost rates, automatic labor cost derivation from time tracking, itemized cost view with category totals
- [ ] **Phase 33: Profit Margin Tracking** — Revenue-minus-cost margin per job/trade scope and project-level rollup, with incomplete-data flagging
- [ ] **Phase 34: Budgeting and Overrun Alerts** — Project/trade budgets, budget-vs-actual view, threshold alerts (80%/100%), quote-revision-driven budget adjustment
- [ ] **Phase 35: Web Financial Dashboard** — Margin and budget-vs-actual charts on the web financial dashboard, permission-gated navigation
- [ ] **Phase 36: AI Profitability Analysis** — Nightly AI scan flagging margin erosion with corrective-action suggestions, finance-gated alerts
- [ ] **Phase 37: AI Quote Planning** — AI-assisted quote line items grounded in company cost history, confidence indicators, quoted-vs-actual variance feedback loop

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
- [x] 13-01-PLAN.md — Backend prep: dual-auth get_current_user (cookie + Bearer), client_type migration, CORS verification
- [x] 13-02-PLAN.md — Next.js scaffold: App Router, TypeScript strict, Tailwind v4, shadcn/ui, Redux makeStore, TanStack Query provider
- [x] 13-03-PLAN.md — Auth layer: Route Handlers (login/refresh/logout), API proxy, apiClient with 401 retry, proxy.ts route guard
- [x] 13-04-PLAN.md — Login page, dashboard shell (sidebar + topbar), dashboard home with KPI cards, error pages, status badge

### Phase 14: Job Management
**Goal**: Admins can manage the full job lifecycle from a single, searchable web interface — reviewing requests, tracking progress, and driving jobs through every status stage
**Depends on**: Phase 13
**Requirements**: JOBS-01, JOBS-02, JOBS-03, JOBS-04
**Success Criteria** (what must be TRUE):
  1. Admin can view all jobs in a filterable list, switch between status tabs, and search by keyword
  2. Admin can open any job and see full detail — notes, contractor assignment, client info, current status, and time tracking
  3. Admin can advance or revert a job's status through the full lifecycle (Quote -> Scheduled -> In Progress -> Complete -> Invoiced)
  4. Admin can view inbound client-submitted job requests and approve or decline each one
**Plans:** 3/3 plans complete

Plans:
- [x] 14-01-PLAN.md — Shared foundation (types, StatusBadge colors, ui-slice pageTitle, shadcn installs, Playwright stubs) + jobs list page with tabs, search, sort, pagination
- [x] 14-02-PLAN.md — Job detail page with two-column layout, notes, activity history, status transitions with confirmation dialogs
- [x] 14-03-PLAN.md — Job request detail page with approve/decline actions and redirect flows

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
- [x] 15-01-PLAN.md — Calendar infrastructure: types, hooks, Redux slice, react-big-calendar with resources prop, booking detail panel, toolbar navigation
- [x] 15-02-PLAN.md — Drag-and-drop rescheduling: backend contractor_id support, optimistic update/rollback, conflict pre-check, conflict warning modal
- [x] 15-03-PLAN.md — Booking creation from empty slots, multi-filter toolbar with chips, E2E test stubs
- [x] 15-04-PLAN.md — Gap closure: add client_name to JobResponse and wire into calendar booking events

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
**Plans:** 6/6 plans complete

Plans:
- [x] 16-01-PLAN.md — Backend list endpoints, amount_paid migration, TypeScript types, StatusBadge extensions, apiFetchRaw, dnd-kit install, E2E stubs
- [x] 16-02-PLAN.md — Quotes list page (DataTable + status tabs) + Quote detail page (two-column layout, lifecycle actions, PDF download)
- [x] 16-03-PLAN.md — Invoices list page (DataTable + payment tabs, overdue highlighting) + Invoice detail (payment recording, PDF download)
- [x] 16-04-PLAN.md — Quote builder (react-hook-form + dnd-kit inline editing, template loading, preview mode) + Job detail integration (Create Quote, Generate Invoice buttons)
- [x] 16-05-PLAN.md — Gap closure: Implement 12 Playwright E2E tests for quotes (list, detail, builder, send, PDF)
- [x] 16-06-PLAN.md — Gap closure: Implement 8 Playwright E2E tests for invoices (list, detail, payments, PDF)

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
**Plans:** 5/5 plans complete

Plans:
- [x] 17-01-PLAN.md — Backend CRM router, TypeScript types, StatusBadge availability colors, E2E test stubs
- [x] 17-02-PLAN.md — Client list page (search, pagination, sorting) + Client detail page (job history, properties, sidebar)
- [x] 17-03-PLAN.md — Contractor list page (availability badges, batch fetch) + Contractor profile (schedule summary, assigned jobs)
- [x] 17-04-PLAN.md — Schedule editor: ScheduleGrid component (drag-to-paint CSS grid) + date overrides (calendar picker, save/remove)
- [x] 17-05-PLAN.md — Cross-page links (job/quote/invoice/schedule to CRM pages) + Playwright E2E tests

### Phase 18: Reporting Dashboard
**Goal**: Admins can review business performance at a glance with charts covering revenue, job status, contractor utilization, and quote conversion, filtered by any date range
**Depends on**: Phase 13
**Requirements**: RPT-01, RPT-02, RPT-03
**Success Criteria** (what must be TRUE):
  1. Admin can view a dashboard with four charts: revenue by month, jobs by status breakdown, contractor utilization, and quote conversion rate
  2. Admin can change the date range and all charts update to reflect the selected period
  3. Admin can view a contractor utilization heatmap showing which contractors are overloaded or underutilized
**Plans:** 3/3 plans complete

Plans:
- [x] 18-01-PLAN.md — Backend utilization-heatmap endpoint, TypeScript types, Recharts + shadcn chart install, E2E test stubs
- [x] 18-02-PLAN.md — Reports page with DateRangeFilter, ChartCard wrapper, Revenue/Jobs/Quote charts with drill-down and CSV export
- [x] 18-03-PLAN.md — Utilization heatmap component, dashboard integration, Playwright E2E + backend integration tests

### Phase 19: Project Data Model
**Goal**: GCs can create multi-trade projects, assign contractors per trade, and view the full project hierarchy — establishing the data layer that every other v3.0 feature depends on
**Depends on**: Phase 18 (v2.0 complete)
**Requirements**: PROJ-01, PROJ-02, PROJ-03
**Success Criteria** (what must be TRUE):
  1. GC can create a project with description, address, client, and target timeline and see it in their project list
  2. GC can add trade scopes (plumbing, electrical, carpentry, etc.) to a project and assign a contractor to each scope
  3. GC can navigate the project hierarchy (Project -> Trade Scopes -> Tasks) as a tree view on mobile and web
  4. Cross-tenant isolation holds: Company B's token cannot access Company A's project data — all new tables have RLS policies enforced
**Plans:** 5/5 plans complete

Plans:
- [x] 19-01-PLAN.md — Backend SQLAlchemy models (6 entities) + Alembic migration 0015 with RLS, indexes, triggers, and data migration
- [x] 19-02-PLAN.md — Mobile Drift schema v7 (5 tables) + DAOs with reactive streams + sync handlers
- [x] 19-03-PLAN.md — Backend CRUD endpoints (repository, service, router) + 16 integration tests covering RLS and status transitions
- [x] 19-04-PLAN.md — Mobile UI: project list, detail, scope cards, task list + Riverpod providers + Projects bottom nav tab + 10 E2E tests
- [x] 19-05-PLAN.md — Web UI: project tree sidebar, detail panels, create dialog, trade scope sheet + 10 Playwright E2E tests

### Phase 20: Dependency Engine
**Goal**: The system enforces cross-trade task dependencies with cycle prevention, and GCs can visualize the full project timeline with all trades and their dependency relationships
**Depends on**: Phase 19
**Requirements**: PROJ-04, PROJ-05, AI-06
**Success Criteria** (what must be TRUE):
  1. GC can define a finish-to-start dependency between trade scopes, and the system rejects circular dependencies with a clear error
  2. The dependency graph computes a valid execution order — tasks in a blocked trade scope cannot be started until their predecessor completes
  3. GC can view a Gantt-style timeline showing all trade scopes with dependency arrows and current progress indicators
  4. AI (and manual edits) that would create two trades needing the same space on the same day are flagged as a conflict before they are saved
**Plans:** 6/6 plans complete

Plans:
- [ ] 20-01-PLAN.md — Backend: TaskDependency + ProjectZone models, migration 0016, DFS cycle detection, blocked status, conflict detection, REST endpoints, integration tests
- [x] 20-02-PLAN.md — Mobile: Drift schema v8 (TaskDependencies + ProjectZones tables), DAOs, sync handlers
- [ ] 20-03-PLAN.md — Web: SVAR Gantt timeline page, dependency/conflict/zone components, Playwright E2E tests
- [ ] 20-04-PLAN.md — Mobile: CustomPainter Gantt chart, dependency arrows, drag-to-connect, blocked enforcement, Flutter E2E tests
- [ ] 20-05-PLAN.md — Gap closure: Wire web Gantt dependency fetching so SVAR arrows render
- [ ] 20-06-PLAN.md — Gap closure: Wire mobile drag-to-connect to persist via Drift + sync queue

### Phase 21: AI Project Intake and Contractor Interview
**Goal**: GCs can describe a project in natural language and AI produces a structured trade breakdown with sequencing; each trade contractor is interviewed by AI to generate a detailed task plan
**Depends on**: Phase 20
**Requirements**: AI-01, AI-02, AI-03
**Success Criteria** (what must be TRUE):
  1. GC can type a plain-English project description in a chat interface and receive an AI-generated breakdown of trade scopes with suggested sequencing and dependencies
  2. AI asks the GC clarifying questions before generating the trade breakdown when the project description is ambiguous
  3. Each trade contractor can complete an AI-guided interview with trade-specific questions and receive a generated task plan with per-task detail
  4. All AI-generated trade scopes and tasks are validated against the data model (referential integrity, no orphan tasks) before being written to the database
**Plans:** 7/7 plans complete

Plans:
- [x] 21-01-PLAN.md — Backend AI module: SQLAlchemy models (3 tables), Alembic migration 0017 with RLS, repository, AIService with Claude streaming + tool dispatch, system prompts
- [x] 21-02-PLAN.md — Backend SSE endpoints: FastAPI router with intake/interview start/message/complete, EventSourceResponse streaming, backend unit + integration E2E tests
- [x] 21-03-PLAN.md — Web chat UI: SSE proxy route, streaming hooks, chat components (bubbles, typing indicator, input), TradeScopePreviewCard, TaskPreviewList, intake + interview pages
- [x] 21-04-PLAN.md — Mobile chat UI: Drift schema v9, SSE client (bypasses Dio), Riverpod providers, chat screens, widgets, navigation routes
- [x] 21-05-PLAN.md — E2E tests: Flutter widget tests (16+ tests) + Playwright E2E tests (14+ tests) covering all three AI requirements on both platforms
- [x] 21-06-PLAN.md — Image upload: backend endpoint with Pillow compression, Claude vision base64 wiring, image_ref_id flow, upload tests

### Phase 22: Task Execution and Photo Annotation
**Goal**: Contractors can complete their assigned tasks on mobile with notes, photos, and attachments; annotated photos (arrows, circles, text, measurements) work on both mobile and web with non-destructive storage
**Depends on**: Phase 21
**Requirements**: TASK-01, TASK-02, TASK-03, TASK-04, TASK-05, TASK-06, TASK-07
**Success Criteria** (what must be TRUE):
  1. Contractor can open their mobile app and see their current task list for the day, ordered by priority
  2. Contractor can check off tasks as complete and the GC's view updates to reflect the new progress state
  3. Contractor can add a progress note (text) to any task and the note persists across app restarts
  4. Contractor can capture or attach a photo to a task and draw annotations (arrows, circles, text, measurements) on it before saving
  5. Contractor can attach a PDF document to any task and the attachment is accessible to the GC
  6. GC can view task progress (completion status, notes, photos) across all trades from the mobile app
**Plans:** 5/5 plans complete

Plans:
- [x] 22-01-PLAN.md — Backend: migration 0019 (task_notes table + annotation_data JSONB), TaskNote model/service/schemas, task note + attachment upload endpoints, integration tests
- [x] 22-02-PLAN.md — Mobile: Drift schema v10 (TaskNotes + annotationData), TaskNoteDao, TaskAttachmentDao, cross-scope TaskDao query, providers, routes, DAO tests
- [x] 22-03-PLAN.md — Mobile UI: MyTasksScreen (cross-scope checklist), TaskDetailScreen (notes, photos, PDFs), TaskChecklistCard (photo gate), GoRouter wiring
- [x] 22-04-PLAN.md — Photo annotation: shared JSON schema, Flutter PhotoAnnotationScreen (4 tools), web PhotoAnnotationCanvas (HTML5 Canvas), annotation unit tests
- [x] 22-05-PLAN.md — GC progress: TradeProgressCard (mobile + web), ProjectDetailScreen upgrade, Phase 22 E2E tests (15+ tests covering TASK-01 through TASK-07)

### Phase 23: Real-Time Chat
**Goal**: GCs and contractors can exchange messages, photos, and files in real time within project-scoped trade threads, with push notifications for offline delivery
**Depends on**: Phase 19
**Requirements**: CHAT-01, CHAT-02, CHAT-03, CHAT-04, CHAT-05
**Success Criteria** (what must be TRUE):
  1. GC can send a text message to any trade contractor on a project and the message appears in under 2 seconds on the contractor's screen
  2. Contractor can reply and both parties see the conversation in a consistent thread — no message duplication or ordering bugs
  3. Both parties can share photos (including annotated photos) and PDF files in chat
  4. Chat threads are organized by trade scope within a project — the GC's electrical chat and plumbing chat are separate threads
  5. A contractor who is offline receives a push notification (FCM) for new messages and sees full message history when they reconnect
**Plans:** 5/6 plans complete

Plans:
- [x] 23-01-PLAN.md — Backend foundation: migration 0020 (4 chat tables with RLS), SQLAlchemy models, repository, service, schemas, WebSocket ConnectionManager with Redis pub/sub
- [x] 23-02-PLAN.md — Mobile data layer: Drift schema v11 (3 chat tables), ChatDao, ChatWsClient with reconnect backoff, ChatSyncService (offline outbox), Riverpod providers
- [x] 23-03-PLAN.md — Backend endpoints: WebSocket router with JWT auth + 5-min re-validation, REST chat endpoints (threads, messages, attachments, read receipts, mute), FCM chat notifications, integration tests
- [x] 23-04-PLAN.md — Mobile chat UI: ChatScreen (thread list), ChatThreadScreen (message view + WS), MessageBubble (4 variants), ChatInputBar (attachments + @mentions), TypingIndicator, GoRouter routes
- [x] 23-05-PLAN.md — Web chat: TypeScript types, useChatWebSocket hook, useChatMessages infinite query hook, ChatPanel split view, thread list, message bubbles, message input, Playwright E2E tests
- [x] 23-06-PLAN.md — Phase E2E tests: 19 backend integration tests + 23 Flutter widget E2E tests covering CHAT-01 through CHAT-05

### Phase 24: GC Inspection Workflow
**Goal**: GCs can formally inspect completed tasks from mobile, approve or reject them with annotated photo evidence, create punch list items, and contractors are notified of decisions immediately
**Depends on**: Phase 22
**Requirements**: INSP-01, INSP-02, INSP-03, INSP-04
**Success Criteria** (what must be TRUE):
  1. GC can open a completed task on mobile and approve or reject it, with the decision and optional comment recorded against the task
  2. GC can flag an issue discovered during a site walk by attaching an annotated photo and a description — the flag is stored independently of a specific task
  3. GC can create a punch list item assigned to a specific trade scope, and that item appears in the trade contractor's task view
  4. When a GC rejects a task, the assigned contractor receives an FCM push notification containing the GC's rejection reason within 30 seconds
**Plans:** 4/4 plans complete

Plans:
- [x] 24-01-PLAN.md — Backend: migration 0022 (3 new tables + task status extension), SQLAlchemy models, repositories, services, schemas, 7 REST endpoints, FCM rejection notification
- [x] 24-02-PLAN.md — Mobile: Drift schema v12 (3 new tables + inspectionChecklist column), DAOs with sync queue dual-write, sync handlers, Riverpod providers
- [x] 24-03-PLAN.md — Mobile UI: inspection checklist + approve/reject on TaskDetailScreen, rejection bottom sheet, site walk flag capture, punch list cards in trade scope view
- [x] 24-04-PLAN.md — E2E tests: 18+ backend integration tests + 22+ Flutter widget tests covering INSP-01 through INSP-04

### Phase 25: Per-Trade Billing
**Goal**: GCs can create quotes and invoices scoped to each trade, aggregate them to a project-level view for client approval, and invoice at milestones within a trade scope
**Depends on**: Phase 19
**Requirements**: BILL-01, BILL-02, BILL-03, BILL-04, BILL-05
**Success Criteria** (what must be TRUE):
  1. GC can create a quote for a specific trade scope with line items and send it for client approval without affecting quotes for other trade scopes
  2. GC can view a project-level quote summary that aggregates all trade quotes into a single client-facing total
  3. GC can generate an invoice for a trade scope from completed work items on that scope
  4. GC can view a project-level invoice summary showing the total billed, paid, and outstanding across all trades
  5. GC can create a progress invoice for a partial milestone within a trade scope (not only at trade completion)
**Plans:** 3/5 plans complete

Plans:
- [x] 25-01-PLAN.md — Backend: migration 0023 (trade_scope_id on quotes/invoices, billing_milestones table with RLS), model extensions, BillingMilestone feature module
- [x] 25-02-PLAN.md — Mobile: Drift schema v13 (BillingMilestones table, tradeScopeId columns), DAOs, entities, sync handler
- [ ] 25-03-PLAN.md — Backend: trade-scoped billing endpoints (quote/invoice per scope), progress billing, project-level aggregation endpoints
- [ ] 25-04-PLAN.md — Mobile UI: TradeScopeDetailScreen billing sections, milestone management, ProjectDetailScreen aggregation summaries
- [x] 25-05-PLAN.md — E2E tests: backend integration tests + Flutter widget/DAO tests covering BILL-01 through BILL-05

### Phase 26: AI Daily Checklists and Monitoring Dashboard
**Goal**: Contractors receive a personalized morning push with today's unblocked tasks; GCs monitor all trades simultaneously on the web dashboard with AI-generated alerts when schedules slip
**Depends on**: Phase 21, Phase 20
**Requirements**: AI-04, AI-05, DASH-01, DASH-02, DASH-03, DASH-04
**Success Criteria** (what must be TRUE):
  1. Each contractor receives a morning FCM push with their AI-generated daily task list — only tasks that are unblocked by dependencies and scheduled for today
  2. GC can view all active projects on the web dashboard with a per-trade status summary (on track / at risk / blocked) at a glance
  3. When a trade falls behind schedule or a dependency is at risk, the GC sees an AI-generated alert on the dashboard explaining the impact and a suggested remediation
  4. GC can drill down from the project overview to an individual trade's task list without leaving the web dashboard
  5. AI adapts task schedules based on actual progress — a delayed task triggers a rescheduling suggestion for all dependent tasks across all trades
**Plans:** 4/4 plans complete

Plans:
- [x] 26-01-PLAN.md — Backend: migration 0024, APScheduler, checklist + dashboard services, AI prompts, REST endpoints
- [x] 26-02-PLAN.md — Mobile: Drift schema v14, DailyChecklistDao, sync handler, DailyChecklistScreen
- [x] 26-03-PLAN.md — Web: monitoring dashboard with project cards, trade timeline, alert panel, drill-down
- [x] 26-04-PLAN.md — E2E tests: 19 backend integration + 11 Flutter widget tests

### Phase 30: Financial Schema Foundation and RBAC Audit
**Goal**: The financial data foundation exists and is protected from day one — finance.* permissions gate all money data, the admin role does not inherit financial access, and every pre-existing money-adjacent surface has been audited so nothing leaks before new financial features are built on top
**Depends on**: Phase 26 (v3.0 complete)
**Requirements**: FINSEC-01, FINSEC-02, FINSEC-03, FINSEC-04
**Success Criteria** (what must be TRUE):
  1. Owner/PM sees finance.* permission toggles in the Roles & Permissions matrix UI, granted by default only to owner and project_manager
  2. The admin role's default derived permission set contains zero finance.* keys — verified by an automated regression test, not manual inspection
  3. Company owner can grant finance.* to a custom role (e.g., bookkeeper) via the existing Roles & Permissions matrix and that role immediately gains access per the grant
  4. Every pre-existing money-adjacent surface (reports endpoint, monitoring dashboard, AI chat/checklist tool results) is audited and returns no cost/margin/budget fields to a user without finance.* permission
**Plans:** 4/4 plans complete
**UI hint**: yes

Plans:
- [x] 30-01-PLAN.md — Permission catalog: 3 finance.* keys in a Finance group, admin-exclusion derivation, PM defaults + regression tests (FINSEC-01/02/03)
- [x] 30-02-PLAN.md — Financial schema: 5 tenant-scoped tables + RLS (migration 0032), 4 system cost categories seed, existing-company PM backfill, XOR create-schemas (FINSEC-01)
- [x] 30-03-PLAN.md — Audit plumbing: finance-scrub helper + permission-aware dashboard alert filter, with unit tests (FINSEC-04)
- [x] 30-04-PLAN.md — Phase E2E suite: backfill/seed/RLS integration + reports/alerts/AI leak tripwires (FINSEC-01..04)

### Phase 31: Actual Cost Capture
**Goal**: Owner/PM can record real project costs as they occur, with supporting documentation, scoped to the job or trade scope they belong to
**Depends on**: Phase 30
**Requirements**: COST-01, COST-02, COST-03
**Success Criteria** (what must be TRUE):
  1. Owner/PM can record a materials cost entry (amount, category, date, vendor, note) against a job or trade scope
  2. Owner/PM can record a subcontractor or other cost entry the same way, against a job or trade scope
  3. Owner/PM can attach a receipt photo to any cost entry
  4. A user without finance.* permission cannot view or create cost entries — attempting to do so returns a 403
**Plans:** 5/5 plans complete

Plans:
- [x] 31-01-PLAN.md — Backend: cost-entry CRUD + category list + project rollup, migration 0034 (cost_receipts table + RLS), inline finance.* gating, backend E2E (Wave 1)
- [x] 31-02-PLAN.md — Backend: receipt upload/list/delete + cost-receipts serve_router branch (RLS-scoped), receipt E2E (Wave 2)
- [x] 31-03-PLAN.md — Web: finance feature module (API/hooks/components) + Costs sections on job/trade-scope/project detail, permission-gated, Playwright + Jest (Wave 3)
- [x] 31-04-PLAN.md — Mobile: Drift v16 cost_entries/cost_receipts tables + DAOs, CostEntrySyncHandler (push), CostReceiptUploadService (retry/backoff), on-demand repository, unit tests (Wave 3)
- [x] 31-05-PLAN.md — Mobile: cost providers + AddCostSheet (camera/gallery receipt) + Costs sections on job/scope/project screens, phase E2E (Wave 4)

### Phase 32: Labor Rates and Cost Rollup
**Goal**: Labor cost is derived automatically and accurately from tracked time, and Owner/PM can see a complete, itemized picture of what every job actually cost
**Depends on**: Phase 30
**Requirements**: COST-04, COST-05, COST-06
**Success Criteria** (what must be TRUE):
  1. Owner/PM can set a worker's hourly cost rate with an effective date, and previously effective rates remain preserved and visible in history
  2. The system automatically computes labor cost for tracked time by multiplying hours worked by the rate that was effective on the day the work happened — a later rate change does not retroactively rewrite past labor cost
  3. Owner/PM can view itemized costs per job, per trade scope, and per project, broken out by category (labor/materials/subcontractor/other) with totals
**Plans:** 4/5 plans executed

Plans:
- [x] 32-01-PLAN.md — Backend: pure effective-dated rate resolution module + append-only labor-rate endpoints gated finance.rates.manage (COST-04/05, Wave 1)
- [x] 32-02-PLAN.md — Backend: two-query labor derivation, job/trade-scope cost-breakdown endpoints, additive rollup extension, reserved labor-category guard (COST-05/06, Wave 2)
- [x] 32-03-PLAN.md — Web: Team page Cost Rate column + RateHistoryDialog with full effective-dated history (COST-04, Wave 2)
- [x] 32-04-PLAN.md — Web: shared CostBreakdownSummary on job/trade-scope/project Costs surfaces + Labor removed from the AddCost picker (COST-06, Wave 3)
- [ ] 32-05-PLAN.md — Mobile: CostBreakdown model/providers/widget on all three Costs screens + phase E2E suite (COST-06, Wave 3)

### Phase 33: Profit Margin Tracking
**Goal**: Owner/PM can trust the profit margin shown for any job, trade scope, or project — real numbers where data exists, an honest flag where it doesn't
**Depends on**: Phase 31, Phase 32
**Requirements**: MARG-01, MARG-02, MARG-03
**Success Criteria** (what must be TRUE):
  1. Owner/PM can view profit margin (revenue minus actual cost) for any job or trade scope
  2. Owner/PM can view a project-level margin rollup that aggregates margin across all trade scopes on that project
  3. A job or project with incomplete cost data (legacy pre-v4.0 job, missing labor rate) displays an explicit "incomplete data" flag instead of a fabricated margin number
**Plans**: TBD

### Phase 34: Budgeting and Overrun Alerts
**Goal**: Owner/PM can set spending ceilings per project and trade scope and get warned before they're blown, with quote changes automatically kept in sync
**Depends on**: Phase 33
**Requirements**: BUDG-01, BUDG-02, BUDG-03, BUDG-04
**Success Criteria** (what must be TRUE):
  1. Owner/PM can set a budget for a project and independently for any trade scope within it
  2. Owner/PM can view budgeted vs. spent vs. remaining at both the project level and the trade scope level
  3. Owner/PM receives an alert (dashboard + FCM push) when spend crosses the 80% warning threshold and again at 100% overrun, and only finance-permitted users receive it
  4. Approving a quote revision automatically adjusts the linked budget by the revision's delta amount, with no manual re-entry required
**Plans**: TBD

### Phase 35: Web Financial Dashboard
**Goal**: Owner/PM can see the financial health of every project and the company as a whole at a glance, in the same reporting experience they already use
**Depends on**: Phase 33, Phase 34
**Requirements**: MARG-04
**Success Criteria** (what must be TRUE):
  1. Owner/PM can view a web financial dashboard showing margin trend and budget-vs-actual charts for any project
  2. Owner/PM can view a company-wide financial rollup alongside the existing v2.0 reporting dashboard, using the same navigation and visual conventions
  3. A user without finance.* permission does not see the Financials nav item or any financial dashboard route at all
**Plans**: TBD
**UI hint**: yes

### Phase 36: AI Profitability Analysis
**Goal**: AI proactively watches every project's financial health so Owner/PM catches margin erosion before it compounds, with every claim grounded in real data
**Depends on**: Phase 33, Phase 34
**Requirements**: FINAI-01, FINAI-02
**Success Criteria** (what must be TRUE):
  1. Every active project is analyzed by AI on a nightly schedule, and margin erosion is flagged with a specific, suggested corrective action
  2. Owner/PM receives a finance-gated alert for each AI profitability finding — the alert is invisible to any user without finance.* permission
  3. Every dollar figure stated in an AI profitability finding traces to a real tool-sourced cost/margin/budget value, never an AI estimate
**Plans**: TBD

### Phase 37: AI Quote Planning
**Goal**: Owner/PM gets AI-assisted quote line items grounded in the company's own cost history, always reviewed by a human before anything is sent to a client
**Depends on**: Phase 32
**Requirements**: FINAI-03, FINAI-04, FINAI-05
**Success Criteria** (what must be TRUE):
  1. Owner/PM can trigger AI to pre-fill a new quote's line items (labor hours, material quantities, unit prices) grounded in the company's historical cost data
  2. Owner/PM must explicitly review and approve AI-suggested line items before a quote can be sent — no quote is ever sent autonomously
  3. Each AI quote suggestion displays a confidence indicator reflecting how much historical data backs it
  4. Owner/PM can view quoted-vs-actual variance for any completed project or trade scope, and that variance history feeds into future AI quote suggestions
**Plans**: TBD

## Progress

**Execution Order:**
v3.0 phases: 19 -> 20 -> 21 -> 22 -> 23 (parallel with 22) -> 24 -> 25 (parallel with 24) -> 26
Note: Phase 23 (Chat) depends only on Phase 19 and may start in parallel with Phase 22.
Note: Phase 25 (Billing) depends only on Phase 19 and may start in parallel with Phase 24.

v4.0 phases: 30 -> {31, 32 in parallel} -> 33 -> 34 -> {35, 36 in parallel} ; 37 depends only on 32 and may run in parallel with 33-36.
Note: Phase 31 (Cost Capture) and Phase 32 (Labor Rates) both depend only on Phase 30 and may run in parallel.
Note: Phase 37 (AI Quote Planning) depends only on Phase 32 and may run in parallel with Phases 33-36.

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
| 13. Web Foundation and Auth | v2.0 | 4/4 | Complete | 2026-03-16 |
| 14. Job Management | v2.0 | 3/3 | Complete | 2026-03-16 |
| 15. Scheduling Calendar | v2.0 | 4/4 | Complete | 2026-03-17 |
| 16. Quotes and Invoices | v2.0 | 6/6 | Complete | 2026-03-18 |
| 17. CRM — Clients and Contractors | v2.0 | 5/5 | Complete | 2026-03-19 |
| 18. Reporting Dashboard | v2.0 | 3/3 | Complete | 2026-03-19 |
| 19. Project Data Model | v3.0 | 5/5 | Complete | 2026-03-21 |
| 20. Dependency Engine | v3.0 | 6/6 | Complete | 2026-03-22 |
| 21. AI Project Intake and Contractor Interview | v3.0 | 7/7 | Complete    | 2026-03-24 |
| 22. Task Execution and Photo Annotation | v3.0 | 5/5 | Complete    | 2026-03-24 |
| 23. Real-Time Chat | v3.0 | 5/6 | Complete    | 2026-03-24 |
| 24. GC Inspection Workflow | v3.0 | 4/4 | Complete    | 2026-03-25 |
| 25. Per-Trade Billing | v3.0 | 3/5 | Complete    | 2026-03-26 |
| 26. AI Daily Checklists and Monitoring Dashboard | v3.0 | 4/4 | Complete    | 2026-03-26 |
| 30. Financial Schema Foundation and RBAC Audit | v4.0 | 4/4 | Complete    | 2026-07-25 |
| 31. Actual Cost Capture | v4.0 | 5/5 | Complete    | 2026-07-26 |
| 32. Labor Rates and Cost Rollup | v4.0 | 4/5 | In Progress|  |
| 33. Profit Margin Tracking | v4.0 | 0/? | Not started | - |
| 34. Budgeting and Overrun Alerts | v4.0 | 0/? | Not started | - |
| 35. Web Financial Dashboard | v4.0 | 0/? | Not started | - |
| 36. AI Profitability Analysis | v4.0 | 0/? | Not started | - |
| 37. AI Quote Planning | v4.0 | 0/? | Not started | - |
