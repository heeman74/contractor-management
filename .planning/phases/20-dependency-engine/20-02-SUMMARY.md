---
phase: 20-dependency-engine
plan: 02
subsystem: mobile-data-layer
tags: [drift, schema-migration, dao, sync-handler, dependency-engine]
dependency_graph:
  requires: [20-01]
  provides: [task-dependency-dao, project-zone-dao, drift-schema-v8]
  affects: [mobile-sync-engine, service-locator]
tech_stack:
  added: []
  patterns: [drift-dao, sync-handler, table-migration]
key_files:
  created:
    - mobile/lib/core/database/tables/task_dependencies.dart
    - mobile/lib/core/database/tables/project_zones.dart
    - mobile/lib/features/projects/data/task_dependency_dao.dart
    - mobile/lib/features/projects/data/project_zone_dao.dart
    - mobile/lib/core/sync/handlers/task_dependency_sync_handler.dart
    - mobile/lib/core/sync/handlers/project_zone_sync_handler.dart
  modified:
    - mobile/lib/core/database/tables/tasks.dart
    - mobile/lib/core/database/app_database.dart
    - mobile/lib/features/projects/data/task_dao.dart
    - mobile/lib/core/sync/handlers/task_sync_handler.dart
    - mobile/lib/core/di/service_locator.dart
    - mobile/test/e2e/phase_19_project_data_model_e2e_test.dart
decisions:
  - "TaskDependencies uses soft FK (no hard FK) from ProjectTasks.zoneId to ProjectZones to keep table definitions decoupled"
  - "TaskDependencyDao.watchByProject joins through ProjectTasks → TradeScopes to filter by projectId — avoids direct project FK on task_dependencies"
  - "Generated .g.dart files are gitignored per project convention — only source files committed"
metrics:
  duration_seconds: 508
  completed_date: "2026-03-22"
  tasks_completed: 2
  files_changed: 12
---

# Phase 20 Plan 02: Mobile Drift Schema v8 — Dependency Engine Data Layer Summary

Drift schema upgraded from v7 to v8 with TaskDependencies edge table, ProjectZones table, updated ProjectTasks (removed dependsOn, added zoneId/startDate), two new DAOs with reactive streams, and two sync handlers registered in the service locator.

## Tasks Completed

| Task | Name | Commit | Files |
|------|------|--------|-------|
| 1 | Drift table definitions, schema v8 migration, updated ProjectTasks | 26f4f59 | task_dependencies.dart, project_zones.dart, tasks.dart, app_database.dart |
| 2 | DAOs, sync handlers, service locator registration | e6bbf52 | task_dependency_dao.dart, project_zone_dao.dart, task_dependency_sync_handler.dart, project_zone_sync_handler.dart, service_locator.dart |

## What Was Built

### Drift Schema v8

**TaskDependencies table** (`task_dependencies.dart`): Edge table for directed task-to-task dependency links. Stores predecessor/successor task IDs, dependency type (FS/SS/FF/SE), lag/lead days, version, and soft-delete. FK references from both `predecessorTaskId` and `successorTaskId` to `ProjectTasks.id`.

**ProjectZones table** (`project_zones.dart`): Named spatial zones within a project (Kitchen, Master Bath, Garage). FK to Projects. Used for resource conflict detection in the dependency engine.

**Migration block `if (from < 8)`**: Creates both new tables, adds `zoneId` (nullable text, soft FK) and `startDate` (nullable DateTime) to ProjectTasks, then runs `alterTable(TableMigration(projectTasks))` to drop the removed `dependsOn` column.

### DAOs

**TaskDependencyDao**: `watchByProject(projectId)` joins through ProjectTasks → TradeScopes to return all project-scoped dependency edges. `watchPredecessors(taskId)` and `watchSuccessors(taskId)` for per-task reactive streams. `upsertDependency` for sync pulls. `insertWithSyncQueue` and `softDeleteWithSyncQueue` for transactional writes with outbox.

**ProjectZoneDao**: `watchByProject(projectId)` and `getByProject` for zone lookups. `upsertZone` for sync pulls. `insertWithSyncQueue` and `softDeleteWithSyncQueue` for offline-first writes.

### Sync Handlers

**TaskDependencySyncHandler**: `entityType => 'task_dependency'`. Push: POST to `/tasks/{successorTaskId}/dependencies` with Idempotency-Key; DELETE to `/dependencies/{id}`. `applyPulled` upserts via TaskDependencyDao.

**ProjectZoneSyncHandler**: `entityType => 'project_zone'`. Push: POST to `/projects/{projectId}/zones`; DELETE to `/zones/{id}`. `applyPulled` upserts via ProjectZoneDao.

### Service Locator

Phase 20 section added: DAOs instantiated before SyncRegistry registration, handlers registered in the registry, DAOs registered as GetIt singletons.

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 1 - Bug] Removed dependsOn reference in phase_19 E2E test**
- **Found during:** Overall verification (flutter test test/e2e/)
- **Issue:** `phase_19_project_data_model_e2e_test.dart` line 242 used `dependsOn: '[]'` in a `ProjectTasksCompanion` fixture helper — column no longer exists in v8 schema.
- **Fix:** Removed the `dependsOn: '[]'` line from the `_makeTask` helper function.
- **Files modified:** `mobile/test/e2e/phase_19_project_data_model_e2e_test.dart`
- **Commit:** 98ad8fa

**2. [Rule 3 - Blocking] DioClient.instance accessor (not .dio)**
- **Found during:** Task 2 sync handler creation
- **Issue:** Plan code used `_dioClient.dio.post(...)` but DioClient exposes `get instance => _dio` (not `get dio`).
- **Fix:** Replaced `.dio.` with `.instance.` in both sync handlers before first build attempt.
- **Files modified:** task_dependency_sync_handler.dart, project_zone_sync_handler.dart

### Pre-existing Out-of-scope Failures

- `phase_10_ui_wiring_e2e_test.dart` sched08_collapsed: OverduePanel test was already failing before this plan's changes (confirmed via git stash test). Not caused by this plan — logged as deferred.

## Verification

```
dart analyze lib/ → no errors (5 pre-existing warnings in unrelated files)
dart run build_runner build → 417 outputs written, 0 errors
flutter test test/e2e/ → 252 passed, 1 pre-existing failure (phase_10 sched08)
```

## Self-Check: PASSED

- mobile/lib/core/database/tables/task_dependencies.dart: FOUND
- mobile/lib/core/database/tables/project_zones.dart: FOUND
- mobile/lib/features/projects/data/task_dependency_dao.dart: FOUND
- mobile/lib/features/projects/data/project_zone_dao.dart: FOUND
- mobile/lib/core/sync/handlers/task_dependency_sync_handler.dart: FOUND
- mobile/lib/core/sync/handlers/project_zone_sync_handler.dart: FOUND
- Commits 26f4f59, e6bbf52, 98ad8fa: FOUND
- schemaVersion => 8: CONFIRMED in app_database.dart
- TaskDependencies in @DriftDatabase tables: CONFIRMED
- TaskDependencyDao, ProjectZoneDao in daos: CONFIRMED
