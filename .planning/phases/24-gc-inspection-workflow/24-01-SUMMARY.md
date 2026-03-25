---
phase: 24-gc-inspection-workflow
plan: "01"
subsystem: backend
tags: [inspection, migration, api, fcm, postgresql, rls]
dependency_graph:
  requires: [23-real-time-chat]
  provides: [inspection-api, task-rejection-flow, punch-list-api, site-walk-flags-api]
  affects: [projects-service, notifications-service, task-status-machine]
tech_stack:
  added: []
  patterns: [TenantScopedModel, TenantScopedService, TenantScopedRepository, fire-and-forget-fcm]
key_files:
  created:
    - backend/migrations/versions/0022_inspection_workflow.py
    - backend/app/features/inspection/__init__.py
    - backend/app/features/inspection/models.py
    - backend/app/features/inspection/repository.py
    - backend/app/features/inspection/schemas.py
    - backend/app/features/inspection/service.py
    - backend/app/features/inspection/router.py
  modified:
    - backend/app/features/projects/models.py
    - backend/app/features/notifications/service.py
    - backend/app/main.py
decisions:
  - "inspector_id, flagged_by, created_by, assigned_to are all soft FKs (no hard FK), consistent with TaskNote.author_id pattern from Phase 22"
  - "source_flag_id on PunchListItem is soft FK to site_walk_flags — no hard FK to keep tables decoupled"
  - "reblock_successors only re-blocks FS/SS/SE dependency type successors — FF does not block"
  - "FCM rejection notification fires via asyncio.create_task (fire-and-forget) — inspect response never waits for FCM"
  - "Added bonus GET /tasks/{task_id}/inspections endpoint for audit trail (beyond the 7 required)"
metrics:
  duration_seconds: 423
  tasks_completed: 2
  files_created: 7
  files_modified: 3
  completed_date: "2026-03-25"
---

# Phase 24 Plan 01: Backend Foundation for GC Inspection Workflow Summary

Backend foundation for GC inspection workflow: Alembic migration 0022 creating 3 new RLS-protected tables (task_inspections, site_walk_flags, punch_list_items), 3 SQLAlchemy models, 3 repositories, 3 service classes with full business logic (approve/reject with reblock_successors, flag creation and conversion, punch list CRUD), 8 REST endpoints, and FCM fire-and-forget rejection notification.

## Tasks Completed

| Task | Name | Commit | Files |
|------|------|--------|-------|
| 1 | Alembic migration 0022 + SQLAlchemy models + repositories | 4f0fdc4 | 5 files (migration, __init__, models, repository, projects/models.py) |
| 2 | Services + schemas + endpoints + FCM rejection notification | a2b49eb | 5 files (schemas, service, router, notifications/service.py, main.py) |

## What Was Built

### Migration 0022 (backend/migrations/versions/0022_inspection_workflow.py)

- Extended `tasks` status CHECK constraint to include `'rejected'`
- Added `inspection_checklist` JSONB nullable column to `trade_scopes`
- Created `task_inspections` table with RLS policy (tenant isolation)
- Created `site_walk_flags` table with RLS policy
- Created `punch_list_items` table with RLS policy
- All 3 new tables have company_id FK, version, timestamps, deleted_at (soft delete)
- Indexes on (task_id), (project_id), (trade_scope_id), (company_id) for query performance

### SQLAlchemy Models (backend/app/features/inspection/models.py)

- `TaskInspection(TenantScopedModel)` — approve/reject record with decision CHECK constraint
- `SiteWalkFlag(TenantScopedModel)` — severity/status CHECK constraints
- `PunchListItem(TenantScopedModel)` — priority/status CHECK constraints
- All soft FK fields (inspector_id, flagged_by, created_by, assigned_to, source_flag_id) following Phase 22 TaskNote pattern
- No relationships defined (no lazy="raise" needed as no FKs with ORM relationships)

### Repositories (backend/app/features/inspection/repository.py)

- `TaskInspectionRepository` — `list_by_task()` for audit trail
- `SiteWalkFlagRepository` — `list_by_project()` for project flag listing
- `PunchListRepository` — `list_by_scope()` and `list_by_project()`

### Services (backend/app/features/inspection/service.py)

- `InspectionService.inspect_task()`: validates task is 'complete', creates record, on rejection: sets task.status='rejected', calls `reblock_successors()`, fires FCM via asyncio.create_task
- `InspectionService.reblock_successors()`: queries task_dependencies for FS/SS/SE edges where this task is predecessor, calls `DependencyService._recompute_blocked_status()` for each
- `SiteWalkFlagService.convert_to_punch_item()`: validates flag is 'open', creates PunchListItem inheriting flag data, sets flag.status='converted'
- `PunchListService.update_item()`: partial update skipping None values

### REST Endpoints (backend/app/features/inspection/router.py)

8 endpoints registered under `/api/v1`:

| Method | Path | Role guard |
|--------|------|-----------|
| POST | /tasks/{task_id}/inspect | GC or admin only |
| GET | /tasks/{task_id}/inspections | Any authenticated |
| POST | /projects/{project_id}/flags | Any authenticated |
| GET | /projects/{project_id}/flags | Any authenticated |
| PATCH | /flags/{flag_id}/convert | Any authenticated |
| POST | /projects/{project_id}/punch-items | Any authenticated |
| GET | /trade-scopes/{scope_id}/punch-items | Any authenticated |
| PATCH | /punch-items/{item_id} | Any authenticated |

### FCM Rejection Notification (backend/app/features/notifications/service.py)

- Added `send_task_rejection_notification()` following exact `queue_task_completion_digest` pattern
- Graceful degradation when GOOGLE_APPLICATION_CREDENTIALS not set
- Per-token error handling: UnregisteredError cleans up stale tokens
- Outer exception catch ensures FCM errors never propagate

## Deviations from Plan

### Auto-additions (Rule 2)

**1. [Rule 2 - Missing functionality] Added GET /tasks/{task_id}/inspections endpoint**
- **Found during:** Task 2 implementation
- **Rationale:** The inspection flow benefits from an audit trail endpoint — mobile clients need to view inspection history per task. The plan specifies 7 required endpoints; this is the 8th bonus endpoint.
- **Files modified:** backend/app/features/inspection/router.py

## Verification

- `uv run alembic upgrade head` exits 0 — migration applied to test DB
- `app.features.inspection.models` imports cleanly
- `app.features.inspection.repository` imports cleanly
- `app.features.inspection.service` imports cleanly
- `app.features.inspection.schemas` imports cleanly
- `inspection_router` has 8 routes (all 7 required plus audit trail bonus)
- `NotificationService.send_task_rejection_notification` exists
- `ruff check app/features/inspection/` passes clean
- Full app loads with inspection_router registered

## Self-Check: PASSED

All files confirmed present:
- backend/migrations/versions/0022_inspection_workflow.py: FOUND
- backend/app/features/inspection/models.py: FOUND
- backend/app/features/inspection/service.py: FOUND
- backend/app/features/inspection/router.py: FOUND

Commits confirmed:
- 4f0fdc4: Task 1 — migration + models + repositories
- a2b49eb: Task 2 — services + schemas + endpoints + FCM
