# Roadmap: ContractorHub

## Overview

ContractorHub is built in eight phases that front-load all architectural risk before any user-visible feature is written. Phases 1-3 establish the three non-negotiable foundations — multi-tenant data isolation, offline-first sync, and the scheduling engine — because all three are non-recoverable if retrofitted later. Phases 4-8 build on this foundation to deliver a complete contractor management workflow: job lifecycle, dispatch calendar, field tools, client transparency, and business operations. Every phase closes a coherent capability loop that can be verified independently.

## Phases

**Phase Numbering:**
- Integer phases (1, 2, 3): Planned milestone work
- Decimal phases (2.1, 2.2): Urgent insertions (marked with INSERTED)

Decimal phases appear between their surrounding integers in numeric order.

- [ ] **Phase 1: Foundation** - Flutter + FastAPI project skeletons with multi-tenant data isolation and role models
- [ ] **Phase 2: Offline Sync Engine** - Local SQLite with transactional outbox, background sync, and conflict resolution
- [ ] **Phase 3: Scheduling Engine** - Conflict detection, travel time awareness, multi-day jobs, and availability tracking
- [ ] **Phase 4: Job Lifecycle** - Job CRUD, lifecycle state machine, client CRM, and dual job creation flows
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
**Plans**: TBD

Plans:
- [ ] 01-01: Flutter project scaffold — Drift, Riverpod, go_router, get_it, directory structure
- [ ] 01-02: FastAPI project scaffold — Docker Compose, PostgreSQL, Alembic, tenant middleware, RLS policies
- [ ] 01-03: Multi-tenant data models — Company, User, Role entities with UUID PKs, version columns, RLS enforcement
- [ ] 01-04: Role-gated navigation — go_router guards for admin, contractor, and client routes
- [ ] 01-05: Tenant isolation tests — E2E tests proving cross-tenant data leakage is impossible

### Phase 2: Offline Sync Engine
**Goal**: The Flutter app stores all data locally first and reliably synchronizes to the backend when connectivity is available, with no data loss or duplication
**Depends on**: Phase 1
**Requirements**: INFRA-03, INFRA-04
**Success Criteria** (what must be TRUE):
  1. All reads in the Flutter app stream from local Drift database — no UI widget awaits an HTTP response directly
  2. User can create a record while offline; it appears immediately in the UI and syncs to the backend when connectivity is restored
  3. A record created offline and retried multiple times due to network failure appears exactly once in the backend (idempotency via client-generated UUID)
  4. The app displays a visible sync status indicator ("N items pending", "Syncing...", "All synced") at all times
  5. A sync conflict between local and server versions resolves predictably — server wins for schedules, field-merge for status updates — with no silent data loss
**Plans**: TBD

Plans:
- [ ] 02-01: Drift local DB and sync_queue table — outbox schema, version tracking, migration framework discipline
- [ ] 02-02: SyncEngine Flutter service — queue drain, exponential backoff, idempotency keys, connectivity detection
- [ ] 02-03: Backend delta sync endpoint — GET /api/v1/sync?cursor=<timestamp>, idempotent mutation endpoints with client_id deduplication
- [ ] 02-04: workmanager background sync — foreground-launch primary trigger, periodic fallback, OS kill recovery
- [ ] 02-05: Sync status UI indicator and offline/online state management
- [ ] 02-06: Conflict resolution tests — E2E tests for offline-create, offline-edit, concurrent edit, retry deduplication

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
**Plans**: TBD

Plans:
- [ ] 03-01: Availability data model — schedules table with EXCLUDE USING GIST constraint, btree_gist extension, contractor availability records
- [ ] 03-02: Scheduling engine module — get_available_slots(), conflict detection, isolated from routing
- [ ] 03-03: Multi-day job availability blocking — algorithm for spanning jobs with partial-day segments
- [ ] 03-04: Travel time integration — mapping API selection, cache layer (Redis, TTL), slot window subtraction
- [ ] 03-05: Conflict detection API endpoints — available slots, conflict check before booking
- [ ] 03-06: Scheduling engine tests — unit tests for slot computation, GIST constraint load test (concurrent booking)

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
**Plans**: TBD

Plans:
- [ ] 04-01: Job data model — Drift table, Freezed entity, lifecycle state machine, composite indexes
- [ ] 04-02: Job CRUD backend — FastAPI endpoints, lifecycle transition service, audit trail
- [ ] 04-03: Client CRM — client profile data model, job history view, client management screens
- [ ] 04-04: Client job request flow — request submission UI, admin review queue, conversion to scheduled job
- [ ] 04-05: Unified job pipeline — admin job list with both flow types, filtering by status
- [ ] 04-06: Job lifecycle tests — unit tests for state machine transitions, E2E test for both creation flows

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
**Plans**: TBD

Plans:
- [ ] 05-01: Flutter calendar library integration — drag-and-drop, time slots, Flutter package selection
- [ ] 05-02: Calendar scheduling UI — contractor lanes, color coding by status, conflict indicators, travel time buffer visualization
- [ ] 05-03: Team availability overview — who's free when, contractor utilization at a glance
- [ ] 05-04: Overdue job detection and warnings — backend detection logic, admin UI warning indicators
- [ ] 05-05: Forced delay justification — contractor delay flow (reason + new ETA required), state transition guard
- [ ] 05-06: Calendar and dispatch UI tests — E2E test for drag-and-drop scheduling, conflict prevention, delay justification flow

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
Phases execute in numeric order: 1 → 2 → 3 → 4 → 5 → 6 → 7 → 8

Note: Phase 3 (Scheduling Engine) depends only on Phase 1 and can begin in parallel with Phase 2 if capacity allows. All other phases depend on Phase 2 completing first.

| Phase | Plans Complete | Status | Completed |
|-------|----------------|--------|-----------|
| 1. Foundation | 0/5 | Not started | - |
| 2. Offline Sync Engine | 0/6 | Not started | - |
| 3. Scheduling Engine | 0/6 | Not started | - |
| 4. Job Lifecycle | 0/6 | Not started | - |
| 5. Calendar and Dispatch UI | 0/6 | Not started | - |
| 6. Field Workflow | 0/6 | Not started | - |
| 7. Client Portal and Notifications | 0/5 | Not started | - |
| 8. Business Operations | 0/5 | Not started | - |
