---
phase: 06-field-workflow
plan: "01"
subsystem: backend
tags: [fastapi, sqlalchemy, alembic, postgresql, rls, file-upload, sync, gps, geocoding]

# Dependency graph
requires:
  - phase: 06-field-workflow
    plan: "00"
    provides: Wave 0 test stubs (test_field_workflow.py)
  - phase: 05-calendar-and-dispatch-ui
    provides: existing sync endpoint, SyncResponse, JobService patterns

provides:
  - migration 0009: job_notes, attachments, time_entries tables with RLS
  - GPS columns on jobs (gps_latitude, gps_longitude, gps_address)
  - JobNote, Attachment, TimeEntry ORM models
  - Phase 6 Pydantic schemas (JobNoteCreate/Response, AttachmentResponse, TimeEntry*)
  - REST endpoints: POST/GET /jobs/{job_id}/notes, POST/PATCH/GET /jobs/{job_id}/time-entries
  - POST /api/v1/files/upload file upload endpoint with disk storage
  - /files StaticFiles mount for serving uploaded attachments
  - Sync endpoint extended with job_notes, time_entries, attachments delta pull
  - GPS reverse geocoding on update_job_gps via ORSGeocodingProvider

affects:
  - 06-02 (mobile DAOs already created — backend API surface now complete)
  - 06-03 through 06-06 (all mobile plans depend on this backend API)

# Tech tracking
tech-stack:
  added:
    - aiofiles (already present, now used for attachment uploads too)
  patterns:
    - "One-active-session-per-contractor: auto-close previous active entry on new clock-in"
    - "JSONB list replacement for adjustment_log (Pitfall 3: never in-place append)"
    - "GPS geocode fail-safe: store coords with gps_address=None, retry on next sync"
    - "Phase 6 sync fields default=[] for backwards compatibility with Phase 5 clients"
    - "StaticFiles mounted at /files (uploads/ dir) matching remote_url prefix in Attachment records"

key-files:
  created:
    - backend/migrations/versions/0009_field_workflow_tables.py
    - backend/app/features/files/__init__.py
    - backend/app/features/files/router.py
  modified:
    - backend/app/features/jobs/models.py
    - backend/app/features/jobs/schemas.py
    - backend/app/features/jobs/service.py
    - backend/app/features/jobs/repository.py
    - backend/app/features/jobs/router.py
    - backend/app/features/sync/router.py
    - backend/app/features/sync/service.py
    - backend/app/features/sync/schemas.py
    - backend/app/main.py

key-decisions:
  - "Attachment remote_url stored as /files/{path} matching StaticFiles mount in main.py"
  - "GPS geocode non-fatal: Exception caught broadly, gps_address=None stored, retry on next sync"
  - "create_time_entry auto-transitions job from scheduled->in_progress on first clock-in"
  - "adjust_time_entry appends to adjustment_log via list replacement (Pitfall 3)"
  - "Files router included before StaticFiles mount (router order requirement in FastAPI)"

# Metrics
duration: 30min
completed: 2026-03-11
---

# Phase 6 Plan 01: Backend Field Workflow Foundation Summary

**Alembic migration 0009 + ORM models + Pydantic schemas + REST endpoints + file upload + sync extension completing the full backend API surface for the field workflow (notes, attachments, time entries, GPS)**

## Performance

- **Duration:** ~30 min
- **Started:** 2026-03-11T23:14:04Z
- **Completed:** 2026-03-11T23:44:00Z
- **Tasks:** 2
- **Files modified:** 13

## Accomplishments

### Task 1: Migration 0009 + ORM models + Pydantic schemas

- Created `0009_field_workflow_tables.py` with `job_notes`, `attachments`, `time_entries` tables
  - Each table: UUID PK, company_id FK (RLS), created_at/updated_at triggers, deleted_at
  - `job_notes`: body TEXT NOT NULL, job_id/author_id FKs
  - `attachments`: attachment_type CHECK('photo','pdf','drawing'), note_id FK, sort_order, remote_url
  - `time_entries`: clocked_in/out TIMESTAMPTZ, duration_seconds, session_status CHECK, adjustment_log JSONB
  - `ALTER TABLE jobs ADD COLUMN gps_latitude/longitude/address`
- Added `JobNote`, `Attachment`, `TimeEntry` ORM models to `jobs/models.py`
  - All use `TenantScopedModel`, all relationships have `lazy="raise"`
  - `Job` model extended with `gps_latitude`, `gps_longitude`, `gps_address` + `job_notes`/`time_entries` relationships
- Added 8 Pydantic schemas: `JobNoteCreate/Response`, `AttachmentResponse`, `TimeEntryCreate/Update/Adjust/Response`
- Extended `JobResponse`/`JobUpdate` with GPS fields; `SyncResponse` with `job_notes`/`time_entries`/`attachments`

### Task 2: REST endpoints, file upload, sync extension

- **JobService methods added:** `create_note`, `list_notes`, `create_time_entry` (one-at-a-time + auto in_progress), `update_time_entry` (clock out), `adjust_time_entry` (JSONB audit log), `list_time_entries`, `update_job_gps` (ORS reverse geocoding)
- **JobRepository methods added:** `get/list notes` with `selectinload(attachments)`, `get/list time entries`, `get_active_time_entry` for session enforcement
- **REST endpoints (all before /jobs/{job_id} catch-all):**
  - `POST /jobs/{job_id}/notes` → 201 JobNoteResponse
  - `GET /jobs/{job_id}/notes` → list[JobNoteResponse]
  - `POST /jobs/{job_id}/time-entries` → 201 TimeEntryResponse
  - `PATCH /jobs/{job_id}/time-entries/{entry_id}` → TimeEntryResponse (clock out)
  - `PATCH /jobs/{job_id}/time-entries/{entry_id}/adjust` → TimeEntryResponse (admin)
  - `GET /jobs/{job_id}/time-entries` → list[TimeEntryResponse]
- **Files feature package:** `POST /api/v1/files/upload` saves to `uploads/attachments/{note_id}/{uuid}{ext}`, creates Attachment DB record, returns AttachmentResponse
- **main.py updated:** files router included, `/files` StaticFiles mount added
- **SyncService extended:** `get_job_notes_since`, `get_time_entries_since`, `get_attachments_since`
- **sync/router.py updated:** Phase 6 entities included in delta pull response

## Task Commits

| Task | Name | Commit | Files |
|------|------|--------|-------|
| 1 | Migration 0009, ORM models, schemas | 12eddc7 | 4 files |
| 2 | REST endpoints, file upload, sync | e1d885f | 9 files |

## Deviations from Plan

None - plan executed exactly as written.

## Issues Encountered

None.

## Self-Check: PASSED

All key files confirmed present on disk:
- `backend/migrations/versions/0009_field_workflow_tables.py` - FOUND
- `backend/app/features/files/__init__.py` - FOUND
- `backend/app/features/files/router.py` - FOUND

Commits 12eddc7 and e1d885f confirmed in git log (Task 1 and Task 2 respectively).
