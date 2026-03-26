---
phase: 25-per-trade-billing
plan: 02
subsystem: mobile-data-layer
tags: [drift, schema-migration, billing, offline-first, sync]
dependency_graph:
  requires: []
  provides:
    - BillingMilestones Drift table (v13 schema)
    - BillingMilestoneDao with CRUD + outbox + sync
    - InvoiceDao.watchInvoicesForScope
    - QuoteDao.watchQuotesForScope
    - BillingMilestoneSyncHandler
  affects:
    - mobile/lib/core/database/app_database.dart
    - mobile/lib/features/invoices/
    - mobile/lib/features/quotes/
    - mobile/lib/core/sync/
tech_stack:
  added:
    - BillingMilestones Drift table
    - BillingMilestoneDao (DatabaseAccessor with SyncQueue dual-write)
    - BillingMilestoneSyncHandler (SyncHandler extension)
  patterns:
    - Drift schema migration with alterTable rewrite for nullable column change
    - Outbox dual-write pattern for offline-first CRUD
    - Soft FK (no hard reference) for tradeScopeId on BillingMilestones
key_files:
  created:
    - mobile/lib/core/database/tables/billing_milestones.dart
    - mobile/lib/features/billing_milestones/data/billing_milestone_dao.dart
    - mobile/lib/features/billing_milestones/domain/billing_milestone_entity.dart
    - mobile/lib/core/sync/handlers/billing_milestone_sync_handler.dart
  modified:
    - mobile/lib/core/database/tables/invoices.dart
    - mobile/lib/core/database/tables/quotes.dart
    - mobile/lib/core/database/app_database.dart
    - mobile/lib/core/database/app_database.g.dart
    - mobile/lib/features/invoices/data/invoice_dao.dart
    - mobile/lib/features/invoices/domain/invoice_entity.dart
    - mobile/lib/features/quotes/data/quote_dao.dart
    - mobile/lib/features/quotes/domain/quote_entity.dart
    - mobile/lib/core/sync/sync_engine.dart
    - mobile/lib/core/di/service_locator.dart
decisions:
  - "BillingMilestones uses soft FK for tradeScopeId (no hard .references()) to keep table definitions decoupled across features — consistent with PunchListItems and TaskDependencies patterns"
  - "jobId made nullable on Invoices and Quotes tables via alterTable rewrite in migration — SQLite does not support ALTER COLUMN; alterTable rewrites the table with current column definitions"
  - "milestoneId added to Invoices as soft FK (no hard reference) to BillingMilestones — avoids circular FK dependency and keeps tables decoupled"
  - "BillingMilestoneSyncHandler registered in service_locator.dart Phase 25 block; billing_milestones added to sync_engine pullDelta entity types list"
metrics:
  duration: 397s
  completed: "2026-03-25"
  tasks: 2
  files: 14
---

# Phase 25 Plan 02: Mobile Drift Schema v13 — Per-Trade Billing Data Layer Summary

Drift schema v13 with BillingMilestones table, tradeScopeId on quotes/invoices, BillingMilestoneDao with outbox dual-write CRUD and upsertFromSync, scope-filtered streams on InvoiceDao and QuoteDao, and BillingMilestoneSyncHandler registered in the sync registry.

## Tasks Completed

| Task | Description | Commit | Files |
|------|-------------|--------|-------|
| 1 | Drift schema v13 — BillingMilestones table and column additions | fb93ad9 | billing_milestones.dart, invoices.dart, quotes.dart, app_database.dart, .g.dart, billing_milestone_dao.dart, billing_milestone_entity.dart |
| 2 | DAOs, entities, and sync handler for billing milestones | 0efdbbb | invoice_dao.dart, invoice_entity.dart, quote_dao.dart, quote_entity.dart, billing_milestone_sync_handler.dart, sync_engine.dart, service_locator.dart |

## What Was Built

### Drift Schema v13
- New `BillingMilestones` table: id, companyId, tradeScopeId (soft FK), name, percentage, description, isInvoiced, sortOrder, version, timestamps, deletedAt
- `Invoices.jobId` changed from required to nullable (for trade-scoped invoices)
- `Invoices.tradeScopeId` added (nullable, soft FK to TradeScopes)
- `Invoices.milestoneId` added (nullable, soft FK to BillingMilestones)
- `Quotes.jobId` changed from required to nullable (for trade-scoped quotes)
- `Quotes.tradeScopeId` added (nullable, soft FK to TradeScopes)
- Migration block `from < 13` handles table creation and column additions; `alterTable` rewrites quotes and invoices to reflect nullable jobId

### BillingMilestoneDao
- `watchByScope(String scopeId)` — reactive stream filtered by tradeScopeId, ordered by sortOrder ASC
- `createMilestone(entity)` — transaction: insert into billingMilestones + SyncQueue CREATE outbox entry
- `updateMilestone(entity)` — transaction: update row + SyncQueue UPDATE outbox entry
- `deleteMilestone(id)` — transaction: soft delete + SyncQueue DELETE outbox entry
- `upsertFromSync(data)` — insertOnConflictUpdate from sync data, no outbox write

### InvoiceDao/InvoiceEntity Extensions
- `InvoiceEntity.jobId` is now `String?` (nullable)
- `InvoiceEntity.tradeScopeId` added as `String?`
- `InvoiceEntity.milestoneId` added as `String?`
- `InvoiceDao.watchInvoicesForScope(String scopeId)` — same pattern as `watchInvoicesForJob` but filtering by tradeScopeId
- `createInvoice` and `upsertFromSync` updated for new fields

### QuoteDao/QuoteEntity Extensions
- `QuoteEntity.jobId` is now `String?` (nullable)
- `QuoteEntity.tradeScopeId` added as `String?`
- `QuoteDao.watchQuotesForScope(String scopeId)` — same pattern as `watchQuotesForJob` but filtering by tradeScopeId
- `createQuote` and `upsertFromSync` updated for new fields

### BillingMilestoneSyncHandler
- `entityType` = `'billing_milestone'`
- `push` — CREATE posts to `/scopes/{trade_scope_id}/milestones`, UPDATE PATCH to `/milestones/{id}`, DELETE to `/milestones/{id}`
- `applyPulled` — delegates to `db.billingMilestoneDao.upsertFromSync(data)`
- Registered in `service_locator.dart` under Phase 25 block
- Added to `sync_engine.dart` `pullDelta` entity types list as `('billing_milestones', 'billing_milestone')`

## Deviations from Plan

### Auto-fixed Issues

None — plan executed exactly as written.

**Note:** The plan referenced `mobile/lib/core/sync/sync_handlers.dart` as the file to modify for sync handler registration. This file does not exist — the project uses individual handler files in `mobile/lib/core/sync/handlers/` and registers them via `service_locator.dart` and the `sync_engine.dart` entity types list. Applied the existing project pattern instead.

## Self-Check: PASSED

All created files exist on disk. All task commits verified in git log.
