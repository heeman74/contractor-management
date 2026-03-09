---
phase: 04-job-lifecycle
plan: "01"
subsystem: backend-data-layer
tags: [migration, orm, pydantic, rls, full-text-search, job-lifecycle]
dependency_graph:
  requires: [03-scheduling-engine]
  provides: [jobs-tables, client-profiles-tables, job-requests-tables, ratings-tables, bookings-job-fk, jobs-orm-models, jobs-pydantic-schemas]
  affects: [04-02-job-service, 04-03-crm-service, 04-04-job-router, 04-05-mobile-data-layer]
tech_stack:
  added: []
  patterns: [TenantScopedModel inheritance, lazy=raise relationships, StrEnum for status machines, primaryjoin with foreign() for DB-only FKs, _create_job_row test helper pattern]
key_files:
  created:
    - backend/migrations/versions/0008_job_lifecycle_tables.py
    - backend/app/features/jobs/__init__.py
    - backend/app/features/jobs/models.py
    - backend/app/features/jobs/schemas.py
  modified:
    - backend/migrations/env.py
    - backend/tests/conftest.py
    - backend/tests/scheduling/conftest.py
    - backend/tests/scheduling/test_booking_conflicts.py
    - backend/tests/scheduling/test_multiday.py
    - backend/tests/scheduling/test_availability.py
    - backend/tests/scheduling/test_travel_time.py
decisions:
  - "Job.bookings relationship uses primaryjoin with foreign() string expression — Booking.job_id has no ORM-level ForeignKey() (FK lives only in DB via migration 0008 ALTER TABLE)"
  - "StatusHistoryEntry embedded in JobResponse.status_history as list[dict[str,Any]] — JSONB column, no separate ORM model needed"
  - "JobTransitionRequest includes version: int for optimistic locking — service layer validates before writing transition"
  - "StrEnum chosen for JobStatus/Priority/Urgency/Direction — type-safe comparisons and accurate OpenAPI schema generation"
  - "_create_job_row helper added to scheduling conftest — bookings_job_id_fkey (migration 0008) requires real jobs rows; seed_contractor now provisions one stub job per test run"
metrics:
  duration: "18 min"
  completed: "2026-03-09"
  tasks: 2
  files: 11
---

# Phase 4 Plan 01: Job Lifecycle Data Layer Summary

**One-liner:** Alembic migration 0008 with 5 new tables (jobs, client_profiles, client_properties, job_requests, ratings), bookings.job_id FK, SQLAlchemy ORM models with lazy="raise", Pydantic schemas with StrEnum status machines, and scheduling test updates for the new FK constraint.

## Tasks Completed

| Task | Name | Commit | Files |
|------|------|--------|-------|
| 1 | Alembic migration 0008 — job lifecycle tables | 1b23517 | backend/migrations/versions/0008_job_lifecycle_tables.py |
| 2 | ORM models, Pydantic schemas, and test fixture updates | 693a57f | models.py, schemas.py, __init__.py, env.py, conftest.py files (x7) |

## What Was Built

### Migration 0008

Five new PostgreSQL tables with RLS + FORCE RLS + tenant_isolation policies:

1. **jobs** — Core job lifecycle table. Status machine (quote/scheduled/in_progress/complete/invoiced/cancelled) enforced via CHECK constraint. status_history JSONB array for audit trail. priority (low/medium/high/urgent) CHECK. GIN index on search_vector (tsvector). Composite index on (company_id, status) for tenant-scoped list queries. Separate tsvector update trigger function `update_jobs_search_vector()` auto-populates search_vector on INSERT/UPDATE of description or notes.

2. **bookings.job_id FK** — `ALTER TABLE bookings ADD CONSTRAINT bookings_job_id_fkey FOREIGN KEY (job_id) REFERENCES jobs(id)`. Deferred from migration 0007 (jobs table didn't exist yet).

3. **client_profiles** — CRM record per client per tenant. user_id UNIQUE. average_rating Numeric(3,2) denormalized field. preferred_contractor_id nullable FK.

4. **client_properties** — Client-to-job-site associations. nickname, is_default for primary property designation.

5. **job_requests** — Inbound requests (portal or manual). Supports anonymous submissions (submitted_name/email/phone) and authenticated (client_id FK). Converted to job via converted_job_id FK.

6. **ratings** — Star ratings (1-5 CHECK). direction CHECK (admin_to_client/client_to_company). UNIQUE(job_id, direction) enforces one rating per direction per job.

All tables have complete `downgrade()` reversing in dependency order.

### ORM Models (app/features/jobs/models.py)

All 5 models inherit `TenantScopedModel` (id UUID PK, company_id FK, version, timestamps).

Key patterns:
- `from __future__ import annotations` + `TYPE_CHECKING` imports for circular-import safety (established Phase 3 pattern)
- All relationships use `lazy="raise"` to surface accidental lazy loads loudly
- `Job.bookings` uses `primaryjoin="foreign(Booking.job_id) == Job.id"` — Booking.job_id has no ORM-level ForeignKey(); the FK exists only at DB level
- `CheckConstraint` in `__table_args__` mirrors DB-level constraints for ORM documentation
- `UniqueConstraint` on Rating `(job_id, direction)` matches DB UNIQUE constraint

### Pydantic Schemas (app/features/jobs/schemas.py)

- **Enums**: `JobStatus`, `JobPriority`, `JobUrgency`, `RatingDirection`, `JobRequestStatus` — all use `StrEnum` for type safety
- **Job**: `JobCreate`, `JobUpdate` (all optional for PATCH), `JobResponse` (extends `BaseResponseSchema`), `JobTransitionRequest` (with `version: int` for optimistic locking), `StatusHistoryEntry`, `JobSearchRequest`
- **ClientProfile**: Create/Update/Response schemas
- **ClientProperty**: Create/Response schemas
- **JobRequest**: `JobRequestCreate`, `JobRequestResponse`, `JobRequestReviewAction` (accepted/declined/info_requested)
- **Rating**: `RatingCreate` (stars with `Field(ge=1, le=5)`), `RatingResponse`

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 1 - Lint] Removed unused imports in models.py and fixed import ordering in schemas.py**
- **Found during:** Task 2 ruff check
- **Issue:** `datetime.datetime` and `sqlalchemy.orm.foreign` unused in models.py; import block unsorted in schemas.py
- **Fix:** Removed unused imports, ran `ruff check --fix` and `ruff format`
- **Files modified:** models.py, schemas.py
- **Commit:** 693a57f

**2. [Rule 3 - Blocking] Scheduling tests failed with FK violation after bookings_job_id_fkey added**
- **Found during:** Task 2 test run
- **Issue:** All scheduling tests that create bookings via API or direct SQL used `uuid.uuid4()` as job_id. Migration 0008's `bookings_job_id_fkey` FK constraint rejects random UUIDs that don't exist in `jobs`. The service's `IntegrityError` catch in `repository.py` converts FK violations (as well as GIST violations) to `SchedulingConflictError([])`, causing tests to see 409 with empty conflicts instead of 201.
- **Fix:** Added `_create_job_row()` helper to scheduling conftest that inserts a minimal `jobs` row. Updated `seed_contractor` fixture to call it and include `job_id` in return dict. Updated `booking_factory` to create a job row per booking. Updated all scheduling test files to use `seed_contractor_weekly_schedule["job_id"]` instead of `uuid.uuid4()`.
- **Files modified:** tests/scheduling/conftest.py, test_booking_conflicts.py, test_multiday.py, test_availability.py, test_travel_time.py
- **Commit:** 693a57f

## Self-Check: PASSED

- FOUND: backend/migrations/versions/0008_job_lifecycle_tables.py
- FOUND: backend/app/features/jobs/__init__.py
- FOUND: backend/app/features/jobs/models.py
- FOUND: backend/app/features/jobs/schemas.py
- FOUND commit 1b23517: chore(04-01): Alembic migration 0008 — job lifecycle tables
- FOUND commit 693a57f: feat(04-01): ORM models, Pydantic schemas, and test fixture updates
- All 118 tests pass
