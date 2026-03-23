---
phase: 21
plan: 02
subsystem: backend-ai
tags: [ai, sse, fastapi, intake, interview, testing]
dependency_graph:
  requires: [21-01]
  provides: [ai-endpoints, ai-tests]
  affects: [backend-api, phase-21-web, phase-21-mobile]
tech_stack:
  added: []
  patterns:
    - StreamingResponse for SSE (not EventSourceResponse — fastapi.sse not available in this version)
    - patch.object for TradeScopeService.create in rollback test
    - contextlib.suppress for catching ASGI transport exceptions
key_files:
  created:
    - backend/app/features/ai/router.py
    - backend/tests/test_ai_service.py
    - backend/tests/test_phase_21_e2e.py
  modified:
    - backend/app/main.py
    - backend/tests/conftest.py
decisions:
  - Used StreamingResponse(text/event-stream) instead of EventSourceResponse — fastapi.sse module does not exist in FastAPI 0.115; StreamingResponse with media_type="text/event-stream" is the correct approach
  - intake/complete creates placeholder tasks (one per scope) wired with FS dependency edges to represent D-23 cross-trade sequencing — tasks can be soft-deleted/replaced when real tasks are added later
  - ai_conversations, ai_messages, ai_token_usage tables added to conftest clean_tables to prevent cross-test pollution (Rule 2 auto-fix)
  - Test URL paths use trailing slashes (e.g. /api/v1/projects/) to avoid 307 redirects from FastAPI's redirect_slashes=True default
metrics:
  duration: 11 minutes
  completed_date: "2026-03-23"
  tasks_completed: 2
  files_created: 3
  files_modified: 2
  tests_added: 36
---

# Phase 21 Plan 02: AI SSE Endpoints and Backend Tests Summary

FastAPI SSE streaming endpoints for AI project intake and contractor interview, plus comprehensive backend tests (23 unit + 13 E2E = 36 total, all passing).

## What Was Built

### Task 1: AI Router with SSE Streaming Endpoints

Created `backend/app/features/ai/router.py` with 7 endpoints:

- `POST /ai/intake/start` — Start or resume intake conversation (201 new / 200 existing)
- `POST /ai/intake/message` — Stream SSE tokens from Claude API for intake turns
- `POST /ai/intake/complete` — Commit AI-suggested trade scopes: creates project, scopes, placeholder tasks, and FS dependency edges for D-23 sequencing
- `POST /ai/interview/start` — Start interview for a trade scope (verifies scope exists)
- `POST /ai/interview/message` — Stream SSE tokens for interview turns
- `POST /ai/interview/complete` — Soft-delete existing tasks, create new tasks from interview
- `GET /ai/conversations/{conversation_id}` — Get conversation with messages for re-entry

Registered `ai_router` in `backend/app/main.py` after `projects_router`.

### Task 2: Backend Tests (TDD)

**Unit tests** (`test_ai_service.py`, 23 tests):
- `TestToolValidation`: 20 tests covering create_trade_scope, create_task, ask_clarifying_question validation edge cases
- `TestConversationPersistence`: 3 tests using HTTP client for get_or_create and message persistence

**Integration E2E tests** (`test_phase_21_e2e.py`, 13 tests):
- `TestIntakeFlow`: start, SSE stream, auth check, produces trade scopes, dependency edges, rollback on partial failure, clarifying questions
- `TestInterviewFlow`: requires scope, unknown scope 404, start+message, produces tasks, re-entry
- `TestTenantIsolation`: cross-tenant conversation access blocked

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 2 - Missing Critical Functionality] AI tables absent from conftest clean_tables**
- **Found during:** Task 2 setup
- **Issue:** `ai_conversations`, `ai_messages`, `ai_token_usage` tables were not in the `clean_tables` fixture, causing cross-test data pollution
- **Fix:** Added the 3 tables to the TRUNCATE statement in `backend/tests/conftest.py` before project data model tables (correct FK order)
- **Files modified:** `backend/tests/conftest.py`
- **Commit:** a4a09dd

**2. [Rule 1 - Bug] EventSourceResponse does not exist in fastapi.sse**
- **Found during:** Task 1 implementation
- **Issue:** The plan specified `from fastapi.sse import EventSourceResponse, ServerSentEvent` but this module does not exist in FastAPI 0.115
- **Fix:** Used `StreamingResponse` with `media_type="text/event-stream"` instead — this is the correct approach and provides identical SSE behavior
- **Files modified:** `backend/app/features/ai/router.py`
- **Commit:** c622583

**3. [Rule 1 - Bug] Test URL paths needed trailing slashes**
- **Found during:** Task 2 E2E test execution
- **Issue:** POST `/api/v1/projects` returned 307 redirect; paths are `/api/v1/projects/` with trailing slash
- **Fix:** Updated all test helper calls to use trailing slashes
- **Files modified:** `backend/tests/test_ai_service.py`, `backend/tests/test_phase_21_e2e.py`
- **Commit:** a4a09dd

## Self-Check: PASSED

- FOUND: `backend/app/features/ai/router.py`
- FOUND: `backend/tests/test_ai_service.py`
- FOUND: `backend/tests/test_phase_21_e2e.py`
- FOUND commit: `c622583` (feat: AI router)
- FOUND commit: `a4a09dd` (test: AI tests)
- All 36 tests pass: `uv run python -m pytest tests/test_ai_service.py tests/test_phase_21_e2e.py`
