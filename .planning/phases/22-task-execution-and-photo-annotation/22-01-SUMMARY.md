---
phase: 22-task-execution-and-photo-annotation
plan: 01
subsystem: api
tags: [fastapi, sqlalchemy, postgresql, rls, alembic, fcm, multipart-upload, jsonb]

# Dependency graph
requires:
  - phase: 19-project-data-model
    provides: Task, TaskAttachment SQLAlchemy models and task REST endpoints
  - phase: 21-ai-project-intake-and-contractor-interview
    provides: Migration 0018 (latest migration before this one)
provides:
  - TaskNote table with RLS and task_id FK (CASCADE)
  - annotation_data JSONB column on task_attachments
  - POST/GET /tasks/{id}/notes endpoints
  - POST/GET/PATCH/DELETE /tasks/{id}/attachments endpoints (multipart upload)
  - Attachment count enforcement (10 photos/videos, 5 documents per task)
  - batch digest FCM notification to GC users on task completion (fire-and-forget)
  - 10 passing integration tests
affects: [22-02, 22-03, 22-04, 22-05, mobile-task-execution, web-gc-dashboard]

# Tech tracking
tech-stack:
  added: [aiofiles (already present), postgresql JSONB for annotation storage]
  patterns:
    - Multipart upload to uploads/task-attachments/{task_id}/{uuid}{ext} via aiofiles
    - Per-type attachment count limits enforced in service layer before insert
    - Fire-and-forget notification: outer try/except in router, inner try/except in service
    - annotation_data non-destructive storage (base photo immutable, JSONB overlay separate)

key-files:
  created:
    - backend/migrations/versions/0019_task_notes_and_annotation.py
    - backend/tests/integration/test_phase_22_e2e.py
  modified:
    - backend/app/features/projects/models.py
    - backend/app/features/projects/schemas.py
    - backend/app/features/projects/service.py
    - backend/app/features/projects/router.py
    - backend/app/features/projects/repository.py
    - backend/app/features/notifications/service.py
    - backend/tests/conftest.py

key-decisions:
  - "CurrentUser has no email attribute — completed_by_name falls back to str(user_id); full name lookup deferred to Phase 23 when user profile endpoints exist"
  - "Phase 22 P01: TaskNote uses soft FK for author_id (no hard FK) consistent with project pattern of avoiding cross-feature hard FKs"
  - "Phase 22 P01: Digest notification mocked at class method level (patch on NotificationService.queue_task_completion_digest) — works because ASGI test environment imports same module"

patterns-established:
  - "Multipart attachment upload: Form() fields + UploadFile parameter + aiofiles.open write + static URL construction matching StaticFiles mount"
  - "Count limit enforcement: count_attachments_by_type() called in service.create_attachment() before insert; raises HTTPException 400 with descriptive message"
  - "Idempotent task completion: track previous_status before update, only trigger side effects on actual not_started->complete transition"

requirements-completed: [TASK-03, TASK-04, TASK-05, TASK-06]

# Metrics
duration: 8min
completed: 2026-03-24
---

# Phase 22 Plan 01: Task Notes and Attachment Backend Summary

**Alembic migration 0019 + TaskNote REST API + multipart attachment upload with annotation JSONB + per-type count limits + fire-and-forget GC digest notification via FCM**

## Performance

- **Duration:** 8 min
- **Started:** 2026-03-24T07:55:53Z
- **Completed:** 2026-03-24T08:04:00Z
- **Tasks:** 2
- **Files modified:** 9

## Accomplishments

- Migration 0019 creates task_notes table (RLS, tenant isolation) and adds annotation_data JSONB to task_attachments — applied cleanly against existing DB
- Full TaskNote CRUD: POST creates note with author_id from JWT, GET returns newest first
- Multipart file upload saves to uploads/task-attachments/{task_id}/{uuid}{ext} via aiofiles; returns remote_url served by existing StaticFiles mount
- Annotation JSONB round-trips through PATCH and is returned in GET list response
- Attachment count limits enforced (10 photos/videos, 5 documents per task) with descriptive 400 errors
- PATCH /tasks/{id} with status=complete triggers fire-and-forget FCM digest to all GC/admin users; notification failure never blocks the status update
- All 10 integration tests pass (notes CRUD, photo/PDF upload, annotation update, limit enforcement, soft delete, digest notification mock, fire-and-forget resilience)

## Task Commits

1. **Task 1: Alembic migration 0019 + TaskNote model + annotation_data column** - `1c290a1` (feat)
2. **Task 2: Task note + attachment endpoints + batch digest notification + tests** - `e13419d` (feat)

## Files Created/Modified

- `backend/migrations/versions/0019_task_notes_and_annotation.py` - Migration creating task_notes (RLS) and adding annotation_data JSONB to task_attachments
- `backend/app/features/projects/models.py` - Added TaskNote model + annotation_data column to TaskAttachment
- `backend/app/features/projects/schemas.py` - Added TaskNoteCreate, TaskNoteResponse; updated TaskAttachmentCreate/Update/Response with annotation_data
- `backend/app/features/projects/repository.py` - Added TaskNoteRepository.list_by_task (newest first)
- `backend/app/features/projects/service.py` - Added TaskNoteService, TaskService.count_attachments_by_type, TaskService.create_attachment
- `backend/app/features/projects/router.py` - Added notes endpoints, attachment upload/list/patch/delete endpoints; updated task PATCH for digest notification trigger
- `backend/app/features/notifications/service.py` - Added NotificationService.queue_task_completion_digest (fire-and-forget FCM to GC users)
- `backend/tests/conftest.py` - Added task_notes to clean_tables truncation list
- `backend/tests/integration/test_phase_22_e2e.py` - 10 integration tests (402 lines)

## Decisions Made

- `CurrentUser` has no `email` attribute — `completed_by_name` uses `str(current_user.user_id)` as fallback. The plan expected a name field but the JWT model only carries user_id, company_id, and roles. Full name display will need a user lookup in a future plan.
- `annotation_data` in the attachment upload endpoint is accepted as a Form string (JSON) since multipart cannot mix JSON body + UploadFile. The string is parsed with `json.loads()` in the endpoint before storing.

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 1 - Bug] Fixed CurrentUser.email attribute error causing digest notification to silently fail**
- **Found during:** Task 2 (integration test test_task_completion_triggers_digest_notification)
- **Issue:** Router accessed `current_user.email` but CurrentUser model only exposes user_id, company_id, and roles — AttributeError thrown inside fire-and-forget try/except, silently swallowing the notification
- **Fix:** Changed to `str(current_user.user_id)` as the completed_by_name fallback
- **Files modified:** backend/app/features/projects/router.py
- **Verification:** Test test_task_completion_triggers_digest_notification now passes; call_log has exactly 1 entry
- **Committed in:** e13419d (Task 2 commit)

---

**Total deviations:** 1 auto-fixed (Rule 1 - Bug)
**Impact on plan:** Fix was essential for correctness — without it, mock assertion failed and the real notification would silently not fire. No scope creep.

## Issues Encountered

None beyond the auto-fixed deviation above.

## User Setup Required

None - no external service configuration required for this plan. FCM gracefully degrades when GOOGLE_APPLICATION_CREDENTIALS is not set.

## Next Phase Readiness

- Backend data layer for task execution is complete — notes, attachments, annotation, count limits, digest notifications all shipped and tested
- Phase 22 Plans 02-05 can build on these endpoints for mobile and web UI
- The `completed_by_name` field currently shows user UUID string; if human-readable names are needed in notifications, a user profile lookup will need to be added in a later plan

---
*Phase: 22-task-execution-and-photo-annotation*
*Completed: 2026-03-24*
