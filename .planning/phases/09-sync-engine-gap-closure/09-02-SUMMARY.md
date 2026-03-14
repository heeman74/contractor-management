---
phase: 09-sync-engine-gap-closure
plan: "02"
subsystem: sync-engine
tags: [sync, e2e-tests, gap-closure, flutter, backend]
completed_date: "2026-03-14"
duration: 15min
tasks_completed: 2
files_modified: 2

dependency_graph:
  requires: [09-01]
  provides: [phase-9-e2e-tests]
  affects: [mobile/test/e2e, backend/tests/integration]

tech_stack:
  added: []
  patterns:
    - "Real Drift in-memory DB + real SyncRegistry + mock DioClient for Flutter E2E"
    - "Full 15-entity pullDelta() coverage test with shared UUID constants"
    - "Backend sync endpoint completeness test with flat array verification"

key_files:
  created:
    - mobile/test/e2e/phase_9_sync_gap_closure_e2e_test.dart
    - backend/tests/integration/test_phase_9_sync_e2e.py
  modified: []

decisions:
  - "Mock response uses `issued_at` set to a real timestamp (not null) because Drift Invoices.issuedAt is non-nullable — null issued_at causes InvalidDataException"
  - "int lat/lng in mock data (gps_latitude: 37 not 37.0) included as separate test case to verify the 'is num' type check in JobSyncHandler"
  - "Backend invoice test uses generate endpoint (not POST /invoices/) — direct invoice creation requires job in complete status; generate flow exercises real approval lifecycle"
  - "Flat quote/invoice line item arrays verified both via: (a) QuoteSyncHandler nested line_items and (b) QuoteLineItemSyncHandler flat array — idempotent upsert handles deduplication"
---

# Phase 9 Plan 02: Sync Engine Gap Closure — E2E Tests Summary

E2E test suite proving pullDelta() processes all 15 entity types, GPS/FK field mapping works, per-entity error handling skips without aborting, and backend sync endpoint returns complete flat arrays.

## What Was Built

### Task 1: Flutter E2E Tests (12 tests)

`mobile/test/e2e/phase_9_sync_gap_closure_e2e_test.dart` — 938 lines covering:

- **INFRA-04**: pullDelta persists all 15 entity types into Drift tables (companies, users, user_roles, jobs, bookings, job_sites, job_notes, time_entries, attachments, client_profiles, job_requests, quotes, quote_line_items, invoices, invoice_line_items)
- **FIELD-02**: GPS field mapping — `gpsLatitude`, `gpsLongitude`, `gpsAddress`, `quoteId`, `invoiceId` correctly mapped from JSON into Drift `JobsCompanion`
- **FIELD-02** (edge): int lat/lng (server JSON returns 37 not 37.0) handled via `is num` type check
- **INFRA-04**: Per-entity failure — invalid job (missing id) skips gracefully; companies/users still inserted; cursor still updated
- **INFRA-04**: Cursor null before first pull, set to `server_timestamp` after; updates on second pull
- **SCHED-03**: Booking cross-device propagation — time_range_start/end parsed, soft-delete tombstone propagated
- **BIZ-01**: Quote + quote_line_items (nested and flat) persisted with correct FKs
- **BIZ-03**: Invoice + invoice_line_items (nested and flat) persisted with correct FKs

### Task 2: Backend Integration Tests (4 tests)

`backend/tests/integration/test_phase_9_sync_e2e.py` — 365 lines covering:

- **INFRA-04**: All 15 entity type keys present in `GET /api/v1/sync` response; each is a list
- **BIZ-01**: `quote_line_items` is a flat array with `quote_id` FK (not nested inside quotes)
- **BIZ-03**: `invoice_line_items` is a flat array with `invoice_id` FK (exercises full quote approval + invoice generate lifecycle)
- **FIELD-02**: `gps_latitude`, `gps_longitude`, `gps_address` keys present in job response (values may be null)

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 1 - Bug] JobNotes mock data used wrong field name**
- **Found during:** Task 1 (test run)
- **Issue:** Mock data had `content` field but `NoteSyncHandler` expects `body`; `ClientProfiles` mock had `business_name` / `contact_name` but the actual fields are `billing_address`, `tags`, etc.
- **Fix:** Updated mock data to match actual handler field names (`body`, `billing_address`, etc.)
- **Files modified:** `mobile/test/e2e/phase_9_sync_gap_closure_e2e_test.dart`

**2. [Rule 1 - Bug] TimeEntry mock data used wrong field names**
- **Found during:** Task 1 (test run)
- **Issue:** Mock used `clock_in`/`clock_out`/`duration_minutes` but `TimeEntrySyncHandler` expects `clocked_in_at`/`clocked_out_at`/`duration_seconds`
- **Fix:** Updated mock data to correct field names
- **Files modified:** `mobile/test/e2e/phase_9_sync_gap_closure_e2e_test.dart`

**3. [Rule 1 - Bug] Invoice mock had null issued_at causing InvalidDataException**
- **Found during:** Task 1 (test run)
- **Issue:** `Invoices.issuedAt` is non-nullable in Drift schema; null value causes `InvalidDataException` at insert time
- **Fix:** Provided real `issued_at: '2026-03-14T00:00:00Z'` in mock data
- **Files modified:** `mobile/test/e2e/phase_9_sync_gap_closure_e2e_test.dart`

**4. [Rule 1 - Bug] greaterThanOrEqualTo([]) used as length matcher**
- **Found during:** Task 1 (test failure on BIZ-01 test)
- **Issue:** `expect(list, greaterThanOrEqualTo([]))` compares lists not lengths, always fails
- **Fix:** Changed to `expect(list.length, greaterThanOrEqualTo(1))`
- **Files modified:** `mobile/test/e2e/phase_9_sync_gap_closure_e2e_test.dart`

**5. [Rule 1 - Bug] Backend invoice test used direct POST /invoices/ which requires complete status**
- **Found during:** Task 2 (test run)
- **Issue:** `POST /api/v1/invoices/` returns 409 if job is not in complete status
- **Fix:** Replaced with full approval lifecycle using `_create_invoice_via_generate()` helper: send quote → add client role → re-login → approve → transition in_progress → complete → generate invoice
- **Files modified:** `backend/tests/integration/test_phase_9_sync_e2e.py`

**6. [Rule 1 - Bug] Backend used non-existent /api/v1/users/me endpoint**
- **Found during:** Task 2 (test failure)
- **Issue:** Helper tried to GET `/api/v1/users/me` to resolve user_id; this endpoint doesn't exist
- **Fix:** Used `seed_two_tenants["tenant_a_user_id"]` which is already available in the fixture
- **Files modified:** `backend/tests/integration/test_phase_9_sync_e2e.py`

## Self-Check: PASSED

- FOUND: `mobile/test/e2e/phase_9_sync_gap_closure_e2e_test.dart`
- FOUND: `backend/tests/integration/test_phase_9_sync_e2e.py`
- FOUND: commit a47bc54 (Flutter E2E tests — 12 passing)
- FOUND: commit c460345 (Backend integration tests — 4 passing)
