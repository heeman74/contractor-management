---
phase: 03-scheduling-engine
plan: "01"
subsystem: backend-scheduling-data-layer
tags: [postgresql, alembic, sqlalchemy, pydantic, gist-constraint, rls, scheduling]
dependency_graph:
  requires: [01-foundation, 02-offline-sync-engine]
  provides: [scheduling-db-schema, scheduling-orm-models, scheduling-pydantic-schemas]
  affects: [03-02-scheduling-service, 03-03-availability-engine, 03-04-conflict-detection]
tech_stack:
  added: [tzdata]
  patterns:
    - EXCLUDE USING GIST on TSTZRANGE for database-level booking conflict prevention
    - op.execute(raw SQL) pattern for ExcludeConstraint migrations (avoids Alembic autogenerate bug)
    - TenantScopedModel inheritance for all tenant-scoped scheduling entities
    - Base inheritance for non-business entities (ContractorScheduleLock, TravelTimeCache)
    - TYPE_CHECKING import for cross-module forward references (avoids circular imports)
    - from __future__ import annotations enabling unquoted Mapped[] type annotations
key_files:
  created:
    - backend/migrations/versions/0007_scheduling_tables.py
    - backend/app/features/scheduling/__init__.py
    - backend/app/features/scheduling/models.py
    - backend/app/features/scheduling/schemas.py
  modified:
    - backend/app/features/companies/models.py
    - backend/app/features/users/models.py
    - backend/migrations/env.py
    - backend/requirements.txt
    - backend/tests/conftest.py
decisions:
  - "op.execute(raw SQL) for all scheduling table creation — Alembic autogenerate is unreliable for ExcludeConstraint + TSTZRANGE"
  - "TravelTimeCache inherits Base directly (not BaseEntityModel) — cache entries have no version/deleted_at columns"
  - "ContractorScheduleLock inherits Base directly (not TenantScopedModel) — contractor_id IS the PK, no separate UUID id"
  - "Single tenant_isolation USING policy per table (vs. four separate SELECT/INSERT/UPDATE/DELETE policies in migration 0001) — simpler for scheduling tables which are always accessed within tenant context"
  - "TRUNCATE scheduling tables explicitly in conftest.py (no CASCADE) — single TRUNCATE statement prevents FK deadlocks; CASCADE was causing AccessExclusiveLock deadlock with new FK constraints"
metrics:
  duration: "18min"
  completed: "2026-03-06"
  tasks_completed: 2
  files_created: 4
  files_modified: 5
---

# Phase 3 Plan 1: Scheduling Data Foundation Summary

Alembic migration 0007 creates all six scheduling tables with RLS, GIST exclusion constraint, and updated_at triggers. ORM models and Pydantic schemas for the complete scheduling domain are implemented and passing lint and import checks. Existing 71 integration tests continue to pass.

## Objective

Create the database schema foundation for the scheduling engine: six PostgreSQL tables with correct constraints and RLS policies, corresponding SQLAlchemy ORM models, and Pydantic schemas for the scheduling domain.

## What Was Built

### Migration 0007 (`backend/migrations/versions/0007_scheduling_tables.py`)

Six tables created via raw `op.execute(text(...))` SQL per RESEARCH.md recommendation:

1. **contractor_schedule_locks** — Lightweight anchor table for `SELECT FOR UPDATE` per-contractor locking. `contractor_id UUID PRIMARY KEY`. No version/timestamps (lock anchor, not business entity).

2. **contractor_weekly_schedule** — Weekly working-hours template with `UNIQUE (contractor_id, day_of_week, block_index)` for multi-block-per-day support (lunch breaks). `CHECK (end_time > start_time)`.

3. **contractor_date_overrides** — Date-specific overrides with XOR CHECK constraint: `is_unavailable=TRUE AND start/end=NULL` OR `is_unavailable=FALSE AND start/end=NOT NULL AND end > start`.

4. **job_sites** — Geocoded job locations with `NUMERIC(9,6)` lat/lng for ~10cm precision.

5. **bookings** — Core scheduling table with `EXCLUDE USING GIST (contractor_id WITH =, time_range WITH &&) WHERE (deleted_at IS NULL)`. Partial constraint excludes soft-deleted bookings. Self-referential `parent_booking_id` FK for multi-day booking linkage.

6. **travel_time_cache** — ORS travel time results with `UNIQUE (company_id, lat1, lng1, lat2, lng2)`. No RLS (scoped by service layer).

Plus:
- `ALTER companies ADD COLUMN scheduling_config JSONB DEFAULT '{}'::jsonb`
- `ALTER users ADD COLUMN home_address TEXT, home_latitude NUMERIC(9,6), home_longitude NUMERIC(9,6), timezone TEXT DEFAULT 'UTC'`

All tenant-scoped tables have `ENABLE ROW LEVEL SECURITY`, `FORCE ROW LEVEL SECURITY`, `tenant_isolation` policy, and `set_updated_at()` triggers (function from migration 0002).

Downgrade verified: drops tables, triggers, policies, and column additions in correct reverse dependency order.

### ORM Models (`backend/app/features/scheduling/models.py`)

- `ContractorScheduleLock(Base)` — contractor_id as PK, company_id FK
- `ContractorWeeklySchedule(TenantScopedModel)` — contractor/day/block with lazy="raise" User relationship
- `ContractorDateOverride(TenantScopedModel)` — date-specific with is_unavailable flag
- `JobSite(TenantScopedModel)` — address + Numeric(9,6) coordinates, lazy="raise" bookings relationship
- `Booking(TenantScopedModel)` — TSTZRANGE time_range, ExcludeConstraint in `__table_args__` (documentation only), self-referential parent_booking_id relationship
- `TravelTimeCache(Base)` — fetched_at DateTime(timezone=True), no version/deleted_at

All relationships declared with `lazy="raise"` per CLAUDE.md N+1 prevention rules.

### Pydantic Schemas (`backend/app/features/scheduling/schemas.py`)

14 schemas covering the full scheduling API surface:
- `SchedulingConfig` — JSONB-backed company defaults with sensible Field defaults
- `TimeBlock`, `FreeWindow`, `BlockedInterval` — availability computation primitives
- `AvailabilityRequest`, `AvailabilityResponse` — multi-contractor availability query/response
- `BookingCreate`, `MultiDayBookingCreate`, `DayBlock` — booking creation payloads
- `BookingResponse(TenantResponseSchema)` — booking read response
- `ConflictDetail` — 409 conflict error payload
- `DateSuggestion` — multi-day scheduling suggestion
- `WeeklyScheduleCreate`, `DateOverrideCreate` — schedule management

### Updated Models

- `Company.scheduling_config: Mapped[dict | None]` — JSON column with `'{}'::jsonb` server default
- `User.home_address/home_latitude/home_longitude/timezone` — contractor scheduling fields

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 1 - Bug] conftest.py clean_tables deadlock with new scheduling FK constraints**
- **Found during:** Task 2 verification (existing tests failing after migration)
- **Issue:** Original `TRUNCATE TABLE refresh_tokens, user_roles, users, companies RESTART IDENTITY CASCADE` deadlocked because new scheduling tables (bookings, contractor_schedule_locks, etc.) have FK constraints on `users` and `companies`. PostgreSQL CASCADE TRUNCATE acquired AccessExclusiveLock on new tables while another concurrent fixture setup was acquiring locks in a different order.
- **Fix:** Extended `TRUNCATE` to explicitly list all tables in correct dependency order (scheduling leaf tables first, parent tables last) WITHOUT CASCADE. Single TRUNCATE statement acquires all locks atomically, preventing deadlock.
- **Files modified:** `backend/tests/conftest.py`
- **Commit:** `2fcc993`

**2. [Rule 2 - Missing critical functionality] TravelTimeCache inherits wrong base class**
- **Found during:** Task 2 model creation
- **Issue:** Plan said "inherit from Base with manual columns" — initially used `BaseEntityModel` which adds `version`, `created_at`, `updated_at`, `deleted_at` columns not present in the migration table schema.
- **Fix:** Changed `TravelTimeCache` to inherit `Base` directly, adding only `id` + `fetched_at` + business columns matching the migration-created table exactly.
- **Files modified:** `backend/app/features/scheduling/models.py`
- **Commit:** `2fcc993`

**3. [Rule 1 - Bug] Forward reference typing in ORM models**
- **Found during:** Task 2 ruff check
- **Issue:** `Mapped["app.features.users.models.User"]` caused `F821 Undefined name 'app'` ruff errors. Changed to `Mapped["User"]` which triggered `UP037 Remove quotes` errors.
- **Fix:** Added `from __future__ import annotations` (enables PEP 563 deferred evaluation) and `TYPE_CHECKING` block importing `User` for type annotations. This satisfies ruff's rules and avoids circular imports at runtime.
- **Files modified:** `backend/app/features/scheduling/models.py`
- **Commit:** `2fcc993`

## Verification Results

| Check | Result |
|-------|--------|
| `alembic upgrade head` | PASS |
| `alembic downgrade -1 && alembic upgrade head` | PASS |
| All 6 ORM models importable | PASS |
| All 14 Pydantic schemas importable | PASS |
| SchedulingConfig default values correct | PASS |
| Company.scheduling_config column present | PASS |
| User scheduling columns present | PASS |
| GIST constraint visible in `\d bookings` | PASS |
| `ruff check app/features/scheduling/` | PASS |
| `ruff format --check app/features/scheduling/` | PASS |
| 71 existing integration tests | PASS |

## Self-Check: PASSED

All created files confirmed present on disk. Both task commits confirmed in git log.

| Item | Status |
|------|--------|
| `backend/migrations/versions/0007_scheduling_tables.py` | FOUND |
| `backend/app/features/scheduling/__init__.py` | FOUND |
| `backend/app/features/scheduling/models.py` | FOUND |
| `backend/app/features/scheduling/schemas.py` | FOUND |
| `.planning/phases/03-scheduling-engine/03-01-SUMMARY.md` | FOUND |
| Commit `1449232` (migration 0007) | FOUND |
| Commit `2fcc993` (ORM models + schemas) | FOUND |
