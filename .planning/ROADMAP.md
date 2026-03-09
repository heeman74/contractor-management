# Roadmap: ContractorHub

## Overview

ContractorHub is built in eight phases that front-load all architectural risk before any user-visible feature is written. Phases 1-3 establish the three non-negotiable foundations — multi-tenant data isolation, offline-first sync, and the scheduling engine — because all three are non-recoverable if retrofitted later. Phases 4-8 build on this foundation to deliver a complete contractor management workflow: job lifecycle, dispatch calendar, field tools, client transparency, and business operations. Every phase closes a coherent capability loop that can be verified independently.

## Phases

**Phase Numbering:**
- Integer phases (1, 2, 3): Planned milestone work
- Decimal phases (2.1, 2.2): Urgent insertions (marked with INSERTED)

Decimal phases appear between their surrounding integers in numeric order.

- [x] **Phase 1: Foundation** - Flutter + FastAPI project skeletons with multi-tenant data isolation and role models
- [x] **Phase 2: Offline Sync Engine** - Local SQLite with transactional outbox, background sync, and conflict resolution (UAT gap closure in progress) (completed 2026-03-06)
- [ ] **Phase 3: Scheduling Engine** - Conflict detection, travel time awareness, multi-day jobs, and availability tracking
- [x] **Phase 4: Job Lifecycle** - Job CRUD, lifecycle state machine, client CRM, and dual job creation flows (completed 2026-03-09)
- [ ] **Phase 5: Calendar and Dispatch UI** - Drag-and-drop calendar, overdue warnings, and delay justification flow
- [ ] **Phase 6: Field Workflow** - Job notes, photo capture, GPS address, drawing pad, and time tracking
- [ ] **Phase 7: Client Portal and Notifications** - Client-facing job status, progress photos, delay visibility, and push notifications
- [ ] **Phase 8: Business Operations** - Digital quoting, quote approval, invoicing, and reporting dashboard

## Phase Details

### Phase 1: Foundation
**Goal**: Developers can run the full stack locally with multi-tenant data isolation enforced at the database level and role-differentiated user models in place
**Depends on**: Nothing (first phase)
**Requirements**: INFRA-01, INFRA-02, INFRA-05, INFRA-06
**Success Criteria** (what must be TRUE):
  1. Flutter project runs on Android with Drift local DB, Riverpod state management, go_router navigation, and get_it dependency injection wired together
  2. FastAPI backend starts locally via Docker Compose with PostgreSQL, Row Level Security enabled on all tenant tables, and the btree_gist extension installed
  3. Company, user, and role data models exist with UUID primary keys, version columns, and tenant_id foreign keys; Alembic manages all schema changes
  4. A test proves Tenant A cannot read or write Tenant B's data through any API endpoint
  5. All three role types (company admin, contractor, client) are represented in the data model and enforced by role-gated route guards in Flutter
**Plans:** 5/5 plans executed — COMPLETE

Plans:
- [x] 01-01-PLAN.md — Flutter project scaffold with Drift, Riverpod, go_router, get_it, and feature-first directory structure
- [x] 01-02-PLAN.md — FastAPI project scaffold with Docker Compose, PostgreSQL RLS, Alembic migration 0001, tenant middleware, and CI pipeline
- [x] 01-03-PLAN.md — Multi-tenant data models: Freezed entities, Drift DAOs, Pydantic schemas, and REST CRUD endpoints
- [x] 01-04-PLAN.md — Role-gated navigation with go_router guards, auth stub, app shell with bottom nav, and placeholder screens
- [x] 01-05-PLAN.md — Tenant isolation integration tests, role guard unit tests, and seed data script

### Phase 2: Offline Sync Engine
**Goal**: The Flutter app stores all data locally first and reliably synchronizes to the backend when connectivity is available, with no data loss or duplication
**Depends on**: Phase 1
**Requirements**: INFRA-03, INFRA-04
**Success Criteria** (what must be TRUE):
  1. All reads in the Flutter app stream from local Drift database — no UI widget awaits an HTTP response directly
  2. User can create a record while offline; it appears immediately in the UI and syncs to the backend when connectivity is restored
  3. A record created offline and retried multiple times due to network failure appears exactly once in the backend (idempotency via client-generated UUID)
  4. The app displays a visible sync status indicator ("N items pending", "Syncing...", "All synced") at all times
  5. A sync conflict between local and server versions resolves predictably — server always wins on all entity types — with no silent data loss
**Plans:** 7/7 plans complete

Plans:
- [x] 02-01-PLAN.md — Drift sync_queue outbox table, sync_cursor table, deleted_at soft-delete columns, schema v2 migration, SyncQueueDao, SyncCursorDao
- [x] 02-02-PLAN.md — Backend Alembic migration 0002 (deleted_at, updated_at triggers), delta sync endpoint, idempotent mutation services
- [x] 02-03-PLAN.md — SyncEngine service with queue drain, delta pull, SyncRegistry, SyncHandlers, ConnectivityService, DioClient retry interceptor
- [x] 02-04-PLAN.md — WorkManager background sync dispatcher, sync status Riverpod provider, app bar subtitle, pull-to-refresh on main screens
- [x] 02-05-PLAN.md — SyncEngine unit tests (mock Dio), delta sync and idempotency integration tests (real PostgreSQL)
- [x] 02-06-PLAN.md — GAP CLOSURE: Fix sync endpoint empty cursor 422 and GoRouter authenticated redirect from onboarding
- [ ] 02-07-PLAN.md — GAP CLOSURE: Backfill user_roles.updated_at NULL rows and fix sync status provider premature allSynced on reconnect

### Phase 3: Scheduling Engine
**Goal**: The backend can compute contractor availability, detect booking conflicts (including travel time buffers), and safely block multiple days for spanning jobs — all enforced at the database level
**Depends on**: Phase 1
**Requirements**: SCHED-04, SCHED-05, SCHED-06, SCHED-07
**Success Criteria** (what must be TRUE):
  1. The scheduling engine returns available time slots for a contractor on a given day, accounting for existing bookings and travel time buffers between job sites
  2. Two simultaneous booking attempts for the same contractor slot result in exactly one success — the database EXCLUDE USING GIST constraint rejects the second even if application checks pass
  3. A multi-day job blocks the contractor's availability across all days it spans, including partial-day segments correctly
  4. Travel time between consecutive job sites is fetched, cached with TTL, and subtracted from available slot windows before returning results
  5. The scheduling engine is exercised by unit tests independent of any HTTP routing — it is a pure business logic module
**Plans:** 2/4 plans executed

Plans:
- [ ] 03-01-PLAN.md — Data foundation: Alembic migration 0007 with 6 scheduling tables (GIST constraint on bookings), ORM models, Pydantic schemas
- [ ] 03-02-PLAN.md — Travel time and geocoding: pluggable provider interfaces, ORS implementations, PostgreSQL cache with TTL
- [ ] 03-03-PLAN.md — Scheduling engine core: SchedulingRepository, SchedulingService (availability, booking, multi-day, date suggestion)
- [ ] 03-04-PLAN.md — API endpoints and tests: REST router, unit tests, concurrent booking integration tests, multi-day and travel time tests

### Phase 4: Job Lifecycle
**Goal**: Company admins can create, assign, and progress jobs through the full lifecycle, and clients can submit job requests that admins convert into scheduled jobs
**Depends on**: Phase 2, Phase 3
**Requirements**: SCHED-01, SCHED-02, CLNT-01, CLNT-04
**Success Criteria** (what must be TRUE):
  1. Admin can create a job with description, address, client, and assigned contractor; it appears in the job pipeline immediately (offline-first)
  2. A job moves through all five lifecycle stages (Quote, Scheduled, In Progress, Complete, Invoiced) and each transition is recorded with a timestamp
  3. Client CRM shows a client profile with full job history — every job associated with that client across all lifecycle stages
  4. A client can submit a job request with preferred dates; it appears in the admin review queue; admin can convert it to a scheduled job
  5. Both job creation flows (client-initiated and company-assigned) produce jobs in the same unified pipeline visible to admins
**Plans:** 9/9 plans complete

Plans:
- [x] 04-01-PLAN.md — Backend data foundation: Alembic migration 0008 with 5 tables (jobs, client_profiles, client_properties, job_requests, ratings), ORM models, Pydantic schemas
- [x] 04-02-PLAN.md — Job service layer: JobRepository + JobService with lifecycle state machine, role-based transitions, version-checked updates, full-text search
- [x] 04-03-PLAN.md — CRM and request services: CrmService (client profiles, saved properties), RequestService (submit, review, accept-to-job conversion), RatingService (mutual ratings with 30-day window)
- [x] 04-04-PLAN.md — REST API layer: Job router with all endpoints, Jinja2 web form for client requests, sync endpoint extension for jobs/profiles/requests
- [x] 04-05-PLAN.md — Mobile data layer: Drift tables (jobs, client_profiles, client_properties, job_requests), JobDao with sync queue dual-write, sync handlers, database migration v2->v3
- [x] 04-06-PLAN.md — Mobile job UI: Admin pipeline (kanban + list toggle), 4-step job creation wizard, tabbed job detail, contractor job list with quick-action transitions
- [x] 04-07-PLAN.md — Mobile client UI: Client CRM screen (searchable, expandable cards), client detail (profile, properties, history, ratings), request review queue, in-app request form
- [x] 04-08-PLAN.md — Backend tests and seed data: State machine unit tests, job lifecycle integration tests, CRM + request flow tests, demo seed data at every lifecycle stage
- [ ] 04-09-PLAN.md — GAP CLOSURE: Functional photo picker (image_picker) and GoRoute registration for in-app job request form

### Phase 5: Calendar and Dispatch UI
**Goal**: Company admins can visually schedule and reschedule contractor assignments using a drag-and-drop calendar that surfaces conflicts, travel time gaps, and overdue job warnings
**Depends on**: Phase 3, Phase 4
**Requirements**: SCHED-03, SCHED-08, SCHED-09
**Success Criteria** (what must be TRUE):
  1. Admin can drag a job onto a contractor's calendar slot; the UI prevents dropping on a conflicting slot and shows travel time buffer zones between consecutive jobs
  2. Color coding on the calendar distinguishes job lifecycle stages at a glance
  3. An overdue job (past scheduled completion with no status change) displays a warning indicator visible to the admin
  4. When a contractor marks a job delayed, the system requires a written reason and a new ETA before accepting the update
  5. Conflict indicators appear explicitly in the calendar view — they are never silent
**Plans:** 6 plans

Plans:
- [ ] 05-01-PLAN.md — Data foundation: Drift Bookings/JobSites tables (schema v4), BookingDao with sync queue dual-write, sync handlers, BookingEntity, backend delay endpoint, sync pull extension
- [ ] 05-02-PLAN.md — Calendar core: Day view with CustomPainter grid, paginated contractor lanes, color-coded booking cards, travel time hatched blocks, overdue severity indicators
- [ ] 05-03-PLAN.md — Drag-and-drop dispatch: Unscheduled jobs sidebar drawer, DragTarget grid, tap-to-schedule, cross-lane reassignment, edge resize, undo snackbar, multi-day wizard
- [ ] 05-04-PLAN.md — Overdue and delay: Expandable overdue panel, bottom nav badge, delay justification dialog, job detail Report Delay button, offline delay mutation
- [ ] 05-05-PLAN.md — Views and contractor: Week view (collapsed cards), month view (count badges), contractor personal schedule (list + calendar toggle), schedule settings screen, route registration
- [ ] 05-06-PLAN.md — Tests: Backend delay endpoint integration tests, overdue service unit tests, BookingDao Drift tests, calendar widget tests, delay dialog tests, E2E scheduling flow

### Phase 6: Field Workflow
**Goal**: Contractors can capture job notes, photos, GPS location, sketches, and time on-site from their mobile device — all while offline — and the data syncs when connectivity returns
**Depends on**: Phase 2, Phase 4
**Requirements**: FIELD-01, FIELD-02, FIELD-03, FIELD-04
**Success Criteria** (what must be TRUE):
  1. Contractor can add a timestamped text note to a job while offline; it syncs to the backend when connectivity is restored
  2. Contractor can take a photo from the job screen; it uploads to cloud storage and appears in the job record accessible to admins and the client
  3. Contractor can capture the job site address using GPS — the device location populates the address field without manual typing
  4. Contractor can open a drawing/handwriting pad, sketch a site layout or handwritten note, and save it to the job record
  5. Contractor can clock in and out per job; the time tracking record is stored locally and syncs with a precise duration
**Plans**: TBD

Plans:
- [ ] 06-01: Job notes — offline-capable note capture, Drift storage, sync integration, timestamping
- [ ] 06-02: Photo capture — Flutter camera integration, presigned S3 URL upload, photo gallery in job record
- [ ] 06-03: GPS address capture — device location to address field, permission handling, offline graceful degradation
- [ ] 06-04: Drawing and handwriting pad — canvas widget, save as image, attach to job record
- [ ] 06-05: Time tracking — clock in/out per job, duration calculation, Drift storage, sync
- [ ] 06-06: Field workflow tests — offline photo + note capture E2E, GPS permission handling, time tracking unit tests

### Phase 7: Client Portal and Notifications
**Goal**: Clients can view live job status, progress photos, and delay reasons through the client-facing portal, and receive push notifications at every significant job milestone
**Depends on**: Phase 4, Phase 6
**Requirements**: CLNT-02, CLNT-03, CLNT-05
**Success Criteria** (what must be TRUE):
  1. Client opening the app sees the current status of their job with a progress indicator and the latest ETA
  2. Client can scroll through a chronological photo timeline of their job's progress — photos added by contractors appear here
  3. When a contractor delays a job, the delay reason and updated ETA are visible to the client in the portal within one sync cycle
  4. Client receives a push notification when their job is scheduled, when work starts, and when the job is marked complete
  5. The client portal is gated by role — no contractor or admin data is accessible from the client view
**Plans**: TBD

Plans:
- [ ] 07-01: Client portal screens — job status view, progress percentage, ETA display, role gating
- [ ] 07-02: Photo timeline — chronological photo display, link to Field Workflow photo data
- [ ] 07-03: Delay visibility — delay reason and updated ETA surfaced in client portal from Phase 5 delay flow
- [ ] 07-04: Push notifications — FCM integration, notification dispatch on job milestones (scheduled, started, complete)
- [ ] 07-05: Client portal tests — role gating E2E, notification delivery test, delay reason display test

### Phase 8: Business Operations
**Goal**: Admins can create and send digital quotes to clients, receive approval, generate invoices from completed jobs, and view a reporting dashboard showing business performance
**Depends on**: Phase 4
**Requirements**: BIZ-01, BIZ-02, BIZ-03, BIZ-04
**Success Criteria** (what must be TRUE):
  1. Admin can create a quote with line items and send it to a client; the client can approve or decline from the portal
  2. A declined quote can be revised and resent; an approved quote transitions the job to Scheduled status
  3. Admin can generate a digital invoice from a completed job with one action; the invoice includes all job details and line items from the quote
  4. The reporting dashboard shows jobs by status, total revenue from invoiced jobs, and contractor utilization — all filterable by date range
  5. All quote, approval, and invoice actions are captured in the job history and visible in the client portal
**Plans**: TBD

Plans:
- [ ] 08-01: Digital quoting — quote data model, line item builder, quote creation UI for admins
- [ ] 08-02: Quote approval flow — send to client, client approve/decline UI in portal, status transitions
- [ ] 08-03: Digital invoicing — auto-generate from completed job, invoice data model, admin invoice view
- [ ] 08-04: Reporting dashboard — jobs by status chart, revenue summary, contractor utilization, date range filter
- [ ] 08-05: Business operations tests — E2E test for full quote-to-invoice flow, reporting data accuracy tests

## Progress

**Execution Order:**
Phases execute in numeric order: 1 -> 2 -> 3 -> 4 -> 5 -> 6 -> 7 -> 8

Note: Phase 3 (Scheduling Engine) depends only on Phase 1 and can begin in parallel with Phase 2 if capacity allows. All other phases depend on Phase 2 completing first.

| Phase | Plans Complete | Status | Completed |
|-------|----------------|--------|-----------|
| 1. Foundation | 5/5 | Complete | 2026-03-05 |
| 2. Offline Sync Engine | 7/7 | Complete   | 2026-03-06 |
| 3. Scheduling Engine | 2/4 | In Progress|  |
| 4. Job Lifecycle | 9/9 | Complete   | 2026-03-09 |
| 5. Calendar and Dispatch UI | 0/6 | Not started | - |
| 6. Field Workflow | 0/6 | Not started | - |
| 7. Client Portal and Notifications | 0/5 | Not started | - |
| 8. Business Operations | 0/5 | Not started | - |
