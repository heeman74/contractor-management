---
phase: "08"
plan: "03"
subsystem: "mobile-data-layer"
tags: [flutter, drift, sqlite, quotes, invoices, sync, offline-first]
dependency-graph:
  requires: [08-01, 08-02]
  provides: [quote-dao, invoice-dao, quote-sync-handler, invoice-sync-handler, schema-v6]
  affects: [mobile-sync-engine, mobile-service-locator]
tech-stack:
  added: []
  patterns:
    - transactional-outbox-dual-write
    - two-query-no-n+1-line-items
    - parent-child-sync-payload
    - drift-manual-generated-code
key-files:
  created:
    - mobile/lib/core/database/tables/quotes.dart
    - mobile/lib/core/database/tables/quote_line_items.dart
    - mobile/lib/core/database/tables/quote_templates.dart
    - mobile/lib/core/database/tables/invoices.dart
    - mobile/lib/core/database/tables/invoice_line_items.dart
    - mobile/lib/features/quotes/domain/line_item_entity.dart
    - mobile/lib/features/quotes/domain/quote_entity.dart
    - mobile/lib/features/invoices/domain/invoice_entity.dart
    - mobile/lib/features/quotes/data/quote_dao.dart
    - mobile/lib/features/quotes/data/quote_dao.g.dart
    - mobile/lib/features/quotes/data/quote_sync_handler.dart
    - mobile/lib/features/invoices/data/invoice_dao.dart
    - mobile/lib/features/invoices/data/invoice_dao.g.dart
    - mobile/lib/features/invoices/data/invoice_sync_handler.dart
  modified:
    - mobile/lib/core/database/app_database.dart
    - mobile/lib/core/database/app_database.g.dart
    - mobile/lib/core/database/tables/jobs.dart
    - mobile/lib/core/di/service_locator.dart
decisions:
  - Schema v6 migration creates 5 new tables and adds quoteId/invoiceId FK columns to jobs
  - Two-query approach in DAO stream methods avoids N+1 and duplicate rows from JOINs
  - Quote templates use local-only operations (no sync queue dual-write)
  - ProcessedTableManager typedefs replaced with RootTableManager classes to match existing pattern
metrics:
  duration: "~7h 40m"
  completed: "2026-03-14"
  tasks: 2
  files: 14
---

# Phase 08 Plan 03: Flutter Quote/Invoice Data Layer Summary

**One-liner:** Drift schema v6 with 5 new tables, QuoteDao/InvoiceDao with transactional outbox dual-write, domain entities with computed financials, and SyncHandler registration.

## What Was Built

### Task 1: Drift Tables, Schema v6 Migration, Domain Entities

**New Drift table definitions** (5 tables):
- `Quotes`: status, revisionNumber, taxRate, discount fields, expiry/lifecycle timestamps, adminNotes
- `QuoteLineItems`: itemType, description, quantity, unit, unitPrice, sortOrder
- `QuoteTemplates`: name, description, lineItemsJson (JSON-encoded line items for local templates)
- `Invoices`: invoiceNumber, status, quoteId (FK), dueDate, issuedAt, finalizedAt
- `InvoiceLineItems`: mirrors QuoteLineItems but with invoiceId FK

**Schema v6 migration** in `app_database.dart`:
- Creates all 5 new tables
- Adds `quoteId` and `invoiceId` nullable FK columns to `Jobs` table

**Domain entities** (plain immutable classes, no @freezed since build_runner unavailable):
- `LineItemEntity`: shared between quotes and invoices, computed `lineTotal = quantity * unitPrice`
- `QuoteEntity`: computed `subtotal`, `discountAmount`, `discountedSubtotal`, `taxAmount`, `total`; status helpers (`isDraft`, `isSent`, `isApproved`, `isPending`, etc.)
- `InvoiceEntity`: same computed financials; status helpers (`isUnpaid`, `isPaid`, `requiresPayment`, etc.)

**Generated file updates** (`app_database.g.dart`):
- Added `quoteId`/`invoiceId` columns to `$JobsTable`, `Job`, `JobsCompanion`
- Added 5 new table classes, DataClasses, Companion classes
- Added `fromJson`/`toJson` to all 5 new DataClasses
- Added proper `RootTableManager` class definitions (replacing erroneous `ProcessedTableManager` typedefs)
- Added missing Phase 6 TableManagers: `$$JobNotesTableTableManager`, `$$AttachmentsTableTableManager`, `$$TimeEntriesTableTableManager`
- Added new table accessors and DAO accessors to `_$AppDatabase`

### Task 2: DAOs with Sync Queue Dual-Write and Sync Handlers

**QuoteDao** (`@DriftAccessor` on Quotes, QuoteLineItems, QuoteTemplates, SyncQueue):
- Stream queries: `watchQuotesForJob(jobId)`, `watchQuote(quoteId)`, `getAllQuotes()`
- Line item population: two-query approach (fetch parents → fetch all children → group by parentId) to avoid N+1 and JOIN duplicates
- Mutations: `createQuote`, `updateQuote`, `deleteQuote` — each atomically writes to entity table + sync_queue (transactional outbox pattern)
- Template operations (local-only, no sync): `watchTemplates`, `createTemplate`, `deleteTemplate`
- `upsertFromSync(data)`: processes parent + nested `line_items` array in single transaction

**InvoiceDao** (`@DriftAccessor` on Invoices, InvoiceLineItems, SyncQueue):
- Stream queries: `watchInvoicesForJob(jobId)`, `watchInvoice(invoiceId)`, `getAllInvoices()`
- Mutations: `createInvoice`, `updateInvoice`, `updatePaymentStatus` with sync queue dual-write
- `upsertFromSync(data)`: same pattern as QuoteDao for nested line_items

**Sync handlers**:
- `QuoteSyncHandler`: entityType='quote', routes CREATE→POST, UPDATE→PATCH, DELETE→DELETE; `applyPulled` delegates to `quoteDao.upsertFromSync`
- `InvoiceSyncHandler`: same pattern for invoices

**Service locator wiring**:
- Both handlers registered in `SyncRegistry`
- `QuoteDao` and `InvoiceDao` registered as GetIt singletons
- Removed redundant DAO imports (already exported via `app_database.dart`)

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 1 - Bug] DataClasses missing `fromJson`/`toJson` methods**
- **Found during:** Post-task 2 dart analyze
- **Issue:** `Quote`, `QuoteLineItem`, `QuoteTemplate`, `Invoice`, `InvoiceLineItem` DataClasses were missing `fromJson`/`toJson` methods required by Drift's `DataClass` interface
- **Fix:** Added `fromJson` factory constructors and `toJson` methods to all 5 DataClasses in `app_database.g.dart`
- **Files modified:** `mobile/lib/core/database/app_database.g.dart`

**2. [Rule 1 - Bug] Duplicate TableManager definitions and wrong pattern**
- **Found during:** Post-task 2 dart analyze
- **Issue:** Previous session had generated both `typedef $$XTableTableManager = ProcessedTableManager<...>` AND `final class $$XTableTableManager extends RootTableManager` for each new table, causing duplicate definition errors. The typedef pattern also used wrong constructor params (`db:` instead of `$db:`) in Composer calls.
- **Fix:** Removed `ProcessedTableManager` typedefs, kept class-based `RootTableManager` pattern matching the existing codebase (Phases 1-5). Fixed Composer constructor calls to use `$db:` and `$table:` named params.
- **Files modified:** `mobile/lib/core/database/app_database.g.dart`

**3. [Rule 2 - Missing Critical Functionality] Phase 6 TableManagers undefined**
- **Found during:** Post-task 2 dart analyze
- **Issue:** `$$JobNotesTableTableManager`, `$$AttachmentsTableTableManager`, `$$TimeEntriesTableTableManager` were referenced in `$AppDatabaseManager` getters but never defined — pre-existing gap from Phase 6.
- **Fix:** Added proper `RootTableManager` class definitions for all 3 Phase 6 tables with matching FilterComposer/OrderingComposer/AnnotationComposer and CreateCompanionBuilder/UpdateCompanionBuilder typedefs.
- **Files modified:** `mobile/lib/core/database/app_database.g.dart`

**4. [Rule 2 - Missing Critical] Unnecessary imports removed**
- **Found during:** dart analyze info warnings
- **Issue:** `invoice_dao.dart` and `quote_dao.dart` imported explicitly in `service_locator.dart` but already re-exported via `app_database.dart`
- **Fix:** Removed redundant imports
- **Files modified:** `mobile/lib/core/di/service_locator.dart`

## Self-Check

**Files verified:**
- `/Users/heechung/AndroidStudioProjects/contractormanagement/mobile/lib/features/quotes/data/quote_dao.dart` — FOUND
- `/Users/heechung/AndroidStudioProjects/contractormanagement/mobile/lib/features/invoices/data/invoice_dao.dart` — FOUND
- `/Users/heechung/AndroidStudioProjects/contractormanagement/mobile/lib/features/quotes/data/quote_sync_handler.dart` — FOUND
- `/Users/heechung/AndroidStudioProjects/contractormanagement/mobile/lib/features/invoices/data/invoice_sync_handler.dart` — FOUND
- `/Users/heechung/AndroidStudioProjects/contractormanagement/mobile/lib/core/database/app_database.g.dart` — FOUND

**Commits verified:**
- `e3f3619` feat(08-03): Drift tables, schema v6 migration, and Freezed entities — FOUND
- `217a9ed` feat(08-03): DAOs with sync queue dual-write and sync handlers — FOUND

**dart analyze result:** No errors across all plan deliverables (22 pre-existing info-level style warnings only, 5 pre-existing errors in time_entry_entity.dart freezed file from Phase 6 unrelated to this plan)

## Self-Check: PASSED
