---
phase: 21-ai-project-intake-and-contractor-interview
plan: "06"
subsystem: backend
tags: [ai, image-upload, claude-vision, pillow, compression]
dependency_graph:
  requires: [21-02]
  provides: [POST /ai/intake/image endpoint, Claude vision content blocks]
  affects: [ai/router.py, ai/service.py, ai/models.py, ai/schemas.py]
tech_stack:
  added: [Pillow>=10.0.0]
  patterns:
    - Pillow Image.thumbnail() for server-side max-dimension resize
    - base64.b64encode for Claude vision content blocks
    - aiofiles for async disk I/O on both write (upload) and read (vision)
    - UploadFile + Form() multipart pattern (same as files/router.py)
key_files:
  created: []
  modified:
    - backend/app/features/ai/models.py
    - backend/app/features/ai/router.py
    - backend/app/features/ai/schemas.py
    - backend/app/features/ai/service.py
    - backend/migrations/versions/0017_ai_conversations.py
    - backend/requirements.txt
    - backend/tests/test_phase_21_e2e.py
    - backend/tests/conftest.py
decisions:
  - AIImageUpload uses ON DELETE CASCADE from ai_conversations — images are conversation-scoped, not reusable
  - JPEG normalization on upload (all stored as JPEG regardless of input format) simplifies vision block media_type
  - image_ref_id lookup returns None (not 404) on missing image — chat turn degrades to text-only
  - Pillow thumbnail() preserves aspect ratio by fitting within 1280x1280 bounding box
metrics:
  duration: 7 minutes
  tasks_completed: 2
  files_modified: 8
  completed_date: "2026-03-23"
---

# Phase 21 Plan 06: AI Image Upload with Claude Vision Summary

AI image upload endpoint with Pillow compression and Claude vision wiring — POST /ai/intake/image compresses uploads to 1280x1280 JPEG via Pillow, stores on disk, and the chat turn endpoints convert image_ref_id to base64 vision content blocks for the Claude API call.

## What Was Built

### AIImageUpload model (ai/models.py)
New `TenantScopedModel` subclass `AIImageUpload` with columns: `conversation_id` (FK to ai_conversations with CASCADE), `user_id` (FK to users), `file_path` (Text), `original_filename` (Text), `media_type` (Text), `file_size_bytes` (Integer). Relationships defined with `lazy="raise"` per CLAUDE.md rules.

### ImageUploadResponse schema (ai/schemas.py)
New `TenantResponseSchema` subclass with `conversation_id`, `original_filename`, `media_type`, `file_size_bytes`. The `id` field from the base schema is the `image_ref_id` for subsequent chat turn requests.

### Migration 0017 updated (migrations/versions/0017_ai_conversations.py)
Added `CREATE TABLE ai_image_uploads` with full column set, RLS (same tenant isolation policy), `set_updated_at` trigger, and `ix_ai_image_uploads_conversation_id` index. Downgrade drops the table in reverse order.

### POST /ai/intake/image endpoint (ai/router.py)
Accepts `file: UploadFile` and `conversation_id: uuid.UUID = Form(...)`. Validates content-type starts with `image/`, enforces 10 MB raw limit, verifies conversation exists. Compresses via Pillow (`thumbnail(1280, 1280)` + `JPEG quality=85`), writes to `uploads/ai_images/{conversation_id}/{uuid}.jpg` via aiofiles. Creates `AIImageUpload` record and returns 201 with `ImageUploadResponse`.

### build_image_content_block() (ai/service.py)
New `AIService` method that looks up `AIImageUpload` by ID, reads the stored JPEG via aiofiles, base64-encodes it, and returns the Claude API image content block dict (`type: image, source.type: base64`). Returns `None` if image not found.

### intake/message and interview/message updated (ai/router.py)
Both message endpoints now check `req.image_ref_id`. If set, they call `build_image_content_block()` and build a content list `[image_block, text_block]` instead of a plain string. This list is passed to both `persist_user_message` and the Claude API messages array.

### Tests (tests/test_phase_21_e2e.py)
Four tests added to `TestImageUpload` class:
- `test_image_upload_returns_ref_id` — 201 response with UUID image_ref_id
- `test_image_upload_rejects_non_image` — 400 for text/plain content type
- `test_image_upload_compresses_large_image` — 2000x2000 JPEG stored as ≤1280x1280
- `test_chat_turn_with_image_includes_vision_block` — verifies Claude receives content array with `type: image` block and `source.type: base64`

All 17 phase 21 tests pass.

## Deviations from Plan

None — plan executed exactly as written.

## Self-Check: PASSED

Files modified:
- FOUND: backend/app/features/ai/models.py
- FOUND: backend/app/features/ai/router.py
- FOUND: backend/app/features/ai/schemas.py
- FOUND: backend/app/features/ai/service.py
- FOUND: backend/migrations/versions/0017_ai_conversations.py
- FOUND: backend/requirements.txt
- FOUND: backend/tests/test_phase_21_e2e.py
- FOUND: backend/tests/conftest.py

Commits:
- FOUND: 2b078f3 (feat Task 1)
- FOUND: ba0f10e (test Task 2)
