---
phase: 04-job-lifecycle
plan: "05"
subsystem: mobile-data-layer
tags: [drift, dao, sync-handlers, offline-first, job-lifecycle, crm]
dependency_graph:
  requires: [02-offline-sync-engine, 01-foundation]
  provides: [mobile-job-data-layer]
  affects: [04-06, 04-07]
tech_stack:
  added: []
  patterns:
    - Drift table definitions with JSON TEXT columns for JSONB equivalents
    - Transactional outbox dual-write (entity + sync_queue in single transaction)
    - Freezed domain entities with custom getters via const constructor workaround
    - SyncHandler push/pull pattern for new entity types
    - DioClient.pushWithIdempotency extended with method param (POST/PATCH/DELETE)
key_files:
  created:
    - mobile/lib/core/database/tables/jobs.dart
    - mobile/lib/core/database/tables/client_profiles.dart
    - mobile/lib/core/database/tables/client_properties.dart
    - mobile/lib/core/database/tables/job_requests.dart
    - mobile/lib/features/jobs/domain/job_status.dart
    - mobile/lib/features/jobs/domain/job_entity.dart
    - mobile/lib/features/jobs/domain/job_request_entity.dart
    - mobile/lib/features/jobs/domain/client_profile_entity.dart
    - mobile/lib/features/jobs/data/job_dao.dart
    - mobile/lib/features/jobs/data/job_sync_handler.dart
    - mobile/lib/features/jobs/data/client_profile_sync_handler.dart
    - mobile/lib/features/jobs/data/job_request_sync_handler.dart
  modified:
    - mobile/lib/core/database/app_database.dart
    - mobile/lib/core/di/service_locator.dart
    - mobile/lib/core/network/dio_client.dart
decisions:
  - "JSON TEXT columns for statusHistory and tags in Drift/SQLite — mirrors JSONB pattern from RESEARCH.md Pattern 3"
  - "JobStatus enum uses switch expression for backendValue — maps inProgress to 'in_progress' snake_case"
  - "JobEntity uses const JobEntity._() private constructor to enable jobStatus getter on Freezed class"
  - "DioClient.pushWithIdempotency extended with method param defaulting to POST — backward compatible, enables PATCH/DELETE for sync"
  - "requestStatus column named to avoid conflict with Drift reserved word 'status' at table level (no conflict in practice but self-documenting)"
metrics:
  duration: 5 min
  completed: 2026-03-09T02:05:00Z
  tasks_completed: 2
  files_created: 12
  files_modified: 3
---

# Phase 4 Plan 05: Mobile Data Layer Summary

**One-liner:** Complete offline-first mobile data layer with 4 Drift tables, JobStatus state machine, Freezed entities, transactional outbox DAO, and 3 registered sync handlers for job lifecycle, CRM, and job requests.

## What Was Built

### Task 1: Drift Tables, Domain Entities, Database Migration

**4 Drift table definitions** following the established `Users`/`Companies` pattern:

- **`Jobs`** — core business entity with status lifecycle, JSON TEXT statusHistory/tags, soft-delete
- **`ClientProfiles`** — CRM extension of the client User record with billing/tags/ratings
- **`ClientProperties`** — saved property addresses per client referencing Phase 3 JobSite UUIDs
- **`JobRequests`** — client enquiry queue with anonymous web form support (submittedName/Email/Phone)

**Domain entities (Freezed):**

- **`JobStatus`** enum — 6 values (quote, scheduled, inProgress, complete, invoiced, cancelled) with `fromString()`, `backendValue` (snake_case), and `displayLabel` (human-readable)
- **`JobEntity`** — all job fields with `statusHistory` as `List<Map<String, dynamic>>` decoded from JSON TEXT, and `jobStatus` getter returning typed `JobStatus`
- **`JobRequestEntity`** — full request fields including anonymous submitter info and Accept/Decline tracking
- **`ClientProfileEntity`** — CRM fields with decoded `tags` list and cached `averageRating`

**AppDatabase migration:** schemaVersion bumped from 2 to 3 with `if (from < 3)` migration branch creating all 4 new tables.

### Task 2: JobDao + Sync Handlers + Service Locator

**`JobDao`** (`@DriftAccessor(tables: [Jobs, ClientProfiles, ClientProperties, JobRequests, SyncQueue])`):

- Reactive streams: `watchJobsByCompany`, `watchJobsByContractor`, `watchJobsByClient`, `watchPendingRequestsByCompany`, `watchClientProfiles`
- Transactional outbox dual-write: `insertJob`, `updateJobStatus`, `updateJob`, `softDeleteJob`, `insertJobRequest`
- Sync pull upserts: `upsertJobFromSync`, `upsertClientProfileFromSync`, `upsertClientPropertyFromSync`, `upsertJobRequestFromSync`
- JSON decoders in row mappers use `whereType<T>()` per Flutter type-safety rules

**3 Sync handlers:**
- `JobSyncHandler` — routes CREATE→POST /jobs/, UPDATE→PATCH /jobs/{id}, DELETE→DELETE /jobs/{id}
- `ClientProfileSyncHandler` — CREATE→POST /clients/profiles, UPDATE→PATCH /clients/profiles/{id}
- `JobRequestSyncHandler` — CREATE→POST /jobs/requests (pull-only for status transitions)

**`DioClient.pushWithIdempotency` extended** with optional `method` parameter (defaults to 'POST', supports 'PATCH'/'DELETE') using `_dio.request()` for method routing.

**`service_locator.dart` updated** to register all 3 sync handlers in SyncRegistry and expose `JobDao` as a GetIt singleton via `db.jobDao`.

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 1 - Bug] Extended DioClient.pushWithIdempotency to support PATCH/DELETE methods**
- **Found during:** Task 2 (sync handler implementation)
- **Issue:** `pushWithIdempotency` only accepted POST. Sync handlers for UPDATE and DELETE operations would have sent the wrong HTTP method, causing 405 errors on the backend.
- **Fix:** Changed `_dio.post()` to `_dio.request()` with an optional `method` parameter (default 'POST'). Fully backward-compatible — all existing calls (CompanySyncHandler, UserSyncHandler, UserRoleSyncHandler) continue to work unchanged.
- **Files modified:** `mobile/lib/core/network/dio_client.dart`
- **Commit:** 2fdf568

## Self-Check: PASSED

All 12 created files verified on disk. Both task commits exist:
- `4364746` — feat(04-05): Drift tables, domain entities, and database migration
- `2fdf568` — feat(04-05): JobDao with transactional outbox, sync handlers, and DI registration
