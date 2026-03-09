# Phase 4: Job Lifecycle - Research

**Researched:** 2026-03-08
**Updated:** 2026-03-08 (re-run for gap closure planning + Validation Architecture)
**Domain:** Job state machine, CRM data model, offline-first sync, kanban UI, web form ingestion
**Confidence:** HIGH

---

<user_constraints>
## User Constraints (from CONTEXT.md)

### Locked Decisions

**Job-Booking Relationship**
- Job wraps Booking(s) — Job is the business entity (client, description, lifecycle state); it creates one or more Bookings for scheduled time blocks
- Job is the parent; Booking (Phase 3) is how it occupies calendar time
- A Job at Quote stage may have no Bookings yet; Bookings are created when scheduling

**Lifecycle State Machine**
- Six states: Quote, Scheduled, In Progress, Complete, Invoiced, Cancelled
- Flexible with guard rails — forward by default, backward moves allowed with required reason
- Backward transitions (e.g., Complete → In Progress for rework) free existing bookings and require re-scheduling
- Cancelled is a separate status (not soft-delete) — job stays visible in history with Cancelled badge; associated bookings are soft-deleted to free slots
- Invoiced stage is a status marker only — actual invoicing deferred to Phase 8 (BIZ-03)
- Company-assigned jobs can start at any stage (skip Quote if desired)
- Audit trail: JSONB status_history array on job — [{status, timestamp, user_id, reason}]

**Role-Based Transition Matrix**
- Admin: all transitions (forward and backward)
- Contractor: Scheduled → In Progress, In Progress → Complete (own jobs only)
- Client: view only (no status transitions)
- Each backward transition requires a reason

**Job Data Model**
- Core: description, trade_type, status, status_history (JSONB)
- Client: client_id FK (User with client role)
- Contractor: contractor_id FK (optional, required at Scheduled+)
- Addresses: multiple addresses per job via existing JobSite model from Phase 3
- Business: priority (low/medium/high/urgent), purchase_order_number, external_reference, tags/labels, notes
- Attachments deferred to Phase 6

**Offline-First Jobs**
- Job creation offline limited to Quote stage (no scheduling)
- Lifecycle transitions that don't involve scheduling work offline
- Scheduling requires server for GIST conflict detection

**Client CRM**
- Client = User with client role (reuses existing User table)
- Separate client_profiles table (user_id FK) for CRM data
- CRM fields: phone, billing_address, tags/labels, admin notes, referral_source, preferred_contractor (FK), preferred_contact_method
- Saved properties: separate table of saved property addresses per client
- Contractors can add notes to clients they work with

**Mutual Ratings**
- 1-5 stars + optional text review, both directions
- Allowed after Complete or Invoiced stage, one rating per job per direction
- Updatable until 30 days after completion

**Admin Client Management UI**
- Searchable list with inline expandable cards

**Client Job Request Flow**
- In-app form for existing clients + shareable web form link for new clients
- Web form: minimal Jinja2 template hosted alongside FastAPI, no login required
- Creates client User account on submit (or matches existing by email)
- Request fields: description, property address, preferred date range, urgency, trade type, photos (1-5), budget range
- Photos stored on local filesystem, sync to backend (not Base64 in DB)
- No edits after submit
- Dedicated admin review screen; admin can Accept, Decline (with reason), or Request more info
- Client sees decline reason in app

**Job Creation UX**
- Multi-step wizard: Client + description → Address + trade → Contractor + scheduling → Review + submit
- Smart contractor suggestions: top 3 based on availability, trade match, proximity, client preference
- Offline creation limited to Quote stage

**Job Pipeline Views**
- Both kanban board AND filtered list views with toggle
- Kanban: columns for each lifecycle stage
- List: full filter set (status, contractor, client, date range, trade type, priority, address/area)
- Default sort: newest first
- Multi-day job cards show progress bar
- Basic batch operations: multi-select for bulk forward status transitions

**Contractor Views**
- Admin + contractor views built in Phase 4
- Contractor sees assigned jobs list, can tap for details, can transition Scheduled→In Progress and In Progress→Complete

**Job Detail Screen**
- Tabbed layout: Details, Schedule, History
- History tab: lifecycle transition audit trail from status_history JSONB

**Search**
- PostgreSQL full-text search on job description and notes
- Combined with filter chips

**Notifications**
- All notifications deferred to Phase 7 (CLNT-02)

**Testing Strategy**
- Unit tests for state machine transitions
- Integration tests for API endpoints
- E2E for dual-flow pipeline
- Drift + sync tests for offline job creation
- Flutter widget tests

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

### Deferred Ideas (OUT OF SCOPE)
- Client portal with live job status and progress photos — Phase 7 (CLNT-03)
- Client notifications — Phase 7 (CLNT-02)
- GPS-based address capture — Phase 6 (FIELD-02)
- Job notes and photo capture by contractors — Phase 6 (FIELD-01)
- Digital quoting/estimates with line items — Phase 8 (BIZ-01)
- Digital invoicing from completed jobs — Phase 8 (BIZ-03)
- Drag-and-drop calendar scheduling — Phase 5 (SCHED-03)
</user_constraints>

---

<phase_requirements>
## Phase Requirements

| ID | Description | Research Support |
|----|-------------|-----------------|
| SCHED-01 | Job creation with details (description, address, client, assigned contractor) | Multi-step wizard + Job model + Booking integration + offline-first Drift table |
| SCHED-02 | Job lifecycle stages (Quote → Scheduled → In Progress → Complete → Invoiced) | State machine service + role-based transition matrix + JSONB audit trail |
| CLNT-01 | Customer/client CRM with profiles and job history | client_profiles table + saved properties + job history query via client_id FK |
| CLNT-04 | Client-initiated job requests with preferred dates | job_requests table + Jinja2 web form + admin review queue + Accept/Decline flow |
</phase_requirements>

---

## Summary

Phase 4 builds the core business domain for ContractorHub: the Job entity and its full lifecycle. The phase is large — it touches the backend (four new tables, a state machine service, search, a Jinja2 web form), the mobile app (Drift tables, sync handlers, a four-step wizard, kanban/list pipeline views, contractor job list, client CRM, admin request review), and tests for all of the above.

The codebase is already in excellent shape for Phase 4. All architectural scaffolding exists: `TenantScopedModel`, `TenantScopedService`, `TenantScopedRepository`, `SyncHandler`, `SyncRegistry`, `AppDatabase`, and `GoRouter` with role-filtered navigation. The `Booking` model already has a `job_id` column (currently an unlinked UUID). Migration 0007 even notes "FK will be added in Phase 4 migration." The Phase 3 `SchedulingService` with `book_slot()` and `book_multiday_job()` is ready to be called by the new job scheduling path.

The biggest technical challenges in this phase are: (1) the state machine transition guard logic with role enforcement; (2) the unified sync approach for Jobs (some transitions are online-required, some work offline); (3) the kanban board UI widget; and (4) the photo file storage for job requests. Each of these has a clear, well-established solution in the existing stack.

**Primary recommendation:** Build the backend Job CRUD + state machine first (plan 04-02), then Drift + sync (plan 04-01), then layer the UI features (plans 04-03 through 04-05), finishing with tests (plan 04-06). The FK addition to `bookings.job_id` must be migration 0008.

**Gap closure note (2026-03-08):** Phase 4 was executed and verified. Two gaps remain in the client-facing mobile path: (1) `image_picker` not added to pubspec.yaml and `_pickPhoto()` is a stub, and (2) `JobRequestFormScreen` has no GoRoute registration. All backend functionality, admin UI, and tests are complete. Gap closure is confined to mobile Flutter changes only.

---

## Standard Stack

### Core (all already in use — no new packages needed)

| Component | Version | Purpose | Confirmed By |
|-----------|---------|---------|--------------|
| FastAPI | 0.115.12 | HTTP API, Jinja2 web form hosting | requirements.txt |
| SQLAlchemy async | 2.0.38 | ORM for all new tables | requirements.txt |
| PostgreSQL JSONB | 13 | status_history audit array, tags | migration 0007 |
| PostgreSQL FTS | 13 | Full-text search on description/notes | Built-in, no extension needed |
| Alembic | 1.14.1 | Migration 0008 for new tables | requirements.txt |
| Jinja2 | bundled with FastAPI[standard] | Web form template | fastapi[standard] includes jinja2 |
| Drift | 2.32.0 | Local SQLite tables for Jobs, ClientProfiles, JobRequests | pubspec.yaml |
| Freezed | 3.2.5 / annotation 3.1.0 | Immutable domain entities | pubspec.yaml |
| Riverpod | 3.2.1 | State management for all new providers | pubspec.yaml |
| GoRouter | 17.1.0 | New routes: job detail, wizard, client CRM, request queue | pubspec.yaml |

### Supporting — New for Phase 4 (backend)

| Library | Purpose | Notes |
|---------|---------|-------|
| `aiofiles` | Async file write for request photos | Add to requirements.txt; standard for FastAPI file uploads |
| `python-multipart` | FastAPI form + file upload parsing | Already bundled in `fastapi[standard]` |

### Supporting — New for Phase 4 (mobile)

| Library | Version | Purpose | Notes |
|---------|---------|---------|-------|
| `image_picker` | ^1.2.1 | Select 1-5 photos for job request form | Add to pubspec.yaml; published by flutter.dev; no Android config required beyond `retrieveLostData` |

**No kanban library needed.** Implement kanban board with standard Flutter `PageView` + `ListView` + `DragTarget`/`LongPressDraggable` or a simple horizontal `ScrollView` of column widgets. The simplest correct approach uses a `Row` of `ListView` columns in a `SingleChildScrollView`.

### Alternatives Considered

| Standard Choice | Alternative | Why Standard Wins |
|-----------------|-------------|-------------------|
| JSONB status_history array | Separate status_history table | JSONB is simpler, no join needed for audit display, history is append-only and never queried individually — fits JSONB perfectly |
| Enum + transition dict for state machine | Full state machine library | The transition matrix is small (6 states × 3 roles) — a plain Python dict with guard functions is idiomatic, no library needed |
| Flutter PageView kanban | `flutter_kanban`/`trello_flutter` | Third-party kanban libraries have poor null-safety records; PageView approach is fully controlled |
| aiofiles for photo storage | S3/object storage | Local filesystem is appropriate for v1; Phase 6 or later can migrate to object storage |

---

## Architecture Patterns

### Recommended Project Structure (Backend)

```
app/features/jobs/
├── __init__.py
├── models.py          # Job, ClientProfile, ClientProperty, JobRequest, Rating
├── schemas.py         # JobCreate, JobResponse, JobTransitionRequest, etc.
├── repository.py      # JobRepository(TenantScopedRepository[Job])
├── service.py         # JobService(TenantScopedService[Job]) — state machine here
└── router.py          # APIRouter (plain, not CRUDRouter — lifecycle ops are non-CRUD)
```

The job request web form lives at `app/features/jobs/templates/job_request.html`.

### Recommended Project Structure (Mobile)

```
lib/features/jobs/
├── data/
│   ├── jobs_table.dart             # Drift table definition
│   ├── client_profiles_table.dart  # Drift table definition
│   ├── job_requests_table.dart     # Drift table definition
│   ├── job_dao.dart                # Drift DAO — CRUD + sync queue enqueue
│   └── job_sync_handler.dart       # SyncHandler for push/applyPulled
├── domain/
│   ├── job_entity.dart             # @freezed JobEntity
│   ├── job_status.dart             # JobStatus enum (6 values)
│   └── job_request_entity.dart     # @freezed JobRequestEntity
└── presentation/
    ├── providers/
    │   ├── job_providers.dart       # @riverpod JobNotifier (AsyncNotifier)
    │   └── job_providers.g.dart
    └── screens/
        ├── jobs_pipeline_screen.dart    # Replaces jobs_screen.dart placeholder
        ├── job_detail_screen.dart       # Tabbed: Details / Schedule / History
        ├── job_wizard_screen.dart       # 4-step wizard
        ├── contractor_jobs_screen.dart  # Contractor's job list
        ├── client_crm_screen.dart       # Replaces client_management_screen.dart
        └── request_review_screen.dart   # Admin request review queue

lib/features/client/
└── presentation/
    └── screens/
        └── job_request_form_screen.dart # In-app client request form
```

### Pattern 1: State Machine as Transition Table

**What:** A Python dict maps `(current_status, role) -> list[allowed_next_statuses]`. The service method validates the requested transition before applying it.

**When to use:** All job status transitions on the backend.

```python
# Source: project pattern — confirmed via CLAUDE.md OOP rules
from enum import StrEnum

class JobStatus(StrEnum):
    QUOTE = "quote"
    SCHEDULED = "scheduled"
    IN_PROGRESS = "in_progress"
    COMPLETE = "complete"
    INVOICED = "invoiced"
    CANCELLED = "cancelled"

# (current_status, role) -> frozenset of allowed next statuses
ALLOWED_TRANSITIONS: dict[tuple[str, str], frozenset[str]] = {
    ("quote",       "admin"):      frozenset({"scheduled", "cancelled"}),
    ("quote",       "contractor"): frozenset(),
    ("scheduled",   "admin"):      frozenset({"quote", "in_progress", "cancelled"}),
    ("scheduled",   "contractor"): frozenset({"in_progress"}),
    ("in_progress", "admin"):      frozenset({"scheduled", "complete", "cancelled"}),
    ("in_progress", "contractor"): frozenset({"complete"}),
    ("complete",    "admin"):      frozenset({"in_progress", "invoiced", "cancelled"}),
    ("complete",    "contractor"): frozenset(),
    ("invoiced",    "admin"):      frozenset({"complete"}),
    ("invoiced",    "contractor"): frozenset(),
    ("cancelled",   "admin"):      frozenset(),  # terminal — no transitions out
    ("cancelled",   "contractor"): frozenset(),
}

BACKWARD_TRANSITIONS = {
    ("scheduled",   "quote"),
    ("in_progress", "scheduled"),
    ("complete",    "in_progress"),
    ("invoiced",    "complete"),
}

def is_backward(current: str, next_status: str) -> bool:
    return (current, next_status) in BACKWARD_TRANSITIONS
```

**Rule:** Backward transitions always require a `reason` string (non-empty). The service raises `InvalidTransitionError` if the transition is not in the allowed set.

### Pattern 2: JSONB status_history Append

**What:** The `status_history` JSONB column holds a PostgreSQL array of transition records. The service appends entries; the frontend renders them in the History tab.

**When to use:** Every status transition, including the initial status assignment on creation.

```python
# Source: SQLAlchemy 2.0 + PostgreSQL JSONB — project pattern
from sqlalchemy.dialects.postgresql import JSONB
from sqlalchemy import func

class Job(TenantScopedModel):
    __tablename__ = "jobs"
    ...
    status: Mapped[str] = mapped_column(String, nullable=False, default="quote")
    status_history: Mapped[list] = mapped_column(
        JSONB, nullable=False, server_default="'[]'::jsonb"
    )

# Service — append to JSONB array using PostgreSQL's jsonb_insert or || operator
# SQLAlchemy approach: fetch, append in Python, write back
# Reason: SQLAlchemy 2.0 JSONB mutation tracking handles this correctly for
# single-update operations; for high-concurrency append, use raw SQL:
# UPDATE jobs SET status_history = status_history || %s::jsonb WHERE id = %s
```

**Entry format:**
```json
{"status": "in_progress", "timestamp": "2026-03-08T14:00:00Z", "user_id": "uuid", "reason": null}
```

### Pattern 3: Drift Table with JSONB-equivalent (TEXT for status_history)

**What:** Drift/SQLite does not support JSONB. Store `status_history` as a JSON-encoded TEXT column. Decode in the DAO's row mapper.

**When to use:** The Drift `Jobs` table definition.

```dart
// Source: established project pattern (see sync_queue.dart uses TEXT payload)
class Jobs extends Table {
  TextColumn get id => text().clientDefault(() => const Uuid().v4())();
  TextColumn get companyId => text().references(Companies, #id)();
  TextColumn get clientId => text().nullable()();
  TextColumn get contractorId => text().nullable()();
  TextColumn get description => text()();
  TextColumn get tradeType => text()();
  TextColumn get status => text().withDefault(const Constant('quote'))();
  // JSON-encoded list of {status, timestamp, user_id, reason}
  TextColumn get statusHistory => text().withDefault(const Constant('[]'))();
  TextColumn get priority => text().withDefault(const Constant('medium'))();
  TextColumn get purchaseOrderNumber => text().nullable()();
  TextColumn get externalReference => text().nullable()();
  TextColumn get tags => text().withDefault(const Constant('[]'))(); // JSON array
  TextColumn get notes => text().nullable()();
  TextColumn get estimatedDuration => text().nullable()(); // ISO 8601 duration or minutes
  DateTimeColumn get scheduledCompletionDate => dateTime().nullable()();
  IntColumn get version => integer().withDefault(const Constant(1))();
  DateTimeColumn get createdAt => dateTime()();
  DateTimeColumn get updatedAt => dateTime()();
  DateTimeColumn get deletedAt => dateTime().nullable()();

  @override
  Set<Column> get primaryKey => {id};
}
```

### Pattern 4: SyncHandler Registration for Jobs

**What:** Create `JobSyncHandler`, `ClientProfileSyncHandler`, `JobRequestSyncHandler` implementing the existing `SyncHandler` abstract class. Register all three in `setupServiceLocator`.

**When to use:** Every new entity that participates in offline sync.

```dart
// Source: existing UserSyncHandler pattern
class JobSyncHandler extends SyncHandler {
  @override
  String get entityType => 'job';

  @override
  Future<void> push(SyncQueueData item) async {
    final payload = jsonDecode(item.payload) as Map<String, dynamic>;
    await _dioClient.pushWithIdempotency('/jobs', payload, item.id);
  }

  @override
  Future<void> applyPulled(Map<String, dynamic> data) async {
    // Build JobsCompanion from server response fields, upsert
    await _db.into(_db.jobs).insertOnConflictUpdate(companion);
  }
}
```

### Pattern 5: Sync Endpoint Extension

**What:** Extend the existing `GET /api/v1/sync` endpoint to include jobs, client_profiles, and job_requests in the delta response. The `SyncResponse` schema gains new list fields.

```python
# Source: app/features/sync/router.py — existing delta sync pattern
class SyncResponse(BaseModel):
    companies: list[CompanyResponse]
    users: list[UserResponse]
    user_roles: list[UserRoleResponse]
    jobs: list[JobResponse] = []           # NEW
    client_profiles: list[ClientProfileResponse] = []  # NEW
    job_requests: list[JobRequestResponse] = []        # NEW
    server_timestamp: str
```

### Pattern 6: Jinja2 Web Form for Client Requests

**What:** Mount a Jinja2 template at `GET /jobs/request` (unauthenticated). POST handler creates `JobRequest` + optional `User` (matching or new client by email). No JWT required.

```python
# Source: FastAPI docs — Jinja2Templates + StaticFiles
from fastapi import Request
from fastapi.responses import HTMLResponse
from fastapi.templating import Jinja2Templates

templates = Jinja2Templates(directory="app/features/jobs/templates")

@router.get("/request", response_class=HTMLResponse)
async def job_request_form(request: Request):
    return templates.TemplateResponse("job_request.html", {"request": request})

@router.post("/request", status_code=201)
async def submit_job_request(
    name: str = Form(...),
    email: str = Form(...),
    phone: str = Form(...),
    description: str = Form(...),
    photos: list[UploadFile] = File(default=[]),
    ...
):
    # Find or create client User by email, create JobRequest
    ...
```

**Photo storage:** Save to `uploads/job_requests/{request_id}/` on the server filesystem. Return relative paths stored in `photos` JSONB on `job_requests`.

### Pattern 7: Kanban Board (Flutter)

**What:** A horizontally scrollable `Row` of `SizedBox`-width columns, each containing a `ListView` of job cards for that status. Status transitions via `LongPressDraggable` + `DragTarget` for drag-and-drop (batch) OR a tap-to-advance action button (primary for Phase 4).

**For Phase 4:** Use tap-to-advance as the primary interaction (long-press drag is complex and deferred feel; batch operations via multi-select checkboxes are sufficient). The kanban board renders columns; tapping a job card navigates to job detail.

```dart
// Kanban structure
SingleChildScrollView(
  scrollDirection: Axis.horizontal,
  child: Row(
    children: JobStatus.values.map((status) =>
      SizedBox(
        width: 280,
        child: Column(
          children: [
            // Status header chip
            // ListView of job cards for this status
          ],
        ),
      )
    ).toList(),
  ),
)
```

### Anti-Patterns to Avoid

- **Querying inside transition handlers:** Never load jobs' bookings in a loop to free slots on Cancelled. Use `UPDATE bookings SET deleted_at = now() WHERE job_id = $1 AND deleted_at IS NULL` — a single bulk SQL update.
- **Storing status as integer ordinal:** Use string enums (Python `StrEnum`, Dart `enum` with `.name`). Ordinal comparison breaks when states are reordered or new states are added.
- **Blocking the event loop on file writes:** Always use `aiofiles.open()` for photo uploads in FastAPI. Synchronous `open()` blocks the uvicorn event loop under concurrent upload load.
- **Lazy-loading Job relationships:** `Job` model MUST define `relationship(lazy="raise")` for bookings, client, and contractor. Any accidental lazy load fails loudly rather than silently causing N+1.
- **Using `db.commit()` in service functions:** Forbidden by CLAUDE.md. The `get_db` dependency handles commit/rollback.
- **Running Alembic autogenerate for the bookings FK:** The bookings table has a GIST constraint — autogenerate is unreliable. Use `op.execute(text(...))` for all Phase 4 migration DDL, consistent with migration 0007.

---

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| Conflict detection when scheduling jobs | Custom overlap query | `SchedulingService.book_slot()` / `book_multiday_job()` | Already implements SELECT FOR UPDATE + GIST constraint; re-implementing will miss edge cases |
| Smart contractor suggestions | Custom availability + distance logic | `SchedulingService.get_available_slots()` with `job_site_id` | Already sorts by proximity; Phase 3 already built this |
| Token refresh / auth on mobile | Custom Dio interceptor chain | Existing `DioClient` with `AuthInterceptor` | Already handles 401 → refresh → retry with `QueuedInterceptor` |
| Offline queue management | Custom outbox logic | Existing `SyncQueueDao` + `SyncEngine.drainQueue()` | Already handles retry, parking on 4xx, deduplication |
| Full-text search | Custom LIKE queries | PostgreSQL `to_tsvector` / `to_tsquery` with GIN index | LIKE `%term%` cannot use an index; tsvector is built-in, no extension needed |
| Multi-tenant data isolation | Custom WHERE clauses | RLS policies + `TenantScopedModel` | RLS is enforced at DB level — adding manual WHERE is redundant and error-prone |
| UUID primary keys on mobile | Sequential integer IDs | `Uuid().v4()` via `clientDefault` | Already established project pattern; integer IDs cause sync conflicts |

**Key insight:** The Phase 3 engine already handles the hardest scheduling problems. Phase 4's job service must call into SchedulingService, not duplicate its logic.

---

## Common Pitfalls

### Pitfall 1: Forgetting the bookings.job_id FK in Migration 0008
**What goes wrong:** The `job_id` column on `bookings` was created in migration 0007 as a plain `UUID NOT NULL` with NO foreign key constraint. The migration docstring explicitly notes "FK will be added in Phase 4 migration."
**Why it happens:** Developer reads the Booking model which has `job_id: Mapped[uuid.UUID]` and assumes the FK exists.
**How to avoid:** Migration 0008 MUST include `ALTER TABLE bookings ADD CONSTRAINT bookings_job_id_fkey FOREIGN KEY (job_id) REFERENCES jobs(id)`. Use `op.execute(text(...))` not autogenerate.
**Warning signs:** If you can insert a Booking with a non-existent `job_id`, the FK is missing.

### Pitfall 2: Offline Transition Conflicts for Status Updates
**What goes wrong:** A contractor transitions a job to "In Progress" offline; the admin concurrently transitions it to "Cancelled" online. The sync engine applies the offline mutation, reinstating In Progress after Cancelled.
**Why it happens:** The sync engine uses `on_conflict_do_nothing(index_elements=[id])` for creates (idempotent), but status updates need last-write-wins with version checks.
**How to avoid:** Job status transitions sent to the server MUST include the current `version` number. The backend rejects the transition with 409 if the job's current version doesn't match. The mobile re-syncs and presents a conflict to the user.
**Implementation:** The `PATCH /api/v1/jobs/{id}/transition` endpoint checks `version` before applying. The Drift DAO increments `version` locally on transition; the sync engine includes `version` in the payload.

### Pitfall 3: JSONB status_history Mutation Tracking
**What goes wrong:** SQLAlchemy's JSONB mutation tracking does not automatically detect in-place list appends (e.g., `job.status_history.append(entry)`). The session sees no change and doesn't flush the update.
**Why it happens:** JSONB columns are treated as mutable but SQLAlchemy's default change detection misses list mutations.
**How to avoid:** Use the `MutableList.as_mutable(JSONB)` pattern, or (simpler) replace the entire list on each update: `job.status_history = [*job.status_history, new_entry]`. The simpler approach is safe because status_history is never concurrently written by two processes for the same job.
**Warning signs:** Status history appears not to persist across requests despite no error.

### Pitfall 4: Cancellation Must Soft-Delete Bookings in One Query
**What goes wrong:** Cancelling a job soft-deletes associated bookings by looping and calling `repository.soft_delete(booking_id)` for each — classic N+1 write pattern.
**How to avoid:** Use a single bulk UPDATE:
```python
from sqlalchemy import update
await db.execute(
    update(Booking)
    .where(Booking.job_id == job.id, Booking.deleted_at.is_(None))
    .values(deleted_at=datetime.now(UTC))
)
```

### Pitfall 5: AppDatabase schemaVersion Must Be Bumped
**What goes wrong:** Adding new Drift tables without bumping `AppDatabase.schemaVersion` causes Drift to skip the `onUpgrade` migration path. Existing users' apps crash with "table not found."
**How to avoid:** Every PR that adds a Drift table MUST bump `schemaVersion` (e.g., 2 → 3) and add a corresponding `if (from < 3) { await m.createTable(...); }` branch in `onUpgrade`.
**Warning signs:** New tables work on fresh install but crash on update from a previous version.

### Pitfall 6: Jinja2 Templates Path Resolution in Production
**What goes wrong:** `Jinja2Templates(directory="app/features/jobs/templates")` uses a relative path that resolves differently depending on the working directory where uvicorn is started.
**How to avoid:** Use `Path(__file__).parent / "templates"` for an absolute path relative to the module file:
```python
from pathlib import Path
templates = Jinja2Templates(directory=str(Path(__file__).parent / "templates"))
```

### Pitfall 7: Photo Upload Size and Content Type Validation
**What goes wrong:** Accepting arbitrary file uploads without validation allows clients to upload non-image files or huge files that fill the server disk.
**How to avoid:**
- Validate `content_type in {"image/jpeg", "image/png", "image/heic"}` before writing.
- Enforce max 10MB per file at the FastAPI level using `UploadFile.size` or reading in chunks.
- Enforce max 5 files via `len(photos) <= 5` check.

### Pitfall 8: clean_tables TRUNCATE in Tests Must Include New Tables
**What goes wrong:** The existing `conftest.py` `clean_tables` fixture truncates all tables explicitly. Adding new tables without updating `conftest.py` causes cross-test data pollution from job/client data.
**How to avoid:** Update the `TRUNCATE TABLE` statement in `clean_tables` to include all new Phase 4 tables in dependency order (children before parents): `ratings, job_requests, jobs, client_properties, client_profiles`, then existing tables.

---

## Code Examples

### Backend: Job model (complete)

```python
# Source: project conventions — TenantScopedModel + lazy="raise" relationships
import uuid
from sqlalchemy import ARRAY, CheckConstraint, ForeignKey, String, Text
from sqlalchemy.dialects.postgresql import JSONB, UUID
from sqlalchemy.orm import Mapped, mapped_column, relationship
from app.core.base_models import TenantScopedModel

class Job(TenantScopedModel):
    __tablename__ = "jobs"

    description: Mapped[str] = mapped_column(Text, nullable=False)
    trade_type: Mapped[str] = mapped_column(String, nullable=False)
    status: Mapped[str] = mapped_column(
        String, nullable=False, default="quote"
    )
    status_history: Mapped[list] = mapped_column(
        JSONB, nullable=False, server_default="'[]'::jsonb"
    )
    priority: Mapped[str] = mapped_column(
        String, nullable=False, server_default="'medium'"
    )
    client_id: Mapped[uuid.UUID | None] = mapped_column(
        UUID(as_uuid=True), ForeignKey("users.id"), nullable=True
    )
    contractor_id: Mapped[uuid.UUID | None] = mapped_column(
        UUID(as_uuid=True), ForeignKey("users.id"), nullable=True
    )
    purchase_order_number: Mapped[str | None] = mapped_column(String, nullable=True)
    external_reference: Mapped[str | None] = mapped_column(String, nullable=True)
    tags: Mapped[list] = mapped_column(JSONB, nullable=False, server_default="'[]'::jsonb")
    notes: Mapped[str | None] = mapped_column(Text, nullable=True)
    estimated_duration_minutes: Mapped[int | None] = mapped_column(nullable=True)
    scheduled_completion_date: Mapped[str | None] = mapped_column(String, nullable=True)

    # tsvector column for full-text search (updated by trigger in migration)
    search_vector: Mapped[str | None] = mapped_column(nullable=True)

    __table_args__ = (
        CheckConstraint(
            "status IN ('quote','scheduled','in_progress','complete','invoiced','cancelled')",
            name="valid_job_status",
        ),
        CheckConstraint(
            "priority IN ('low','medium','high','urgent')",
            name="valid_job_priority",
        ),
    )

    # Relationships — lazy="raise" to surface accidental lazy loads
    client: Mapped["User"] = relationship(
        "User", foreign_keys=[client_id], lazy="raise"
    )
    contractor: Mapped["User"] = relationship(
        "User", foreign_keys=[contractor_id], lazy="raise"
    )
    bookings: Mapped[list["Booking"]] = relationship(
        "Booking",
        primaryjoin="Job.id == foreign(Booking.job_id)",
        lazy="raise",
    )
```

### Backend: Migration 0008 structure (key DDL)

```python
# Source: migration 0007 pattern — all DDL via op.execute(text(...))
def upgrade() -> None:
    # 1. jobs table
    op.execute(text("""
        CREATE TABLE jobs (
            id                      UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
            company_id              UUID        NOT NULL REFERENCES companies(id),
            description             TEXT        NOT NULL,
            trade_type              TEXT        NOT NULL,
            status                  TEXT        NOT NULL DEFAULT 'quote'
                CHECK (status IN ('quote','scheduled','in_progress','complete','invoiced','cancelled')),
            status_history          JSONB       NOT NULL DEFAULT '[]'::jsonb,
            priority                TEXT        NOT NULL DEFAULT 'medium'
                CHECK (priority IN ('low','medium','high','urgent')),
            client_id               UUID        REFERENCES users(id),
            contractor_id           UUID        REFERENCES users(id),
            purchase_order_number   TEXT,
            external_reference      TEXT,
            tags                    JSONB       NOT NULL DEFAULT '[]'::jsonb,
            notes                   TEXT,
            estimated_duration_minutes  INTEGER,
            scheduled_completion_date   DATE,
            search_vector           TSVECTOR,
            version                 INTEGER     NOT NULL DEFAULT 1,
            created_at              TIMESTAMPTZ NOT NULL DEFAULT now(),
            updated_at              TIMESTAMPTZ NOT NULL DEFAULT now(),
            deleted_at              TIMESTAMPTZ
        )
    """))
    op.execute(text("ALTER TABLE jobs ENABLE ROW LEVEL SECURITY"))
    op.execute(text("ALTER TABLE jobs FORCE ROW LEVEL SECURITY"))
    op.execute(text("""
        CREATE POLICY tenant_isolation ON jobs
        USING (company_id = current_setting('app.current_company_id', true)::uuid)
    """))
    op.execute(text("""
        CREATE TRIGGER set_jobs_updated_at
        BEFORE UPDATE ON jobs
        FOR EACH ROW EXECUTE FUNCTION set_updated_at()
    """))
    # Full-text search index
    op.execute(text("""
        CREATE INDEX idx_jobs_search ON jobs USING GIN (search_vector)
    """))
    op.execute(text("""
        CREATE INDEX idx_jobs_status ON jobs (company_id, status) WHERE deleted_at IS NULL
    """))
    op.execute(text("""
        CREATE INDEX idx_jobs_client_id ON jobs (client_id) WHERE deleted_at IS NULL
    """))
    op.execute(text("""
        CREATE INDEX idx_jobs_contractor_id ON jobs (contractor_id) WHERE deleted_at IS NULL
    """))
    # Full-text search update trigger
    op.execute(text("""
        CREATE FUNCTION update_jobs_search_vector() RETURNS trigger AS $$
        BEGIN
          NEW.search_vector := to_tsvector('english',
            coalesce(NEW.description, '') || ' ' ||
            coalesce(NEW.notes, ''));
          RETURN NEW;
        END;
        $$ LANGUAGE plpgsql;

        CREATE TRIGGER jobs_search_vector_update
        BEFORE INSERT OR UPDATE OF description, notes ON jobs
        FOR EACH ROW EXECUTE FUNCTION update_jobs_search_vector();
    """))

    # 2. Add FK from bookings.job_id to jobs.id (missing from migration 0007)
    op.execute(text("""
        ALTER TABLE bookings
        ADD CONSTRAINT bookings_job_id_fkey
        FOREIGN KEY (job_id) REFERENCES jobs(id)
    """))

    # 3. client_profiles table
    op.execute(text("""
        CREATE TABLE client_profiles (
            id                      UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
            company_id              UUID        NOT NULL REFERENCES companies(id),
            user_id                 UUID        NOT NULL UNIQUE REFERENCES users(id),
            billing_address         TEXT,
            tags                    JSONB       NOT NULL DEFAULT '[]'::jsonb,
            admin_notes             TEXT,
            referral_source         TEXT,
            preferred_contractor_id UUID        REFERENCES users(id),
            preferred_contact_method TEXT,
            average_rating          NUMERIC(3,2),
            version                 INTEGER     NOT NULL DEFAULT 1,
            created_at              TIMESTAMPTZ NOT NULL DEFAULT now(),
            updated_at              TIMESTAMPTZ NOT NULL DEFAULT now(),
            deleted_at              TIMESTAMPTZ
        )
    """))
    op.execute(text("ALTER TABLE client_profiles ENABLE ROW LEVEL SECURITY"))
    op.execute(text("ALTER TABLE client_profiles FORCE ROW LEVEL SECURITY"))
    op.execute(text("""
        CREATE POLICY tenant_isolation ON client_profiles
        USING (company_id = current_setting('app.current_company_id', true)::uuid)
    """))

    # 4. client_properties table (saved property addresses per client)
    op.execute(text("""
        CREATE TABLE client_properties (
            id              UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
            company_id      UUID        NOT NULL REFERENCES companies(id),
            client_id       UUID        NOT NULL REFERENCES users(id),
            job_site_id     UUID        NOT NULL REFERENCES job_sites(id),
            nickname        TEXT,
            is_default      BOOLEAN     NOT NULL DEFAULT false,
            version         INTEGER     NOT NULL DEFAULT 1,
            created_at      TIMESTAMPTZ NOT NULL DEFAULT now(),
            updated_at      TIMESTAMPTZ NOT NULL DEFAULT now(),
            deleted_at      TIMESTAMPTZ
        )
    """))
    op.execute(text("ALTER TABLE client_properties ENABLE ROW LEVEL SECURITY"))
    op.execute(text("ALTER TABLE client_properties FORCE ROW LEVEL SECURITY"))
    op.execute(text("""
        CREATE POLICY tenant_isolation ON client_properties
        USING (company_id = current_setting('app.current_company_id', true)::uuid)
    """))

    # 5. job_requests table
    op.execute(text("""
        CREATE TABLE job_requests (
            id                  UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
            company_id          UUID        NOT NULL REFERENCES companies(id),
            client_id           UUID        REFERENCES users(id),
            description         TEXT        NOT NULL,
            trade_type          TEXT,
            urgency             TEXT        NOT NULL DEFAULT 'normal'
                CHECK (urgency IN ('normal','urgent')),
            preferred_date_start DATE,
            preferred_date_end   DATE,
            budget_min          NUMERIC(10,2),
            budget_max          NUMERIC(10,2),
            photos              JSONB       NOT NULL DEFAULT '[]'::jsonb,
            status              TEXT        NOT NULL DEFAULT 'pending'
                CHECK (status IN ('pending','accepted','declined','info_requested')),
            decline_reason      TEXT,
            decline_message     TEXT,
            converted_job_id    UUID        REFERENCES jobs(id),
            submitted_name      TEXT,
            submitted_email     TEXT,
            submitted_phone     TEXT,
            version             INTEGER     NOT NULL DEFAULT 1,
            created_at          TIMESTAMPTZ NOT NULL DEFAULT now(),
            updated_at          TIMESTAMPTZ NOT NULL DEFAULT now(),
            deleted_at          TIMESTAMPTZ
        )
    """))
    op.execute(text("ALTER TABLE job_requests ENABLE ROW LEVEL SECURITY"))
    op.execute(text("ALTER TABLE job_requests FORCE ROW LEVEL SECURITY"))
    op.execute(text("""
        CREATE POLICY tenant_isolation ON job_requests
        USING (company_id = current_setting('app.current_company_id', true)::uuid)
    """))

    # 6. ratings table
    op.execute(text("""
        CREATE TABLE ratings (
            id              UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
            company_id      UUID        NOT NULL REFERENCES companies(id),
            job_id          UUID        NOT NULL REFERENCES jobs(id),
            rater_id        UUID        NOT NULL REFERENCES users(id),
            ratee_id        UUID        NOT NULL REFERENCES users(id),
            direction       TEXT        NOT NULL CHECK (direction IN ('admin_to_client','client_to_company')),
            stars           INTEGER     NOT NULL CHECK (stars BETWEEN 1 AND 5),
            review_text     TEXT,
            version         INTEGER     NOT NULL DEFAULT 1,
            created_at      TIMESTAMPTZ NOT NULL DEFAULT now(),
            updated_at      TIMESTAMPTZ NOT NULL DEFAULT now(),
            deleted_at      TIMESTAMPTZ,
            UNIQUE (job_id, direction)
        )
    """))
    op.execute(text("ALTER TABLE ratings ENABLE ROW LEVEL SECURITY"))
    op.execute(text("ALTER TABLE ratings FORCE ROW LEVEL SECURITY"))
    op.execute(text("""
        CREATE POLICY tenant_isolation ON ratings
        USING (company_id = current_setting('app.current_company_id', true)::uuid)
    """))
```

### Backend: State machine service method

```python
# Source: project pattern — TenantScopedService + specific exception types
class InvalidTransitionError(Exception):
    def __init__(self, from_status: str, to_status: str, role: str) -> None:
        self.from_status = from_status
        self.to_status = to_status
        self.role = role
        super().__init__(f"Role '{role}' cannot transition job from '{from_status}' to '{to_status}'")

class JobService(TenantScopedService[Job]):
    repository_class = JobRepository

    async def transition_status(
        self,
        job_id: uuid.UUID,
        new_status: str,
        role: str,
        user_id: uuid.UUID,
        reason: str | None = None,
    ) -> Job:
        job = await self.repository.get_by_id(job_id)
        if job is None:
            raise HTTPException(status_code=404, detail="Job not found")

        allowed = ALLOWED_TRANSITIONS.get((job.status, role), frozenset())
        if new_status not in allowed:
            raise InvalidTransitionError(job.status, new_status, role)

        if is_backward(job.status, new_status) and not reason:
            raise HTTPException(
                status_code=422,
                detail="A reason is required for backward transitions",
            )

        # Append to status_history (replace list to trigger SQLAlchemy change detection)
        entry = {
            "status": new_status,
            "timestamp": datetime.now(UTC).isoformat(),
            "user_id": str(user_id),
            "reason": reason,
        }
        job.status_history = [*job.status_history, entry]
        job.status = new_status

        # If cancelled: bulk soft-delete associated bookings
        if new_status == "cancelled":
            await self.repository.cancel_job_bookings(job_id)

        await self.db.flush()
        await self.db.refresh(job)
        return job
```

### Mobile: JobStatus enum

```dart
// Source: project pattern — enum with .name for string representation
enum JobStatus {
  quote,
  scheduled,
  inProgress,
  complete,
  invoiced,
  cancelled;

  static JobStatus fromString(String value) {
    return JobStatus.values.firstWhere(
      (s) => s.name == value || s.backendValue == value,
      orElse: () => JobStatus.quote,
    );
  }

  String get backendValue => switch (this) {
    JobStatus.inProgress => 'in_progress',
    _ => name,
  };

  String get displayLabel => switch (this) {
    JobStatus.quote       => 'Quote',
    JobStatus.scheduled   => 'Scheduled',
    JobStatus.inProgress  => 'In Progress',
    JobStatus.complete    => 'Complete',
    JobStatus.invoiced    => 'Invoiced',
    JobStatus.cancelled   => 'Cancelled',
  };
}
```

### Mobile: AppDatabase schemaVersion bump

```dart
// Source: app/core/database/app_database.dart — established migration pattern
@DriftDatabase(
  tables: [
    Companies, Users, UserRoles, SyncQueue, SyncCursor,
    Jobs, ClientProfiles, ClientProperties, JobRequests,  // NEW Phase 4
  ],
  daos: [CompanyDao, UserDao, SyncQueueDao, SyncCursorDao, JobDao],
)
class AppDatabase extends _$AppDatabase {
  @override
  int get schemaVersion => 3;  // Bumped from 2

  @override
  MigrationStrategy get migration => MigrationStrategy(
    onCreate: (m) async { await m.createAll(); },
    onUpgrade: (m, from, to) async {
      if (from < 2) {
        await m.createTable(syncQueue);
        await m.createTable(syncCursor);
        await m.addColumn(companies, companies.deletedAt);
        await m.addColumn(users, users.deletedAt);
        await m.addColumn(userRoles, userRoles.deletedAt);
      }
      if (from < 3) {
        // Phase 4 tables
        await m.createTable(jobs);
        await m.createTable(clientProfiles);
        await m.createTable(clientProperties);
        await m.createTable(jobRequests);
      }
    },
  );
}
```

### Mobile: Job provider (AsyncNotifier pattern)

```dart
// Source: established Riverpod 3.x pattern — AsyncNotifier for async build()
@riverpod
class JobNotifier extends _$JobNotifier {
  @override
  Future<List<JobEntity>> build() async {
    final db = getIt<AppDatabase>();
    final authState = ref.watch(authNotifierProvider);
    if (authState is! AuthAuthenticated) return [];

    // Watch Drift stream — auto-rebuilds on local DB changes
    final stream = db.jobDao.watchJobsByCompany(authState.companyId);
    return ref.watch(
      StreamProvider.family((ref, _) => stream).call(ref, null).future,
    );
  }
}
```

### Backend: Full-text search query

```python
# Source: PostgreSQL tsvector — built-in, no extension
from sqlalchemy import func, select

async def search_jobs(self, query: str) -> list[Job]:
    ts_query = func.plainto_tsquery('english', query)
    stmt = (
        select(Job)
        .where(
            Job.deleted_at.is_(None),
            Job.search_vector.op('@@')(ts_query),
        )
        .order_by(
            func.ts_rank(Job.search_vector, ts_query).desc()
        )
        .options(selectinload(Job.client), selectinload(Job.contractor))
    )
    result = await self.db.execute(stmt)
    return list(result.scalars().all())
```

---

## State of the Art

| Old Approach | Current Approach | Impact for Phase 4 |
|--------------|------------------|-------------------|
| Separate status_history table | JSONB array on job row | Single query for job + history; no join needed for History tab |
| Integer status enum | String enum (`StrEnum`) | Self-documenting, safe to add states, no ordinal arithmetic bugs |
| Autogenerate Alembic for all DDL | `op.execute(text(...))` for complex constraints | Required for Phase 4 migration (GIST constraint on bookings table persists) |
| Global float file storage config | `Path(__file__).parent` relative path | Consistent across dev/prod, no CWD dependency |
| `Interceptor` with async in `onError` | `QueuedInterceptor` | Already established — Phase 4 sync handlers inherit this behavior |

---

## Integration Points: What Phase 4 Touches

### Backend Changes
1. **New router** `app/features/jobs/router.py` — registered in `main.py` as `app.include_router(jobs_router, prefix="/api/v1")`
2. **Sync endpoint extension** — `app/features/sync/router.py` gains `jobs`, `client_profiles`, `job_requests` in `SyncResponse`
3. **Sync service extension** — `app/features/sync/service.py` gains `get_jobs_since()`, `get_client_profiles_since()`, `get_job_requests_since()` methods
4. **Migration 0008** — jobs, client_profiles, client_properties, job_requests, ratings tables + bookings.job_id FK

### Mobile Changes
1. **AppDatabase** — schemaVersion 2 → 3; new tables and DAO registrations
2. **service_locator.dart** — register `JobSyncHandler`, `ClientProfileSyncHandler`, `JobRequestSyncHandler`
3. **app_router.dart** — add routes: `/jobs/:id`, `/jobs/new` (wizard), `/admin/clients/:id`, `/admin/requests`, `/contractor/jobs`
4. **route_names.dart** — add constants for all new routes
5. **app_shell.dart** — the existing "Team" tab (branch 4) remains; add admin "Requests" as sub-route; contractor branch gets new job list home
6. **jobs_screen.dart** placeholder — replaced with `JobsPipelineScreen` (kanban + list toggle)
7. **client_management_screen.dart** placeholder — replaced with `ClientCrmScreen`

---

## Gap Closure Research

**Context:** Phase 4 executed successfully (8/8 plans complete). Verification found 2 gaps in the client mobile path. All backend, admin UI, and tests are fully verified. The gaps are confined to Flutter-only changes. This section provides what the planner needs to create gap closure plans.

---

### Gap 1: image_picker — Photo Picker Implementation

**Gap description:** `_pickPhoto()` in `job_request_form_screen.dart` (line 394-411) shows a developer-facing SnackBar stub instead of launching a photo picker. `image_picker` is not in `pubspec.yaml`.

**Current state (confirmed by code inspection):**
- File: `mobile/lib/features/client/presentation/screens/job_request_form_screen.dart`
- `_photoPaths` list exists and is wired to the thumbnail grid and submit logic correctly
- The submit path (`_submit()`) encodes `_photoPaths` as a JSON array and writes to Drift — this is correct and requires no changes
- The thumbnail grid renders photo paths as placeholder containers (acceptable for Phase 4 — actual image rendering is Phase 6 scope)
- Only `_pickPhoto()` is broken; everything else in the form is functional

**Package to add:**
- Package: `image_picker`
- Version: `^1.2.1` (latest stable, published by flutter.dev, HIGH confidence)
- Verified at: https://pub.dev/packages/image_picker (2026-03-08)

**Android setup required:** None. The image_picker README states "No configuration required — the plugin should work out of the box" on Android. No AndroidManifest.xml changes needed. The existing `network_security_config.xml` and manifest are unaffected.

**iOS setup required:** Not applicable for Android-first project. CLAUDE.md states "Android first, iOS second." iOS Info.plist entries (`NSPhotoLibraryUsageDescription`, `NSCameraUsageDescription`) are required only when building for iOS — not blocking for Phase 4 gap closure on Android.

**Key API (verified from official docs):**

Single image pick from gallery (what `_pickPhoto()` needs):
```dart
import 'package:image_picker/image_picker.dart';

final ImagePicker _picker = ImagePicker();

Future<void> _pickPhoto() async {
  final XFile? file = await _picker.pickImage(source: ImageSource.gallery);
  if (file != null) {
    setState(() => _photoPaths.add(file.path));
  }
}
```

**`retrieveLostData` pattern for Android high-memory-pressure case:**
Android can kill the MainActivity during image picking under memory pressure. The existing `JobRequestFormScreen` form state would be lost in this case, but photo paths can be recovered. This is a known Android limitation; handle gracefully in `initState`:
```dart
@override
void initState() {
  super.initState();
  _recoverLostData();
}

Future<void> _recoverLostData() async {
  final LostDataResponse response = await _picker.retrieveLostData();
  if (response.isEmpty) return;
  if (response.file != null) {
    setState(() => _photoPaths.add(response.file!.path));
  }
}
```

**What does NOT need changing:**
- The `_photoPaths` list and its use in `_submit()` — already correct
- The thumbnail grid widget — already renders paths as placeholders (acceptable)
- The `_maxPhotos = 5` guard — already enforces the 1-5 photo limit
- The `JobRequestsCompanion` construction — already serializes `_photoPaths` to JSON
- Any backend code — photo path storage is backend-complete

**pubspec.yaml change:**
```yaml
# Under dependencies:
image_picker: ^1.2.1
```

**Confidence:** HIGH — pub.dev official package page verified version and Android setup requirements directly.

---

### Gap 2: Route Registration for JobRequestFormScreen

**Gap description:** `JobRequestFormScreen` has no `GoRoute` in `app_router.dart` and no constant in `route_names.dart`. Clients navigating the app have no path to the in-app request form.

**Current state (confirmed by code inspection):**
- `app_router.dart` Branch 6 (client portal) contains only one route: `/client/portal` → `ClientPortalScreen`
- `route_names.dart` has `clientPortal = '/client/portal'` but nothing for the request form
- `ClientPortalScreen` is a Phase 7 placeholder ("Coming in Phase 5") — it should remain as-is; the request form is a separate screen
- `_checkRoleAccess()` already handles `/client/` prefix → requires `UserRole.client` — no role guard changes needed
- The `AppShell` client tab (Branch 6, index 6) already exists in `StatefulShellRoute.indexedStack` — no shell changes needed

**Correct route path:** `/client/request`

Rationale: Follows the established `/client/` prefix convention (role-gated to clients). Keeps it distinct from `/client/portal` (the Phase 7 portal). Short and self-documenting.

**Exact changes required:**

`route_names.dart` — add one constant:
```dart
/// In-app job request submission form — client only.
static const jobRequestForm = '/client/request';
```

`app_router.dart` — add import and GoRoute under Branch 6:
```dart
// Add import at top of file (near other client imports):
import '../../features/client/presentation/screens/job_request_form_screen.dart';

// In Branch 6 (client portal branch), add route alongside existing /client/portal:
StatefulShellBranch(
  routes: [
    GoRoute(
      path: RouteNames.clientPortal,
      builder: (context, state) => const ClientPortalScreen(),
    ),
    GoRoute(
      path: RouteNames.jobRequestForm,  // '/client/request'
      builder: (context, state) => const JobRequestFormScreen(),
    ),
  ],
),
```

**Entry point from ClientPortalScreen:** The `ClientPortalScreen` is currently a placeholder. The most minimal gap closure is to update `ClientPortalScreen` to include a "Submit Job Request" button that navigates to `/client/request`. This connects the client's existing bottom-nav tab to the request form.

```dart
// In ClientPortalScreen body, add a button:
FilledButton.icon(
  onPressed: () => context.go(RouteNames.jobRequestForm),
  icon: const Icon(Icons.add_task),
  label: const Text('Submit Job Request'),
),
```

Alternatively, the `HomeScreen` already has a "Client Portal" quick link for client users — updating it to go directly to `/client/request` instead of `/client/portal` is also valid. Both approaches work; the planner should choose the one that makes the client flow most discoverable.

**`app_router.dart` route ordering note:** GoRouter matches routes in declaration order within a branch. The two client routes (`/client/portal` and `/client/request`) have different static paths — no ordering conflict exists. Both can be declared in either order.

**`app_router.g.dart` impact:** The `app_router.dart` uses `@riverpod` code generation (`part 'app_router.g.dart'`). Adding routes to `StatefulShellBranch` does NOT require `build_runner` regeneration — only the `@riverpod` annotation on the `router` function itself triggers generation, and that annotation is not changing. The `.g.dart` file handles only the `routerProvider` provider code, not route declarations.

**What does NOT need changing:**
- The `_checkRoleAccess()` function — already handles `/client/` prefix correctly
- `AppShell._buildTabs()` — no new tab needed; request form is accessed within the existing Client branch
- Any backend code — already complete
- Any Drift/sync code — `JobRequestFormScreen._submit()` already writes to `jobDao.insertJobRequest()`

**Confidence:** HIGH — based on direct inspection of `app_router.dart`, `route_names.dart`, `client_portal_screen.dart`, and `job_request_form_screen.dart`.

---

### Gap Closure: Dependency Ordering

Both gaps are independent of each other. They can be implemented in a single plan or two separate plans:

| Gap | Files Changed | Scope |
|-----|--------------|-------|
| Gap 1: image_picker | `pubspec.yaml`, `job_request_form_screen.dart` | 2 files |
| Gap 2: Route registration | `route_names.dart`, `app_router.dart`, `client_portal_screen.dart` | 3 files |

**Recommended approach:** One combined plan (single `flutter pub get` + `dart analyze` pass covers both changes together). No backend changes. No Drift schema changes. No code generation needed.

---

### Gap Closure: Test Requirements

Per CLAUDE.md: "Every new service function or endpoint MUST have corresponding tests before merging."

**Gap 1 (image_picker) tests:**
- Widget test for `JobRequestFormScreen` that mocks `ImagePicker` and verifies a picked photo path is added to `_photoPaths` and the thumbnail grid renders the expected count
- Widget test verifying the submit path includes photos in the `JobRequestsCompanion`
- Use `mocktail` — mock `ImagePicker` as a collaborator injected via constructor or via a test helper

**Known challenge:** `image_picker` uses a platform channel. In widget tests, platform channels are not available unless you register a mock handler. The standard approach is to use `TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler` or wrap `ImagePicker` behind a thin interface that can be overridden in tests.

**Simpler test approach:** Extract a `PhotoPickerService` abstraction:
```dart
// lib/shared/services/photo_picker_service.dart
abstract class PhotoPickerService {
  Future<String?> pickPhoto();
}

class ImagePickerService implements PhotoPickerService {
  final ImagePicker _picker = ImagePicker();

  @override
  Future<String?> pickPhoto() async {
    final file = await _picker.pickImage(source: ImageSource.gallery);
    return file?.path;
  }
}
```
Inject `PhotoPickerService` into `JobRequestFormScreen`. In tests, inject a `MockPhotoPickerService` via GetIt or constructor param. This avoids platform channel issues entirely and is consistent with CLAUDE.md's "unit tests with mocktail for services" rule.

**Gap 2 (route registration) tests:**
- Widget test that navigates to `/client/request` and verifies `JobRequestFormScreen` is rendered
- Widget test that taps the "Submit Job Request" button in `ClientPortalScreen` and verifies navigation to `/client/request`
- Use `ProviderScope` overrides and a `GoRouter` configured with `initialLocation: '/client/request'` for direct route testing

---

## Validation Architecture

**Purpose:** This section documents how to verify Phase 4 gap closure is complete. The verifier uses these checks to confirm CLNT-04 is fully satisfied after gap closure plans execute.

---

### What "Complete" Looks Like for CLNT-04

CLNT-04 states: "Client-initiated job requests with preferred dates."

Current state: PARTIAL. Backend fully implemented. Mobile gaps prevent the in-app client path from functioning.

After gap closure, CLNT-04 is SATISFIED when ALL of the following are true:

| Check | How to Verify |
|-------|--------------|
| Photo picker launches | Tap "Add photos" in `JobRequestFormScreen` → OS gallery picker opens (or mock resolves correctly in test) |
| Photo path stored | After picking, `_photoPaths` has one more entry and thumbnail count increments |
| Form submits with photos | Submit a request with 1+ photos — `JobRequestsCompanion.photos` contains JSON array with path strings |
| Route exists in router | `app_router.dart` has a `GoRoute` with `path: '/client/request'` |
| Route constant exists | `route_names.dart` has `jobRequestForm = '/client/request'` |
| Client can navigate there | From `ClientPortalScreen` (or HomeScreen), tapping the entry point navigates to `JobRequestFormScreen` |
| Role guard works | A non-client user navigating to `/client/request` is redirected to `/unauthorized` |

---

### Verification Checks by File

**`mobile/pubspec.yaml`**
- `image_picker: ^1.2.x` appears under `dependencies`
- `flutter pub get` has been run (check `pubspec.lock` for `image_picker` entry)

**`mobile/lib/features/client/presentation/screens/job_request_form_screen.dart`**
- `import 'package:image_picker/image_picker.dart'` present
- `_pickPhoto()` calls `_picker.pickImage(source: ImageSource.gallery)` or delegates to a `PhotoPickerService`
- `_pickPhoto()` calls `setState(() => _photoPaths.add(file.path))` (or equivalent)
- No `ScaffoldMessenger.showSnackBar` stub remains in `_pickPhoto()`
- `retrieveLostData()` called in `initState` (Android safety)

**`mobile/lib/core/routing/route_names.dart`**
- `static const jobRequestForm = '/client/request'` present

**`mobile/lib/core/routing/app_router.dart`**
- `import '../../features/client/presentation/screens/job_request_form_screen.dart'` present
- `GoRoute(path: RouteNames.jobRequestForm, builder: ...)` present inside Branch 6

**`mobile/lib/features/client/presentation/screens/client_portal_screen.dart`** (or `home_screen.dart`)
- A navigable entry point to `RouteNames.jobRequestForm` exists (button, tile, or nav action)

---

### Automated Test Checklist

These tests MUST pass before marking gap closure complete:

**Widget tests (new):**
- [ ] `job_request_form_screen_test.dart`: mock photo picker resolves a path → thumbnail count increments
- [ ] `job_request_form_screen_test.dart`: submit with 2 photos → `JobRequestsCompanion.photos` contains 2-item JSON array
- [ ] `client_portal_screen_test.dart`: "Submit Job Request" button tap → router navigates to `/client/request`
- [ ] `app_router_test.dart`: GoRouter with client auth state → `/client/request` resolves to `JobRequestFormScreen`
- [ ] `app_router_test.dart`: GoRouter with admin auth state → `/client/request` redirects to `/unauthorized`

**Existing tests must continue to pass:**
- [ ] All 8 existing Flutter widget tests (no regressions from pubspec or router changes)
- [ ] `dart analyze` with zero errors

**Backend tests (no changes expected — all should still pass):**
- [ ] `pytest backend/tests/` — all 162 tests pass (no backend changes in gap closure)

---

### Non-Automated Verification (Human Required)

These checks cannot be fully automated and require on-device or on-emulator verification:

**1. Photo picker launches on Android**
- Log in as a client user
- Navigate to `/client/request`
- Tap "Add photos"
- Expected: OS gallery/photo picker opens
- Why human: Platform channel behavior cannot be verified in widget tests

**2. Full dual-flow E2E on device**
- Log in as client → navigate to request form → fill form with 1 photo → submit
- Log in as admin → see request in review queue → accept request
- Confirm: new job appears in admin pipeline at Quote stage
- Why human: Multi-session, multi-role flow with real OS photo picker requires device

---

### What Is Out of Scope for Gap Closure

These items were identified in the verification report but are NOT part of gap closure — they are either acceptable for Phase 4 or deferred:

| Item | Disposition |
|------|------------|
| Client dropdown in job wizard has only null item | Acceptable — admin can still create jobs; CRM integration with wizard is Phase 5 scope. Not a CLNT-04 requirement. |
| Photo thumbnails in request review screen are grey placeholders | Acceptable — photo paths stored correctly; visual thumbnails are Phase 6 (FIELD-01) scope |
| `ClientPortalScreen` says "Coming in Phase 5" | Expected — full client portal is Phase 7. The request form is a separate screen. |

---

## Open Questions

1. **Photo file path on the server in the web form**
   - What we know: Photos are stored on local filesystem, paths stored as JSONB array on `job_requests`
   - What's unclear: The serving path — should FastAPI mount a `StaticFiles` route for `uploads/`?
   - Recommendation: Yes, mount `StaticFiles(directory="uploads")` at `/uploads` in `main.py`. The mobile client references photos by URL `{baseUrl}/uploads/job_requests/{request_id}/{filename}`. This is the standard FastAPI pattern for local file serving.

2. **Offline status_history consistency**
   - What we know: Status transitions that don't involve scheduling work offline
   - What's unclear: When the mobile transitions In Progress → Complete offline, it writes a `status_history` entry locally. When synced to server, the server re-appends the entry. Does the server validate the transition against the JSONB it receives or re-derive it?
   - Recommendation: Server re-derives and re-appends the history entry from the transition request. Do NOT trust client-sent `status_history` — the server always owns the canonical history. The PATCH endpoint accepts `{new_status, reason}` only; the server writes the history entry itself.

3. **Ratings — update window enforcement**
   - What we know: Ratings can be updated until 30 days after completion
   - What's unclear: "30 days after completion" — measured from the `complete` status timestamp in `status_history`, or from `updated_at` when status last changed to `complete`?
   - Recommendation: Query `status_history` JSONB for the most recent `complete` entry timestamp. This is accurate even if the job later goes Complete → Invoiced.

---

## Sources

### Primary (HIGH confidence)
- Direct codebase inspection: `mobile/lib/features/client/presentation/screens/job_request_form_screen.dart` — gap 1 root cause, stub location, existing data wiring confirmed
- Direct codebase inspection: `mobile/lib/core/routing/app_router.dart` — gap 2 root cause, Branch 6 structure confirmed, `_checkRoleAccess()` behavior confirmed
- Direct codebase inspection: `mobile/lib/core/routing/route_names.dart` — missing constant confirmed
- Direct codebase inspection: `mobile/pubspec.yaml` — `image_picker` absent confirmed, current package versions noted
- Direct codebase inspection: `mobile/lib/features/client/presentation/screens/client_portal_screen.dart` — placeholder screen structure confirmed
- Direct codebase inspection: `.planning/phases/04-job-lifecycle/04-VERIFICATION.md` — gap descriptions, artifact status, requirements coverage
- pub.dev/packages/image_picker — version 1.2.1 confirmed, Android setup requirements confirmed, API signatures confirmed (2026-03-08)
- pub.dev/packages/image_picker/changelog — no breaking changes in 1.1.x → 1.2.1 confirmed (2026-03-08)
- Direct codebase inspection: `backend/app/features/scheduling/models.py` — Booking model, job_id field, GIST constraint
- Direct codebase inspection: `backend/migrations/versions/0007_scheduling_tables.py` — migration pattern, FK gap in bookings
- Direct codebase inspection: `backend/app/core/base_models.py`, `base_service.py`, `base_repository.py`, `base_schemas.py` — OOP architecture confirmed
- Direct codebase inspection: `mobile/lib/core/sync/sync_handler.dart`, `sync_registry.dart`, `handlers/user_sync_handler.dart` — sync extension pattern
- Direct codebase inspection: `mobile/lib/core/database/app_database.dart` — schema version, migration strategy

### Secondary (MEDIUM confidence)
- SQLAlchemy 2.0 docs — MutableList.as_mutable(JSONB) for JSONB mutation tracking
- Flutter docs — LongPressDraggable + DragTarget for kanban drag interaction
- image_picker README — Android `retrieveLostData()` pattern for MainActivity kill recovery

### Tertiary (LOW confidence — needs validation during implementation)
- `aiofiles` 24.x compatibility with Python 3.12 / FastAPI 0.115 — standard library, but version not pinned yet
- `PhotoPickerService` abstraction approach for testability — standard pattern but not yet validated in this specific codebase's test setup

---

## Metadata

**Confidence breakdown:**
- Standard stack: HIGH — all packages already in use; gap closure adds only `image_picker: ^1.2.1`
- Architecture patterns: HIGH — directly derived from existing Phase 1-4 code
- Migration design: HIGH — directly modeled after migration 0007; critical FK gap confirmed from source
- State machine: HIGH — transition table approach is idiomatic Python; rules directly from CONTEXT.md
- Kanban UI: MEDIUM — straightforward Flutter approach, but exact widget nesting may require iteration
- Photo upload/storage: MEDIUM — aiofiles pattern is standard but not yet in this codebase
- Pitfalls: HIGH — all derived from direct code inspection of existing patterns
- Gap 1 (image_picker): HIGH — API verified against official pub.dev, Android setup confirmed no-config
- Gap 2 (route registration): HIGH — based on direct code inspection of all 3 affected files

**Research date:** 2026-03-08
**Updated:** 2026-03-08 (gap closure research and Validation Architecture added)
**Valid until:** 2026-06-08 (stable libraries; re-verify if Flutter or GoRouter major version changes)
