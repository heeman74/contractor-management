---
phase: 07-client-portal-and-notifications
plan: "01"
subsystem: backend-notifications
tags: [backend, fcm, push-notifications, sync, role-filtering]
dependency_graph:
  requires: []
  provides:
    - device_tokens table (migration 0010)
    - NotificationService (FCM dispatch, upsert_token)
    - POST /api/v1/notifications/token endpoint
    - job milestone notifications wired into JobService
    - sync role filtering for client-role users
  affects:
    - backend/app/features/jobs/service.py (notification calls)
    - backend/app/features/sync/service.py (client_user_id param)
    - backend/app/features/sync/router.py (role extraction)
tech_stack:
  added:
    - firebase-admin==6.6.0
  patterns:
    - BaseService[DeviceToken] (user-scoped, not tenant-scoped)
    - BaseRepository[DeviceToken] with upsert ON CONFLICT (user_id, token)
    - Fire-and-forget FCM dispatch (errors logged, never raised)
    - Lazy Firebase init guard (not firebase_admin._apps)
    - GOOGLE_APPLICATION_CREDENTIALS graceful degradation
    - client_user_id keyword-only param for sync filtering
key_files:
  created:
    - backend/migrations/versions/0010_device_tokens.py
    - backend/app/features/notifications/__init__.py
    - backend/app/features/notifications/models.py
    - backend/app/features/notifications/repository.py
    - backend/app/features/notifications/schemas.py
    - backend/app/features/notifications/service.py
    - backend/app/features/notifications/router.py
    - backend/.gitignore
  modified:
    - backend/app/main.py (notifications router registered)
    - backend/app/features/jobs/service.py (notification calls in transition_status, report_delay)
    - backend/app/features/sync/service.py (client_user_id param on 4 methods)
    - backend/app/features/sync/router.py (role extraction, client_user_id routing)
    - backend/requirements.txt (firebase-admin added)
decisions:
  - "DeviceToken inherits Base directly (not TenantScopedModel) — device tokens are user-scoped across all tenants"
  - "Lazy Firebase init with _apps guard prevents double-init in multi-worker environments"
  - "GOOGLE_APPLICATION_CREDENTIALS absent degrades gracefully — FCM skipped with warning, not an error"
  - "Notification failures are fire-and-forget — logged but never raised to prevent blocking job operations"
  - "Sync client_user_id filtering uses subquery JOIN through Job.client_id — clean, no N+1"
  - "client role check uses 'in current_user.roles' list — supports multi-role users correctly"
metrics:
  duration: "~5 min"
  completed_date: "2026-03-13"
  tasks_completed: 2
  files_created: 9
  files_modified: 5
---

# Phase 07 Plan 01: Backend Notification Infrastructure and Sync Role Filtering Summary

FCM push notification backend with device token registry, job milestone dispatch wired into JobService, and client-role sync filtering via client_user_id subquery.

## What Was Built

### Task 1: Device Tokens, NotificationService, and Token Endpoint

**Migration 0010 (device_tokens):** Created `device_tokens` table with user_id FK, platform CHECK ('android'/'ios'), UNIQUE(user_id, token) for upsert deduplication, and index on user_id for efficient per-user token lookup. RLS policy scoped to `app.current_user_id`.

**DeviceToken model:** Inherits from `Base` directly (not `TenantScopedModel`) — device tokens are user-scoped, not company-scoped.

**NotificationRepository:** Extends `BaseRepository[DeviceToken]`. Key methods:
- `get_tokens_for_user(user_id)` — returns all registered tokens for FCM dispatch
- `upsert_token(user_id, token, platform)` — INSERT ON CONFLICT updates `last_used_at`
- `delete_token(token)` — removes invalid tokens on FCM `UnregisteredError`

**NotificationService:** Extends `BaseService[DeviceToken]`. Key methods:
- `upsert_token()` — delegates to repository
- `send_job_notification(user_id, job_description, event, job_id)` — fetches all tokens, dispatches FCM per-token with fire-and-forget error handling. `UnregisteredError` triggers cleanup.
- Firebase init uses `_get_firebase_app()` with lazy init guard and `GOOGLE_APPLICATION_CREDENTIALS` graceful degradation.

**Router:** `POST /api/v1/notifications/token` (204) — authenticated endpoint registered in `main.py`.

### Task 2: Notification Dispatch Wiring and Sync Role Filtering

**JobService.transition_status():** After successful transition, if `job.client_id` is set and `new_status` in {scheduled, in_progress, complete}, creates `NotificationService` and calls `send_job_notification()`. Event map: scheduled→"scheduled", in_progress→"started", complete→"completed". Wrapped in `try/except` — notification failure never blocks the transition.

**JobService.report_delay():** After successful delay record, if `job.client_id` is set, sends "delayed" event notification. Same fire-and-forget pattern.

**SyncService (CLNT-05):** Added `client_user_id: str | None = None` keyword-only param to:
- `get_jobs_since()` — WHERE Job.client_id == client_uuid
- `get_bookings_since()` — WHERE Booking.job_id IN (client's job IDs subquery)
- `get_job_notes_since()` — WHERE JobNote.job_id IN (client's job IDs subquery)
- `get_attachments_since()` — WHERE Attachment.note_id IN (client's note IDs subquery through JobNote)

**Sync router:** Extracts `client_user_id = str(current_user.user_id)` when `"client" in current_user.roles`, passes it to all four filtered SyncService methods. Admin/contractor roles pass `None` (no additional filtering).

## Deviations from Plan

None - plan executed exactly as written.

## Self-Check

### Files exist:
- [x] `backend/migrations/versions/0010_device_tokens.py`
- [x] `backend/app/features/notifications/__init__.py`
- [x] `backend/app/features/notifications/models.py`
- [x] `backend/app/features/notifications/repository.py`
- [x] `backend/app/features/notifications/schemas.py`
- [x] `backend/app/features/notifications/service.py`
- [x] `backend/app/features/notifications/router.py`
- [x] `backend/.gitignore` (firebase-service-account.json excluded)
- [x] `backend/requirements.txt` (firebase-admin added)

### Commits:
- [x] 2acaac0 — Task 1: notifications infrastructure
- [x] e89c2b8 — Task 2: wiring and sync filtering

### Verification:
- [x] `ruff check app/` — passes
- [x] `ruff format --check app/` — passes
- [x] Import verification — `NotificationService`, `SyncService`, `JobService` all import OK

## Self-Check: PASSED
