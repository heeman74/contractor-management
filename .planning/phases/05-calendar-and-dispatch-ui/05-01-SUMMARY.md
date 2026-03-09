---
phase: 05-calendar-and-dispatch-ui
plan: "01"
subsystem: data-layer
tags:
  - drift
  - sqlite
  - booking
  - job-site
  - sync
  - offline-first
  - delay-reporting
dependency_graph:
  requires:
    - "04-job-lifecycle: Booking model, Job model, JobStatus, sync engine"
    - "02-offline-sync-engine: SyncEngine, SyncHandler, SyncRegistry, outbox pattern"
  provides:
    - "Drift Bookings table (schema v4)"
    - "Drift JobSites table (schema v4)"
    - "BookingDao with transactional outbox dual-write"
    - "BookingEntity Freezed domain object"
    - "BookingSyncHandler (push+pull)"
    - "JobSiteSyncHandler (pull-only)"
    - "PATCH /jobs/{id}/delay backend endpoint"
    - "Delta sync pull includes bookings and job_sites"
  affects:
    - "05-02: Calendar UI depends on Bookings table and BookingDao"
    - "05-03: Dispatch drawer depends on watchUnscheduledJobs LEFT JOIN"
tech_stack:
  added:
    - "Drift Bookings table: multi-day booking support via dayIndex/parentBookingId"
    - "Drift JobSites table: geocoded location sync pull"
    - "BookingEntity: Freezed domain entity matching Bookings table"
    - "BookingDao: stream queries + transactional outbox dual-write"
    - "BookingSyncHandler: push (CREATE/UPDATE/DELETE) + pull (upsert)"
    - "JobSiteSyncHandler: pull-only (read-only on mobile)"
    - "DelayReportRequest: Pydantic schema for delay reporting"
    - "JobService.report_delay: optimistic locking + status validation"
    - "PATCH /jobs/{id}/delay: delay endpoint with route ordering"
    - "SyncService.get_bookings_since / get_job_sites_since"
    - "JobSiteResponse: sync pull schema for job_sites"
    - "SyncResponse extended with bookings + job_sites lists"
  patterns:
    - "Transactional outbox dual-write (entity + sync_queue in single transaction)"
    - "Server-wins upsert for sync pull (insertOnConflictUpdate)"
    - "LEFT JOIN in Drift for unscheduled jobs query (watchUnscheduledJobs)"
    - "List replacement for status_history/delay_entry append (not in-place)"
    - "Route ordering: delay endpoint BEFORE {job_id} catch-all"
    - "Pull-only handler pattern for read-only mobile entities (JobSiteSyncHandler)"
key_files:
  created:
    - mobile/lib/core/database/tables/bookings.dart
    - mobile/lib/core/database/tables/job_sites.dart
    - mobile/lib/features/schedule/data/booking_dao.dart
    - mobile/lib/features/schedule/data/booking_sync_handler.dart
    - mobile/lib/features/schedule/data/job_site_sync_handler.dart
    - mobile/lib/features/schedule/domain/booking_entity.dart
  modified:
    - mobile/lib/core/database/app_database.dart
    - mobile/lib/core/di/service_locator.dart
    - backend/app/features/jobs/schemas.py
    - backend/app/features/jobs/service.py
    - backend/app/features/jobs/router.py
    - backend/app/features/sync/service.py
    - backend/app/features/sync/schemas.py
    - backend/app/features/sync/router.py
decisions:
  - "Drift schema v4: Bookings + JobSites tables added via migration from v3"
  - "BookingDao includes Jobs in @DriftAccessor tables for watchUnscheduledJobs LEFT JOIN"
  - "JobSiteSyncHandler is pull-only — push() throws StateError (read-only on mobile)"
  - "delay endpoint declared BEFORE GET /jobs/{job_id} to prevent FastAPI route shadowing"
  - "JobSiteResponse is a flat Pydantic schema (not inheriting from BaseResponseSchema) to avoid import cycle risks with scheduling models"
  - "bookings/job_sites fields in SyncResponse default to empty list for Phase 4 client backwards compatibility"
  - "import 'package:drift/drift.dart' hide isNotNull, isNull in DAO files (established project pattern)"
metrics:
  duration: 13 minutes
  completed: "2026-03-09"
  tasks: 2
  files_created: 6
  files_modified: 8
---

# Phase 5 Plan 01: Data Foundation for Calendar and Dispatch — Summary

**One-liner:** Drift schema v4 with Bookings/JobSites tables, BookingDao with transactional outbox dual-write and LEFT JOIN unscheduled jobs query, BookingSyncHandler/JobSiteSyncHandler, BookingEntity, and backend PATCH /jobs/{id}/delay endpoint with sync pull extension for bookings/job_sites.

## What Was Built

### Flutter Data Layer (Task 1)

**Drift Schema v4:**
- `Bookings` table: mirrors backend Booking model, columns for id, companyId, contractorId, jobId, jobSiteId (nullable), timeRangeStart, timeRangeEnd, dayIndex (nullable), parentBookingId (nullable), notes (nullable), version, createdAt, updatedAt, deletedAt. UUID PK via clientDefault.
- `JobSites` table: read-only sync pull table, columns for id, companyId, address, lat/lng (nullable Real), formattedAddress (nullable), version, timestamps.
- `app_database.dart`: schemaVersion bumped 3→4, both tables added to `@DriftDatabase`, BookingDao added to daos list, v3→v4 migration creates both tables.

**BookingEntity:**
- Freezed class with all Booking fields. Required fields placed before nullable ones (dart lint compliance). Includes `fromJson` factory for JSON serialization.

**BookingDao (`@DriftAccessor` on Bookings, Jobs, SyncQueue):**
- `watchBookingsByContractorAndDate`: Stream filtered by contractorId + date range [dayStart, dayStart+1day) + non-deleted.
- `watchBookingsByCompanyAndDateRange`: Stream for multi-day calendar views.
- `watchUnscheduledJobs`: LEFT JOIN Jobs against Bookings — returns jobs with no active booking on the given date (for dispatch drawer). Statuses 'quote'/'scheduled' only.
- `insertBooking`, `updateBookingTime`, `softDeleteBooking`: all transactional outbox dual-write (entity table + sync_queue in single transaction, no orphaned items).
- `upsertBookingFromSync`: server-wins insertOnConflictUpdate for sync pull (no outbox entry).
- `_buildQueueEntry`, `_bookingPayload`: helpers following established job_dao.dart patterns.

**Sync Handlers:**
- `BookingSyncHandler`: push CREATE→POST, UPDATE→PATCH, DELETE→PATCH to `/scheduling/bookings[/{id}]`. Pull upserts into local bookings table.
- `JobSiteSyncHandler`: pull-only. Push throws StateError. Pull upserts into local jobSites table. Parses lat/lng from JSON `num` → `double`.

**Service Locator:**
- BookingSyncHandler and JobSiteSyncHandler registered in SyncRegistry.
- BookingDao registered as GetIt singleton.

### Backend (Task 2)

**DelayReportRequest schema:** `reason` (str, min_length=1), `new_eta` (date), `version` (int). Docstring explains status_history append semantics.

**JobService.report_delay:**
1. Fetch job, 404 if not found.
2. Version check, 409 on conflict.
3. Status validation — only 'scheduled' or 'in_progress', 422 otherwise.
4. Build delay_entry dict with type, reason, new_eta, timestamp, user_id.
5. List replacement on status_history (never in-place append — Pitfall 3).
6. Update scheduled_completion_date = data.new_eta.
7. Bump version, flush, refresh, return.

**PATCH /jobs/{job_id}/delay:** Declared BEFORE GET /jobs/{job_id} to prevent FastAPI route shadowing (literal path segment "delay" before UUID catch-all). Delegates to JobService.report_delay. Returns JobResponse.

**SyncService extensions:** `get_bookings_since` and `get_job_sites_since` — follow existing delta sync pattern, filter by `updated_at > since OR deleted_at > since`, RLS auto-scoped.

**SyncResponse extension:** Added `bookings: list[BookingResponse] = []` and `job_sites: list[JobSiteResponse] = []`. JobSiteResponse is a flat Pydantic schema with `from_attributes=True` for ORM compat. Both default to empty lists for Phase 4 client backwards compatibility.

## Deviations from Plan

### Auto-fixed Issues

None — plan executed as written with one structural note:

**Schema approach for JobSiteResponse:** The plan referred to the sync pull extension using existing patterns. JobSiteResponse was added to `sync/schemas.py` as a new flat schema (rather than reusing scheduling/schemas.py) to avoid potential import cycle issues — sync/schemas.py importing from scheduling/schemas.py while scheduling/models.py must be side-effect imported before mapper registry resolves. The BookingResponse was imported from scheduling/schemas.py as it already existed and worked correctly.

## Verification Results

- Drift schema version 4 defined (schemaVersion = 4)
- Bookings and JobSites tables added with migration block
- BookingDao: watchBookingsByContractorAndDate, watchBookingsByCompanyAndDateRange, watchUnscheduledJobs (LEFT JOIN), insertBooking, updateBookingTime, softDeleteBooking (all with outbox dual-write), upsertBookingFromSync
- BookingSyncHandler: push (CREATE/UPDATE/DELETE) + pull registered in SyncRegistry
- JobSiteSyncHandler: pull-only registered in SyncRegistry
- PATCH /jobs/{id}/delay: declared before GET /jobs/{job_id}
- ruff check: all files pass
- ruff format: all files formatted
- pytest: 162 tests passed, 0 failures

## Self-Check: PASSED

Files created/modified:
- mobile/lib/core/database/tables/bookings.dart: FOUND
- mobile/lib/core/database/tables/job_sites.dart: FOUND
- mobile/lib/features/schedule/data/booking_dao.dart: FOUND
- mobile/lib/features/schedule/data/booking_sync_handler.dart: FOUND
- mobile/lib/features/schedule/data/job_site_sync_handler.dart: FOUND
- mobile/lib/features/schedule/domain/booking_entity.dart: FOUND
- mobile/lib/core/database/app_database.dart: FOUND (modified)
- mobile/lib/core/di/service_locator.dart: FOUND (modified)
- backend/app/features/jobs/schemas.py: FOUND (modified)
- backend/app/features/jobs/service.py: FOUND (modified)
- backend/app/features/jobs/router.py: FOUND (modified)
- backend/app/features/sync/service.py: FOUND (modified)
- backend/app/features/sync/schemas.py: FOUND (modified)
- backend/app/features/sync/router.py: FOUND (modified)

Commits:
- f5d276a: feat(05-01): Drift schema v4 with Bookings/JobSites tables, BookingDao, and sync handlers
- 334d631: feat(05-01): Backend delay endpoint and sync pull extension for bookings/job_sites
