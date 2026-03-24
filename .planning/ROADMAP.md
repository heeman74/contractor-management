# Roadmap: ContractorHub

## Milestones

- ✅ **v1.0 MVP** — Phases 1-12 (shipped 2026-03-15) — [archive](milestones/v1.0-ROADMAP.md)
- ✅ **v2.0 Web Admin Dashboard** — Phases 13-18 (shipped 2026-03-19)
- 🚧 **v3.0 AI-Driven Construction Management** — Phases 19-26 (in progress)

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

### v3.0 AI-Driven Construction Management (In Progress)

**Milestone Goal:** Transform ContractorHub from single-contractor job tracking into an AI-driven multi-trade project management platform where AI plans projects by trade, generates daily checklists, GCs coordinate all trades through chat and inspection tools, and the full quoting/invoicing lifecycle works per trade.

- [x] **Phase 19: Project Data Model** — Project -> Trade Scope -> Task hierarchy with RLS, Drift schema, and sync handlers (completed 2026-03-20)
- [x] **Phase 20: Dependency Engine** — Cross-trade dependency graph with cycle detection, topological sort, and Gantt timeline view (gap closure in progress) (completed 2026-03-22)
- [x] **Phase 21: AI Project Intake and Contractor Interview** — Claude API integration: GC describes project, AI structures by trade, AI interviews each contractor (completed 2026-03-24)
- [x] **Phase 22: Task Execution and Photo Annotation** — Contractor daily checklists, task progress on mobile, non-destructive photo annotation on mobile and web (completed 2026-03-24)
- [x] **Phase 23: Real-Time Chat** — Bidirectional GC-contractor chat with WebSocket, Redis pub/sub, file sharing, and FCM offline delivery
- [ ] **Phase 24: GC Inspection Workflow** — Approve/reject/flag tasks, punch list, annotated photo evidence, FCM notifications to contractors
- [ ] **Phase 25: Per-Trade Billing** — Trade-scoped quotes and invoices, project-level aggregation, progress billing at milestones
- [ ] **Phase 26: AI Daily Checklists and Monitoring Dashboard** — Morning checklist push, AI schedule adaptation, cross-trade monitoring dashboard with AI alerts

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
**Plans**: TBD

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
**Plans**: TBD

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
**Plans**: TBD

## Progress

**Execution Order:**
v3.0 phases: 19 -> 20 -> 21 -> 22 -> 23 (parallel with 22) -> 24 -> 25 (parallel with 24) -> 26
Note: Phase 23 (Chat) depends only on Phase 19 and may start in parallel with Phase 22.
Note: Phase 25 (Billing) depends only on Phase 19 and may start in parallel with Phase 24.

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
| 24. GC Inspection Workflow | v3.0 | 0/TBD | Not started | - |
| 25. Per-Trade Billing | v3.0 | 0/TBD | Not started | - |
| 26. AI Daily Checklists and Monitoring Dashboard | v3.0 | 0/TBD | Not started | - |
