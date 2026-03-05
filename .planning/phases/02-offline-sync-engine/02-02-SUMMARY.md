---
phase: 02-offline-sync-engine
plan: "02"
subsystem: backend-sync
tags: [sync, delta-sync, soft-delete, alembic, idempotent, postgresql-trigger]
dependency_graph:
  requires: [01-02, 01-03]
  provides: [sync-endpoint, soft-delete-columns, updated-at-trigger, idempotent-creates]
  affects: [companies-service, users-service, company-schema, user-schema]
tech_stack:
  added:
    - sqlalchemy.dialects.postgresql.insert (for ON CONFLICT DO NOTHING/DO UPDATE)
    - sqlalchemy.or_ (for tombstone delta filter)
  patterns:
    - PostgreSQL trigger for updated_at (bypass ORM-level onupdate limitation)
    - INSERT ON CONFLICT DO NOTHING for offline sync idempotency
    - Cursor-based delta pull with epoch-default for full first-launch download
    - Tombstone propagation via deleted_at > cursor filter
key_files:
  created:
    - backend/migrations/versions/0002_soft_delete_sync.py
    - backend/app/features/sync/__init__.py
    - backend/app/features/sync/schemas.py
    - backend/app/features/sync/service.py
    - backend/app/features/sync/router.py
  modified:
    - backend/app/features/companies/models.py
    - backend/app/features/companies/schemas.py
    - backend/app/features/companies/service.py
    - backend/app/features/users/models.py
    - backend/app/features/users/schemas.py
    - backend/app/features/users/service.py
    - backend/app/main.py
decisions:
  - "PostgreSQL trigger set_updated_at() used instead of SQLAlchemy onupdate — fires on bulk/raw SQL updates that bypass ORM"
  - "Default sync cursor is 2000-01-01T00:00:00Z — enables full download on first launch without client needing to pass epoch"
  - "UserRole.updated_at added as nullable (not NOT NULL) to avoid migration errors on existing rows"
  - "on_conflict_do_nothing uses index_elements=[id] — relies on primary key uniqueness constraint"
  - "server_timestamp in SyncResponse uses datetime.now(timezone.utc).isoformat() — ISO8601 string for Android/Flutter compatibility"
metrics:
  duration: "4 min"
  completed_date: "2026-03-05"
  tasks_completed: 2
  files_created: 5
  files_modified: 7
---

# Phase 02 Plan 02: Backend Sync Infrastructure Summary

**One-liner:** Delta sync endpoint (GET /api/v1/sync?cursor=) with PostgreSQL trigger for updated_at, soft-delete tombstones, and idempotent INSERT ON CONFLICT DO NOTHING across all entity tables.

## What Was Built

### Task 1: Alembic Migration 0002 + Model Updates (commit: 9a5ef92)

Created `backend/migrations/versions/0002_soft_delete_sync.py`:
- Added `deleted_at` (nullable `timestamptz`) to `companies`, `users`, `user_roles`
- Added `updated_at` to `user_roles` (was missing from initial migration — required for delta sync cursor)
- Created `set_updated_at()` PostgreSQL trigger function (fires BEFORE UPDATE on each row)
- Attached trigger to all three entity tables

Updated SQLAlchemy models to reflect the new columns:
- `Company.deleted_at: Mapped[datetime | None]`
- `User.deleted_at: Mapped[datetime | None]`
- `UserRole.updated_at: Mapped[datetime | None]`, `UserRole.deleted_at: Mapped[datetime | None]`

### Task 2: Sync Module + Idempotent Services (commit: 25337a0)

Created `backend/app/features/sync/` module:
- `schemas.py`: `SyncResponse` with `companies`, `users`, `user_roles`, `server_timestamp`
- `service.py`: Three delta query functions using `or_(updated_at > since, deleted_at > since)` for tombstone inclusion
- `router.py`: `GET /api/v1/sync?cursor=` endpoint, defaulting cursor to epoch 2000-01-01 for full first-launch download

Updated company and user services:
- `companies/service.py`: `create_company_idempotent()` + `update_company_server_wins()` using PostgreSQL `insert().on_conflict_do_nothing()`
- `users/service.py`: `create_user_idempotent()` + `create_user_role_idempotent()` with same pattern

Updated schemas:
- `CompanyResponse`: added `deleted_at: datetime | None = None`
- `UserResponse`: added `deleted_at: datetime | None = None`
- `UserRoleResponse`: added `updated_at: datetime | None = None`, `deleted_at: datetime | None = None`
- `CompanyCreate`: added `id: uuid.UUID | None = None` (client-provided UUID for sync deduplication)

Registered sync router in `main.py` under `/api/v1` prefix.

## Decisions Made

| Decision | Rationale |
|----------|-----------|
| PostgreSQL trigger for `updated_at` | SQLAlchemy `onupdate=func.now()` is ORM-level only; bulk SQL updates bypass it |
| Default cursor = 2000-01-01 | Epoch default enables full download on first launch without client logic |
| `on_conflict_do_nothing(index_elements=["id"])` | Uses PK uniqueness; silent on duplicate — correct for sync retry deduplication |
| `UserRole.updated_at` as nullable | Avoids NOT NULL constraint failure on existing rows during migration |
| `server_timestamp` as `str` (ISO8601) | String type avoids timezone serialization complexity; Flutter/Android parse easily |

## Deviations from Plan

None — plan executed exactly as written.

## Self-Check

Files created:
- [x] `backend/migrations/versions/0002_soft_delete_sync.py`
- [x] `backend/app/features/sync/__init__.py`
- [x] `backend/app/features/sync/schemas.py`
- [x] `backend/app/features/sync/service.py`
- [x] `backend/app/features/sync/router.py`

Commits:
- [x] 9a5ef92 — Task 1: migration + model updates
- [x] 25337a0 — Task 2: sync module + idempotent services

## Self-Check: PASSED
