---
phase: 13-web-foundation-and-auth
plan: "03"
subsystem: auth
tags: [nextjs, typescript, cookies, httponly, jwt, jose, fetch, proxy, route-handlers]

# Dependency graph
requires:
  - phase: 13-02
    provides: "Next.js 16 scaffold with TypeScript types (LoginRequest, TokenResponse, AuthUser, ApiErrorResponse) and jose package"
provides:
  - Login Route Handler at /api/auth/login — proxies to FastAPI, sets httpOnly cookies, returns user metadata
  - Refresh Route Handler at /api/auth/refresh — rotates both cookies from refresh_token cookie
  - Logout Route Handler at /api/auth/logout — clears both cookies, calls FastAPI best-effort
  - API Proxy Route Handler at /api/proxy — injects access_token cookie as Bearer to FastAPI
  - apiClient fetch wrapper with 401 retry and ApiError class
  - getServerUser() server-only utility decoding JWT from cookie for Server Components
  - proxy.ts edge route guard redirecting unauthenticated requests to /login
affects:
  - 13-04-ui-shell (login form uses /api/auth/login; pages use getServerUser; sidebar uses apiClient)

# Tech tracking
tech-stack:
  added: []  # No new packages — jose already installed in 13-02
  patterns:
    - httpOnly cookie pattern for token storage — tokens never in localStorage or client JS
    - Route Handler proxy pattern — Next.js server routes sit between browser and FastAPI
    - Optimistic route guard (cookie existence check) in proxy.ts — real validation at FastAPI
    - 401 retry pattern in apiClient — transparent refresh without user action

key-files:
  created:
    - web/src/app/api/auth/login/route.ts
    - web/src/app/api/auth/refresh/route.ts
    - web/src/app/api/auth/logout/route.ts
    - web/src/app/api/proxy/route.ts
    - web/src/lib/api-client.ts
    - web/src/lib/auth.ts
    - web/proxy.ts
    - web/.env.local
  modified: []

key-decisions:
  - "proxy.ts checks cookie existence only — no JWT signature verification at edge (optimistic guard); FastAPI validates on each API call"
  - "Refresh cookie scoped to path=/api/auth/refresh so browser only sends it to that specific endpoint"
  - "apiClient redirects to /login?reason=session_expired (no redirectTo param) on failed refresh — per prior decision"
  - "Logout calls FastAPI best-effort — always clears cookies regardless of FastAPI response to prevent stuck sessions"

patterns-established:
  - "Pattern: All Route Handlers use FASTAPI_URL env var (default http://localhost:8000) — no hardcoded URLs"
  - "Pattern: access_token maxAge=900 (15min), refresh_token maxAge=2592000 (30 days) — mirrors JWT_ACCESS_TOKEN_EXPIRE_MINUTES"
  - "Pattern: cookies() always awaited (Next.js 16 async requirement) — missing await is silent bug"
  - "Pattern: apiClient routes via /api/proxy not directly to FastAPI — browser never gets FASTAPI_URL"

requirements-completed: [AUTH-01, AUTH-02, AUTH-03, AUTH-04]

# Metrics
duration: 8min
completed: 2026-03-16
---

# Phase 13 Plan 03: Auth Route Handlers and API Client Summary

**httpOnly cookie auth layer: login/refresh/logout Route Handlers proxying to FastAPI, generic API proxy forwarding Bearer from cookie, apiClient with 401 retry, server-side getServerUser, and proxy.ts edge guard**

## Performance

- **Duration:** 8 min
- **Started:** 2026-03-16T07:11:04Z
- **Completed:** 2026-03-16T07:19:00Z
- **Tasks:** 2
- **Files modified:** 8

## Accomplishments

- Four Route Handlers (login, refresh, logout, API proxy) that keep tokens exclusively in httpOnly cookies — browser JS never touches raw JWTs
- apiClient fetch wrapper with transparent 401 recovery: calls /api/auth/refresh, retries once, falls through to /login on failure; ApiError class carries status + detail
- getServerUser() server-only utility using jose.decodeJwt() (no signature verification) for Server Components to conditionally render based on user role
- proxy.ts edge route guard that redirects any unauthenticated request to /login with no redirectTo parameter; public routes bypass the guard

## Task Commits

Each task was committed atomically:

1. **Task 1: Auth Route Handlers + API Proxy** - `ab83523` (feat)
2. **Task 2: apiClient, server auth utility, proxy.ts** - `670e5a8` (feat)

**Plan metadata:** (docs commit follows)

## Files Created/Modified

- `web/src/app/api/auth/login/route.ts` - POST handler: proxies credentials to FastAPI, sets access_token (httpOnly, maxAge 900) and refresh_token (httpOnly, path=/api/auth/refresh, maxAge 2592000)
- `web/src/app/api/auth/refresh/route.ts` - POST handler: reads refresh_token cookie, exchanges with FastAPI, rotates both cookies; clears on failure
- `web/src/app/api/auth/logout/route.ts` - POST handler: calls FastAPI logout best-effort, always clears both cookies via maxAge=0
- `web/src/app/api/proxy/route.ts` - GET/POST/PATCH/DELETE handler: reads access_token cookie, forwards as Bearer header to FastAPI with original body/content-type
- `web/src/lib/api-client.ts` - Client-side fetch wrapper routing via /api/proxy; ApiError class; 401 retry with refresh; convenience methods apiGet/apiPost/apiPatch/apiDelete
- `web/src/lib/auth.ts` - Server-only utility using jose.decodeJwt(); extracts user_id/company_id/roles from access_token cookie; returns null on missing or malformed token
- `web/proxy.ts` - Next.js 16 edge route guard; PUBLIC_ROUTES allowlist; cookie existence check; redirect to /login
- `web/.env.local` - FASTAPI_URL=http://localhost:8000 (server-side only, not exposed to client)

## Decisions Made

- Refresh cookie scoped to `path=/api/auth/refresh` so browsers only transmit it to that one endpoint, reducing the attack surface
- Logout calls FastAPI best-effort (fire-and-forget with catch) — cookies always cleared so users can never get stuck in an invalid session state
- proxy.ts performs cookie existence check only (not signature verification) — this is the documented "optimistic guard" pattern; real validation happens at FastAPI
- apiClient redirect to `/login?reason=session_expired` with no `redirectTo` parameter — consistent with prior decision that login always goes to dashboard home

## Deviations from Plan

None — plan executed exactly as written.

## Issues Encountered

None.

## User Setup Required

`web/.env.local` was created with `FASTAPI_URL=http://localhost:8000`. For production, override with the actual FastAPI deployment URL. This file is not committed to git (should be in .gitignore).

## Next Phase Readiness

- Login form in 13-04 can POST to `/api/auth/login` and dispatch `setAuthUser` to Redux
- All dashboard pages can use `getServerUser()` in Server Components for role-based rendering
- `apiClient` is ready for TanStack Query data fetching hooks in 13-04 and beyond
- proxy.ts is active — any new unauthenticated route will automatically redirect to /login
- No blockers for Plan 13-04 (UI Shell: sidebar, topbar, login page)

---
*Phase: 13-web-foundation-and-auth*
*Completed: 2026-03-16*

## Self-Check: PASSED

- FOUND: web/src/app/api/auth/login/route.ts
- FOUND: web/src/app/api/auth/refresh/route.ts
- FOUND: web/src/app/api/auth/logout/route.ts
- FOUND: web/src/app/api/proxy/route.ts
- FOUND: web/src/lib/api-client.ts
- FOUND: web/src/lib/auth.ts
- FOUND: web/proxy.ts
- FOUND commit ab83523 (Task 1: auth route handlers + API proxy)
- FOUND commit 670e5a8 (Task 2: apiClient + server auth + proxy.ts)
