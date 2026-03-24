---
phase: 13-web-foundation-and-auth
verified: 2026-03-16T07:26:33Z
status: human_needed
score: 16/16 must-haves verified
human_verification:
  - test: "End-to-end login flow — visit http://localhost:3000 (unauthenticated), confirm redirect to /login, submit empty form and confirm per-field inline validation errors, submit invalid credentials and confirm red alert banner above form, submit valid admin credentials and confirm redirect always goes to / (never honors redirectTo)"
    expected: "Redirect to /login, inline validation errors on empty submit, red banner on bad creds, redirect to dashboard home on success"
    why_human: "Browser cookie behavior (httpOnly cookie being set by Route Handler) and visual layout cannot be verified without a live browser session"
  - test: "Session persistence — after successful login, refresh the browser tab and confirm the user remains authenticated (still on dashboard, not redirected to /login)"
    expected: "Refresh does not clear the session; proxy.ts sees the httpOnly access_token cookie and allows the request through"
    why_human: "Requires a real browser to verify the httpOnly cookie survives a page refresh"
  - test: "Sidebar collapse and localStorage persistence — click the ChevronLeft collapse toggle, verify sidebar shrinks to 64px icon-only mode, then refresh the page and confirm it remains collapsed"
    expected: "Sidebar collapses to icon-only (w-16); after refresh, still collapsed (localStorage value persists)"
    why_human: "CSS transition behavior and localStorage hydration on mount require visual/browser verification"
  - test: "Dashboard KPI cards with real data — with the FastAPI backend running, log in and view the dashboard home; verify the 4 KPI cards load with real counts (not stubbed zeros) and the Recent Activity feed shows actual job records"
    expected: "KPI cards show real counts from backend; Recent Activity shows job titles with StatusBadge colors"
    why_human: "Requires both FastAPI and Next.js running simultaneously; actual data varies per environment"
  - test: "Error toast persistence — trigger an API error condition (e.g., network error or invalid endpoint), confirm the error toast appears at bottom-right and does NOT auto-dismiss after 5 seconds"
    expected: "toast.error renders at bottom-right, remains visible indefinitely until user manually dismisses"
    why_human: "Auto-dismiss behavior is time-dependent and requires visual confirmation"
  - test: "Logout flow — click avatar dropdown > Log out, confirm redirect to /login, then attempt to navigate to http://localhost:3000 directly and confirm proxy.ts redirects back to /login"
    expected: "Cookies cleared, redirect to /login, subsequent navigation to / redirects to /login"
    why_human: "Cookie clearing and redirect behavior require a live browser session"
  - test: "Custom 404 page — navigate to http://localhost:3000/nonexistent-page, confirm the custom 404 page renders with '404' heading and 'Go to Dashboard' button"
    expected: "Custom not-found.tsx renders with indigo-600 '404' text and working Go to Dashboard link"
    why_human: "Visual rendering confirmation requires a browser"
  - test: "Mobile responsive sidebar — resize browser to < 768px, confirm the desktop sidebar is hidden and a hamburger Menu button appears in the topbar; click it and confirm the Sheet overlay slides in with the nav items"
    expected: "Desktop sidebar hidden at <768px; hamburger visible; Sheet overlay opens with all 8 nav items"
    why_human: "Viewport-dependent CSS and animated Sheet behavior require a browser"
---

# Phase 13: Web Foundation and Auth Verification Report

**Phase Goal:** Web Foundation and Auth — scaffold Next.js project, implement cookie-based auth proxy, build login page and admin dashboard shell
**Verified:** 2026-03-16T07:26:33Z
**Status:** human_needed
**Re-verification:** No — initial verification

## Goal Achievement

### Observable Truths

| # | Truth | Status | Evidence |
|---|-------|--------|----------|
| 1 | get_current_user accepts both Bearer header and access_token cookie without breaking mobile | VERIFIED | `security.py` line 124: `raw_token = (credentials.credentials if credentials else None) or access_token`; 8/8 E2E tests pass |
| 2 | CORS allows http://localhost:3000 with credentials | VERIFIED | `main.py` has `allow_credentials=True` and `["http://localhost:3000"]` fallback; confirmed no-op in 13-01 summary |
| 3 | Web and mobile sessions can be attributed to their origin | VERIFIED | `client_type` nullable column added to users model (line 32) and migration 0012 |
| 4 | Next.js dev server scaffolded with TypeScript strict mode | VERIFIED | `web/` exists; `npx tsc --noEmit` exits with zero errors |
| 5 | Redux makeStore factory creates per-request stores (not singleton) | VERIFIED | `web/src/store/index.ts`: `export const makeStore = () => configureStore(...)` (factory, not singleton) |
| 6 | TanStack Query provider wraps the app | VERIFIED | `layout.tsx` imports and renders `QueryProvider` wrapping children |
| 7 | Login Route Handler proxies credentials to FastAPI and stores tokens in httpOnly cookies | VERIFIED | `login/route.ts`: fetches `${FASTAPI_URL}/api/v1/auth/login`, sets `httpOnly: true` cookies, returns only user metadata |
| 8 | Refresh Route Handler exchanges refresh token cookie for new token pair | VERIFIED | `refresh/route.ts`: reads `refresh_token` cookie, calls FastAPI, rotates both cookies; returns 401 + clears on failure |
| 9 | Logout Route Handler calls FastAPI logout and clears both cookies | VERIFIED | `logout/route.ts`: best-effort FastAPI call, always sets `maxAge: 0` on both cookies |
| 10 | apiClient retries once on 401 by calling refresh, then redirects to /login on failure | VERIFIED | `api-client.ts` lines 35-46: 401 calls `/api/auth/refresh`, retries with `retry=false`, redirects to `/login?reason=session_expired` on failure |
| 11 | proxy.ts redirects unauthenticated requests to /login (no redirectTo) | VERIFIED | `proxy.ts`: checks `request.cookies.has("access_token")`, redirects to `/login` with no query params |
| 12 | Tokens are NEVER exposed to JavaScript (httpOnly cookies only) | VERIFIED | Login route returns only `{user_id, company_id, roles}`; proxy reads cookie server-side; apiClient routes via `/api/proxy`; no token in Redux (auth-slice holds display metadata only) |
| 13 | Admin can log in and land on dashboard home | VERIFIED (code) | Login page POSTs to `/api/auth/login`, dispatches `setAuthUser`, calls `router.push("/")` unconditionally on success |
| 14 | Global sidebar visible with all 8 module links | VERIFIED | `sidebar.tsx`: `navItems` array has exactly 8 items (Dashboard, Jobs, Schedule, Quotes, Invoices, Clients, Contractors, Reports) with correct Lucide icons |
| 15 | Sidebar collapses and persists state to localStorage | VERIFIED | `sidebar.tsx` lines 196-211: reads localStorage on mount via `setSidebarCollapsed`, dispatches `toggleSidebar` writing to localStorage |
| 16 | Error toasts persist until manually dismissed | VERIFIED | `layout.tsx` Toaster has `toastOptions` with `classNames: { error: "!duration-[Infinity]" }`; `dashboard/page.tsx` uses `toast.error("...", { duration: Infinity })` |

**Score:** 16/16 truths verified

### Required Artifacts

| Artifact | Expected | Status | Details |
|----------|----------|--------|---------|
| `backend/app/core/security.py` | Dual-auth get_current_user (Bearer + Cookie) | VERIFIED | Contains `Cookie` import and `access_token: str | None = Cookie(default=None)` |
| `backend/migrations/versions/0012_add_client_type_to_users.py` | client_type migration | VERIFIED | Adds nullable `client_type` VARCHAR column; `down_revision = "0011"` |
| `backend/tests/integration/test_phase_13_e2e.py` | Backend E2E tests for dual-auth | VERIFIED | 8 tests, all pass |
| `web/package.json` | Project manifest with all dependencies | VERIFIED | Contains `next`, `@reduxjs/toolkit`, `@tanstack/react-query`, `shadcn/ui`, `playwright`, etc. |
| `web/src/store/index.ts` | makeStore factory (SSR-safe) | VERIFIED | Exports `makeStore` function (not singleton), `AppStore`, `RootState`, `AppDispatch` |
| `web/src/store/provider.tsx` | StoreProvider with useRef pattern | VERIFIED | Uses `useRef<AppStore>(undefined)` pattern |
| `web/src/components/providers/query-provider.tsx` | TanStack Query client provider | VERIFIED | Exports `QueryProvider` with `QueryClientProvider` |
| `web/src/types/api.ts` | TypeScript types matching backend schemas | VERIFIED | Contains `TokenResponse`, `LoginRequest`, `AuthUser`, `ApiErrorResponse`, `Job` |
| `web/playwright.config.ts` | Playwright test configuration | VERIFIED | Contains `baseURL: "http://localhost:3000"` and `webServer` config |
| `web/tests/auth.spec.ts` | Auth E2E test stubs | VERIFIED | 7 skipped stubs for AUTH-01 through AUTH-06 using `test.skip()` |
| `web/tests/layout.spec.ts` | Layout E2E test stubs | VERIFIED | 9 skipped stubs for AUTH-05 sidebar/topbar/responsive |
| `web/src/app/api/auth/login/route.ts` | POST handler proxying login to FastAPI | VERIFIED | Exports `POST`; sets httpOnly cookies; returns user metadata only |
| `web/src/app/api/auth/refresh/route.ts` | POST handler exchanging refresh token | VERIFIED | Exports `POST`; reads cookie; rotates both tokens |
| `web/src/app/api/auth/logout/route.ts` | POST handler revoking tokens | VERIFIED | Exports `POST`; clears cookies with `maxAge: 0` |
| `web/src/app/api/proxy/route.ts` | Generic API proxy with Bearer injection | VERIFIED | Exports `GET`, `POST`, `PATCH`, `DELETE`; injects `Authorization: Bearer ${accessToken}` |
| `web/src/lib/api-client.ts` | Client fetch wrapper with 401 retry | VERIFIED | Exports `apiClient`, `ApiError`, `apiGet`, `apiPost`, `apiPatch`, `apiDelete` |
| `web/src/lib/auth.ts` | Server-side utility to decode token from cookie | VERIFIED | Exports `getServerUser()` using `jose.decodeJwt()`; marked `server-only` |
| `web/proxy.ts` | Next.js 16 edge route guard | VERIFIED | Exports default function and `config.matcher`; checks cookie existence |
| `web/src/app/(auth)/login/page.tsx` | Split-screen login page with form (min 80 lines) | VERIFIED | 223 lines; split-screen layout; react-hook-form + zod; inline error banner |
| `web/src/components/layout/sidebar.tsx` | Collapsible dark sidebar (min 80 lines) | VERIFIED | 241 lines; 8 nav items; collapse toggle; Sheet mobile overlay |
| `web/src/components/layout/topbar.tsx` | Breadcrumbs + user dropdown (min 40 lines) | VERIFIED | 142 lines; pathname-based breadcrumbs; logout dropdown |
| `web/src/app/(dashboard)/page.tsx` | Dashboard home with KPI cards (min 60 lines) | VERIFIED | 197 lines; 4 KPI cards via TanStack Query; Recent Activity feed |
| `web/src/components/shared/status-badge.tsx` | Reusable status badge | VERIFIED | Exports `StatusBadge`; semantic color map (green/yellow/red/blue/gray) |
| `web/src/app/not-found.tsx` | Custom 404 page | VERIFIED | Renders "404" heading and "Go to Dashboard" link to "/" |
| `web/src/app/error.tsx` | Custom 500 error boundary | VERIFIED | "use client"; has `reset()` prop; Try Again + Go to Dashboard buttons |

### Key Link Verification

| From | To | Via | Status | Details |
|------|----|-----|--------|---------|
| `backend/app/core/security.py` | `get_current_user` dependency | `Cookie(default=None)` param | WIRED | Pattern `Cookie.*access_token` confirmed at line 116 |
| `web/src/app/layout.tsx` | `web/src/store/provider.tsx` | StoreProvider wrapping children | WIRED | `StoreProvider` imported and used at lines 4, 36 |
| `web/src/app/layout.tsx` | `web/src/components/providers/query-provider.tsx` | QueryProvider wrapping children | WIRED | `QueryProvider` imported and used at lines 5, 37 |
| `web/src/app/api/auth/login/route.ts` | FastAPI `/api/v1/auth/login` | server-side fetch | WIRED | Pattern `FASTAPI_URL.*auth/login` at line 19 |
| `web/src/lib/api-client.ts` | `web/src/app/api/auth/refresh/route.ts` | 401 retry | WIRED | `fetch("/api/auth/refresh", ...)` at line 37 |
| `web/src/app/api/proxy/route.ts` | FastAPI `/api/v1/*` | Bearer header injection | WIRED | `Authorization: \`Bearer ${accessToken}\`` at line 24 |
| `web/src/app/(auth)/login/page.tsx` | `web/src/app/api/auth/login/route.ts` | `fetch POST /api/auth/login` | WIRED | `fetch("/api/auth/login", ...)` at line 62 |
| `web/src/app/(dashboard)/layout.tsx` | `web/src/components/layout/sidebar.tsx` | import and render via DashboardShell | WIRED | `DashboardShell` imports `Sidebar` and renders it |
| `web/src/app/(dashboard)/page.tsx` | `web/src/lib/api-client.ts` | `apiGet` for KPI data | WIRED | `import { apiGet }` and 5 `apiGet(...)` calls |
| `web/src/components/layout/sidebar.tsx` | `web/src/store/slices/ui-slice.ts` | Redux `toggleSidebar` | WIRED | `import { toggleSidebar, setSidebarCollapsed }` and dispatch calls at lines 210, 201 |

### Requirements Coverage

| Requirement | Source Plan | Description | Status | Evidence |
|-------------|------------|-------------|--------|----------|
| AUTH-01 | 13-03, 13-04 | Admin can log in with email and password via the web dashboard | SATISFIED | Login page POSTs to `/api/auth/login` route handler; on success dispatches `setAuthUser` and `router.push("/")`; login route handler proxies to FastAPI and sets httpOnly cookies |
| AUTH-02 | 13-01, 13-03 | Web session persists across browser refresh using httpOnly cookie tokens | SATISFIED (code) | `proxy.ts` checks `access_token` cookie on every request; `refresh/route.ts` rotates cookies; backend `get_current_user` accepts cookie auth; HUMAN VERIFICATION required to confirm browser behavior |
| AUTH-03 | 13-01, 13-03 | Token refresh happens transparently without interrupting admin workflow | SATISFIED (code) | `api-client.ts` 401 retry: calls `/api/auth/refresh`, retries original request on success, redirects to `/login?reason=session_expired` on failure; backend dual-auth confirmed by 8 passing E2E tests |
| AUTH-04 | 13-03 | Admin can log out and session is fully invalidated | SATISFIED | `logout/route.ts` clears both cookies with `maxAge: 0`; calls FastAPI logout best-effort; sidebar/topbar both dispatch `clearAuth()` and `router.push("/login")` |
| AUTH-05 | 13-02, 13-04 | Global sidebar navigation provides persistent access to all modules | SATISFIED (code) | `sidebar.tsx` has 8 nav items with correct icons; `DashboardShell` renders `Sidebar` on all dashboard pages; collapse toggle + localStorage persistence; Sheet mobile overlay; HUMAN VERIFICATION required for visual/responsive behavior |
| AUTH-06 | 13-02, 13-04 | User-friendly error messages display for auth, validation, conflict, and server errors | SATISFIED (code) | Login page has inline red banner (AlertCircle) for auth errors + per-field zod validation errors; `api-client.ts` throws `ApiError` with `detail`; `Toaster` with `duration: Infinity` for error toasts; dashboard uses `toast.error(..., { duration: Infinity })`; HUMAN VERIFICATION required for visual confirmation |

All 6 AUTH requirements are satisfied by code evidence. 4 of them (AUTH-02, AUTH-03, AUTH-05, AUTH-06) require human verification for live browser behavior (cookies, visual layout, responsive design, toast persistence).

### Anti-Patterns Found

| File | Pattern | Severity | Impact |
|------|---------|----------|--------|
| `web/tests/auth.spec.ts` | All 7 tests use `test.skip()` | Info | Intentional — test stubs per CLAUDE.md. Plans 13-03/13-04 were supposed to fill these in but per SUMMARY they remain as stubs. Tests pass because they are skipped, not because behavior is verified. |
| `web/tests/layout.spec.ts` | All 9 tests use `test.skip()` | Info | Same as above — intentional stubs per CLAUDE.md requirement to ship tests alongside scaffold |

No blocker anti-patterns found. The `placeholder` hits in login/page.tsx are HTML `placeholder` attributes on Input fields (correct usage, not code stubs). The `return []` hits in dashboard/page.tsx are legitimate empty-state returns in helper functions.

**Note on Playwright E2E test stubs:** CLAUDE.md requires "Every new feature MUST include intensive end-to-end tests covering the full user flow before merging" and "A feature is NOT considered complete until its E2E tests pass." The Playwright stubs are all `test.skip()` — they list test descriptions only. Plans 13-03 and 13-04 explicitly deferred filling in these stubs ("Plans 13-03/13-04 will fill these in"). This is a policy tension: the scaffolded stubs satisfy the letter of the rule (files exist) but not the spirit (tests verify behavior). This is documented as a human verification concern below.

### Human Verification Required

#### 1. End-to-End Login Flow

**Test:** Start both FastAPI (`cd backend && uv run uvicorn app.main:app --reload`) and Next.js (`cd web && npm run dev`). Visit http://localhost:3000 — should redirect to /login. Submit empty form. Submit invalid credentials. Submit valid credentials.
**Expected:** Redirect to /login (unauthenticated); per-field errors on empty submit; red alert banner on bad credentials; redirect to "/" (dashboard home) on valid credentials.
**Why human:** httpOnly cookie behavior requires a live browser; visual layout and form validation UX need visual confirmation.

#### 2. Session Persistence After Refresh

**Test:** After logging in, press F5 or browser refresh. Check if you remain on the dashboard.
**Expected:** Session persists; proxy.ts detects the httpOnly `access_token` cookie and allows through.
**Why human:** httpOnly cookies cannot be inspected via JavaScript; persistence requires real browser.

#### 3. Sidebar Collapse and localStorage Persistence

**Test:** Click the collapse toggle (ChevronLeft) on the sidebar. Refresh the page.
**Expected:** Sidebar collapses to 64px icon-only mode immediately; after refresh, remains collapsed.
**Why human:** CSS transition animation and localStorage hydration on mount require visual/browser verification.

#### 4. Dashboard KPI Cards With Real Data

**Test:** With FastAPI running and test data seeded, log in and view the dashboard.
**Expected:** 4 KPI cards show real counts; Recent Activity feed shows real job records with StatusBadge colors.
**Why human:** Requires live backend; count values depend on data state; card rendering and badge colors need visual check.

#### 5. Error Toast Persistence

**Test:** With the backend stopped (or trigger a network error), perform an API-dependent action on the dashboard.
**Expected:** Error toast appears at bottom-right, does NOT auto-dismiss after 5+ seconds, remains until manually dismissed.
**Why human:** Time-based behavior; visual persistence requires a browser.

#### 6. Logout and Cookie Clearing

**Test:** Log in, then click avatar dropdown > Log out. Then navigate to http://localhost:3000.
**Expected:** After logout: cookies cleared, redirected to /login. Navigating to "/" again also redirects to /login (proxy.ts).
**Why human:** Cookie deletion requires browser DevTools verification; redirect chain requires live browsing.

#### 7. Custom 404 Page

**Test:** Visit http://localhost:3000/nonexistent-page (while authenticated or unauthenticated).
**Expected:** Custom 404 page renders with large indigo "404", "Page not found" subtext, and "Go to Dashboard" button.
**Why human:** Visual rendering needs browser confirmation.

#### 8. Mobile Responsive Sidebar

**Test:** Open the dashboard in a browser, resize to < 768px width. Check topbar and sidebar.
**Expected:** Desktop sidebar hidden; hamburger Menu button visible in topbar; clicking it opens a Sheet overlay with all 8 nav items.
**Why human:** CSS breakpoint behavior and Sheet animation require visual/browser verification.

#### 9. Playwright E2E Test Coverage (Policy Check)

**Test:** Review whether the `test.skip()` stubs in `web/tests/auth.spec.ts` and `web/tests/layout.spec.ts` should be filled in before the phase is considered complete per CLAUDE.md rules.
**Expected:** Per CLAUDE.md: "A phase is NOT done until all E2E tests pass." The stubs are skipped, not passing. A decision is needed on whether Phase 13 requires filled-in Playwright tests before proceeding to Phase 14.
**Why human:** Policy decision — the plans explicitly deferred test implementation to future plans, but CLAUDE.md says tests must ship with features. Team needs to decide: fill in tests now or accept the stubs as compliant.

### Gaps Summary

No automated gaps were found — all artifacts exist, are substantive (not stubs), and are properly wired. The 8 backend E2E tests pass. The TypeScript build (`npx tsc --noEmit`) exits with zero errors. The Next.js production build succeeds with all routes compiled.

The phase status is `human_needed` rather than `passed` because:
1. httpOnly cookie behavior (AUTH-02, AUTH-03, AUTH-04) can only be confirmed in a real browser
2. Visual rendering of login page, sidebar collapse, error toasts, 404 page, and responsive layout requires browser verification
3. The Playwright test stubs remain as `test.skip()` — a policy decision is needed on whether this satisfies CLAUDE.md's E2E test requirements

---

_Verified: 2026-03-16T07:26:33Z_
_Verifier: Claude (gsd-verifier)_
