---
phase: 20-dependency-engine
plan: 01
subsystem: backend
tags: [dependency-engine, task-dependencies, conflict-detection, project-zones, alembic, fastapi]
dependency_graph:
  requires: [phase-19-project-data-model]
  provides: [task-dependency-edges, project-zones, cycle-detection, blocked-status, conflict-detection]
  affects: [backend/app/features/projects/]
tech_stack:
  added: []
  patterns:
    - DFS cycle detection with white/gray/black coloring
    - SQLAlchemy aliased() for self-join conflict query
    - IntegrityError caught at service layer → 409 HTTP response
key_files:
  created:
    - backend/migrations/versions/0016_dependency_engine.py
    - backend/tests/test_phase_20_e2e.py
  modified:
    - backend/app/features/projects/models.py
    - backend/app/features/projects/schemas.py
    - backend/app/features/projects/repository.py
    - backend/app/features/projects/service.py
    - backend/app/features/projects/router.py
    - backend/tests/conftest.py
decisions:
  - "ConflictService uses .select_from(t1).join(t2, ...) rather than implicit cross-join; SQLAlchemy aliased() requires explicit FROM placement"
  - "IntegrityError for duplicate zone names caught in ProjectZoneService.create() → 409 Conflict (not propagated as 500)"
  - "Conflict detection uses t1.due_date == t2.due_date (single-day match); date-range overlap is Phase 21+ extension"
  - "FF dependency type does NOT set blocked status (only FS/SS/SE block successors)"
metrics:
  duration: "16 minutes"
  completed: "2026-03-22"
  tasks_completed: 2
  files_modified: 8
  tests_added: 24
---

# Phase 20 Plan 01: Dependency Engine Backend Summary

Backend dependency engine with DFS cycle detection, zone-based conflict detection, blocked status auto-compute, migration 0016, and 24 integration tests.

## What Was Built

### Migration 0016
- Created `project_zones` table (id, company_id, project_id, name) with UNIQUE(project_id, name)
- Created `task_dependencies` edge table (predecessor_task_id, successor_task_id, dependency_type, lag_days) with UNIQUE edge constraint and self-loop CHECK
- Added `zone_id` (FK to project_zones, SET NULL on delete) and `start_date` to `tasks`
- Migrated existing `depends_on` JSONB data to FS edges in `task_dependencies`
- Dropped `depends_on` column from `tasks`
- Enabled RLS + set_updated_at triggers + FK indexes on new tables

### Models
- `TaskDependency(TenantScopedModel)` — edge table with predecessor/successor FKs, dependency_type CHECK, no-self-loop CHECK
- `ProjectZone(TenantScopedModel)` — named spatial zone, UNIQUE(project_id, name)
- `Task` updated: added `zone_id`, `start_date`; removed `depends_on`

### Schemas
- `TaskDependencyCreate/Response`, `ProjectZoneCreate/Response`, `ConflictRecord`
- `TaskCreate/Update/Response` updated with `zone_id`/`start_date`, `depends_on` removed

### Services
- `DependencyService.create_dependency()` — loads all project edges, builds adjacency graph, DFS cycle check, persist, recompute blocked status
- `DependencyService._find_cycle()` — white/gray/black DFS, returns cycle path or None
- `DependencyService._recompute_blocked_status()` — sets task to blocked if any FS/SS/SE predecessor is incomplete; unblocks if all complete
- `ConflictService.detect_conflicts()` — self-join query via aliased Task/TradeScope, filters same zone + same due_date + different trade scopes
- `ProjectZoneService` — create (with 409 on duplicate), list, delete
- `TaskService.recompute_successor_statuses()` — called when task completes; unblocks all successors

### Router (7 new endpoints)
- `POST /tasks/{id}/dependencies` — create edge with cycle detection
- `GET /tasks/{id}/dependencies` — list edges for task
- `DELETE /dependencies/{id}` — soft delete + recompute
- `POST /projects/{id}/zones` — create zone
- `GET /projects/{id}/zones` — list zones
- `DELETE /zones/{id}` — soft delete zone
- `GET /projects/{id}/conflicts` — detect zone/date conflicts

### Repositories
- `TaskDependencyRepository` — list_by_project (joins Task→TradeScope for project scope), list_by_task (OR query)
- `ProjectZoneRepository` — list_by_project ordered by name

## Test Results

24 Phase 20 E2E tests passing. 21 Phase 19 tests still passing. 45 total.

Coverage:
- `test_create_fs_dependency` — 201, correct edge record
- `test_create_dependency_with_lag` — SS type + lag_days stored
- `test_list_dependencies` — task appears as pred and succ
- `test_delete_dependency` — 204, edge gone
- `test_delete_nonexistent_dependency_returns_404`
- `test_cycle_rejected_422` — A→B→C→A, cycle path in detail
- `test_self_loop_rejected` — A→A rejected
- `test_direct_cycle_rejected` — A→B, B→A rejected
- `test_task_blocked_by_dependency` — FS dep blocks successor
- `test_task_unblocked_on_completion` — completing predecessor unblocks
- `test_delete_dependency_unblocks_successor`
- `test_ff_dependency_does_not_block`
- `test_create_zone` — 201
- `test_list_zones`
- `test_duplicate_zone_rejected` — 409
- `test_delete_zone` — 204
- `test_zones_isolated_between_tenants` — RLS
- `test_conflict_detected` — same zone, same day, different scopes
- `test_no_conflict_different_zones`
- `test_no_conflict_different_dates`
- `test_no_conflict_same_trade_scope`
- `test_no_conflict_no_zone`
- `test_multiple_conflicts_detected`
- `test_dependency_cross_project_rejected` — 400

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 2 - Missing Error Handling] 409 for duplicate zone name**
- **Found during:** Task 2 — test_duplicate_zone_rejected
- **Issue:** `IntegrityError` from UNIQUE(project_id, name) constraint propagated as unhandled 500
- **Fix:** Added `try/except IntegrityError` in `ProjectZoneService.create()` → raises `HTTPException(409)`
- **Files modified:** `backend/app/features/projects/service.py`
- **Commit:** 4898880

**2. [Rule 1 - Bug] ConflictService aliased join missing FROM clause**
- **Found during:** Task 2 — test_conflict_detected
- **Issue:** SQLAlchemy `aliased(Task)` for `t2` was referenced in WHERE but not joined; ProgrammingError "missing FROM-clause entry for table t2"
- **Fix:** Changed query to use `.select_from(t1).join(s1, ...).join(z, ...).join(t2, t1.zone_id == t2.zone_id).join(s2, ...)` — explicit join chain
- **Files modified:** `backend/app/features/projects/service.py`
- **Commit:** 4898880

## Self-Check: PASSED

All key files exist:
- FOUND: backend/migrations/versions/0016_dependency_engine.py
- FOUND: backend/tests/test_phase_20_e2e.py
- FOUND: .planning/phases/20-dependency-engine/20-01-SUMMARY.md

All commits verified:
- FOUND: 8e9cf27 (Task 1: models, schemas, migration)
- FOUND: 4898880 (Task 2: services, repositories, router, tests)

Test results: 45 passed (24 new Phase 20 + 21 Phase 19 regression), 0 failed.
