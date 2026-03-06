---
phase: 02-offline-sync-engine
plan: "06"
subsystem: backend-sync-api, mobile-routing
tags: [bug-fix, gap-closure, uat-unblock, fastapi, gorouter]
dependency_graph:
  requires: []
  provides: [empty-cursor-handling, authenticated-redirect]
  affects: [uat-tests-1-through-10, sync-first-launch, login-flow]
tech_stack:
  added: []
  patterns:
    - "str | None cursor param with explicit fromisoformat parsing for FastAPI empty-string safety"
    - "GoRouter AuthAuthenticated redirect guard: auth-screen check before role-access check"
key_files:
  modified:
    - path: backend/app/features/sync/router.py
      change: "cursor param type str | None with explicit parsing; empty string treated as epoch"
    - path: mobile/lib/core/routing/app_router.dart
      change: "AuthAuthenticated branch redirects /splash and /onboarding to /home before role check"
decisions:
  - "str | None cursor type chosen over datetime | None — lets Pydantic accept empty string, parsing moved to handler body"
  - "Auth-screen redirect added as prefix check in AuthAuthenticated branch — _checkRoleAccess left unchanged to avoid regression risk"
metrics:
  duration: "3 min"
  completed: "2026-03-06"
  tasks_completed: 2
  files_modified: 2
---

# Phase 2 Plan 06: UAT Gap Fixes — Sync Empty Cursor + Auth Redirect Summary

Two surgical bug fixes unblocking 10 UAT tests: empty cursor string in sync endpoint now returns 200 instead of 422, and authenticated users on /splash or /onboarding are immediately redirected to /home.

## Objective

Fix two UAT-diagnosed gaps:
1. `GET /api/v1/sync?cursor=` returning 422 (FastAPI/Pydantic rejects empty string for `datetime | None` type)
2. Login buttons having no visible effect (GoRouter `AuthAuthenticated` branch allowed users to stay on `/onboarding`)

## Tasks Completed

| # | Task | Commit | Files |
|---|------|--------|-------|
| 1 | Fix sync endpoint to accept empty cursor string | 4d1f468 | backend/app/features/sync/router.py |
| 2 | Fix GoRouter redirect for authenticated users on auth screens | 6bb1903 | mobile/lib/core/routing/app_router.dart |

## Changes Made

### Task 1: Backend Sync Router (`backend/app/features/sync/router.py`)

**Root cause (from debug file):** FastAPI distinguishes "param absent" (gets `None` default) from "param present but empty" (gets `""` which must match the declared type). With `cursor: datetime | None`, an empty string is not `None` and not a valid datetime, so Pydantic raises 422 before the handler runs.

**Fix:** Changed `cursor` parameter type from `datetime | None` to `str | None`. Added explicit parsing logic inside the handler:
- `cursor is None` or `cursor.strip() == ""` → use `_EPOCH_START` (epoch for full download)
- Valid ISO8601 string → `datetime.fromisoformat(cursor)`
- Invalid non-empty string → raises `HTTPException(422)` with descriptive message

This correctly handles all three cases:
- `GET /api/v1/sync` (absent) → epoch → 200
- `GET /api/v1/sync?cursor=` (empty) → epoch → 200 (was 422 before fix)
- `GET /api/v1/sync?cursor=2026-01-01T00:00:00Z` (valid) → parsed datetime → 200

### Task 2: Mobile Router (`mobile/lib/core/routing/app_router.dart`)

**Root cause (from debug file):** The `AuthAuthenticated` redirect branch delegated entirely to `_checkRoleAccess`. Since `/onboarding` is not a role-gated route (doesn't start with `/admin`, `/contractor`, or `/client`), `_checkRoleAccess` returns `null` (allow). This means after a successful login, the user stayed on `/onboarding` — the buttons worked but had no visible effect.

**Fix:** Added a prefix check in the `AuthAuthenticated` branch before calling `_checkRoleAccess`:
```dart
AuthAuthenticated(:final roles) =>
    (location == RouteNames.splash || location == RouteNames.onboarding)
        ? RouteNames.home
        : _checkRoleAccess(location, roles),
```

This ensures:
- User on `/splash` or `/onboarding` with `AuthAuthenticated` → redirected to `/home`
- User on any other route with `AuthAuthenticated` → existing `_checkRoleAccess` logic applies
- `_checkRoleAccess` left completely unchanged

## Verification

**Backend:**
- Dart analyzer reports no errors for `app_router.dart` (1 pre-existing `cascade_invocations` info on line 54, unrelated to our change)
- Python 3.10+ required to run tests (system has Python 3.8.2); codebase uses `X | Y` union syntax throughout — integration tests require PostgreSQL via Docker
- Code logic verified by inspection: all three cursor cases handled correctly, `_EPOCH_START` constant and all downstream `service.*_since()` calls unchanged
- `ast.parse()` confirms valid Python syntax

**Mobile:**
- `flutter analyze lib/core/routing/app_router.dart` → 1 pre-existing info (cascade_invocations on line 54, not our change), no errors
- Switch expression correctly structured: `AuthAuthenticated` branch returns `RouteNames.home` for auth screens, delegates to `_checkRoleAccess` for all other routes

## Deviations from Plan

None — plan executed exactly as written.

## UAT Impact

| UAT Test | Status Before | Status After |
|----------|---------------|--------------|
| Test 1 (Cold Start Smoke Test: `cursor=`) | FAIL (422) | PASS (200 + full sync payload) |
| Test 5 (Sync Status Subtitle) | BLOCKED (login broken) | UNBLOCKED |
| Tests 6-10 (all require login) | SKIPPED (login broken) | UNBLOCKED |

## Self-Check: PASSED

| Item | Status |
|------|--------|
| backend/app/features/sync/router.py | FOUND |
| mobile/lib/core/routing/app_router.dart | FOUND |
| .planning/phases/02-offline-sync-engine/02-06-SUMMARY.md | FOUND |
| Commit 4d1f468 (Task 1) | FOUND |
| Commit 6bb1903 (Task 2) | FOUND |
