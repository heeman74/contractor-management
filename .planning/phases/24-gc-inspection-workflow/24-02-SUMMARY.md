---
phase: 24-gc-inspection-workflow
plan: "02"
subsystem: mobile-data-layer
tags: [drift, dao, riverpod, offline-first, sync, inspection-workflow]
dependency_graph:
  requires: []
  provides:
    - Drift schema v12 with TaskInspections, SiteWalkFlags, PunchListItems tables
    - TaskInspectionDao with createInspection + upsertFromServer
    - SiteWalkFlagDao with createFlag, updateStatus, convertFlag (atomic transaction)
    - PunchListItemDao with watchByScopeId (priority-ordered), createItem, updateItem
    - 3 SyncHandler implementations for server push/pull
    - 7 Riverpod providers for reactive UI consumption
  affects:
    - mobile/lib/core/di/service_locator.dart (3 new DAOs + 3 sync handlers registered)
    - mobile/lib/features/projects/presentation/providers/project_providers.dart (7 new providers)
tech_stack:
  added: []
  patterns:
    - Drift transactional outbox dual-write (same as TaskNoteDao pattern)
    - SiteWalkFlagDao.convertFlag wraps 4 writes (flag update + sync entry + punch item + sync entry) in a single Drift transaction
    - Sync handlers implement SyncHandler.push + applyPulled
    - GetIt-backed Riverpod providers (documented tradeoff per CLAUDE.md)
key_files:
  created:
    - mobile/lib/core/database/tables/task_inspections.dart
    - mobile/lib/core/database/tables/site_walk_flags.dart
    - mobile/lib/core/database/tables/punch_list_items.dart
    - mobile/lib/features/projects/data/task_inspection_dao.dart
    - mobile/lib/features/projects/data/site_walk_flag_dao.dart
    - mobile/lib/features/projects/data/punch_list_item_dao.dart
    - mobile/lib/core/sync/handlers/task_inspection_sync_handler.dart
    - mobile/lib/core/sync/handlers/site_walk_flag_sync_handler.dart
    - mobile/lib/core/sync/handlers/punch_list_item_sync_handler.dart
  modified:
    - mobile/lib/core/database/tables/trade_scopes.dart (added inspectionChecklist column)
    - mobile/lib/core/database/app_database.dart (schema v12, 3 new tables, 3 new DAOs)
    - mobile/lib/core/database/app_database.g.dart (regenerated)
    - mobile/lib/core/di/service_locator.dart (3 DAOs + 3 sync handlers registered)
    - mobile/lib/features/projects/presentation/providers/project_providers.dart (7 new providers)
decisions:
  - SiteWalkFlagDao.convertFlag performs 4 atomic writes in a single Drift transaction (flag status update + flag sync entry + punch item insert + punch item sync entry) — ensures consistency; if any write fails, none persist
  - PunchListItemDao.watchByScopeId uses caseMatch for priority ordering (urgent=0, high=1, medium=2, low=3) — same pattern as TaskDao.watchTasksForContractor
  - SiteWalkFlagDao needs @DriftAccessor(tables: [SiteWalkFlags, PunchListItems, SyncQueue]) to access PunchListItems table in convertFlag transaction
  - Sync handlers registered in service_locator.dart under "Phase 24" comment block following existing phase registration convention
metrics:
  duration: ~15min
  completed: "2026-03-25"
  tasks_completed: 2
  files_modified: 5
  files_created: 9
---

# Phase 24 Plan 02: Mobile Data Layer for GC Inspection Workflow Summary

Established the complete mobile data layer for the GC Inspection Workflow: Drift schema v12 with 3 new tables (TaskInspections, SiteWalkFlags, PunchListItems), 3 DAOs with offline-first sync queue dual-write, atomic flag-to-punch conversion transaction, 3 sync handlers for server push/pull, and 7 Riverpod providers for UI consumption.

## What Was Built

### Drift Schema v12

Schema bumped from v11 to v12. Migration adds 3 new tables and 1 new column:

- `task_inspections` — GC approve/reject audit trail per task; multi-inspection support (one per review cycle); checklist results as JSON array
- `site_walk_flags` — GC field-captured issues with severity, location label, photo URL, and annotation overlay; status lifecycle: open → resolved/converted/dismissed
- `punch_list_items` — formal corrective action items scoped to a trade scope; source_flag_id links back to originating flag; priority-ordered
- `inspection_checklist` nullable column added to `trade_scopes` — per-scope JSON checklist definition

### 3 DAOs with Offline-First Dual-Write

All DAOs follow the `TaskNoteDao` pattern: every mutation atomically writes to both the entity table AND `sync_queue` outbox in a single Drift transaction.

**TaskInspectionDao**: `watchByTaskId` (audit trail stream), `createInspection` (dual-write), `upsertFromServer` (delta sync)

**SiteWalkFlagDao**: `watchByProjectId`, `createFlag`, `updateStatus`, and the critical `convertFlag` method — which wraps 4 writes atomically: flag status → 'converted', flag sync entry (UPDATE), punch item insert, punch item sync entry (CREATE). If any write fails, all 4 are rolled back.

**PunchListItemDao**: `watchByScopeId` (priority-ordered: urgent→high→medium→low using caseMatch), `watchByProjectId`, `createItem`, `updateItem`, `upsertFromServer`

### 3 Sync Handlers

`TaskInspectionSyncHandler`, `SiteWalkFlagSyncHandler`, `PunchListItemSyncHandler` — all implement `SyncHandler.push` (pushes mutations to backend API) and `applyPulled` (upserts server-pushed data into Drift). Registered in service_locator.dart under the Phase 24 comment block.

### 7 Riverpod Providers

3 DAO providers (GetIt-backed, documented tradeoff per CLAUDE.md):
- `taskInspectionDaoProvider`
- `siteWalkFlagDaoProvider`
- `punchListItemDaoProvider`

4 stream providers (StreamProvider.autoDispose.family):
- `inspectionsForTaskProvider` — family by taskId
- `flagsForProjectProvider` — family by projectId
- `punchItemsByScopeProvider` — family by tradeScopeId
- `punchItemsByProjectProvider` — family by projectId

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 1 - Bug] Fixed caseMatch parameter name in PunchListItemDao**
- **Found during:** Task 2 — dart analyze
- **Issue:** Plan used `whens:` parameter name but Drift API uses `when:`
- **Fix:** Changed `whens: {...}` to `when: {...}` in PunchListItemDao.watchByScopeId to match Drift caseMatch API (confirmed by TaskDao.watchTasksForContractor)
- **Files modified:** mobile/lib/features/projects/data/punch_list_item_dao.dart
- **Commit:** 23e3cf3

### Architectural Notes

- Plan referenced `appDatabaseProvider` for DAO initialization but project uses GetIt singleton pattern consistently. Followed existing project pattern (GetIt-backed providers) with documented tradeoff per CLAUDE.md.
- Sync handler files created in `mobile/lib/core/sync/handlers/` (not in `mobile/lib/features/projects/data/sync_handlers.dart` as the plan mentioned — the actual project uses individual handler files per entity type, not a monolithic sync_handlers.dart).

## Self-Check

Verified artifacts:
- `schemaVersion => 12` present in app_database.dart
- `TaskInspection` data class generated in app_database.g.dart
- `convertFlag` method present in SiteWalkFlagDao
- `watchByScopeId` method present in PunchListItemDao
- 7 Riverpod providers present in project_providers.dart
- `dart analyze` on all new files: 0 errors, 0 warnings
