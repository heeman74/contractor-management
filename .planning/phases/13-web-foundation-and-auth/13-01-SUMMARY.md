---
phase: 13-web-foundation-and-auth
plan: 01
subsystem: auth
tags: [jwt, fastapi, cookies, cors, postgres, alembic, dual-auth]

# Dependency graph
requires:
  - phase: 12-business-operations
    provides: existing auth endpoints (login, refresh, logout), users model, security.py infrastructure

provides:
  - get_current_user dependency accepting both Bearer header (mobile) and access_token cookie (web)
  - client_type nullable VARCHAR column on users table
  - Alembic migration 0012 adding client_type to users
  - Phase 13 backend E2E test suite (8 tests)

affects: [13-02-nextjs-scaffold, 13-03-web-auth-flow, 13-04-admin-layout]

# Tech tracking
tech-stack:
  added: []
  patterns:
    - "fastapi.Cookie(default=None) as optional dependency parameter alongside HTTPBearer(auto_error=False)"
    - "Bearer priority pattern: raw_token = (credentials.credentials if credentials else None) or access_token"

key-files:
  created:
    - backend/migrations/versions/0012_add_client_type_to_users.py
    - backend/tests/integration/test_phase_13_e2e.py
  modified:
    - backend/app/core/security.py
    - backend/app/features/users/models.py

key-decisions:
  - "Bearer header always takes priority over cookie when both present — mobile app is unaffected"
  - "access_token cookie name matches Next.js httpOnly cookie set by Route Handler proxy"
  - "client_type is nullable (not required) — existing rows unaffected, no backfill required"
  - "CORS config already correct — http://localhost:3000 fallback already in main.py, no change needed"
  - "down_revision for migration 0012 uses short revision ID '0011' not the filename suffix"

patterns-established:
  - "TDD Red-Green: test file committed in RED state before implementation, then GREEN commit"
  - "Use /api/v1/users/ (list endpoint) as the protected endpoint proxy for auth regression tests"

requirements-completed: [AUTH-02, AUTH-03]

# Metrics
duration: 8min
completed: 2026-03-16
---

# Phase 13 Plan 01: Backend Dual-Auth (Bearer + Cookie) Summary

**FastAPI get_current_user extended to accept httpOnly access_token cookie as web fallback alongside existing mobile Bearer header, with client_type migration and 8-test E2E suite**

## Performance

- **Duration:** 8 min
- **Started:** 2026-03-16T06:58:16Z
- **Completed:** 2026-03-16T07:06:16Z
- **Tasks:** 2 (Task 1: TDD implementation; Task 2: no-op verification)
- **Files modified:** 4

## Accomplishments

- Extended `get_current_user` with `Cookie(default=None)` fallback — Bearer always takes priority; mobile unaffected
- Added `client_type` nullable column to User model + Alembic migration 0012
- Created 8 backend E2E tests covering all auth paths: Bearer regression, cookie auth, priority, 401 guards, login shape, refresh rotation, logout revocation
- Confirmed CORS config (`allow_credentials=True`, `http://localhost:3000` fallback) already correct — no changes needed
- Full backend test suite: 253 passed, 0 failed

## Task Commits

Each task was committed atomically:

1. **Task 1 (RED): Add failing test for dual-auth** - `e1d5197` (test)
2. **Task 1 (GREEN): Extend get_current_user + client_type migration** - `45faf6c` (feat)
3. **Task 2: CORS verification no-op** — no commit (no code changes; full suite pass confirmed in task 2)

_Note: TDD tasks have RED + GREEN commits. Task 2 had no code changes._

## Files Created/Modified

- `backend/app/core/security.py` — Added `from fastapi import Cookie`; `get_current_user` now accepts `access_token: str | None = Cookie(default=None)`
- `backend/app/features/users/models.py` — Added `client_type: Mapped[str | None] = mapped_column(String, nullable=True)`
- `backend/migrations/versions/0012_add_client_type_to_users.py` — Alembic migration adding nullable client_type column to users table
- `backend/tests/integration/test_phase_13_e2e.py` — 8 E2E integration tests for dual-auth behavior

## Decisions Made

- Bearer header takes priority over cookie: `raw_token = (credentials.credentials if credentials else None) or access_token` — this ensures existing mobile Bearer flow is completely unaffected
- Cookie parameter named `access_token` to match the httpOnly cookie name the Next.js Route Handler proxy will set
- `client_type` nullable (no server_default) — existing rows remain NULL; no backfill migration needed since it's informational only
- CORS config was already compatible with web origin — `http://localhost:3000` fallback already present, `allow_credentials=True` already set, no change needed

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 3 - Blocking] Wrong down_revision key in migration 0012**
- **Found during:** Task 1 (migration execution in tests)
- **Issue:** Used `"0011_business_operations_tables"` as down_revision but Alembic maps by revision ID `"0011"`, not filename
- **Fix:** Changed `down_revision` to `"0011"` (the short revision string)
- **Files modified:** `backend/migrations/versions/0012_add_client_type_to_users.py`
- **Verification:** `pytest tests/integration/test_phase_13_e2e.py` all 8 tests pass
- **Committed in:** `45faf6c` (Task 1 GREEN commit)

---

**Total deviations:** 1 auto-fixed (Rule 3 - blocking)
**Impact on plan:** Migration key fix was necessary for correctness. No scope creep.

## Issues Encountered

- `/api/v1/users/me` endpoint doesn't exist — test file updated to use `/api/v1/users/` (list endpoint) as the protected endpoint proxy for regression checks. This is an equivalent protected endpoint requiring auth.

## User Setup Required

None - no external service configuration required.

## Next Phase Readiness

- Backend dual-auth is live: Next.js web layer can now authenticate via httpOnly `access_token` cookie
- CORS already configured for `http://localhost:3000` (dev); production requires `CORS_ORIGINS` env var
- `client_type` column available for session attribution when Next.js login flow is implemented in Plan 13-03
- All 253 existing backend tests pass — mobile app unaffected

## Self-Check: PASSED

All created files exist on disk. All task commits verified in git history.

---
*Phase: 13-web-foundation-and-auth*
*Completed: 2026-03-16*
