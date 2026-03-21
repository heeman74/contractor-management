# Phase 20: Dependency Engine - Context

**Gathered:** 2026-03-21
**Status:** Ready for planning

<domain>
## Phase Boundary

Cross-trade dependency graph with cycle detection, topological sort, and Gantt timeline view. GCs can define task-to-task dependencies (all four types: FS, SS, FF, SE) with lag/lead time, the system enforces them with hard blocking, detects cycles at creation time, and visualizes the full project timeline on both web and mobile with interactive Gantt charts showing trade swim lanes, dependency arrows, progress bars, and conflict warnings.

</domain>

<decisions>
## Implementation Decisions

### Dependency Modeling
- **All four dependency types** supported: Finish-to-Start, Start-to-Start, Finish-to-Finish, Start-to-End
- **Task-to-task granularity** for cross-trade dependencies (not scope-to-scope)
- **Unified edge table** — migrate intra-scope `depends_on` JSONB into a single `TaskDependency` edge table. Remove `depends_on` JSONB from Task model. Single source of truth for all dependencies (intra-scope and cross-scope)
- **Lag/lead time supported** — each dependency link has an optional lag field (positive = delay in days, negative = overlap/lead)
- **Hard block enforcement** — tasks with unmet dependencies cannot be started. Status stays 'blocked', start button disabled. No override mechanism
- **Sync to Drift** — TaskDependency edges sync to mobile like other entities. Contractors see blocked status offline

### Gantt Timeline View
- **Both platforms** — full interactive Gantt on web AND mobile
- **Full interactive** — drag bars to reschedule, drag-connect to create dependencies, click to edit task details, zoom in/out (MS Project-like on web)
- **Swim lanes by trade** — each trade scope gets its own horizontal lane colored by trade. Tasks within each lane are sequential/stacked. Dependency arrows cross lanes
- **Progress visualization** — filled progress bars showing completion %, status colors (green = on track, yellow = at risk/behind schedule, red = blocked), today line as vertical marker
- **Dependency creation via drag-connect** on the Gantt chart (visual arrow drawing from one task bar to another). Mobile needs equivalent interaction for the full Gantt

### Conflict Detection (AI-06)
- **Location + date overlap** defines a conflict — two tasks from different trades scheduled on the same date AND assigned to the same project zone/area
- **Project-level zone list** — GC defines zones for the project (Kitchen, Master Bath, Garage, etc.). Tasks pick from this list. Consistent naming enables reliable conflict matching
- **Warning with details** — show prominent warning: "Electrical and Plumbing overlap in Kitchen on Mar 25". GC decides whether to reschedule or allow. Not a hard block
- **Surfaced everywhere** — conflict indicators on Gantt chart (overlapping bars highlighted), conflict badge on task detail page, and conflict count on project overview card

### Cycle Prevention UX
- **Detection at creation time** — validate every new dependency link before saving. Reject immediately if it creates a cycle. Cycles never exist in the system
- **Visual cycle path on Gantt** — highlight the cycle path with red arrows on the Gantt chart showing exactly which links cause the loop
- **Suggest removal** — highlight the newly attempted link as the one causing the cycle and suggest removing it
- **Mobile cycle errors** — text dialog showing the cycle as a readable chain: "Framing -> Electrical -> Plumbing -> Framing" with tappable task names to navigate

### Claude's Discretion
- Gantt chart library selection (web and mobile)
- Topological sort algorithm choice
- Cycle detection algorithm choice (DFS, Kahn's, etc.)
- TaskDependency edge table schema details (indexes, constraints)
- Zone list UI design (modal vs inline)
- Gantt chart zoom levels and time scale options
- Mobile Gantt interaction patterns (pinch-to-zoom, horizontal scroll)

</decisions>

<canonical_refs>
## Canonical References

**Downstream agents MUST read these before planning or implementing.**

### Data Model (Phase 19 foundation)
- `backend/app/features/projects/models.py` — Project, TradeScope, Task models with `depends_on` JSONB (to be migrated to edge table)
- `backend/app/features/projects/schemas.py` — Existing create/update/response schemas for project entities
- `backend/app/features/projects/service.py` — ProjectService, TradeScopeService, TaskService
- `backend/app/features/projects/repository.py` — ProjectRepository, TradeScopeRepository, TaskRepository
- `backend/app/features/projects/router.py` — Existing REST endpoints for project entities

### OOP Architecture (must follow)
- `backend/app/core/base_models.py` — BaseEntityModel, TenantScopedModel inheritance
- `backend/app/core/base_service.py` — BaseService, TenantScopedService patterns
- `backend/app/core/base_repository.py` — BaseRepository, TenantScopedRepository
- `backend/app/core/base_router.py` — CRUDRouter mixin
- `backend/app/core/base_schemas.py` — BaseResponseSchema

### Mobile (Drift + sync)
- `mobile/lib/core/database/tables/tasks.dart` — ProjectTasks table with `dependsOn` field (to be migrated)
- `mobile/lib/features/projects/data/task_dao.dart` — Task DAO with sync queue integration
- `mobile/lib/core/sync/sync_handler.dart` — Abstract SyncHandler for new TaskDependency sync
- `mobile/lib/core/sync/sync_registry.dart` — Handler registration

### Web (existing project UI)
- `web/src/app/(dashboard)/projects/components/ProjectTree.tsx` — Expandable project hierarchy tree
- `web/src/types/projects.ts` — TypeScript interfaces for project API responses

### Requirements
- `.planning/REQUIREMENTS.md` — PROJ-04 (cross-trade dependencies), PROJ-05 (Gantt chart), AI-06 (conflict detection)
- `.planning/ROADMAP.md` — Phase 20 success criteria

</canonical_refs>

<code_context>
## Existing Code Insights

### Reusable Assets
- `Task.depends_on` JSONB — existing intra-scope dependency data to migrate into edge table
- `Task.status` — already has 'blocked' value, auto-compute logic to implement
- `TenantScopedModel` — new TaskDependency model inherits from this
- `TenantScopedService/Repository` — new DependencyService/Repository follow these
- `StatusBadge` (web) — reuse for conflict/blocked status display
- `recharts` — already installed in web, may be usable for timeline elements
- Trade scope `color` field — drives swim lane coloring on Gantt

### Established Patterns
- UUID primary keys with clientDefault for offline creation
- Soft-delete via `deletedAt`
- Version column for optimistic concurrency
- `lazy="raise"` on all SQLAlchemy relationships
- Idempotency-Key header for sync deduplication
- SyncHandler abstract class for new entity sync

### Integration Points
- Backend: extend projects feature module with DependencyService, new TaskDependency model, migration to drop `depends_on` JSONB
- Mobile: new `TaskDependencies` Drift table, new sync handler, new Gantt screen(s)
- Web: new Gantt timeline component integrated into project page, extend ProjectTree with blocked badges
- Task model: add `zone_id` FK to project zones; new `ProjectZone` model for zone list
- Gantt on web: new route/page under projects, or embedded in project detail view

</code_context>

<specifics>
## Specific Ideas

- Dependencies should feel like MS Project — full four-type support with lag/lead, drag-connect on Gantt
- Gantt swim lanes colored by trade — visual at a glance which trade owns which tasks
- Cycle detection on the Gantt should highlight the exact cycle path with red arrows so GC can see the problem visually, not just read an error message
- Zone list is project-scoped (Kitchen, Master Bath, etc.) — simple list management, not a complex location hierarchy
- Hard block means contractors literally cannot start blocked tasks — no overrides, no workarounds

</specifics>

<deferred>
## Deferred Ideas

- AI-generated zone lists from project description — Phase 21 (AI Intake)
- AI conflict resolution suggestions — Phase 21+ (AI features)
- Critical path highlighting on Gantt — possible future enhancement
- Milestone diamonds on Gantt — possible future enhancement

</deferred>

---

*Phase: 20-dependency-engine*
*Context gathered: 2026-03-21*
