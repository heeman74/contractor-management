---
phase: 09-sync-engine-gap-closure
plan: "01"
subsystem: sync-engine
tags: [sync, pullDelta, handlers, gap-closure, flutter]
dependency_graph:
  requires: []
  provides: [complete-pull-delta-loop, attachment-sync-handler, quote-line-item-sync-handler, invoice-line-item-sync-handler]
  affects: [sync-engine, service-locator, job-sync-handler]
tech_stack:
  added: []
  patterns: [pull-only-sync-handler, entity-loop-with-per-entity-try-catch]
key_files:
  created:
    - mobile/lib/core/sync/handlers/attachment_sync_handler.dart
    - mobile/lib/features/quotes/data/quote_line_item_sync_handler.dart
    - mobile/lib/features/invoices/data/invoice_line_item_sync_handler.dart
  modified:
    - mobile/lib/core/sync/sync_engine.dart
    - mobile/lib/features/jobs/data/job_sync_handler.dart
    - mobile/lib/core/di/service_locator.dart
decisions:
  - "pullDelta() entityTypes loop uses const tuples (serverResponseKey, handlerEntityType) — single source of truth for entity ordering"
  - "Per-entity and per-type try/catch ensures cursor updates even when some entities fail"
  - "Pull-only handlers throw StateError from push() — binary attachments use AttachmentUploadService, line items pushed via parent handler"
  - "GPS fields use 'is num' type check (not != null) to prevent runtime type error when JSON returns int instead of double"
metrics:
  duration: "~4 minutes"
  completed_date: "2026-03-14"
  tasks_completed: 2
  files_modified: 6
requirements: [INFRA-04, SCHED-03, FIELD-02, BIZ-01, BIZ-03]
---

# Phase 9 Plan 01: Sync Engine Gap Closure — pullDelta Loop + New Handlers Summary

**One-liner:** Refactored pullDelta() from 7 copy-paste blocks into a 15-entity type loop and created 3 pull-only handlers (attachment, quote line item, invoice line item) with complete JobSyncHandler GPS/FK field mapping.

## What Was Built

### Task 1: New Sync Handlers + JobSyncHandler Field Fix

**3 new pull-only sync handlers created:**

- `AttachmentSyncHandler` — maps server attachment records to local Drift `attachments` table; `push()` throws `StateError` since binary upload uses `AttachmentUploadService`
- `QuoteLineItemSyncHandler` — maps flat `quote_line_items` arrays from server delta; `push()` throws `StateError` since line items are pushed via parent `QuoteSyncHandler`
- `InvoiceLineItemSyncHandler` — mirrors `QuoteLineItemSyncHandler` for invoice line items; uses `invoiceId` FK instead of `quoteId`

**JobSyncHandler field fix:** Added 5 previously missing fields to `applyPulled()`:
- `gpsLatitude` / `gpsLongitude` — using `is num` check to safely handle int-vs-double JSON types
- `gpsAddress` — nullable string from server
- `quoteId` / `invoiceId` — nullable FK references added in Phase 8 schema migration

**service_locator.dart:** Registered all 3 new handlers after `InvoiceSyncHandler`. Total: 15 handlers.

### Task 2: pullDelta() Loop Refactor

Replaced 7 copy-paste entity processing blocks with a single `for (final (responseKey, handlerType) in entityTypes)` loop over 15 entity type tuples in FK dependency order:

```
companies → users → user_roles → jobs → bookings → job_sites →
job_notes → time_entries → attachments → client_profiles →
job_requests → quotes → quote_line_items → invoices → invoice_line_items
```

**Error handling:**
- Per-entity `try/catch` logs and skips individual entity failures, continues with remaining entities
- Per-type `try/catch` handles unregistered handler gracefully — logs and skips entire type
- Outer `DioException` handler unchanged — network failures remain non-fatal, cursor not updated

**Logging:** Added `debugPrint` for per-type counts and aggregate totals. Forward-compatibility: unknown response keys are logged.

**Preserved:** Attachment upload after loop, cursor update after loop.

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 1 - Bug] Removed unused sync_queue_dao.dart imports from new handlers**
- **Found during:** Task 1 verification (dart analyze)
- **Issue:** New pull-only handlers imported `sync_queue_dao.dart` but `SyncQueueData` is available transitively via `app_database.dart` → `sync_handler.dart`
- **Fix:** Removed `sync_queue_dao.dart` import from `attachment_sync_handler.dart`, `quote_line_item_sync_handler.dart`, and `invoice_line_item_sync_handler.dart`
- **Files modified:** 3 new handler files
- **Commit:** 6b4d101

**Note:** Pre-existing unused import in `job_sync_handler.dart:8` (`sync_queue_dao.dart`) — this was present before our changes and is out of scope. Logged below.

## Deferred Items

- Pre-existing unused import warning: `mobile/lib/features/jobs/data/job_sync_handler.dart:8` — `'../../../core/sync/sync_queue_dao.dart'` is redundant (type available via `app_database.dart` chain). Cleanup deferred.
- Pre-existing `cascade_invocations` and `directives_ordering` info-level issues in `service_locator.dart` and `sync_engine.dart` — pre-existing, out of scope.

## Commits

| Task | Commit | Description |
|------|--------|-------------|
| Task 1 | 6b4d101 | feat(09-01): create 3 new sync handlers and fix JobSyncHandler fields |
| Task 2 | 0953b19 | feat(09-01): refactor pullDelta() to loop over 15 entity types |

## Self-Check

Verified below.
