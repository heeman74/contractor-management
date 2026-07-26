---
phase: 31-actual-cost-capture
plan: 04
subsystem: mobile
tags: [flutter, drift, riverpod, dio, offline-first, sync, finance]

# Dependency graph
requires:
  - phase: 31-actual-cost-capture
    plan: 01
    provides: "Gated /api/v1/cost-entries CRUD + /projects/{id}/cost-entries rollup + /cost-categories"
  - phase: 31-actual-cost-capture
    plan: 02
    provides: "POST/GET/DELETE /cost-entries/{id}/receipts + authenticated /files/cost-receipts/... serving"
provides:
  - "Drift v16 schema: CostEntries + CostReceipts tables"
  - "CostEntryDao: offline-first CRUD with sync_queue outbox dual-write, reactive watch streams, on-demand upsert"
  - "CostReceiptDao: binary-upload lifecycle DAO mirroring AttachmentDao"
  - "CostEntrySyncHandler: outbound push handler (entityType 'cost_entry'), registered in SyncRegistry"
  - "CostReceiptUploadService: multipart upload with 3-retry backoff (5s/15s/45s), wired into SyncEngine.pullDelta after attachments"
  - "FinanceRepository: on-demand Dio fetch + Drift upsert for cost entries/rollup/categories/receipts — never via the company-wide /sync delta"
affects: [31-05-cost-capture-mobile-screens]

# Tech tracking
tech-stack:
  added: []
  patterns:
    - "Cost data is fetched ON-DEMAND per job/scope/project via FinanceRepository, never added to sync_engine.dart's pullDelta entityTypes list — closes the Pitfall 2 leak surface (non-finance devices never pull cost data into local Drift) by construction, not by permission filtering after the fact"
    - "CostEntryResponse/CostReceiptResponse extend BaseResponseSchema (not TenantResponseSchema) so backend responses carry no company_id — FinanceRepository injects 'company_id' into each response map before calling DAO upsertFromRemote/CostEntrySyncHandler.applyPulled"
    - "watchByProject uses an explicit jobIds parameter (not a local Jobs.projectId join) since the mobile Jobs table has no projectId FK — callers (31-05's project detail screen) supply the project's known job IDs; trade-scope membership is still derived locally via the two-stream watchProjectsForContractor-style pattern"

key-files:
  created:
    - mobile/lib/core/database/tables/cost_entries.dart
    - mobile/lib/core/database/tables/cost_receipts.dart
    - mobile/lib/features/finance/data/cost_entry_dao.dart
    - mobile/lib/features/finance/data/cost_receipt_dao.dart
    - mobile/lib/core/sync/handlers/cost_entry_sync_handler.dart
    - mobile/lib/features/finance/services/cost_receipt_upload_service.dart
    - mobile/lib/features/finance/data/finance_repository.dart
    - mobile/test/unit/features/finance/cost_entry_dao_test.dart
    - mobile/test/unit/features/finance/cost_receipt_upload_service_test.dart
  modified:
    - mobile/lib/core/database/app_database.dart
    - mobile/lib/core/sync/sync_engine.dart
    - mobile/lib/core/di/service_locator.dart

key-decisions:
  - "Mobile receipts follow Attachment/AttachmentUploadService exactly (NOT TaskAttachmentDao, which has no registered push handler in this codebase — 31-RESEARCH.md Pitfall 1)"
  - "CostEntrySyncHandler is registered in SyncRegistry (for outbound push via drainQueue) but deliberately NOT added to sync_engine.dart's pullDelta entityTypes list — inbound reads are on-demand only"
  - "cost_categories has no local Drift table this plan — FinanceRepository.fetchCostCategories() returns a validated List<Map> without persistence; categories change rarely and 31-05's screens can add local caching if offline category selection proves necessary"
  - "watchByProject takes an explicit jobIds parameter rather than joining through a Jobs.projectId column that doesn't exist on mobile — the project detail screen (31-05) supplies known job IDs"

requirements-completed: [COST-01, COST-02, COST-03]

# Metrics
duration: 35min
completed: 2026-07-25
---

# Phase 31 Plan 04: Mobile Offline-First Cost Capture Data Layer Summary

**Drift v16 `cost_entries`/`cost_receipts` tables, DAOs with sync-queue outbox dual-write, a `CostEntrySyncHandler` outbound push handler, a `CostReceiptUploadService` mirroring the working `AttachmentUploadService` retry/backoff pattern (not the broken `TaskAttachment` flow), and an on-demand `FinanceRepository` that keeps cost data out of the company-wide `/sync` delta.**

## Performance

- **Duration:** ~35 min
- **Tasks:** 3 completed
- **Files modified:** 12 (9 created, 3 modified)

## Accomplishments

- A cost entry created offline (job- or trade-scope-anchored) persists to Drift and is atomically enqueued to `sync_queue` with `entityType: 'cost_entry'`; `CostEntrySyncHandler` pushes CREATE/UPDATE/DELETE to the flat `/cost-entries` collection with an `Idempotency-Key` header on drain.
- A receipt captured offline is stored locally with `uploadStatus = 'pending_upload'` and uploaded via `CostReceiptUploadService` with 3-retry exponential backoff (5s/15s/45s), 4xx-no-retry, multipart POST to `/cost-entries/{id}/receipts` — wired into `SyncEngine.pullDelta` immediately after the existing attachment upload call (text-first-then-binary ordering).
- Cost entries and receipts are readable only via `FinanceRepository`'s explicit, on-demand Dio fetches (per job/trade-scope/project/cost-entry) — `cost_entries`/`cost_receipts` are never added to `sync_engine.dart`'s company-wide `pullDelta` entity list, so a non-finance device's local Drift DB never receives cost data.
- Drift schema upgrades cleanly from v15 to v16 (`createTable` for both new tables in `onUpgrade`), verified by a clean `build_runner build --delete-conflicting-outputs` regeneration with zero new conflicts.
- 12 new unit tests (in-memory Drift for `CostEntryDao`, mocked Dio for `CostReceiptUploadService`) cover insert/enqueue, XOR anchor rejection, soft-delete exclusion, trade-scope/project rollup watch streams, on-demand upsert, upload retry/backoff, and 4xx no-retry — all green, `dart analyze` clean across `lib/features/finance`, `lib/core/sync`, `lib/core/database`, and the new test directory.

## Task Commits

Each task was committed atomically:

1. **Task 1: Drift v16 — cost_entries + cost_receipts tables, migration, DAOs** - `d8107a4` (feat)
2. **Task 2: CostEntrySyncHandler + CostReceiptUploadService + on-demand repository + wiring** - `e8f21f5` (feat)
3. **Task 3: DAO + upload-service unit tests** - `b70f260` (test)

## Files Created/Modified

- `mobile/lib/core/database/tables/cost_entries.dart` - `CostEntries` Drift table: job XOR trade-scope soft-FK anchor, `RealColumn amount`, ISO `incurredDate` string, `companyId` references `Companies`
- `mobile/lib/core/database/tables/cost_receipts.dart` - `CostReceipts` Drift table mirroring `Attachments`' `uploadStatus` lifecycle exactly
- `mobile/lib/core/database/app_database.dart` - `schemaVersion` 15→16, `onUpgrade` creates both tables, both tables/DAOs registered and exported
- `mobile/lib/features/finance/data/cost_entry_dao.dart` - `watchByJob`/`watchByTradeScope`/`watchByProject` (two-stream), `insertCostEntry` (XOR-guarded, sync_queue dual-write), `updateCostEntry`, `softDeleteCostEntry`, `upsertFromRemote`
- `mobile/lib/features/finance/data/cost_receipt_dao.dart` - `insertReceipt`, `getPendingUploads`, `setUploadStatus`, `markUploaded`, `incrementRetry`, `watchByCostEntry`, `upsertFromRemote`
- `mobile/lib/core/sync/handlers/cost_entry_sync_handler.dart` - outbound push (CREATE→POST, UPDATE→PATCH, DELETE→DELETE against flat `/cost-entries`), `applyPulled` for on-demand upsert only
- `mobile/lib/features/finance/services/cost_receipt_upload_service.dart` - mirrors `AttachmentUploadService` exactly: 3-retry backoff, 4xx-no-retry, multipart POST to `/cost-entries/{id}/receipts`
- `mobile/lib/features/finance/data/finance_repository.dart` - `fetchCostEntriesForJob`/`fetchCostEntriesForTradeScope`/`fetchProjectRollup`/`fetchCostCategories`/`fetchReceipts`, all validated (no bare `as` casts), injects `company_id` before DAO upsert
- `mobile/lib/core/sync/sync_engine.dart` - `setCostReceiptUploadService` + `uploadPending()` call right after the attachment upload call in `pullDelta`; no `cost_entries` key anywhere in the file
- `mobile/lib/core/di/service_locator.dart` - registers `CostEntrySyncHandler`, `CostEntryDao`, `CostReceiptDao`, constructs + wires `CostReceiptUploadService`, registers `FinanceRepository`
- `mobile/test/unit/features/finance/cost_entry_dao_test.dart` - 8 tests: insert/enqueue, XOR rejection (both/neither), soft-delete exclusion, trade-scope filter, project rollup (trade-scope + job anchored), on-demand upsert
- `mobile/test/unit/features/finance/cost_receipt_upload_service_test.dart` - 4 tests: empty-pending no-op, uploading-status transition, successful upload path/markUploaded, 4xx single-attempt no-retry

## Decisions Made

- **Mobile receipts mirror `Attachment`/`AttachmentUploadService`, not `TaskAttachmentDao`** — 31-RESEARCH.md verified `TaskAttachmentDao`'s sync_queue entries have no registered handler in this codebase (photos captured that way are silently never uploaded); `CostReceiptDao`/`CostReceiptUploadService` replicate the working pattern exactly, including the retry/backoff timing and multipart shape.
- **`CostEntrySyncHandler` is registered but not added to `pullDelta`'s entity list** — outbound push (drain queue) and inbound on-demand fetch (`FinanceRepository`) both use the same handler's `applyPulled`, but the company-wide sync delta never carries cost data (Pitfall 2).
- **No local `cost_categories` Drift table this plan** — `FinanceRepository.fetchCostCategories()` returns a validated `List<Map<String, dynamic>>` without Drift persistence. Categories are a small, low-churn reference lookup; the field-capture screens (31-05) can add local caching there if offline category selection proves necessary. This is a deliberate, documented scope trim, not an oversight — it keeps this plan's `files_modified` list accurate to the frontmatter.
- **`watchByProject` takes an explicit `jobIds` parameter** — the mobile `Jobs` table has no `projectId` FK (unlike the backend's migration-0030 column), so job-anchored project-rollup membership cannot be derived via a local join. The two-stream trade-scope lookup (mirroring `watchProjectsForContractor`) still works locally; job-anchored membership is supplied by the caller, which will have already fetched the project's job list through an existing project/job API.
- **`CostEntryResponse`/`CostReceiptResponse` carry no `company_id`** (they extend `BaseResponseSchema`, not `TenantResponseSchema`) — `FinanceRepository` injects a `'company_id'` key into each response map before calling `upsertFromRemote`/`applyPulled`, matching the DAO convention of accepting `companyId` explicitly (same as `NoteDao.insertNote`) rather than trying to extract it from a field that doesn't exist in the payload.

## Deviations from Plan

None beyond the documented "Claude's Discretion" scope trim on `cost_categories` persistence (see Decisions Made above) — that choice was made during Task 2 implementation, is low-risk (no offline-capture correctness impact this plan, since category selection UI ships in 31-05), and does not touch any file outside the plan's declared `files_modified` list.

### Process note (not a code deviation)

During Task 2, two rounds of edits to `mobile/lib/core/sync/sync_engine.dart` and `mobile/lib/core/di/service_locator.dart` were silently reverted by an external process between tool calls (most likely file-state contention with the concurrently-running 31-03 web-plan executor sharing the same working tree, per the parallel-execution setup). Each loss was caught immediately by re-running `dart analyze` before committing, the missing edits were reapplied, and the task's commit was made only after `dart analyze lib/core/sync lib/features/finance lib/core/di` came back clean. No stale/partial code was committed.

## Issues Encountered

- See "Process note" above — resolved by verify-before-commit discipline; no code-level issue.

## User Setup Required

None — no external service configuration required.

## Next Phase Readiness

- Plan 31-05 (mobile cost-capture screens) can proceed immediately: `CostEntryDao`/`CostReceiptDao` reactive streams, `FinanceRepository`'s on-demand fetchers, and `CostReceiptUploadService`'s upload lifecycle are all available via `GetIt` (`getIt<CostEntryDao>()`, `getIt<FinanceRepository>()`, etc.) and unit-tested.
- `watchByProject(companyId, projectId, {jobIds})` requires the caller to supply the project's job IDs — 31-05's project detail screen should source these from its existing job-list fetch before calling this stream.
- `FinanceRepository.fetchCostCategories()` is not cached locally; 31-05's category picker will call it live. If offline category selection turns out to be required, a lightweight `CostCategories` Drift table can be added in 31-05 without touching this plan's files.
- No blockers.

---
*Phase: 31-actual-cost-capture*
*Completed: 2026-07-25*

## Self-Check: PASSED

All created/modified files found on disk; all three task commit hashes (`d8107a4`, `e8f21f5`, `b70f260`) found in git history.
