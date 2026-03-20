# Phase 19: Project Data Model - Research

**Researched:** 2026-03-19
**Domain:** Multi-entity data model (PostgreSQL + SQLAlchemy + Drift + sync + CRUD UI)
**Confidence:** HIGH — all findings verified directly against existing codebase

---

<user_constraints>
## User Constraints (from CONTEXT.md)

### Locked Decisions

**Trade Scope Catalog**
- Trade types are a company-configurable list stored as a reference table (not free-text, not a fixed enum)
- Each trade catalog entry has: name + color (auto-assigned from palette, editable). No icon field.
- GC can pick from catalog OR type an ad-hoc trade when creating a trade scope on a project
- Ad-hoc trades trigger a "Save to catalog?" prompt — not auto-saved, not silently discarded
- One contractor per trade scope — if two electricians needed, create two scopes (e.g., "Electrical - Main", "Electrical - Low Voltage")
- Trade scopes can exist without an assigned contractor (contractor_id nullable) — GC assigns later
- Contractors have trade specialties on their profile (one or more). When GC assigns a scope, matching-trade contractors appear first, others still selectable
- Migrate existing data: Write a migration that reads existing free-text trade_type strings from Jobs and comma-separated trade_types from Companies, creates catalog entries from unique values, and links existing records

**Trade Scope Status**
- Trade scopes have their own status lifecycle: not_started → in_progress → complete → approved
- Status is computed from task completion % but can be manually overridden by the GC

**Project Status Lifecycle**
- 6 states: Draft → Planning → Active → On Hold → Complete → Archived
- Semi-automatic transitions: Draft→Planning when first trade scope added, Planning→Active when first task started. GC must manually complete/archive. On Hold is always manual.
- Any backward transition allowed — GC can revert (e.g., Complete → Active for rework). No state is final except as a business convention.
- Status history tracked in JSONB array (same pattern as Jobs): [{status, changed_at, changed_by}]
- No budget field on project — cost tracking lives in Phase 25 (Per-Trade Billing)
- Client linked via FK to existing clients/users table — reuses CRM data

**Tree View Navigation — Mobile**
- Drill-down pages: Project list → tap project → project detail with trade scope cards → tap scope → task list
- Each trade scope card shows: trade name (with color), contractor name, "3/8 tasks" count, thin colored progress bar
- New "Projects" bottom navigation tab — projects are a top-level concept in v3.0
- GC sees all company projects, contractors see only projects where they have an assigned trade scope
- Contractors see own scope in detail + read-only view of other scopes (cross-trade awareness)

**Tree View Navigation — Web**
- Sidebar tree + detail panel: Left sidebar shows collapsible project tree (Project → Scopes → Tasks), clicking any node shows its detail in the main content area (file-explorer pattern)
- Same role-based filtering: GC sees all, contractors see assigned projects only

**Task Data Model**
- Full construction task fields: title, description, estimated_hours, estimated_cost (AI-generated in Phase 21), sort_order, status (not_started/in_progress/complete/blocked), materials_needed (structured JSONB: [{name, quantity, unit}]), photo_required (bool), assigned_to (nullable user FK), due_date, priority, depends_on (JSONB array of task IDs)
- Flat list within trade scope — no sub-tasks, no nesting. Sort order for manual ordering, dependencies for sequencing.
- AI creates tasks (Phase 21), GC can manually edit and add tasks. Both paths coexist.
- Blocked status auto-computed from unresolved dependencies (Phase 20 engine enforces). No manual block.
- depends_on JSONB array on Task for intra-scope dependencies. Cross-trade dependencies are a separate edge table (Phase 20).
- Attachments designed for multi-photo/video: separate attachments table (not a single field), supporting multiple photos and video per task. Data model defined now, execution UI in Phase 22.

### Claude's Discretion
- Exact Drift schema version increment (currently version 6)
- Alembic migration numbering (currently at 0014)
- Trade color palette selection (material design colors, tailwind palette, etc.)
- Sync handler implementation details (pull/push ordering for new entities)
- Web sidebar tree component choice (build custom vs library)
- Project list sorting/filtering on mobile and web

### Deferred Ideas (OUT OF SCOPE)
- Video attachment support — data model supports it (attachment type field), but capture/playback UI is Phase 22
- AI cost estimation logic — Phase 21 (AI Intake), not Phase 19
- Cross-trade dependency validation and cycle detection — Phase 20 (Dependency Engine)
- Gantt timeline visualization — Phase 20
</user_constraints>

---

<phase_requirements>
## Phase Requirements

| ID | Description | Research Support |
|----|-------------|-----------------|
| PROJ-01 | GC can create a project with description, address, client, and target timeline | Backend: Project model + TenantScopedModel + CRUDRouter. Mobile: Projects Drift table + DAO + sync handler. Web: project creation form + API client. |
| PROJ-02 | GC can add trade scopes (plumbing, electrical, etc.) to a project with assigned contractors | Backend: TradeCatalog + TradeScope models + contractor specialty field on User. Mobile: TradeScope Drift table + DAO. Data migration 0015 from Jobs.trade_type and Companies.trade_types. |
| PROJ-03 | GC can view project hierarchy (Project → Trade Scopes → Tasks) in a tree view | Mobile: drill-down pages with new Projects bottom nav tab. Web: sidebar tree + detail panel. Task model + Drift table needed for hierarchy to render (even if AI-create is Phase 21, manual task creation belongs here). |
</phase_requirements>

---

## Summary

Phase 19 is a pure data model and basic CRUD UI phase — no AI, no complex business logic beyond status transitions. The codebase has highly evolved, reusable infrastructure: `TenantScopedModel`, `TenantScopedService`, `TenantScopedRepository`, `CRUDRouter`, and the `SyncHandler` pattern are all production-ready and must be followed exactly. Every new entity fits the same template.

The phase introduces five new backend tables: `projects`, `trade_catalog`, `trade_scopes`, `tasks`, and `task_attachments`. It also requires a data migration (0015) from the current free-text `Jobs.trade_type` and `Company.trade_types` array into normalized `trade_catalog` rows. On the mobile side, Drift schema goes from version 6 to version 7, adding five new tables with matching DAOs and sync handlers. On web, a new Projects section appears in the left sidebar.

The most nuanced design decisions — all already locked by user — are: trade catalog as a reference table (not enum), one contractor per scope, nullable contractor_id for unassigned scopes, JSONB status_history mirroring the Jobs pattern, and contractor specialties stored as a new join table on the User. The planner should structure work as: (1) backend models + migration + RLS, (2) mobile Drift schema + DAOs + sync, (3) backend CRUD endpoints, (4) mobile UI screens, (5) web UI, (6) E2E tests.

**Primary recommendation:** Follow the Jobs/TenantScopedModel template exactly for all five new entities. The migration 0015 is the highest-risk task — test data migration logic against a copy of production data before finalizing.

---

## Standard Stack

### Core
| Library | Version | Purpose | Why Standard |
|---------|---------|---------|--------------|
| SQLAlchemy (async) | existing | ORM for new models | All models in codebase use AsyncSession via get_db |
| Alembic | existing | DB migrations (next: 0015) | All schema changes are Alembic migrations |
| Pydantic v2 | existing | Request/response schemas | Project rule: all schemas inherit BaseResponseSchema |
| Drift | existing (schema v6→7) | Mobile offline DB | Established pattern; all tables follow jobs.dart template |
| Riverpod | existing | Mobile state management | AsyncNotifier for async builds; documented GetIt bridge |
| React + Next.js | existing | Web frontend | Existing web app; new Projects section fits same pattern |

### Supporting
| Library | Version | Purpose | When to Use |
|---------|---------|---------|-------------|
| JSONB (PostgreSQL) | built-in | status_history, materials_needed, depends_on | Flexible nested data where column count would explode |
| PostgreSQL RLS | built-in | Row Level Security per tenant | Every new table with company_id requires RLS policy |
| go_router | existing | Mobile routing | New project routes added to RouteNames and app_router.dart |

### Alternatives Considered
| Instead of | Could Use | Tradeoff |
|------------|-----------|----------|
| JSONB for materials_needed | Separate table | Table cleaner but adds JOIN complexity; JSONB established pattern in this codebase (tags, status_history) |
| Join table for contractor specialties | JSONB array on User | Join table is correct (queryable, indexable); JSONB would require unnesting for matching |
| Custom tree widget (web) | react-arborist or similar library | Library adds bundle size; given file-explorer pattern is straightforward, custom is fine per Claude's discretion |

**Installation:** No new packages required — all libraries are already in the project.

---

## Architecture Patterns

### Recommended Project Structure

**Backend:**
```
backend/app/features/projects/
├── models.py          # Project, TradeCatalog, TradeScope, Task, TaskAttachment
├── schemas.py         # Create/Update/Response schemas per model
├── repository.py      # ProjectRepository, TradeScopeRepository, etc.
├── service.py         # ProjectService with status transition logic
└── router.py          # CRUDRouter subclass per entity

backend/migrations/versions/
└── 0015_project_data_model.py   # All 5 tables + RLS + triggers + data migration
```

**Mobile:**
```
mobile/lib/core/database/tables/
├── projects.dart
├── trade_catalog.dart
├── trade_scopes.dart
├── tasks.dart
└── task_attachments.dart

mobile/lib/features/projects/
├── data/
│   ├── project_dao.dart
│   ├── trade_scope_dao.dart
│   ├── task_dao.dart
│   ├── project_sync_handler.dart
│   ├── trade_catalog_sync_handler.dart
│   ├── trade_scope_sync_handler.dart
│   └── task_sync_handler.dart
├── domain/
│   ├── project_entity.dart
│   ├── trade_scope_entity.dart
│   └── task_entity.dart
└── presentation/
    ├── screens/
    │   ├── project_list_screen.dart
    │   ├── project_detail_screen.dart
    │   ├── trade_scope_detail_screen.dart
    │   └── task_list_screen.dart
    ├── providers/
    │   └── project_providers.dart
    └── widgets/
        ├── trade_scope_card.dart
        └── project_status_badge.dart
```

**Web:**
```
web/src/app/(dashboard)/projects/
├── page.tsx                    # Project list (sidebar + detail panel layout)
├── [id]/
│   └── page.tsx               # Project detail
└── components/
    ├── ProjectSidebar.tsx      # Collapsible tree
    └── ProjectDetail.tsx       # Main content area
```

### Pattern 1: Backend Model Inheritance

All five new models inherit `TenantScopedModel` — which provides `id` (UUID), `company_id` (FK), `version` (int), and timestamp/soft-delete columns from `TimestampMixin`.

```python
# Source: backend/app/core/base_models.py + backend/app/features/jobs/models.py
from __future__ import annotations
import uuid
from sqlalchemy import CheckConstraint, Date, Text
from sqlalchemy.dialects.postgresql import JSONB, UUID
from sqlalchemy.orm import Mapped, mapped_column, relationship
from app.core.base_models import TenantScopedModel

class Project(TenantScopedModel):
    __tablename__ = "projects"

    name: Mapped[str] = mapped_column(Text, nullable=False)
    description: Mapped[str | None] = mapped_column(Text, nullable=True)
    address: Mapped[str | None] = mapped_column(Text, nullable=True)
    client_id: Mapped[uuid.UUID | None] = mapped_column(
        UUID(as_uuid=True), ForeignKey("users.id"), nullable=True
    )
    target_start_date: Mapped[date | None] = mapped_column(Date, nullable=True)
    target_end_date: Mapped[date | None] = mapped_column(Date, nullable=True)
    status: Mapped[str] = mapped_column(Text, nullable=False, server_default="draft")
    status_history: Mapped[list] = mapped_column(
        JSONB, nullable=False, server_default="'[]'::jsonb"
    )

    __table_args__ = (
        CheckConstraint(
            "status IN ('draft','planning','active','on_hold','complete','archived')",
            name="projects_status_check",
        ),
    )

    # All relationships MUST use lazy="raise" — CLAUDE.md N+1 prevention rule
    client: Mapped[User | None] = relationship("User", foreign_keys=[client_id], lazy="raise")
    trade_scopes: Mapped[list[TradeScope]] = relationship("TradeScope", back_populates="project", lazy="raise")
```

### Pattern 2: Alembic Migration with RLS (migration 0015)

Migration numbering: next is `0015_project_data_model.py`. The RLS loop pattern from 0011 applies directly.

```python
# Source: backend/migrations/versions/0011_business_operations_tables.py
# RLS enforcement pattern — identical for all 5 new tables

for table in ["projects", "trade_catalog", "trade_scopes", "tasks", "task_attachments"]:
    op.execute(text(f"ALTER TABLE {table} ENABLE ROW LEVEL SECURITY"))
    op.execute(text(f"""
        CREATE POLICY tenant_isolation ON {table}
            USING (
                company_id = NULLIF(current_setting('app.current_company_id', TRUE), '')::UUID
            )
    """))
    op.execute(text(f"ALTER TABLE {table} FORCE ROW LEVEL SECURITY"))
    op.execute(text(f"""
        CREATE TRIGGER set_updated_at
            BEFORE UPDATE ON {table}
            FOR EACH ROW EXECUTE FUNCTION set_updated_at()
    """))
```

### Pattern 3: Data Migration (trade_type normalization)

This migration reads free-text strings from `jobs.trade_type` and `companies.trade_types` (PostgreSQL ARRAY), deduplicates them, inserts into `trade_catalog`, then back-fills `trade_scope` references where applicable. This runs as part of migration 0015 after creating the new tables.

```python
# In migration 0015 upgrade() — after creating trade_catalog table
op.execute(text("""
    INSERT INTO trade_catalog (id, company_id, name, color, version, created_at, updated_at)
    SELECT
        gen_random_uuid(),
        company_id,
        trade_name,
        '#9E9E9E',   -- default grey; GCs can customize after migration
        1,
        now(),
        now()
    FROM (
        SELECT DISTINCT company_id, trade_type AS trade_name FROM jobs
        WHERE trade_type IS NOT NULL AND trade_type != ''
        UNION
        SELECT DISTINCT company_id, unnest(trade_types) AS trade_name FROM companies
        WHERE trade_types IS NOT NULL
    ) AS unique_trades
    ON CONFLICT DO NOTHING
"""))
```

### Pattern 4: Drift Table Definition

```dart
// Source: mobile/lib/core/database/tables/jobs.dart — follow exactly

class Projects extends Table {
  TextColumn get id => text().clientDefault(() => const Uuid().v4())();
  TextColumn get companyId => text().references(Companies, #id)();
  TextColumn get name => text()();
  TextColumn get description => text().nullable()();
  TextColumn get address => text().nullable()();
  TextColumn get clientId => text().nullable()();
  TextColumn get status => text().withDefault(const Constant('draft'))();
  TextColumn get statusHistory => text().withDefault(const Constant('[]'))();
  DateTimeColumn get targetStartDate => dateTime().nullable()();
  DateTimeColumn get targetEndDate => dateTime().nullable()();
  IntColumn get version => integer().withDefault(const Constant(1))();
  DateTimeColumn get createdAt => dateTime()();
  DateTimeColumn get updatedAt => dateTime()();
  DateTimeColumn get deletedAt => dateTime().nullable()();

  @override
  Set<Column> get primaryKey => {id};
}
```

### Pattern 5: Sync Handler

```dart
// Source: mobile/lib/core/sync/handlers/company_sync_handler.dart
class ProjectSyncHandler extends SyncHandler {
  final DioClient _dioClient;
  final AppDatabase _db;

  ProjectSyncHandler(this._dioClient, this._db);

  @override
  String get entityType => 'project';

  @override
  Future<void> push(SyncQueueData item) async {
    final payload = jsonDecode(item.payload) as Map<String, dynamic>;
    await _dioClient.pushWithIdempotency('/projects', payload, item.id);
  }

  @override
  Future<void> applyPulled(Map<String, dynamic> data) async {
    final companion = ProjectsCompanion(
      id: Value(data['id'] as String),
      companyId: Value(data['company_id'] as String),
      name: Value(data['name'] as String),
      // ... all fields
      deletedAt: Value(data['deleted_at'] != null
          ? DateTime.parse(data['deleted_at'] as String)
          : null),
    );
    await _db.into(_db.projects).insertOnConflictUpdate(companion);
  }
}
```

### Pattern 6: DAO with transactional sync queue writes

```dart
// Source: mobile/lib/features/users/data/user_dao.dart — transaction pattern
Future<void> insertProject(ProjectsCompanion entry) async {
  await db.transaction(() async {
    await into(projects).insert(entry);
    await into(syncQueue).insert(
      _buildQueueEntry(
        entityType: 'project',
        entityId: entry.id.value,
        operation: 'CREATE',
        payload: _projectPayload(entry),
      ),
    );
  });
}
```

### Pattern 7: Drift Schema Migration (version 6 → 7)

```dart
// Source: mobile/lib/core/database/app_database.dart — onUpgrade pattern
if (from < 7) {
  await m.createTable(tradeCatalog);
  await m.createTable(projects);
  await m.createTable(tradeScopes);
  await m.createTable(tasks);
  await m.createTable(taskAttachments);
}
```

### Pattern 8: Mobile Bottom Nav Extension

The `AppShell` uses a `StatefulShellRoute` with branches indexed 0–7. Adding a "Projects" tab means:
1. Add a new branch to the router (`StatefulShellBranchData` for `/projects`)
2. Add to `_allBranchRoutes` list in `AppShell`
3. Add `_TabItem` to `_buildTabs()` — visible to admin (GC) and contractor roles

```dart
// Source: mobile/lib/shared/widgets/app_shell.dart
// Projects tab — GC (admin) and contractor only; client role excluded
if (isAdmin || isContractor)
  const _TabItem(
    label: 'Projects',
    icon: Icons.folder_outlined,
    selectedIcon: Icons.folder,
    route: RouteNames.projects,
  ),
```

### Pattern 9: Contractor Trade Specialty — Join Table

The `User` model does not have a trade specialties field. A new `user_trade_specialties` join table is required (not a JSONB column — the context decision says contractors appear first when their specialty matches a scope, which requires a queryable structure).

```python
class UserTradeSpecialty(TenantScopedModel):
    __tablename__ = "user_trade_specialties"

    user_id: Mapped[uuid.UUID] = mapped_column(UUID(as_uuid=True), ForeignKey("users.id"), nullable=False)
    trade_catalog_id: Mapped[uuid.UUID] = mapped_column(UUID(as_uuid=True), ForeignKey("trade_catalog.id"), nullable=False)

    __table_args__ = (UniqueConstraint("user_id", "trade_catalog_id", name="uq_user_trade"),)
    user: Mapped[User] = relationship("User", lazy="raise")
    trade: Mapped[TradeCatalog] = relationship("TradeCatalog", lazy="raise")
```

### Anti-Patterns to Avoid
- **Querying inside a loop:** Never iterate trade scopes and query tasks per scope. Use `selectinload(Project.trade_scopes, TradeScope.tasks)` in one query.
- **JSONB for queryable data:** `depends_on` as JSONB is fine (intra-scope, single-entity); but `user_trade_specialties` must be a join table not a JSONB array on User.
- **Forgetting `lazy="raise"` on relationships:** Every relationship on every new model MUST have `lazy="raise"`. Accidental lazy loads will raise `InvalidRequestError` loudly.
- **Committing in service:** Do NOT call `db.commit()` in service methods — `get_db` handles it. Only `db.flush()` when IDs are needed before return.
- **Skipping RLS on any new table:** Every table with `company_id` needs `ENABLE ROW LEVEL SECURITY`, the `tenant_isolation` policy, and `FORCE ROW LEVEL SECURITY`. All five new tables + `user_trade_specialties`.
- **Using `pumpAndSettle()` in Drift stream widget tests:** Drift streams never settle. Use `pump()` instead (MEMORY.md documented pattern).
- **Hardcoded migration numbers:** Check the actual latest migration file before naming 0015 — confirmed latest is `0014_add_unique_email_constraint.py`.

---

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| Multi-tenant data isolation | Custom query filters | PostgreSQL RLS via TenantMiddleware + SET LOCAL | RLS enforced at DB level — even raw SQL queries are filtered |
| Optimistic concurrency | Custom timestamp comparison | `version` column on every entity | Pattern already in jobs; version mismatch raises 409 |
| Offline create with server ID | Client-side DB sequences | `clientDefault(() => const Uuid().v4())` in Drift | UUID generated client-side; idempotency-key deduplicates on server |
| Sync deduplication | Custom hash tracking | `Idempotency-Key` header + `insertOnConflictUpdate` | Already implemented in DioClient and all existing sync handlers |
| Eager loading for lists | N+1 per-row queries | `selectinload()` / `joinedload()` in repository | CLAUDE.md rule; `lazy="raise"` will make violations fail loudly |
| Status audit trail | Custom log table | JSONB `status_history` array on entity | Established pattern in `jobs`; avoids extra table and join |
| Soft delete | Hard delete | `deleted_at` nullable column + tombstone sync | Required for offline sync tombstone propagation across devices |

**Key insight:** The infrastructure is mature — every new entity is 95% configuration of existing patterns. The only genuinely new logic is the status transition service (semi-automatic Draft→Planning→Active triggers) and the data migration from free-text trade types.

---

## Common Pitfalls

### Pitfall 1: Forgetting `lazy="raise"` on any relationship
**What goes wrong:** SQLAlchemy raises `InvalidRequestError: 'TradeScope' object has been expired` at runtime, sometimes only under async context, and only when a relationship is accessed outside an eager-load.
**Why it happens:** Default lazy loading issues a SELECT for each accessed relationship attribute. Async sessions don't support implicit lazy loading.
**How to avoid:** Every relationship on every new model gets `lazy="raise"` without exception. Use `selectinload()` in repository methods for all list queries.
**Warning signs:** Tests pass but production hits `MissingGreenlet` or `InvalidRequestError` on nested object access.

### Pitfall 2: Drift schema version mismatch
**What goes wrong:** App crashes on upgrade if `onUpgrade` doesn't have the `from < 7` branch, or if a new table is added to `@DriftDatabase` but not created in `onUpgrade`.
**Why it happens:** Drift checks `schemaVersion` at open; if the on-disk version doesn't match, it calls `onUpgrade`. Missing branch = tables not created = DAO crashes.
**How to avoid:** Every table added to `@DriftDatabase(tables: [...])` must also be created in the `onUpgrade` `if (from < 7)` block. Increment `schemaVersion` from 6 to 7.
**Warning signs:** `SqliteException(1): no such table: projects` on first run after schema change.

### Pitfall 3: RLS not applied to `user_trade_specialties`
**What goes wrong:** Cross-tenant data leak — Company B can read Company A's contractor specialty assignments.
**Why it happens:** The table has `company_id` but migration forgets to `ENABLE ROW LEVEL SECURITY` on it.
**How to avoid:** The RLS loop in 0015 must include `user_trade_specialties` alongside the five primary tables.
**Warning signs:** Integration test with two companies can see each other's specialty data.

### Pitfall 4: Data migration creates duplicate trade catalog entries
**What goes wrong:** Two companies that both have "Plumbing" end up with separate `trade_catalog` rows — which is correct — but if the migration runs twice, it creates duplicates.
**Why it happens:** Alembic `upgrade()` should be idempotent but often isn't for data migrations.
**How to avoid:** Use `ON CONFLICT DO NOTHING` on the INSERT into `trade_catalog` (unique constraint on `company_id + name`). Add a `UniqueConstraint("company_id", "name")` to `trade_catalog`.
**Warning signs:** Running migration twice produces doubled rows.

### Pitfall 5: Semi-automatic status transitions not triggered by sync
**What goes wrong:** GC creates a trade scope via mobile while offline. Local Drift state shows Planning, but after sync the backend still shows Draft because the trigger logic only runs in the web UI.
**Why it happens:** The status transition logic (Draft→Planning on first scope) lives in the backend service, but the mobile client has already advanced its local state. On sync, the backend response overwrites local state with the old status.
**How to avoid:** The backend `ProjectService.create_trade_scope()` must check if the project is in Draft and advance it to Planning as part of that operation — not as a separate trigger. Then the sync pull response will return the updated project with status=planning.
**Warning signs:** Mobile shows Planning; after sync pull, project reverts to Draft.

### Pitfall 6: `pumpAndSettle()` hangs in widget tests
**What goes wrong:** Widget tests using Drift stream providers never complete `pumpAndSettle()` — the test hangs indefinitely.
**Why it happens:** Drift's reactive streams emit continuously; `pumpAndSettle()` waits for all microtasks to settle, which never happens with live streams.
**How to avoid:** Use `pump()` (single frame advance) instead of `pumpAndSettle()` for all widget tests that observe Drift streams. This is a documented pattern in MEMORY.md.
**Warning signs:** Widget test times out after 5 seconds.

### Pitfall 7: Circular import in SQLAlchemy models
**What goes wrong:** `ImportError: cannot import name 'Task' from partially initialized module` when `TradeScope` and `Task` mutually reference each other.
**Why it happens:** Python circular imports occur when models.py files import from each other at module load time.
**How to avoid:** Follow the established pattern from `backend/app/features/jobs/models.py`: use `from __future__ import annotations` at top of file, wrap cross-feature imports in `if TYPE_CHECKING:` block.
**Warning signs:** ImportError on module load; works in isolation but fails when both models are imported.

---

## Code Examples

### Full Table Schema (PostgreSQL migration 0015)

```python
# Source: backend/migrations/versions/0011_business_operations_tables.py pattern

op.execute(text("""
    CREATE TABLE trade_catalog (
        id          UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
        company_id  UUID        NOT NULL REFERENCES companies(id),
        name        TEXT        NOT NULL,
        color       TEXT        NOT NULL DEFAULT '#9E9E9E',
        version     INTEGER     NOT NULL DEFAULT 1,
        created_at  TIMESTAMPTZ NOT NULL DEFAULT now(),
        updated_at  TIMESTAMPTZ NOT NULL DEFAULT now(),
        deleted_at  TIMESTAMPTZ,
        UNIQUE (company_id, name)
    )
"""))

op.execute(text("""
    CREATE TABLE projects (
        id                UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
        company_id        UUID        NOT NULL REFERENCES companies(id),
        name              TEXT        NOT NULL,
        description       TEXT,
        address           TEXT,
        client_id         UUID        REFERENCES users(id),
        target_start_date DATE,
        target_end_date   DATE,
        status            TEXT        NOT NULL DEFAULT 'draft'
                                      CHECK (status IN (
                                        'draft','planning','active','on_hold','complete','archived'
                                      )),
        status_history    JSONB       NOT NULL DEFAULT '[]'::jsonb,
        version           INTEGER     NOT NULL DEFAULT 1,
        created_at        TIMESTAMPTZ NOT NULL DEFAULT now(),
        updated_at        TIMESTAMPTZ NOT NULL DEFAULT now(),
        deleted_at        TIMESTAMPTZ
    )
"""))

op.execute(text("""
    CREATE TABLE trade_scopes (
        id               UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
        company_id       UUID        NOT NULL REFERENCES companies(id),
        project_id       UUID        NOT NULL REFERENCES projects(id) ON DELETE CASCADE,
        trade_catalog_id UUID        REFERENCES trade_catalog(id),
        trade_name       TEXT        NOT NULL,
        trade_color      TEXT        NOT NULL DEFAULT '#9E9E9E',
        contractor_id    UUID        REFERENCES users(id),
        status           TEXT        NOT NULL DEFAULT 'not_started'
                                     CHECK (status IN (
                                       'not_started','in_progress','complete','approved'
                                     )),
        status_override  BOOLEAN     NOT NULL DEFAULT false,
        sort_order       INTEGER     NOT NULL DEFAULT 0,
        version          INTEGER     NOT NULL DEFAULT 1,
        created_at       TIMESTAMPTZ NOT NULL DEFAULT now(),
        updated_at       TIMESTAMPTZ NOT NULL DEFAULT now(),
        deleted_at       TIMESTAMPTZ
    )
"""))

op.execute(text("""
    CREATE TABLE tasks (
        id               UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
        company_id       UUID        NOT NULL REFERENCES companies(id),
        trade_scope_id   UUID        NOT NULL REFERENCES trade_scopes(id) ON DELETE CASCADE,
        title            TEXT        NOT NULL,
        description      TEXT,
        status           TEXT        NOT NULL DEFAULT 'not_started'
                                     CHECK (status IN (
                                       'not_started','in_progress','complete','blocked'
                                     )),
        sort_order       INTEGER     NOT NULL DEFAULT 0,
        priority         TEXT        NOT NULL DEFAULT 'medium'
                                     CHECK (priority IN ('low','medium','high','urgent')),
        estimated_hours  NUMERIC(6,2),
        estimated_cost   NUMERIC(10,2),
        due_date         DATE,
        photo_required   BOOLEAN     NOT NULL DEFAULT false,
        assigned_to      UUID        REFERENCES users(id),
        materials_needed JSONB       NOT NULL DEFAULT '[]'::jsonb,
        depends_on       JSONB       NOT NULL DEFAULT '[]'::jsonb,
        version          INTEGER     NOT NULL DEFAULT 1,
        created_at       TIMESTAMPTZ NOT NULL DEFAULT now(),
        updated_at       TIMESTAMPTZ NOT NULL DEFAULT now(),
        deleted_at       TIMESTAMPTZ
    )
"""))

op.execute(text("""
    CREATE TABLE task_attachments (
        id              UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
        company_id      UUID        NOT NULL REFERENCES companies(id),
        task_id         UUID        NOT NULL REFERENCES tasks(id) ON DELETE CASCADE,
        attachment_type TEXT        NOT NULL
                                    CHECK (attachment_type IN ('photo','video','document')),
        remote_url      TEXT,
        local_path      TEXT,
        caption         TEXT,
        sort_order      INTEGER     NOT NULL DEFAULT 0,
        version         INTEGER     NOT NULL DEFAULT 1,
        created_at      TIMESTAMPTZ NOT NULL DEFAULT now(),
        updated_at      TIMESTAMPTZ NOT NULL DEFAULT now(),
        deleted_at      TIMESTAMPTZ
    )
"""))

op.execute(text("""
    CREATE TABLE user_trade_specialties (
        id              UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
        company_id      UUID        NOT NULL REFERENCES companies(id),
        user_id         UUID        NOT NULL REFERENCES users(id),
        trade_catalog_id UUID       NOT NULL REFERENCES trade_catalog(id),
        version         INTEGER     NOT NULL DEFAULT 1,
        created_at      TIMESTAMPTZ NOT NULL DEFAULT now(),
        updated_at      TIMESTAMPTZ NOT NULL DEFAULT now(),
        deleted_at      TIMESTAMPTZ,
        UNIQUE (user_id, trade_catalog_id)
    )
"""))
```

### Project Status Transition Service Logic

```python
# Source: pattern from backend/app/features/jobs/ service layer

async def create_trade_scope(self, project_id: uuid.UUID, data: TradeScopeCreate) -> TradeScope:
    """Create a trade scope and auto-advance project from Draft to Planning."""
    project = await self.repository.get_by_id(project_id)
    scope = TradeScope(project_id=project_id, company_id=project.company_id, **data.model_dump())
    scope = await self.scope_repository.create(scope)

    # Semi-automatic: Draft → Planning on first scope added
    if project.status == "draft":
        project.status = "planning"
        entry = {"status": "planning", "changed_at": datetime.now(UTC).isoformat(), "changed_by": str(current_user_id)}
        project.status_history = [*project.status_history, entry]
        await self.db.flush()

    return scope
```

### Mobile Riverpod Provider (AsyncNotifier pattern)

```dart
// Source: mobile/lib/features/jobs/presentation/providers/job_providers.dart
class ProjectListNotifier extends AsyncNotifier<List<ProjectEntity>> {
  @override
  Future<List<ProjectEntity>> build() async {
    final authState = ref.watch(authNotifierProvider);
    if (authState is! AuthAuthenticated) return [];
    final dao = ref.watch(projectDaoProvider);
    // Return stream subscription for offline-first reactivity
    final stream = dao.watchProjectsByCompany(authState.companyId);
    ref.listen(stream.provider, (_, __) => ref.invalidateSelf());
    return stream.first;
  }
}
```

### Indexes for FK lookups

```python
# Source: backend/migrations/versions/0011 index pattern
op.execute(text("CREATE INDEX idx_projects_company_id ON projects (company_id)"))
op.execute(text("CREATE INDEX idx_projects_client_id ON projects (client_id)"))
op.execute(text("CREATE INDEX idx_trade_scopes_project_id ON trade_scopes (project_id)"))
op.execute(text("CREATE INDEX idx_trade_scopes_contractor_id ON trade_scopes (contractor_id)"))
op.execute(text("CREATE INDEX idx_tasks_trade_scope_id ON tasks (trade_scope_id)"))
op.execute(text("CREATE INDEX idx_task_attachments_task_id ON task_attachments (task_id)"))
op.execute(text("CREATE INDEX idx_user_trade_specialties_user_id ON user_trade_specialties (user_id)"))
op.execute(text("CREATE INDEX idx_trade_catalog_company_id ON trade_catalog (company_id)"))
```

---

## State of the Art

| Old Approach | Current Approach | When Changed | Impact |
|--------------|------------------|--------------|--------|
| Free-text `trade_type` on Job | Normalized `trade_catalog` reference table | Phase 19 (this phase) | Enables company-specific trade catalog, color coding, contractor specialty matching |
| Jobs entity for work tracking | Projects → Trade Scopes → Tasks hierarchy | Phase 19 (v3.0 start) | Multi-trade coordination; existing Jobs domain continues for v2.0 work |
| Attachment linked to JobNote | Attachment linked to Task (separate table) | Phase 19 | Photo/video per task for progress documentation |

**Deprecated/outdated:**
- `Jobs.trade_type` free-text: remains on existing jobs for backward compatibility; new work uses `trade_scopes.trade_catalog_id` + `trade_scopes.trade_name`.
- `Companies.trade_types` PostgreSQL ARRAY: after migration 0015 seeds `trade_catalog`, this column is superseded but NOT dropped (backward compat).

---

## Open Questions

1. **Contractor specialty filtering in the assignment UI**
   - What we know: When GC assigns a contractor to a scope, contractors with matching specialties appear first.
   - What's unclear: Is this a server-side sorted list endpoint, or client-side sorting in the UI?
   - Recommendation: Server-side ordering is cleaner — the `/contractors?trade_catalog_id=X` endpoint returns matching contractors first, others second. This avoids loading all contractors on mobile.

2. **Trade scope color vs. catalog color**
   - What we know: Trade scopes have `trade_color` field; catalog has `color` field.
   - What's unclear: When GC uses a catalog trade, does the scope inherit the catalog color? Is it independently editable?
   - Recommendation: On scope creation, copy catalog color as default; allow independent override on the scope. Both `trade_catalog.color` and `trade_scopes.trade_color` fields exist.

3. **Task attachment schema vs. existing Attachment model**
   - What we know: Existing `Attachments` table is linked to `JobNote`. New `task_attachments` is linked to `Task`.
   - What's unclear: Should this be the same table with a nullable `note_id` and nullable `task_id`, or a separate table?
   - Recommendation: Separate `task_attachments` table (cleaner, independent lifecycle, different attachment_type CHECK — includes 'video' which existing table does not).

---

## Validation Architecture

### Test Framework
| Property | Value |
|----------|-------|
| Backend framework | pytest + ASGI client (existing conftest.py) |
| Mobile framework | flutter_test + Drift in-memory DB |
| Config file | `backend/tests/conftest.py` (existing) |
| Quick run (backend) | `cd backend && uv run python -m pytest tests/test_phase_19_e2e.py -x` |
| Full suite (backend) | `cd backend && uv run python -m pytest` |
| Quick run (mobile) | `cd mobile && flutter test test/e2e/phase_19_project_data_model_e2e_test.dart` |
| Full suite (mobile) | `cd mobile && flutter test` |

### Phase Requirements → Test Map

| Req ID | Behavior | Test Type | Automated Command | File Exists? |
|--------|----------|-----------|-------------------|--------------|
| PROJ-01 | GC creates project with name/address/client/dates | integration | `uv run python -m pytest tests/test_phase_19_e2e.py::test_gc_creates_project -x` | Wave 0 |
| PROJ-01 | Project appears in GC project list | integration | `uv run python -m pytest tests/test_phase_19_e2e.py::test_project_list_returns_created -x` | Wave 0 |
| PROJ-01 | Cross-tenant isolation: Company B cannot read Company A's project | integration | `uv run python -m pytest tests/test_phase_19_e2e.py::test_rls_isolation -x` | Wave 0 |
| PROJ-02 | GC adds trade scope from catalog | integration | `uv run python -m pytest tests/test_phase_19_e2e.py::test_add_trade_scope_from_catalog -x` | Wave 0 |
| PROJ-02 | GC adds ad-hoc trade (no catalog match) | integration | `uv run python -m pytest tests/test_phase_19_e2e.py::test_add_adhoc_trade_scope -x` | Wave 0 |
| PROJ-02 | Assigning contractor to scope advances status | integration | `uv run python -m pytest tests/test_phase_19_e2e.py::test_contractor_assignment -x` | Wave 0 |
| PROJ-02 | Project auto-advances Draft→Planning on first scope | integration | `uv run python -m pytest tests/test_phase_19_e2e.py::test_status_auto_advance_planning -x` | Wave 0 |
| PROJ-03 | Mobile: project list screen renders with Drift data | E2E widget | `flutter test test/e2e/phase_19_project_data_model_e2e_test.dart -t "project_list"` | Wave 0 |
| PROJ-03 | Mobile: tap project shows trade scope cards | E2E widget | `flutter test test/e2e/phase_19_project_data_model_e2e_test.dart -t "project_detail"` | Wave 0 |
| PROJ-03 | Mobile: tap scope shows task list | E2E widget | `flutter test test/e2e/phase_19_project_data_model_e2e_test.dart -t "scope_detail"` | Wave 0 |
| PROJ-03 | Web: sidebar tree renders project hierarchy | unit/integration | `cd web && npm test -- projects` | Wave 0 |
| All | Data migration seeds trade_catalog from Jobs + Companies | integration | `uv run python -m pytest tests/test_phase_19_e2e.py::test_data_migration -x` | Wave 0 |

### Sampling Rate
- **Per task commit:** `uv run python -m pytest tests/test_phase_19_e2e.py -x` (backend) or `flutter test test/e2e/phase_19_project_data_model_e2e_test.dart` (mobile)
- **Per wave merge:** Full suite: `uv run python -m pytest` + `flutter test`
- **Phase gate:** Full suite green before `/gsd:verify-work`

### Wave 0 Gaps
- [ ] `backend/tests/test_phase_19_e2e.py` — covers all PROJ-01, PROJ-02 backend behaviors + RLS isolation
- [ ] `mobile/test/e2e/phase_19_project_data_model_e2e_test.dart` — covers PROJ-03 mobile tree view
- [ ] No new framework install needed — pytest and flutter_test already configured

---

## Sources

### Primary (HIGH confidence)
- `backend/app/core/base_models.py` — TenantScopedModel, BaseEntityModel verified directly
- `backend/app/core/base_service.py` — TenantScopedService pattern verified
- `backend/app/core/base_repository.py` — TenantScopedRepository with eager_load_options verified
- `backend/app/core/base_router.py` — CRUDRouter mixin verified
- `backend/app/core/base_schemas.py` — BaseResponseSchema, TenantResponseSchema verified
- `backend/app/core/tenant.py` — RLS via SET LOCAL, after_begin event verified
- `backend/app/features/jobs/models.py` — Job status machine, JSONB patterns, lazy="raise" verified
- `backend/app/features/jobs/schemas.py` — StrEnum, StatusHistoryEntry, Create/Update/Response pattern verified
- `backend/migrations/versions/0011_business_operations_tables.py` — RLS loop, trigger creation, downgrade pattern verified
- `backend/migrations/versions/0014_add_unique_email_constraint.py` — Confirmed latest migration is 0014
- `mobile/lib/core/database/app_database.dart` — Schema version 6, onUpgrade pattern verified
- `mobile/lib/core/database/tables/jobs.dart` — Drift table definition pattern verified
- `mobile/lib/core/database/tables/attachments.dart` — attachment_type, uploadStatus, localPath pattern verified
- `mobile/lib/core/sync/sync_handler.dart` — SyncHandler abstract interface verified
- `mobile/lib/core/sync/handlers/company_sync_handler.dart` — insertOnConflictUpdate, idempotency pattern verified
- `mobile/lib/core/sync/sync_registry.dart` — Handler registration pattern verified
- `mobile/lib/features/users/data/user_dao.dart` — Transaction + sync queue atomic write pattern verified
- `mobile/lib/shared/widgets/app_shell.dart` — Bottom nav tab structure, StatefulShellRoute branches verified
- `mobile/lib/core/routing/route_names.dart` — RouteNames constants pattern verified
- `backend/app/features/users/models.py` — User model (no trade specialty field confirmed)
- `backend/app/features/companies/models.py` — Company.trade_types is PostgreSQL ARRAY(String) confirmed

### Secondary (MEDIUM confidence)
- `mobile/lib/core/routing/app_router.dart` — GoRouter/StatefulShellRoute/branch structure (read first 180 lines, pattern clear)

### Tertiary (LOW confidence)
- None — all critical claims verified directly against codebase

---

## Metadata

**Confidence breakdown:**
- Standard stack: HIGH — all verified in existing code
- Architecture: HIGH — patterns extracted directly from jobs/quotes feature templates
- Pitfalls: HIGH — derived from documented rules (CLAUDE.md, MEMORY.md) and code inspection
- Data migration: MEDIUM — logic correct but SQL needs testing against real data distribution

**Research date:** 2026-03-19
**Valid until:** 2026-06-19 (stable — no external library changes; only internal codebase patterns)
