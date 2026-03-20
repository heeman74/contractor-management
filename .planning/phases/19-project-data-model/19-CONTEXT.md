# Phase 19: Project Data Model - Context

**Gathered:** 2026-03-19
**Status:** Ready for planning

<domain>
## Phase Boundary

GCs can create multi-trade projects, assign contractors per trade, and view the full project hierarchy (Project → Trade Scopes → Tasks) on mobile and web. Establishes the data layer (PostgreSQL + Drift + sync) that every other v3.0 feature depends on. Includes backend models, migrations with RLS, Drift tables, sync handlers, and basic CRUD UI on both platforms.

</domain>

<decisions>
## Implementation Decisions

### Trade Scope Catalog
- Trade types are a **company-configurable list** stored as a reference table (not free-text, not a fixed enum)
- Each trade catalog entry has: **name + color** (auto-assigned from palette, editable). No icon field.
- GC can **pick from catalog OR type an ad-hoc trade** when creating a trade scope on a project
- Ad-hoc trades trigger a **"Save to catalog?" prompt** — not auto-saved, not silently discarded
- **One contractor per trade scope** — if two electricians needed, create two scopes (e.g., "Electrical - Main", "Electrical - Low Voltage")
- Trade scopes can exist **without an assigned contractor** (contractor_id nullable) — GC assigns later
- **Contractors have trade specialties** on their profile (one or more). When GC assigns a scope, matching-trade contractors appear first, others still selectable
- **Migrate existing data**: Write a migration that reads existing free-text trade_type strings from Jobs and comma-separated trade_types from Companies, creates catalog entries from unique values, and links existing records

### Trade Scope Status
- Trade scopes have their **own status lifecycle**: not_started → in_progress → complete → approved
- Status is computed from task completion % but can be **manually overridden** by the GC

### Project Status Lifecycle
- **6 states**: Draft → Planning → Active → On Hold → Complete → Archived
- **Semi-automatic transitions**: Draft→Planning when first trade scope added, Planning→Active when first task started. GC must manually complete/archive. On Hold is always manual.
- **Any backward transition allowed** — GC can revert (e.g., Complete → Active for rework). No state is final except as a business convention.
- **Status history tracked** in JSONB array (same pattern as Jobs): [{status, changed_at, changed_by}]
- **No budget field** on project — cost tracking lives in Phase 25 (Per-Trade Billing)
- **Client linked via FK** to existing clients/users table — reuses CRM data

### Tree View Navigation — Mobile
- **Drill-down pages**: Project list → tap project → project detail with trade scope cards → tap scope → task list
- Each trade scope card shows: **trade name (with color), contractor name, "3/8 tasks" count, thin colored progress bar**
- **New "Projects" bottom navigation tab** — projects are a top-level concept in v3.0
- **GC sees all company projects**, contractors see only projects where they have an assigned trade scope
- **Contractors see own scope in detail + read-only view of other scopes** (cross-trade awareness)

### Tree View Navigation — Web
- **Sidebar tree + detail panel**: Left sidebar shows collapsible project tree (Project → Scopes → Tasks), clicking any node shows its detail in the main content area (file-explorer pattern)
- Same role-based filtering: GC sees all, contractors see assigned projects only

### Task Data Model
- **Full construction task fields**: title, description, estimated_hours, estimated_cost (AI-generated in Phase 21), sort_order, status (not_started/in_progress/complete/blocked), materials_needed (structured JSONB: [{name, quantity, unit}]), photo_required (bool), assigned_to (nullable user FK), due_date, priority, depends_on (JSONB array of task IDs)
- **Flat list within trade scope** — no sub-tasks, no nesting. Sort order for manual ordering, dependencies for sequencing.
- **AI creates tasks** (Phase 21), GC can manually edit and add tasks. Both paths coexist.
- **Blocked status auto-computed** from unresolved dependencies (Phase 20 engine enforces). No manual block.
- **depends_on JSONB array** on Task for intra-scope dependencies. Cross-trade dependencies are a separate edge table (Phase 20).
- **Attachments designed for multi-photo/video**: separate attachments table (not a single field), supporting multiple photos and video per task. Data model defined now, execution UI in Phase 22.

### Claude's Discretion
- Exact Drift schema version increment (currently version 6)
- Alembic migration numbering (currently at 0014)
- Trade color palette selection (material design colors, tailwind palette, etc.)
- Sync handler implementation details (pull/push ordering for new entities)
- Web sidebar tree component choice (build custom vs library)
- Project list sorting/filtering on mobile and web

</decisions>

<canonical_refs>
## Canonical References

**Downstream agents MUST read these before planning or implementing.**

### Data Model Patterns
- `backend/app/core/base_models.py` — BaseEntityModel, TenantScopedModel inheritance pattern
- `backend/app/core/base_service.py` — BaseService, TenantScopedService patterns
- `backend/app/core/base_repository.py` — BaseRepository, TenantScopedRepository with eager_load_options
- `backend/app/core/base_router.py` — CRUDRouter mixin pattern
- `backend/app/core/base_schemas.py` — BaseResponseSchema, TenantResponseSchema
- `backend/app/core/tenant.py` — RLS setup via SET LOCAL app.current_company_id

### Existing Feature Examples (follow these patterns)
- `backend/app/features/jobs/models.py` — Complex tenant-scoped model with relationships, status machine, JSONB fields
- `backend/app/features/jobs/schemas.py` — Create/Update/Response schema pattern
- `backend/app/features/companies/service.py` — Idempotent create pattern for sync
- `backend/migrations/versions/0011_business_operations_tables.py` — Migration with RLS policies, triggers, check constraints

### Mobile Patterns
- `mobile/lib/core/database/app_database.dart` — Drift schema (version 6), table/DAO registration, migration strategy
- `mobile/lib/core/database/tables/jobs.dart` — Drift table definition pattern (UUID PK, companyId FK, soft-delete, version)
- `mobile/lib/features/users/data/user_dao.dart` — DAO pattern with watch streams + transactional mutations
- `mobile/lib/core/sync/sync_handler.dart` — Abstract SyncHandler (push/applyPulled)
- `mobile/lib/core/sync/handlers/company_sync_handler.dart` — Concrete sync handler example
- `mobile/lib/core/sync/sync_registry.dart` — Handler registration pattern

### Web Patterns
- `web/src/types/api.ts` — TypeScript interface pattern for API responses

### Project Context
- `.planning/REQUIREMENTS.md` — PROJ-01, PROJ-02, PROJ-03 requirements
- `.planning/ROADMAP.md` — Phase 19 success criteria and dependency chain
- `.planning/STATE.md` — Prior decisions on hierarchy, dependency storage, architecture

</canonical_refs>

<code_context>
## Existing Code Insights

### Reusable Assets
- `TenantScopedModel` — All new project/scope/task models inherit from this
- `CRUDRouter` mixin — Auto-generates REST endpoints for new entities
- `TenantScopedService` / `TenantScopedRepository` — Standard CRUD with tenant isolation
- `SyncHandler` abstract class — Template for new entity sync handlers
- `StatusBadge` component (web) — Already supports color-coded status display
- Existing attachments table in Drift — May need extending for task attachments

### Established Patterns
- UUID primary keys with clientDefault for offline creation
- Soft-delete via deletedAt nullable column
- Version column for optimistic concurrency
- JSONB for flexible nested data (status_history, tags, materials)
- Idempotency-Key header for sync deduplication
- `lazy="raise"` on all SQLAlchemy relationships (N+1 prevention)

### Integration Points
- Mobile bottom navigation — new "Projects" tab alongside existing tabs
- Web sidebar — new "Projects" section in the global navigation
- Existing users table — contractor trade specialties need a new field or join table
- Existing companies table — trade catalog as new related table
- SyncRegistry — register new handlers for Project, TradeScope, Task entities
- GoRouter — new routes for project list, detail, scope detail, task list

</code_context>

<specifics>
## Specific Ideas

- AI generates tasks in Phase 21, but GC should be able to manually edit and add tasks too — both creation paths coexist
- AI will generate cost estimates using project location and detailed prompts — the estimated_cost field on tasks stores these AI-generated values
- Multi-photo and video support for documenting current conditions on tasks — design the attachments schema to support this from day one (separate table, not a JSONB blob)
- Trade scope cards on mobile should feel information-dense but clean: trade color, contractor name, progress bar, task count — similar to the existing job cards pattern

</specifics>

<deferred>
## Deferred Ideas

- Video attachment support — data model supports it (attachment type field), but capture/playback UI is Phase 22
- AI cost estimation logic — Phase 21 (AI Intake), not Phase 19
- Cross-trade dependency validation and cycle detection — Phase 20 (Dependency Engine)
- Gantt timeline visualization — Phase 20

</deferred>

---

*Phase: 19-project-data-model*
*Context gathered: 2026-03-19*
