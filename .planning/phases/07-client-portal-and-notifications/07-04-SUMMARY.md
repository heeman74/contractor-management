---
phase: "07"
plan: "04"
subsystem: "client-portal-and-notifications"
tags: ["testing", "e2e", "notifications", "client-portal", "flutter", "pytest"]
dependency_graph:
  requires: ["07-01", "07-02", "07-03"]
  provides: ["phase-07-complete"]
  affects: ["backend/tests", "mobile/test/e2e"]
tech_stack:
  added: []
  patterns:
    - "StreamProvider.family.overrideWith() for Flutter widget test isolation"
    - "ASGITransport(app=app) module-level constant for backend integration tests"
    - "pump(Duration) instead of pumpAndSettle() for Drift stream-backed widgets"
    - "Fire-and-forget FCM graceful degradation (test without GOOGLE_APPLICATION_CREDENTIALS)"
key_files:
  created:
    - "backend/tests/test_notification_service.py"
    - "backend/tests/test_phase_7_e2e.py"
    - "mobile/test/e2e/phase_7_client_portal_e2e_test.dart"
  modified:
    - "backend/tests/conftest.py"
    - "backend/app/core/tenant.py"
    - "backend/app/core/security.py"
decisions:
  - "Use ASGI test client for DB operations in notification unit tests to avoid raw AsyncSession teardown errors"
  - "Override StreamProvider.family not real Drift DB for Flutter E2E to avoid async* nested stream resolution in FakeAsync"
  - "pump(Duration(milliseconds:300)) for TabBarView animation instead of pumpAndSettle (Drift never settles)"
metrics:
  duration: "~22 hours (across two sessions)"
  completed_date: "2026-03-13"
  tasks_completed: 2
  files_changed: 6
---

# Phase 07 Plan 04: E2E Tests for Client Portal and Notifications Summary

Backend integration tests (20 passing) and Flutter widget E2E tests (24 passing) covering the full phase 7 client portal and notification feature set.

## Tasks Completed

| # | Task | Commit | Result |
|---|------|--------|--------|
| 1 | Backend integration and unit tests | 9e8e1b4 | 20 tests passing |
| 2 | Flutter E2E widget tests for client portal | 3bc9b8c | 24 tests passing |

## What Was Built

### Task 1: Backend Tests (20 tests)

**test_notification_service.py** — 7 unit tests:
- `test_upsert_token_creates_new`: FCM token registration via API → 204
- `test_upsert_token_updates_existing`: same token twice → both 204 (upsert semantics)
- `test_upsert_token_multiple_devices`: two tokens same user → both 204
- `test_send_notification_unregistered_error`: `_send_to_token` with `UnregisteredError` → `delete_token` called
- `test_send_notification_generic_error_token_not_deleted`: generic error → `delete_token` NOT called
- `test_send_job_notification_success`: `send_job_notification` dispatches to both device tokens
- `test_no_notification_when_fcm_not_configured`: `_get_firebase_app` None → early exit, no token lookup

**test_phase_7_e2e.py** — 13 integration tests:
- Notification triggers on job transition to scheduled, in_progress, complete
- Delay report trigger fires notification
- No notification when job has no client assigned
- FCM token CRUD: register, unauthenticated rejection, invalid platform rejection, upsert
- Sync delta filtering: admin sees all jobs, client_id filter restricts to own jobs
- Sync client notes filter: client sees only own job notes

### Task 2: Flutter E2E Widget Tests (24 tests)

**phase_7_client_portal_e2e_test.dart**:
- `ClientPortalScreen` group (8 tests): active jobs visible, ETA display, delay warning icon, completed job dimming, pending requests section, declined reason, empty state, "My Jobs" header
- `ClientJobDetailScreen` group (11 tests): progress stepper, cancelled banner, delay banner visibility/hiding, multiple delays expandable, photos tab badge count, photos empty state, tabs visible, details tab content, pricing note, job not found
- Role gating group (3 tests): portal accessible for client role, detail screen accessible, no edit actions visible
- `JobProgressStepper` group (2 tests): stage labels, check icons

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 2 - Missing Security] Fixed `device_tokens` RLS context variable never set**
- **Found during:** Task 1 — `test_upsert_token_creates_new` failed with `InsufficientPrivilegeError`
- **Issue:** The `device_tokens` migration creates an RLS policy using `app.current_user_id`, but `tenant.py` only set `app.current_company_id`. No code ever set the user context variable, causing all device token writes to fail for non-superuser connections.
- **Fix:** Added `_current_user_id` ContextVar to `tenant.py`, `set_current_user_id()` + `get_current_user_id()` functions, extended `receive_after_begin` to `SET LOCAL app.current_user_id`. Updated `security.py` `get_current_user` dependency to call `set_current_user_id(user_id)`.
- **Files modified:** `backend/app/core/tenant.py`, `backend/app/core/security.py`
- **Commit:** 9e8e1b4 (included with Task 1)

**2. [Rule 1 - Bug] Fixed wrong endpoint URL and HTTP method in E2E test helpers**
- **Found during:** Task 1 — transition tests returned 404
- **Issue:** Used `/api/v1/jobs/{id}/status` (POST) instead of `/api/v1/jobs/{id}/transition` (PATCH); also used `expected_version` instead of `version`
- **Fix:** Corrected endpoint URL, HTTP method, and field name in `transition_job` and `report_delay` helper functions
- **Files modified:** `backend/tests/test_phase_7_e2e.py`
- **Commit:** 9e8e1b4

**3. [Rule 1 - Bug] Fixed cross-client ASGI transport pattern**
- **Found during:** Task 1 — auth client created from `async_client._transport` returned 404 for subsequent requests
- **Fix:** Defined `_TRANSPORT = ASGITransport(app=app)` as module-level constant; `_make_authed_client(token)` creates new `AsyncClient` with shared transport
- **Files modified:** `backend/tests/test_phase_7_e2e.py`
- **Commit:** 9e8e1b4

**4. [Rule 1 - Bug] Multiple Flutter finder scope fixes**
- **Found during:** Task 2 — `findsOneWidget` failures for text appearing in multiple widget tree locations
- **Issues:** "My Jobs" in AppBar + section header; badge "3" in step circles; "plumber" description in AppBar + details card
- **Fix:** Changed to `findsWidgets` where text correctly appears in multiple locations; used `pump(Duration(milliseconds:300))` for TabBarView animation instead of bare `pump()`
- **Files modified:** `mobile/test/e2e/phase_7_client_portal_e2e_test.dart`
- **Commit:** 3bc9b8c

## Decisions Made

1. Used ASGI test client (register via API endpoint) for notification unit tests to avoid raw `AsyncSession` teardown "Event loop is closed" errors in session-scoped test DB.
2. Used `StreamProvider.family.overrideWith()` not real Drift DB for Flutter E2E — Drift's async* nested generators with DB calls cannot resolve in FakeAsync.
3. FCM notifications tested for graceful degradation (no `GOOGLE_APPLICATION_CREDENTIALS` in CI) — tests verify endpoint responses, not actual FCM delivery.

## Self-Check: PASSED

- FOUND: `backend/tests/test_notification_service.py`
- FOUND: `backend/tests/test_phase_7_e2e.py`
- FOUND: `mobile/test/e2e/phase_7_client_portal_e2e_test.dart`
- FOUND: commit `9e8e1b4` (Task 1)
- FOUND: commit `3bc9b8c` (Task 2)
