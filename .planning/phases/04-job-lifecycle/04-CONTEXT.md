# Phase 4: Job Lifecycle - Context

**Gathered:** 2026-03-08
**Status:** Ready for planning

<domain>
## Phase Boundary

Company admins create, assign, and progress jobs through the full lifecycle (Quote → Scheduled → In Progress → Complete → Invoiced). Clients submit job requests with preferred dates that admins review and convert into scheduled jobs. Both creation flows produce jobs in the same unified pipeline. Includes Client CRM with profiles, job history, saved properties, and mutual ratings.

Requirements: SCHED-01, SCHED-02, CLNT-01, CLNT-04

</domain>

<decisions>
## Implementation Decisions

### Job-Booking Relationship
- Job wraps Booking(s) — Job is the business entity (client, description, lifecycle state); it creates one or more Bookings for scheduled time blocks
- Job is the parent; Booking (from Phase 3) is how it occupies calendar time
- A Job at Quote stage may have no Bookings yet; Bookings are created when scheduling

### Lifecycle State Machine
- Six states: Quote, Scheduled, In Progress, Complete, Invoiced, Cancelled
- Flexible with guard rails — forward by default, backward moves allowed with required reason
- Backward transitions (e.g., Complete → In Progress for rework) free existing bookings and require re-scheduling
- Cancelled is a separate status (not soft-delete) — job stays visible in history with Cancelled badge; associated bookings are soft-deleted to free slots
- Invoiced stage is a status marker only — actual invoicing (amounts, line items, PDF) deferred to Phase 8 (BIZ-03)
- Company-assigned jobs can start at any stage (skip Quote if desired via "linear with skip" within flexible model)
- Audit trail: JSONB status_history array on job — [{status, timestamp, user_id, reason}]

### Role-Based Transition Matrix
- Admin: all transitions (forward and backward)
- Contractor: Scheduled → In Progress, In Progress → Complete (own jobs only)
- Client: view only (no status transitions)
- Each backward transition requires a reason

### Job Data Model (Full Business)
- Core: description, trade_type, status, status_history (JSONB)
- Client: client_id FK (User with client role)
- Contractor: contractor_id FK (optional, required at Scheduled+)
- Addresses: multiple addresses per job, each address = separate booking(s) with travel time between them — uses existing JobSite model from Phase 3
- Scheduling: estimated_duration, scheduled_completion_date
- Business: priority (low/medium/high/urgent), purchase_order_number, external_reference, tags/labels, notes
- Contractor assignable at any stage (optional until Scheduled)
- Soft-delete cascades to associated bookings (frees time slots)
- Attachments deferred to Phase 6 (FIELD-01)

### Offline-First Jobs
- Drift table + sync — jobs stored locally with full offline support, registered in Phase 2 sync engine
- Job creation offline is limited to Quote stage (no scheduling) — scheduling requires server for GIST conflict detection
- Lifecycle transitions that don't involve scheduling work offline (e.g., In Progress → Complete)

### Client CRM
- Client = User with client role (reuses existing User table + auth + sync infrastructure)
- One client per company — scoped via tenant isolation
- Separate client_profiles table (user_id FK) for CRM data — keeps User model lean
- CRM fields: phone, billing_address, tags/labels, admin notes, referral_source, preferred_contractor (single FK), preferred_contact_method
- Saved properties: client has a list of saved property addresses (separate table). When creating a job, admin picks from saved properties for speed
- Contractors can add notes to clients they work with — visible to all in the company

### Mutual Ratings
- 1-5 stars + optional text review
- Both directions: admin rates clients AND clients rate company/contractor
- Ratings allowed after Complete or Invoiced stage (one rating per job per direction)
- Can be updated until 30 days after completion
- Client profile shows average star rating

### Admin Client Management UI
- Searchable list with inline expandable cards — each row expands to show key info (recent jobs, contact) without navigating away
- Search + filter across client list

### Client Job Request Flow
- In-app form for existing clients + shareable web form link for new clients
- Web form: minimal HTML/CSS hosted alongside FastAPI (Jinja2 template). No login required — collects name, email, phone. Creates client User account on submit (or matches existing by email)
- Request fields (trade-aware): description, property address (from saved or new), preferred date range, urgency (normal/urgent), trade type needed, photos of the issue (1-5), budget range
- Photos stored on local filesystem + sync to backend (not Base64 in DB)
- No changes after submit — client cannot edit or cancel pending requests
- Dedicated admin review screen for incoming requests (separate from job pipeline)
- Admin can: Accept (auto-creates Job at Quote stage, pre-filled from request), Decline (with reason from preset list + optional message), or Request more info
- Client sees decline reason in their app
- Client request status visibility (beyond Pending/Accepted/Declined) deferred to Phase 7 Client Portal

### Job Creation & Assignment UX
- Multi-step wizard: Step 1 (Client + description) → Step 2 (Address + trade type) → Step 3 (Contractor + scheduling) → Step 4 (Review + submit)
- Smart contractor suggestions: top 3 based on availability, trade match, proximity to job site, client preference. Admin always confirms — no auto-assign
- Offline creation limited to Quote stage (no scheduling step)

### Job Pipeline Views
- Both kanban board AND filtered list views with toggle
- Kanban: columns for each lifecycle stage, job cards
- List: full filter set — status, contractor, client, date range, trade type, priority, address/area
- Default sort: newest first
- Multi-day job cards show progress bar (completed days / total days)
- Basic batch operations: multi-select for bulk forward status transitions (e.g., mark 5 jobs Complete)

### Contractor Views
- Admin + contractor views both built in Phase 4
- Contractor sees assigned jobs in a simple list, can tap for details, can transition Scheduled→In Progress and In Progress→Complete

### Job Detail Screen
- Tabbed layout: Details, Schedule, History
- Schedule tab: all booking dates/times, contractor, job site addresses
- History tab: lifecycle transition audit trail from status_history JSONB

### Search
- PostgreSQL full-text search on job description and notes
- Combined with filter chips (status, contractor, client, trade, priority, date range)
- Default sort: newest first

### Notifications
- All notifications deferred to Phase 7 (CLNT-02) — no in-app or push notifications in Phase 4

### Testing Strategy
- Unit tests for state machine transitions (all valid transitions, rejected invalid transitions, backward with reason, role permissions)
- Integration tests for API endpoints with real PostgreSQL (job CRUD, lifecycle transitions, client request flow, conversion)
- E2E for dual-flow pipeline: client request → admin accept → Quote → Scheduled → In Progress → Complete
- E2E for company-assigned flow: admin create → assign → schedule → complete
- Drift + sync tests for offline job creation and sync
- Flutter widget tests for wizard form, pipeline views, contractor job list

### Seed Data
- Full demo pipeline: jobs at every lifecycle stage (Quote through Invoiced + Cancelled)
- 3-5 clients with profiles, saved properties, and job history
- Client requests in various states (Pending, Accepted, Declined)
- Enough to demo the full pipeline and both creation flows

### Claude's Discretion
- Exact table schemas and column types for jobs, client_profiles, client_properties, job_requests, ratings tables
- Alembic migration structure (single vs multiple migrations)
- Drift table schema design for mobile
- Sync handler registration for new entity types
- Jinja2 web form template design
- File storage implementation details for request photos
- State machine implementation pattern (enum + transition table vs. method-based)
- Search index configuration
- Kanban board implementation approach

</decisions>

<specifics>
## Specific Ideas

- The dual-flow pipeline is a key differentiator — client requests and admin-created jobs must feel like one unified system, not two bolted-together features
- Smart contractor suggestions should leverage all Phase 3 engine capabilities (availability, proximity, trade match) plus client preference from CRM
- The wizard form should feel guided but fast — experienced admins should be able to create a job in under 30 seconds
- Kanban view should feel natural for dispatchers who think in terms of job stages
- Contractor view should be dead simple — just "my jobs today" with big tap targets for status transitions in the field

</specifics>

<code_context>
## Existing Code Insights

### Reusable Assets
- `TenantScopedModel` / `TenantScopedService` / `TenantScopedRepository` — base classes for all new job/CRM entities
- `SchedulingService` with `get_available_slots()`, `book_slot()`, `book_multiday_job()`, `suggest_dates()` — drives smart contractor suggestions and job scheduling
- `JobSite` model (Phase 3) — geocoded job locations, reusable for job addresses
- `Booking` model (Phase 3) — time blocks that Jobs will wrap
- Existing `User` model with roles — clients are Users with client role
- Drift `AppDatabase` with sync queue and registry pattern — register new entity types
- `SyncEngine` with handler registration pattern — add job, client_profile, job_request handlers
- `AppShell` with role-filtered navigation — add job pipeline to admin tabs
- `JobsScreen` placeholder — ready to be replaced with real implementation
- `ClientManagementScreen` placeholder — ready for CRM implementation
- `ClientPortalScreen` placeholder — exists but Phase 4 only handles request submission, not full portal

### Established Patterns
- Feature-first Flutter structure: `lib/features/<domain>/`
- Domain-driven backend: `app/features/<domain>/` with routes, services, models, schemas
- OOP architecture: inherit from base classes (BaseService, BaseRepository, CRUDRouter)
- Drift streams for reactive UI updates
- GoRouter + StatefulShellRoute for navigation
- UUID client-generated PKs for offline-first sync

### Integration Points
- Alembic migration 0008+ — new tables for jobs, client_profiles, client_properties, job_requests, ratings
- SchedulingService — job creation calls book_slot/book_multiday_job for scheduling
- SyncEngine — register handlers for jobs, client_profiles, job_requests
- GoRouter — add routes for job pipeline, job detail, job wizard, client management, request review queue
- AppShell — update navigation for new screens (admin sees pipeline + requests, contractor sees job list)

</code_context>

<deferred>
## Deferred Ideas

- Client portal with live job status and progress photos — Phase 7 (CLNT-03)
- Client notifications (job scheduled, started, completed, delayed) — Phase 7 (CLNT-02)
- GPS-based address capture — Phase 6 (FIELD-02)
- Job notes and photo capture by contractors — Phase 6 (FIELD-01)
- Digital quoting/estimates with line items — Phase 8 (BIZ-01)
- Digital invoicing from completed jobs — Phase 8 (BIZ-03)
- Drag-and-drop calendar scheduling — Phase 5 (SCHED-03)

</deferred>

---

*Phase: 04-job-lifecycle*
*Context gathered: 2026-03-08*
