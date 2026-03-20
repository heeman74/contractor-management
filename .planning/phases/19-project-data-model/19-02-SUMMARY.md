---
phase: 19-project-data-model
plan: 02
subsystem: mobile/database
tags: [drift, sqlite, offline-first, sync, dao, schema-migration]
dependency_graph:
  requires: [19-01]
  provides: [mobile-drift-schema-v7, project-dao, trade-catalog-dao, trade-scope-dao, task-dao, project-sync-handlers]
  affects: [app-database, sync-registry, service-locator]
tech_stack:
  added: []
  patterns: [drift-table-definition, drift-dao-accessor, sync-handler-pattern, transactional-sync-queue]
key_files:
  created:
    - mobile/lib/core/database/tables/projects.dart
    - mobile/lib/core/database/tables/trade_catalog.dart
    - mobile/lib/core/database/tables/trade_scopes.dart
    - mobile/lib/core/database/tables/tasks.dart
    - mobile/lib/core/database/tables/task_attachments.dart
    - mobile/lib/core/database/tables/user_trade_specialties.dart
    - mobile/lib/features/projects/data/project_dao.dart
    - mobile/lib/features/projects/data/trade_catalog_dao.dart
    - mobile/lib/features/projects/data/trade_scope_dao.dart
    - mobile/lib/features/projects/data/task_dao.dart
    - mobile/lib/core/sync/handlers/project_sync_handler.dart
    - mobile/lib/core/sync/handlers/trade_catalog_sync_handler.dart
    - mobile/lib/core/sync/handlers/trade_scope_sync_handler.dart
    - mobile/lib/core/sync/handlers/task_sync_handler.dart
  modified:
    - mobile/lib/core/database/app_database.dart
    - mobile/lib/core/di/service_locator.dart
decisions:
  - "ProjectTasks named to avoid conflict with any existing Task class in app"
  - "UserTradeSpecialties uses plain text FKs (no Drift references) to avoid cross-feature coupling"
  - "watchProjectsForContractor uses selectOnly+JOIN on TradeScopes for contractor role filtering"
  - "Sync handler registrations placed in service_locator.dart (not sync_registry.dart) following existing project convention"
  - "DAO imports in service_locator.dart are technically redundant (app_database.dart re-exports them) but kept for explicitness; lint warns info-level only"
metrics:
  duration: ~20 minutes
  completed: "2026-03-20T11:40:00Z"
  tasks_completed: 2
  files_created: 14
  files_modified: 2
---

# Phase 19 Plan 02: Drift Schema v7 and Project DAOs Summary

Drift SQLite schema upgraded from v6 to v7 with six new tables for the project data model. Four DAOs with reactive streams and transactional sync queue writes. Four sync handlers registered in the SyncRegistry for offline-first project entity sync.

## Tasks Completed

| Task | Description | Commit | Key Files |
|------|-------------|--------|-----------|
| 1 | Create Drift table definitions and update AppDatabase to schema v7 | 8d02692 | tables/projects.dart, tables/trade_catalog.dart, tables/trade_scopes.dart, tables/tasks.dart, tables/task_attachments.dart, tables/user_trade_specialties.dart, app_database.dart, four DAO files |
| 2 | Create sync handlers and register in service locator | c1edbd1 | handlers/project_sync_handler.dart, handlers/trade_catalog_sync_handler.dart, handlers/trade_scope_sync_handler.dart, handlers/task_sync_handler.dart, service_locator.dart |

## What Was Built

### Drift Tables (6 new)

- **Projects** — top-level project container with status, client, dates, and statusHistory (JSON TEXT)
- **TradeCatalogEntries** — company-level trade type definitions with name and hex color
- **TradeScopes** — per-trade scope of work within a project; contractor assignment, status, sortOrder
- **ProjectTasks** — atomic work units within a scope; priority, estimatedHours/Cost, photoRequired, dependsOn (JSON)
- **TaskAttachments** — photo/document attachments linked to tasks with remoteUrl and localPath
- **UserTradeSpecialties** — maps contractors to trade catalog entries for smart assignment suggestions

### AppDatabase Migration v6 → v7

Added migration branch `if (from < 7)` that creates all six new tables in dependency order:
`tradeCatalogEntries → projects → tradeScopes → projectTasks → taskAttachments → userTradeSpecialties`

### DAOs (4 new)

**ProjectDao** — `watchProjectsByCompany` (GC/admin) + `watchProjectsForContractor` (contractor role filtering via JOIN on TradeScopes.contractorId) + insert/update/softDelete with sync queue.

**TradeCatalogDao** — `watchCatalogByCompany` ordered by name + insert/update with sync queue.

**TradeScopeDao** — `watchScopesByProject` ordered by sortOrder + insert/update/softDelete with sync queue.

**TaskDao** — `watchTasksByScope` + `countTasksByScope` + `countCompletedTasksByScope` (for progress % display) + insert/update/softDelete with sync queue.

### Sync Handlers (4 new)

Each handler follows the existing `CompanySyncHandler` pattern:
- `push()` calls `dioClient.pushWithIdempotency()` with snake_case payload to API endpoint
- `applyPulled()` maps snake_case server JSON to Drift Companion fields with null safety, then calls `insertOnConflictUpdate`

Endpoints: `/projects`, `/trade-catalog`, `/trade-scopes`, `/tasks`

## Verification

- `dart run build_runner build --delete-conflicting-outputs` — succeeded, 544 outputs
- `dart analyze` on all new files — no errors (only cascade_invocations info-level lint in existing file patterns)
- AppDatabase `schemaVersion => 7` confirmed
- Migration branch `if (from < 7)` confirmed
- All four sync handlers registered in `service_locator.dart` Phase 19 section
- All four DAOs registered in GetIt for direct injection

## Deviations from Plan

### Minor Implementation Choices

**1. [Rule 1 - Pattern] sync_registry.dart not modified directly**
- **Found during:** Task 2
- **Issue:** Plan lists sync_registry.dart in files_modified, but by convention (followed by all existing handlers since Phase 3), handler registrations go in service_locator.dart, not sync_registry.dart itself. SyncRegistry is just a container class.
- **Fix:** Registered handlers in service_locator.dart Phase 19 section, which is consistent with all other phases.
- **Files modified:** mobile/lib/core/di/service_locator.dart

## Self-Check: PASSED

- All 14 created files confirmed present on disk
- Commits 8d02692 and c1edbd1 verified in git log
- AppDatabase schemaVersion => 7 confirmed
- Migration branch `if (from < 7)` confirmed
- ProjectSyncHandler registration confirmed in service_locator.dart
