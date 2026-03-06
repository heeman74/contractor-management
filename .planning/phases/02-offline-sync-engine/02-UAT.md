---
status: complete
phase: 02-offline-sync-engine
source: 02-01-SUMMARY.md, 02-02-SUMMARY.md, 02-03-SUMMARY.md, 02-04-SUMMARY.md, 02-05-SUMMARY.md, 02-06-SUMMARY.md
started: 2026-03-05T22:30:00Z
updated: 2026-03-06T00:05:00Z
---

## Current Test

[testing complete]

## Tests

### 1. Cold Start Smoke Test
expected: Kill any running backend server. Run Alembic migrations (including new 0002_soft_delete_sync). Start the FastAPI backend from scratch. Server boots without errors, migration 0002 completes (deleted_at columns, updated_at triggers created), and GET /api/v1/sync?cursor= returns a valid JSON response with companies, users, user_roles arrays and a server_timestamp field.
result: issue
reported: "There is user_roles: []"
severity: minor

### 2. Delta Sync Endpoint Returns Changes Since Cursor
expected: Create a company via POST /api/v1/companies. Note the server_timestamp from GET /api/v1/sync (no cursor). Create a second company. Call GET /api/v1/sync?cursor={first_timestamp}. Only the second company appears in the response — the first is excluded by the cursor filter.
result: pass

### 3. Tombstone Propagation in Sync Response
expected: Create a company, then soft-delete it (set deleted_at via direct DB update or API if available). Call GET /api/v1/sync with a cursor before the deletion. The deleted company appears in the response with a non-null deleted_at field, proving tombstones propagate through delta sync.
result: pass

### 4. Idempotent Company Create (Duplicate UUID)
expected: POST /api/v1/companies with a client-provided UUID. POST the same request again with the same UUID. The second request returns 201 (not 409 or 500). Only one company row exists in the database. The original data is preserved (not overwritten by the duplicate).
result: pass

### 5. Sync Status Subtitle Always Visible in App Bar
expected: Launch the Flutter app. The app bar shows a subtitle below the screen title at all times — "All synced" with a check icon on fresh launch. Navigate between Home, Jobs, and Schedule tabs. The sync status subtitle remains visible on every tab (shared AppShell AppBar, not per-screen).
result: pass

### 6. Offline Create Appears Immediately in UI
expected: Put the device in airplane mode (or disconnect network). Create a new company. The company appears immediately in the list (from local Drift database). The sync status subtitle changes to show pending items (e.g., "1 item pending"). No error dialog or loading spinner appears.
result: pass

### 7. Offline Record Syncs on Connectivity Restore
expected: With the record created offline (from test 6), restore network connectivity. The SyncEngine automatically triggers (ConnectivityService detects network restore). The sync status shows "Syncing 1 of 1..." then transitions to "All synced". The record now exists in the backend database.
result: issue
reported: "I says it is all synced, but there is not enough data to see syncing status"
severity: minor

### 8. Pull-to-Refresh Triggers Sync
expected: On the Home screen (or Jobs or Schedule), pull down to trigger RefreshIndicator. The sync status subtitle briefly shows syncing activity. The pull-to-refresh gesture works on all three main screens (Home, Jobs, Schedule).
result: skipped
reason: Not enough data to test — needs more content in later phases

### 9. No Loading Spinner on App Launch
expected: Force-close the app and relaunch. The app opens immediately showing cached data from the local Drift database. No loading spinner or skeleton screen appears. The sync status subtitle shows "All synced" (not a loading state) while background sync runs silently.
result: skipped
reason: Not enough data to test — needs more content in later phases

### 10. Sync Engine Retry Behavior (4xx Parks, 5xx Retries)
expected: If a sync push fails with a 4xx error (e.g., validation error), the queue item is parked immediately and does not retry. If a sync push fails with a 5xx error, it retries with exponential backoff (1s, 2s, 4s, 8s, 16s). After 5 failed retries, the item stays in the queue and retries fresh on the next connectivity cycle — it is never abandoned.
result: pass

## Summary

total: 10
passed: 6
issues: 2
pending: 0
skipped: 2
skipped: 0

## Gaps

- truth: "Sync endpoint returns populated user_roles array when user roles exist in database"
  status: failed
  reason: "User reported: There is user_roles: []"
  severity: minor
  test: 1
  artifacts: []
  missing: []

- truth: "Sync status shows active syncing state (e.g., 'Syncing 1 of 1...') before transitioning to 'All synced' on connectivity restore"
  status: failed
  reason: "User reported: I says it is all synced, but there is not enough data to see syncing status"
  severity: minor
  test: 7
  artifacts: []
  missing: []

- truth: "GET /api/v1/sync?cursor= returns a valid JSON response with companies, users, user_roles arrays and a server_timestamp field when cursor is empty or omitted"
  status: resolved
  reason: "User reported: GET /api/v1/sync?cursor= returns 422 validation error: 'Input should be a valid datetime or date, input is too short'. Empty cursor string is not handled — should default to epoch for full first-launch download."
  severity: major
  test: 1
  root_cause: "FastAPI/Pydantic type coercion rejects empty string for datetime | None query parameter. The cursor param in router.py is typed as datetime | None with default=None, but when cursor= is present as empty string, Pydantic tries to parse '' as datetime and fails. The epoch fallback logic is unreachable because validation rejects before handler executes."
  artifacts:
    - path: "backend/app/features/sync/router.py"
      issue: "cursor parameter typed as datetime | None — empty string rejected at validation layer"
  missing:
    - "Change cursor type to str | None and manually parse/coerce in handler body: empty/None defaults to epoch, non-empty parsed as datetime"
  debug_session: ".planning/debug/sync-empty-cursor-422.md"

- truth: "App bar shows sync status subtitle on all tabs after login"
  status: resolved
  reason: "User reported: No response with clicking login buttons."
  severity: blocker
  test: 5
  root_cause: "GoRouter redirect function in app_router.dart missing redirect case for authenticated users on auth-only screens. AuthAuthenticated branch only calls _checkRoleAccess() which returns null for /onboarding (not a role-gated route), so user stays on onboarding screen after login. Pre-existing logic gap, not a Phase 2 regression."
  artifacts:
    - path: "mobile/lib/core/routing/app_router.dart"
      issue: "AuthAuthenticated redirect case does not redirect away from /splash or /onboarding to /home"
  missing:
    - "Add check in AuthAuthenticated branch: if location is /splash or /onboarding, redirect to /home before calling _checkRoleAccess"
  debug_session: ".planning/debug/login-buttons-not-responding.md"
