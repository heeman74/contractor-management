---
phase: 21-ai-project-intake-and-contractor-interview
plan: 07
subsystem: backend/ai
tags: [ai, image-upload, claude-vision, pillow, rls, migration]
dependency_graph:
  requires: [21-01, 21-02, 21-03]
  provides: [ai-image-upload-endpoint, claude-vision-wiring]
  affects: [backend/app/features/ai]
tech_stack:
  added: [Pillow>=11.0.0, aiofiles (existing)]
  patterns: [server-side image compression, Claude vision base64 blocks, multipart form upload]
key_files:
  created:
    - backend/migrations/versions/0018_ai_image_uploads.py
  modified:
    - backend/app/features/ai/models.py
    - backend/app/features/ai/schemas.py
    - backend/app/features/ai/router.py
    - backend/app/features/ai/service.py
    - backend/requirements.txt
    - backend/tests/test_phase_21_e2e.py
    - backend/tests/conftest.py
decisions:
  - "Migration 0018 uses CREATE TABLE IF NOT EXISTS for idempotency — the table already existed in the test DB from a merged worktree without Alembic stamp, so IF NOT EXISTS + DO $$ BEGIN policy check guards allow upgrade to run cleanly"
  - "image compression test uses glob on disk path (uploads/ai_images/{conv_id}/) rather than DB lookup — raw SQLAlchemy session without RLS context cannot select ai_image_uploads records"
  - "conftest.py clean_tables extended to include ai_image_uploads TRUNCATE — without it test data persists across tests (Rule 2 auto-fix)"
metrics:
  duration: "~15 minutes"
  completed: "2026-03-24T01:14:22Z"
  tasks_completed: 2
  files_modified: 7
  files_created: 1
---

# Phase 21 Plan 07: Gap Closure — AI Image Upload Summary

**One-liner:** AIImageUpload model + POST /ai/intake/image with Pillow 1280x1280 compression + build_image_content_block() for Claude vision base64 wiring + 4 passing integration tests.

## What Was Built

### Task 1: AIImageUpload model, schema, migration, endpoint, and service method

Added `AIImageUpload` SQLAlchemy model to `models.py` with `TenantScopedModel` inheritance and CASCADE FK to `ai_conversations`. Added `ImageUploadResponse` schema inheriting `BaseResponseSchema`.

Created migration `0018_ai_image_uploads.py` with idempotent `CREATE TABLE IF NOT EXISTS` and conditional policy creation (required because the table existed from a prior worktree that ran but didn't stamp Alembic).

Added `POST /ai/intake/image` to `router.py`:
- Validates content type starts with `image/`
- Reads file bytes, rejects > 10MB
- Compresses with Pillow `thumbnail((1280, 1280))`, converts RGBA/P to RGB for JPEG
- Saves to `uploads/ai_images/{conversation_id}/{uuid}.jpg`
- Creates `AIImageUpload` DB record via `db.add() + db.flush()`

Added `build_image_content_block(image_ref_id)` to `AIService`:
- Looks up `AIImageUpload` by ID with soft-delete check
- Reads file async with `aiofiles`
- Returns Claude vision content block: `{"type": "image", "source": {"type": "base64", "media_type": ..., "data": ...}}`

Wired `image_ref_id` into both `intake_message` and `interview_message` router functions:
- If `req.image_ref_id` is set, calls `build_image_content_block()` and prepends image block to content list
- Passes `user_content` (str or list) to `persist_user_message` (which already accepts both types)
- Builds correct API `content` array (text block for string, image+text list for vision)

### Task 2: 4 image upload integration tests

Added `TestImageUpload` class to `test_phase_21_e2e.py` with 4 tests:
- `test_image_upload_returns_ref_id` — JPEG upload returns 201 with valid UUID
- `test_image_upload_rejects_non_image` — text/plain returns 400 with "image" in detail
- `test_image_upload_compresses_large_image` — 2000x2000 JPEG stored as <= 1280x1280 (verified via `glob` + Pillow on disk)
- `test_chat_turn_with_image_includes_vision_block` — Claude mock captures `messages` call and asserts image block with `source.type == "base64"`

All 4 pass.

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 1 - Bug] Migration 0018 required idempotency guards**
- **Found during:** Task 1 migration execution
- **Issue:** `ai_image_uploads` table already existed in `contractorhub_test` DB from Plan 06 worktree that ran migration SQL without stamping Alembic version. `alembic upgrade head` failed with `DuplicateTableError`.
- **Fix:** Changed `CREATE TABLE` to `CREATE TABLE IF NOT EXISTS`, `CREATE INDEX` to `CREATE INDEX IF NOT EXISTS`, and wrapped `CREATE POLICY` and `CREATE TRIGGER` in `DO $$ BEGIN IF NOT EXISTS ... END $$` blocks.
- **Files modified:** `backend/migrations/versions/0018_ai_image_uploads.py`
- **Commit:** 55a273f

**2. [Rule 2 - Missing critical functionality] conftest.py missing ai_image_uploads truncation**
- **Found during:** Task 2 test setup
- **Issue:** `clean_tables` fixture did not include `ai_image_uploads` in TRUNCATE list, causing test data to persist across tests.
- **Fix:** Added `"ai_image_uploads, "` to the TRUNCATE statement in `conftest.py`.
- **Files modified:** `backend/tests/conftest.py`
- **Commit:** f69a1c0

**3. [Rule 1 - Bug] Compression test used raw DB session without RLS context**
- **Found during:** Task 2 first test run
- **Issue:** `test_image_upload_compresses_large_image` initially tried to read `AIImageUpload.file_path` via a raw SQLAlchemy session with `RESET app.current_company_id`, but RLS blocked the query (returned None).
- **Fix:** Replaced DB lookup with `glob` on disk path `uploads/ai_images/{conv_id}/*.jpg` to find and open the compressed file.
- **Files modified:** `backend/tests/test_phase_21_e2e.py`
- **Commit:** f69a1c0

## Self-Check

### Verify files exist:
- [x] `backend/migrations/versions/0018_ai_image_uploads.py` — created
- [x] `backend/app/features/ai/models.py` — AIImageUpload class added
- [x] `backend/app/features/ai/schemas.py` — ImageUploadResponse class added
- [x] `backend/app/features/ai/router.py` — POST /ai/intake/image endpoint added
- [x] `backend/app/features/ai/service.py` — build_image_content_block() added
- [x] `backend/tests/test_phase_21_e2e.py` — 4 image tests added

### Verify commits:
- 55a273f — feat(21-07): add AIImageUpload model, image upload endpoint, and Claude vision wiring
- f69a1c0 — test(21-07): add 4 image upload integration tests and fix clean_tables fixture

## Self-Check: PASSED
