# Architecture Research

**Domain:** Contractor Management SaaS (Field Service Management)
**Researched:** 2026-03-04
**Confidence:** HIGH (multi-tenancy, offline sync) / MEDIUM (scheduling engine internals)

## Standard Architecture

### System Overview

```
┌─────────────────────────────────────────────────────────────────────┐
│                         FLUTTER MOBILE APP                           │
│                                                                       │
│  ┌──────────────┐  ┌──────────────┐  ┌────────────────────────────┐  │
│  │  Admin UI    │  │ Contractor UI│  │       Client UI            │  │
│  │  (schedule,  │  │ (my jobs,    │  │   (job status, photos)     │  │
│  │   team mgmt) │  │  availability│  │                            │  │
│  └──────┬───────┘  └──────┬───────┘  └────────────┬───────────────┘  │
│         │                 │                        │                  │
│  ┌──────┴─────────────────┴────────────────────────┴───────────────┐  │
│  │              Presentation Layer (Riverpod Providers)            │  │
│  └──────────────────────────────┬──────────────────────────────────┘  │
│  ┌───────────────────────────────┼──────────────────────────────────┐  │
│  │              Domain Layer (Use Cases / Entities)                 │  │
│  └──────────────────────────────┬──────────────────────────────────┘  │
│  ┌───────────────────────────────┼──────────────────────────────────┐  │
│  │              Data Layer (Repositories)                           │  │
│  │  ┌──────────────────┐    ┌───┴─────────────────────────────┐    │  │
│  │  │  Local DB (Drift) │    │  Remote Data Source (API client) │    │  │
│  │  │  + Sync Queue     │    │  (HTTP to FastAPI backend)       │    │  │
│  │  └──────────────────┘    └─────────────────────────────────┘    │  │
│  └──────────────────────────────────────────────────────────────────┘  │
└─────────────────────────────────────────────────────────────────────┘
                         │ HTTPS REST / JSON
┌─────────────────────────────────────────────────────────────────────┐
│                         FASTAPI BACKEND                              │
│                                                                       │
│  ┌────────────────┐  ┌─────────────────┐  ┌──────────────────────┐  │
│  │  Auth Layer    │  │ Tenant Resolver  │  │  Request Validation  │  │
│  │  (JWT, future) │  │  (middleware)    │  │  (Pydantic)          │  │
│  └───────┬────────┘  └────────┬────────┘  └────────────┬─────────┘  │
│          └───────────────────┬┴───────────────────────┘             │
│  ┌──────────────────────────────────────────────────────────────────┐  │
│  │                      API Routers                                 │  │
│  │  /jobs   /contractors   /schedules   /clients   /companies       │  │
│  └──────────────────────────────┬───────────────────────────────────┘  │
│  ┌───────────────────────────────┼──────────────────────────────────┐  │
│  │                    Service Layer                                 │  │
│  │  ┌─────────────────┐  ┌──────────────────┐  ┌────────────────┐  │  │
│  │  │  Job Service    │  │ Scheduling Engine │  │  Sync Service  │  │  │
│  │  │  (lifecycle)    │  │ (conflict detect) │  │  (deltas)      │  │  │
│  │  └─────────────────┘  └──────────────────┘  └────────────────┘  │  │
│  └──────────────────────────────────────────────────────────────────┘  │
│  ┌──────────────────────────────────────────────────────────────────┐  │
│  │              Data Access (SQLAlchemy + RLS Session Events)       │  │
│  └──────────────────────────────┬───────────────────────────────────┘  │
└─────────────────────────────────┼────────────────────────────────────┘
                                  │
┌─────────────────────────────────┼────────────────────────────────────┐
│                    PostgreSQL (shared database)                       │
│  ┌───────────────────────────────────────────────────────────────┐   │
│  │  Row-Level Security policies on all tenant tables             │   │
│  │  EXCLUDE USING GIST on schedule tables (overlap prevention)   │   │
│  │  Tables: companies, users, jobs, schedules, availability,     │   │
│  │          job_photos, clients, sync_cursors                    │   │
│  └───────────────────────────────────────────────────────────────┘   │
└──────────────────────────────────────────────────────────────────────┘
```

### Component Responsibilities

| Component | Responsibility | Communicates With |
|-----------|---------------|-------------------|
| Flutter UI (Role screens) | Render role-appropriate views; dispatch user actions | Riverpod providers |
| Riverpod Providers | Manage UI state; orchestrate use cases; expose streams | Use cases, local DB streams |
| Use Cases (Domain) | Encode business rules (e.g., "book a job slot") | Repositories (interface) |
| Repository (Data) | Merge local and remote data; manage sync queue | Drift local DB, API client |
| Drift Local DB | SQLite on-device storage; reactive streams; sync queue table | Repository |
| API Client | HTTP calls to backend; retry logic | FastAPI backend |
| Tenant Resolver Middleware | Extract company_id from JWT; set PostgreSQL session variable | SQLAlchemy session |
| Scheduling Engine (Service) | Detect conflicts, compute available slots, handle travel time | Database (schedules, availability) |
| PostgreSQL RLS | Database-enforced tenant isolation; overlap exclusion constraints | All queries |

## Recommended Project Structure

### Flutter (feature-first, clean architecture)

```
lib/
├── core/
│   ├── database/          # Drift database definition, migrations
│   ├── network/           # HTTP client, interceptors, connectivity
│   ├── sync/              # Sync engine, outbox processor, retry logic
│   ├── routing/           # Go Router setup, route guards
│   └── theme/             # Design tokens, typography
├── features/
│   ├── jobs/
│   │   ├── domain/        # Job entity, JobRepository interface, use cases
│   │   ├── data/          # JobRepositoryImpl, local DAO, remote data source
│   │   └── presentation/  # Riverpod providers, screens, widgets
│   ├── scheduling/
│   │   ├── domain/        # Schedule entity, conflict check use case
│   │   ├── data/          # ScheduleRepository, local DAO, remote DS
│   │   └── presentation/  # Calendar view providers, schedule screen
│   ├── contractors/
│   │   ├── domain/        # Contractor entity, availability use cases
│   │   ├── data/
│   │   └── presentation/
│   ├── clients/
│   │   ├── domain/
│   │   ├── data/
│   │   └── presentation/
│   └── company/
│       ├── domain/        # Company entity, admin use cases
│       ├── data/
│       └── presentation/
└── shared/
    ├── widgets/           # Reusable UI components
    └── models/            # Shared DTOs, enums (job status, role)
```

### FastAPI Backend (domain-driven)

```
app/
├── main.py                # App factory, middleware registration
├── core/
│   ├── config.py          # Settings (env vars, DB URL)
│   ├── database.py        # SQLAlchemy engine, session factory
│   ├── tenant.py          # Tenant middleware, session RLS helper
│   └── security.py        # JWT decode (future auth)
├── features/
│   ├── jobs/
│   │   ├── router.py      # FastAPI router (/jobs endpoints)
│   │   ├── service.py     # Job lifecycle business logic
│   │   ├── models.py      # SQLAlchemy ORM models
│   │   └── schemas.py     # Pydantic request/response schemas
│   ├── scheduling/
│   │   ├── router.py
│   │   ├── engine.py      # Conflict detection, slot availability
│   │   ├── models.py      # Schedule, availability ORM models
│   │   └── schemas.py
│   ├── contractors/
│   ├── clients/
│   └── companies/
├── migrations/            # Alembic migration scripts
└── tests/
    ├── unit/
    └── integration/
```

### Structure Rationale

- **Feature-first (Flutter):** Each feature is self-contained (domain → data → presentation). Adding a new feature doesn't touch other features. Enables parallel development and isolated testing.
- **Core vs features (Flutter):** Sync engine, DB init, and routing live in `core/` because they are cross-cutting concerns shared by all features.
- **Feature-first (FastAPI):** Each domain area owns its router, service, models, and schemas. Avoids the "models.py with 50 classes" anti-pattern.
- **Separate engine module (scheduling):** `engine.py` is isolated from routing so it can be tested as pure business logic without HTTP context.

## Architectural Patterns

### Pattern 1: Repository with Offline-First Writes

**What:** Local database is the single source of truth for reads. Writes go to local DB first, then enqueue a sync command. Background worker drains the queue when online.

**When to use:** Always — this is the foundational pattern for all data operations in this app.

**Trade-offs:** Immediate UI responsiveness; complexity in conflict handling; requires careful schema versioning.

**Example (Dart):**
```dart
// Repository implementation
class JobRepositoryImpl implements JobRepository {
  final JobLocalDataSource _local;
  final JobRemoteDataSource _remote;
  final SyncQueue _syncQueue;

  // READ: stream from local DB only — UI always reactive, never blocked on network
  Stream<List<Job>> watchJobs() => _local.watchAll();

  // WRITE: local first, then enqueue sync — never blocks on network
  Future<void> updateJobStatus(String jobId, JobStatus status) async {
    await _local.db.transaction(() async {
      await _local.updateStatus(jobId, status);
      await _syncQueue.enqueue(SyncCommand(
        operation: SyncOp.update,
        entity: 'jobs',
        entityId: jobId,
        payload: {'status': status.name},
        createdAt: DateTime.now(),
      ));
    });
  }
}
```

### Pattern 2: Transactional Outbox (Sync Queue)

**What:** A `sync_queue` table in the local SQLite database stores every mutation that hasn't been confirmed by the server. A background isolate drains the queue with exponential backoff.

**When to use:** Whenever the app must guarantee delivery of mutations even if the app is killed mid-sync.

**Trade-offs:** Guarantees no data loss; requires idempotent server endpoints (use client-generated UUIDs as idempotency keys).

**Example (Drift schema):**
```dart
class SyncQueue extends Table {
  TextColumn get id => text()();          // client-generated UUID
  TextColumn get operation => text()();   // CREATE | UPDATE | DELETE
  TextColumn get entityType => text()();  // jobs | schedules | etc.
  TextColumn get entityId => text()();
  TextColumn get payload => text()();     // JSON blob
  IntColumn get attempts => integer().withDefault(const Constant(0))();
  TextColumn get status => text().withDefault(const Constant('pending'))();
  DateTimeColumn get createdAt => dateTime()();
}
```

**Server requirement:** All mutation endpoints must accept a client-provided `client_id` UUID for idempotency — if the same `client_id` arrives twice (retry), return 200 with the existing result.

### Pattern 3: Multi-Tenant Row-Level Security

**What:** All tenant-scoped tables carry a `company_id` column. PostgreSQL RLS policies enforce that every query only sees rows matching the session variable `app.current_company_id`. The FastAPI middleware sets this variable on every request before any SQL executes.

**When to use:** All tenant-scoped tables from day one.

**Trade-offs:** Security enforced at the database layer (cannot be bypassed by application bugs); slight overhead per query; requires `btree_gist` extension for range tables.

**Example (Python):**
```python
# Middleware: extract tenant from JWT, set session variable
class TenantMiddleware(BaseHTTPMiddleware):
    async def dispatch(self, request: Request, call_next):
        company_id = extract_company_id_from_jwt(request)
        request.state.company_id = company_id
        response = await call_next(request)
        return response

# SQLAlchemy event: set RLS variable before every query
@event.listens_for(Session, "after_begin")
def set_tenant_context(session, transaction, connection):
    company_id = get_current_company_id()  # from context var
    connection.execute(
        text("SET LOCAL app.current_company_id = :cid"),
        {"cid": str(company_id)}
    )

# PostgreSQL RLS policy (applied to every tenant table):
# CREATE POLICY tenant_isolation ON jobs
#   USING (company_id = current_setting('app.current_company_id')::uuid);
# ALTER TABLE jobs ENABLE ROW LEVEL SECURITY;
```

### Pattern 4: Scheduling Engine with Database-Level Conflict Prevention

**What:** The scheduling engine has two layers. Application layer: compute available slots (query availability windows, subtract existing bookings, add travel time buffer). Database layer: an `EXCLUDE USING GIST` constraint on the `schedules` table prevents any overlapping bookings from being committed, even under concurrent race conditions.

**When to use:** Any time a contractor is assigned to a job slot.

**Trade-offs:** The DB constraint is the safety net — application logic provides UX (suggest slots, show conflicts early); DB constraint prevents data corruption. Travel time is modeled as a buffer on each end of the slot.

**Example (SQL):**
```sql
-- Requires: CREATE EXTENSION btree_gist;
CREATE TABLE schedules (
    id          UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    company_id  UUID NOT NULL,
    contractor_id UUID NOT NULL,
    job_id      UUID NOT NULL,
    slot        TSTZRANGE NOT NULL,  -- [start, end) with timezone
    EXCLUDE USING GIST (
        contractor_id WITH =,
        slot WITH &&             -- && means "overlaps"
    )
);

-- Travel-time buffer: expand slot by travel_minutes on each side
-- Application adds buffer BEFORE inserting:
-- effective_slot = [start - travel_buffer, end + travel_buffer)
```

**Example (Python — available slot query):**
```python
def get_available_slots(
    contractor_id: UUID,
    date: date,
    duration_minutes: int,
    travel_buffer_minutes: int,
) -> list[TimeSlot]:
    # 1. Get contractor's availability windows for the day
    # 2. Get all existing schedule slots (with travel buffers)
    # 3. Subtract booked slots from availability windows
    # 4. Filter windows large enough for duration + travel buffer
    # 5. Return candidate slots
    ...
```

## Data Flow

### Write Flow: Contractor Updates Job Status (Offline-Capable)

```
Contractor taps "Mark In Progress"
    |
    v
UpdateJobStatusUseCase (domain)
    |
    v
JobRepositoryImpl.updateJobStatus()
    |
    +-- [atomic SQLite transaction] --------+
    |   1. jobs table: status = in_progress  |
    |   2. sync_queue: INSERT pending entry  |
    +----------------------------------------+
    |
    v
Local Drift DB emits stream update
    |
    v
Riverpod JobProvider rebuilds
    |
    v
UI shows updated status immediately
    |
    [background, when online]
    v
SyncEngine.drainQueue()
    |
    v
POST /api/v1/jobs/{id}/status  (with idempotency key = sync_queue.id)
    |
    v
FastAPI: TenantMiddleware sets app.current_company_id in session
    |
    v
JobService.update_status() → SQLAlchemy → PostgreSQL (RLS enforced)
    |
    v
200 OK → SyncEngine marks queue entry as "synced"
```

### Write Flow: Admin Books a Contractor (Online, Conflict Check)

```
Admin selects contractor + time slot
    |
    v
CheckAvailabilityUseCase → GET /api/v1/schedules/available-slots
    |
    v
SchedulingEngine.get_available_slots(contractor_id, date, duration)
    |
    +-- Query contractor availability windows
    +-- Query existing bookings (with travel buffers)
    +-- Compute free intervals large enough for job
    |
    v
Backend returns list of available TimeSlots
    |
    v
Admin confirms slot
    |
    v
POST /api/v1/schedules (with slot details)
    |
    v
PostgreSQL EXCLUDE USING GIST constraint checked atomically
    |-- PASS: schedule row inserted, 201 Created
    |-- FAIL: ExclusionViolation → 409 Conflict → UI shows "slot taken"
```

### Read Flow: Client Checks Job Progress

```
Client opens job detail screen
    |
    v
Riverpod JobDetailProvider.build()
    |
    v
JobRepository.watchJob(jobId) → Drift Stream<Job>
    |
    v
Emit cached local data immediately (no loading spinner)
    |
    [background, if online]
    v
Repository.refreshJob(jobId) → GET /api/v1/jobs/{id}
    |
    v
FastAPI: RLS ensures client only sees their own jobs
    |
    v
Response written to local Drift DB
    |
    v
Stream emits updated Job → UI updates silently
```

### Sync Flow: Reconnect After Offline Period

```
ConnectivityService detects network restoration
    |
    v
SyncEngine.drainQueue() triggered
    |
    v
SELECT * FROM sync_queue WHERE status = 'pending' ORDER BY created_at ASC
    |
    v
For each entry:
    |
    +-- POST/PATCH/DELETE to backend with idempotency key
    |       |
    |       +-- 200/201: mark entry 'synced'
    |       +-- 409 conflict: apply conflict resolution strategy
    |           (server-wins for schedule conflicts, merge for status updates)
    |       +-- 5xx/timeout: increment attempts, exponential backoff
    |
    v
On full drain: pull server deltas (GET /api/v1/sync?cursor=<last_sync>)
    |
    v
Write server changes to local DB
    |
    v
Streams emit → UI updates with latest state
```

## Scaling Considerations

| Scale | Architecture Adjustments |
|-------|--------------------------|
| 0–50 companies | Single FastAPI instance + single PostgreSQL. RLS handles isolation. Sync polling every 30s is fine. |
| 50–500 companies | Add read replica for heavy schedule queries. Redis cache for availability windows. Increase sync efficiency (delta cursors). |
| 500+ companies | Connection pooling with PgBouncer becomes critical (RLS requires per-request SET LOCAL, incompatible with session-level pooling — use transaction-mode pooling). Consider schema-per-tenant for largest customers. |

### Scaling Priorities

1. **First bottleneck: Scheduling engine queries.** Availability window queries join several tables. Fix with materialized views or pre-computed availability caches with TTL.
2. **Second bottleneck: PostgreSQL connections.** RLS with `SET LOCAL` requires transaction-mode connection pooling (PgBouncer). Session-mode pooling will assign the wrong tenant context to pooled connections.
3. **Third bottleneck: Sync queue volume.** With many active contractors, the sync queue drains will generate significant write load. Batch mutation endpoints (`/api/v1/sync/batch`) reduce round-trips.

## Anti-Patterns

### Anti-Pattern 1: Treating Authentication as Tenant Isolation

**What people do:** Check `if user.company_id == requested_company_id` in application code and assume this is sufficient isolation.

**Why it's wrong:** Application-level checks can be bypassed by bugs, missing checks on new endpoints, or internal tooling that bypasses the check. A privilege escalation bug exposes all tenants' data.

**Do this instead:** Enforce isolation at the database level with PostgreSQL RLS. Application code cannot accidentally bypass a DB policy. This is defense-in-depth — application checks are still fine as UX, but the DB is the authoritative security boundary.

### Anti-Pattern 2: Optimistic Lock on Schedules Without DB Constraint

**What people do:** Check for conflicts in application code ("is this slot free?"), then insert the schedule. Under concurrent load, two requests that both pass the check can both insert, causing a double-booking.

**Why it's wrong:** The check-then-act sequence is not atomic. This is a classic TOCTOU (time-of-check/time-of-use) race condition. Under any concurrency this will happen.

**Do this instead:** Use PostgreSQL's `EXCLUDE USING GIST` constraint. The constraint check and the insert are atomic. The constraint cannot be raced. Application-level conflict checking is still useful for UX (show "here are available slots"), but the DB constraint is the ultimate safety net.

### Anti-Pattern 3: Online-First Writes

**What people do:** Write mutations directly to the API, update local state from the response.

**Why it's wrong:** Contractors are at job sites with poor connectivity. Any operation that requires a network round-trip will fail or feel sluggish. The core value proposition (scheduling management) breaks at exactly the moment it's most needed.

**Do this instead:** Local-first writes with the transactional outbox pattern. All writes succeed locally immediately. Sync happens asynchronously. The user experience is always responsive.

### Anti-Pattern 4: Single Monolithic Sync

**What people do:** On reconnect, push all local changes and pull the entire database.

**Why it's wrong:** Mobile data is expensive; sync is slow for large datasets; conflict resolution becomes complex when many changes collide.

**Do this instead:** Delta cursors. Each client tracks its last-synced server timestamp/cursor. Pushes send only the contents of the sync queue. Pulls request only records changed since the last cursor (`GET /sync?cursor=<timestamp>`). This keeps sync payloads small and fast.

### Anti-Pattern 5: Shared ORM Session Without Tenant Context

**What people do:** Create one global SQLAlchemy session or connection pool without setting the tenant variable per-request.

**Why it's wrong:** With connection pooling, a session created for Tenant A might be reused for Tenant B without the `app.current_company_id` variable being reset. This causes data leakage between tenants.

**Do this instead:** Use SQLAlchemy event listeners on session begin (`after_begin`) to set `SET LOCAL app.current_company_id`. `SET LOCAL` scopes the setting to the current transaction, not the connection — safe with any pooling mode. Verify this in integration tests with two active tenants.

## Integration Points

### External Services

| Service | Integration Pattern | Notes |
|---------|---------------------|-------|
| Google Maps / OpenRouteService | REST API from backend, cache results | Used to calculate travel time between job sites. Call at scheduling time, cache result by (origin, destination) pair with 24h TTL. Never call from Flutter directly (hides API key). |
| Push Notifications (FCM) | Backend sends on job status changes | Used to trigger background sync on client devices. Reduces polling frequency. Required for "client sees update instantly." |
| File Storage (S3-compatible) | Presigned URL from backend, direct upload from Flutter | Job photos uploaded directly from device to storage; backend only stores the URL. Avoids proxying large files through the API server. |

### Internal Boundaries

| Boundary | Communication | Notes |
|----------|---------------|-------|
| Flutter UI layer ↔ Domain layer | Riverpod providers; pure Dart interfaces | No direct DB or HTTP calls from UI. All data via use cases and providers. |
| Flutter Domain ↔ Data layer | Repository interfaces (dependency inversion) | Domain defines the interface; data layer implements it. Allows swapping storage or mocking in tests. |
| Flutter Data ↔ Local DB | Drift DAO methods + reactive streams | All local reads are streams. UI is always reactive to local state. |
| Flutter Data ↔ Sync Engine | `sync_queue` table in Drift DB | Repository writes to queue; sync engine reads from queue. They share the same SQLite DB but are decoupled. |
| FastAPI ↔ PostgreSQL | SQLAlchemy async sessions with RLS context | Tenant context set per transaction via event listener. |
| Scheduling Engine ↔ Maps API | Internal HTTP client with caching | Travel time is fetched by the backend; Flutter never calls maps APIs directly. |
| Admin ↔ Contractor ↔ Client views | Same Flutter codebase, role-gated routes | Riverpod providers expose role from auth token; router guards redirect unauthorized roles. |

## Build Order Implications

The component dependencies create a natural build order that the roadmap should follow:

```
1. Core Infrastructure (prerequisite for everything)
   PostgreSQL schema + RLS policies
   FastAPI project skeleton + tenant middleware
   Flutter project skeleton + Drift DB + Riverpod wiring

2. Multi-Tenant Data Layer (prerequisite for all features)
   Company, user, role models
   Tenant isolation verification tests
   Basic auth context (company_id in JWT even before full auth)

3. Offline Sync Engine (prerequisite for all mobile features)
   Sync queue table + transactional write pattern
   Background sync worker + connectivity detection
   Delta cursor sync protocol on backend
   Conflict resolution strategy

4. Scheduling Engine (can run parallel with sync, but needs data layer)
   Availability model + EXCLUDE USING GIST constraints
   Slot computation algorithm
   Travel time integration
   Conflict detection API endpoint

5. Job Lifecycle Features (need sync + scheduling)
   Job CRUD, status machine
   Photo upload (presigned URLs)
   Both job flows: client-request + company-assign

6. Role-Specific Views (need job lifecycle)
   Admin: team calendar, dispatch view
   Contractor: my jobs, availability management
   Client: job status portal

7. Notifications + Real-Time (last, enhances existing flows)
   FCM integration for sync triggers
   Job status push notifications to clients
```

**Critical path:** Core infra → Multi-tenant data → Offline sync → everything else. The sync engine must be designed before any features are built on top of it, because retrofitting offline-first onto online-first features is a rewrite, not a refactor.

## Sources

- Flutter offline-first patterns: [Flutter official docs — Offline-First](https://docs.flutter.dev/app-architecture/design-patterns/offline-first)
- Transactional outbox sync: [GeekyAnts Offline-First Blueprint](https://geekyants.com/blog/offline-first-flutter-implementation-blueprint-for-real-world-apps)
- Riverpod + Drift + PowerSync pattern: [Local-First Flutter with Riverpod, Drift, PowerSync](https://dinkomarinac.dev/blog/building-local-first-flutter-apps-with-riverpod-drift-and-powersync/)
- PostgreSQL RLS for multi-tenancy: [AWS — Multi-Tenant Data Isolation with PostgreSQL RLS](https://aws.amazon.com/blogs/database/multi-tenant-data-isolation-with-postgresql-row-level-security/)
- FastAPI multi-tenancy patterns: [FastAPI Multi-Tenant Architecture Patterns (2025)](https://medium.com/@koushiksathish3/multi-tenant-architecture-with-fastapi-design-patterns-and-pitfalls-aa3f9e75bf8c)
- FastAPI + SQLAlchemy + RLS: [fastapi-rowsecurity package](https://pypi.org/project/fastapi-rowsecurity/)
- PostgreSQL EXCLUDE USING GIST: [Exclusion Constraints in Postgres](https://java-jedi.medium.com/exclusion-constraints-b2cbd62b637a), [Double Booking Problem](https://betterstack.com/community/guides/databases/postgres-temporal-constraints/)
- Scheduling conflict detection: [Advanced Conflict Detection Algorithms](https://www.myshyft.com/blog/conflict-detection-algorithms/)
- Multi-tenancy guide 2025: [Bix-Tech Multi-Tenant Architecture Guide](https://bix-tech.com/multi-tenant-architecture-the-complete-guide-for-modern-saas-and-analytics-platforms-2/)
- Flutter clean architecture with Riverpod: [Flutter App Architecture with Riverpod](https://codewithandrea.com/articles/flutter-app-architecture-riverpod-introduction/)

---
*Architecture research for: ContractorHub — Contractor Management SaaS*
*Researched: 2026-03-04*
