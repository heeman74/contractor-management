---
phase: 13-web-foundation-and-auth
plan: "02"
subsystem: ui
tags: [nextjs, react, typescript, tailwind, redux, tanstack-query, shadcn, playwright]

# Dependency graph
requires: []
provides:
  - Next.js 16.1.6 project at web/ with TypeScript strict, App Router, Tailwind v4
  - Redux makeStore factory (SSR-safe, per-request store) with ui-slice and auth-slice
  - TanStack Query provider wrapping the app
  - shadcn/ui components: sonner, skeleton, button, input, label, card, avatar, dropdown-menu, breadcrumb, separator, sheet, badge
  - TypeScript API types matching backend schemas (LoginRequest, TokenResponse, AuthUser, ApiErrorResponse)
  - Playwright 1.58.2 configured with Chromium and test stubs for Plans 13-03 and 13-04
affects:
  - 13-03-auth-routes (implements login/logout route handlers)
  - 13-04-ui-shell (implements sidebar/topbar using the store providers)

# Tech tracking
tech-stack:
  added:
    - next@16.1.6
    - react@19.2.3
    - typescript@5.x (strict)
    - tailwindcss@4.x
    - "@reduxjs/toolkit@2.x"
    - react-redux@9.x
    - "@tanstack/react-query@5.x"
    - "@tanstack/react-query-devtools@5.x"
    - shadcn/ui (button, sonner, skeleton, input, label, card, avatar, dropdown-menu, breadcrumb, separator, sheet, badge)
    - react-hook-form@7.x
    - "@hookform/resolvers"
    - zod@4.x
    - nextjs-toploader@3.x
    - clsx, tailwind-merge, lucide-react
    - jose@6.x
    - "@playwright/test@1.58.2"
  patterns:
    - Redux makeStore factory (NEVER module-level singleton) for SSR-safe per-request store isolation
    - StoreProvider with useRef pattern for client-side store creation
    - TanStack Query owns server/API state; Redux owns client UI state only
    - Error toasts persist with duration Infinity; success toasts auto-dismiss after 5s
    - All test.skip() Playwright stubs to satisfy CLAUDE.md test-ship requirement without false failures

key-files:
  created:
    - web/src/store/index.ts
    - web/src/store/provider.tsx
    - web/src/store/slices/ui-slice.ts
    - web/src/store/slices/auth-slice.ts
    - web/src/components/providers/query-provider.tsx
    - web/src/types/api.ts
    - web/playwright.config.ts
    - web/tests/auth.spec.ts
    - web/tests/layout.spec.ts
  modified:
    - web/src/app/layout.tsx
    - web/package.json

key-decisions:
  - "Redux makeStore factory pattern (never module-level singleton) prevents cross-request tenant data leakage in SSR"
  - "Error toasts must call toast.error(..., { duration: Infinity }) at each call site — belt-and-suspenders via Toaster toastOptions"
  - "All Playwright stubs use test.skip() — Plans 13-03/13-04 remove .skip and implement test bodies"
  - "web/.git removed to avoid submodule — web/ tracked as plain directory in project repo"

patterns-established:
  - "Pattern: StoreProvider wraps children in root layout before QueryProvider"
  - "Pattern: QueryProvider uses useState factory to create one QueryClient per component tree"
  - "Pattern: auth-slice holds display metadata only (displayName, companyName, roles) — never tokens"
  - "Pattern: ui-slice persists sidebarCollapsed to localStorage via initSidebar/toggleSidebar actions"

requirements-completed: [AUTH-05]

# Metrics
duration: 9min
completed: 2026-03-16
---

# Phase 13 Plan 02: Web Foundation Scaffold Summary

**Next.js 16.1.6 project scaffolded with Redux makeStore factory, TanStack Query, shadcn/ui, TypeScript API types, and Playwright E2E stubs for auth and layout tests**

## Performance

- **Duration:** 9 min
- **Started:** 2026-03-16T06:58:18Z
- **Completed:** 2026-03-16T07:07:28Z
- **Tasks:** 3
- **Files modified:** 41

## Accomplishments

- Next.js 16.1.6 project at `web/` with TypeScript strict mode, App Router, Tailwind v4 (`@import "tailwindcss"` syntax), and zero build errors
- Redux Toolkit store with SSR-safe `makeStore` factory, `StoreProvider` with `useRef` pattern, `ui-slice` (sidebar state + localStorage persistence), `auth-slice` (display metadata only, tokens never in Redux)
- TanStack Query provider + shadcn/ui Toaster (bottom-right, error toasts persist until dismissed) + NProgress toploader wired in root layout
- TypeScript API types matching backend schemas: `LoginRequest`, `TokenResponse`, `AuthUser`, `ApiErrorResponse`, `Job`
- Playwright 1.58.2 with Chromium installed, `playwright.config.ts` with `webServer` config, 16 skipped test stubs in `auth.spec.ts` (AUTH-01 to AUTH-06) and `layout.spec.ts` (AUTH-05 sidebar/topbar/responsive)

## Task Commits

Each task was committed atomically:

1. **Task 1+2: Scaffold + Providers/Store/Types** - `81f9092` (chore)
2. **Task 3: Playwright + E2E stubs** - `dbe49a1` (chore)

## Files Created/Modified

- `web/src/store/index.ts` - makeStore factory, AppStore/RootState/AppDispatch types
- `web/src/store/provider.tsx` - StoreProvider client component with useRef
- `web/src/store/slices/ui-slice.ts` - sidebarCollapsed state + localStorage persistence
- `web/src/store/slices/auth-slice.ts` - auth display metadata (NOT tokens)
- `web/src/components/providers/query-provider.tsx` - TanStack Query client provider
- `web/src/types/api.ts` - TypeScript types matching backend schemas
- `web/src/app/layout.tsx` - Root layout with StoreProvider, QueryProvider, Toaster, NextTopLoader
- `web/playwright.config.ts` - Playwright config with baseURL localhost:3000 and webServer
- `web/tests/auth.spec.ts` - Skipped stubs for AUTH-01 through AUTH-06
- `web/tests/layout.spec.ts` - Skipped stubs for AUTH-05 sidebar, topbar, responsive
- `web/package.json` - Added test-e2e and test-e2e:chromium scripts
- All `web/src/components/ui/` shadcn components (avatar, badge, breadcrumb, button, card, dropdown-menu, input, label, separator, sheet, skeleton, sonner)

## Decisions Made

- Used `makeStore` factory (never module-level `configureStore()`) as required by Redux Toolkit's official Next.js App Router docs — prevents cross-request tenant data leakage in SSR
- Error toasts configured for `duration: Infinity` — convention established: all `toast.error()` calls throughout the app MUST include `{ duration: Infinity }`; success toasts use default 5-second auto-dismiss
- Removed `web/.git` to avoid embedded git submodule — `web/` is tracked as a plain subdirectory in the project repository
- Test stubs use `test.skip()` to satisfy CLAUDE.md requirement that test files ship with features while avoiding false failures during scaffold phase

## Deviations from Plan

**1. [Rule 3 - Blocking] Removed embedded .git from web/ before committing**

- **Found during:** Task 1 (initial commit)
- **Issue:** `npx create-next-app` initializes a git repository inside `web/`, creating an embedded submodule that prevents proper file tracking
- **Fix:** Ran `git rm --cached web`, deleted `web/.git`, reset the bad commit, then re-added all files as plain directory
- **Files modified:** None (git housekeeping)
- **Verification:** `git add web/` tracked all 37 source files without node_modules; committed cleanly
- **Committed in:** 81f9092 (part of Task 1 commit)

---

**Total deviations:** 1 auto-fixed (Rule 3 - blocking)
**Impact on plan:** Blocking git issue resolved. No scope creep. All planned files delivered.

## Issues Encountered

- `create-next-app` creates its own `.git` directory — handled by removing it before first commit (see Deviations)
- Engine compatibility warning from `eslint-visitor-keys@5.0.1` requiring Node 20.19+ (current: 20.18.1) — this is a non-breaking warning, package still works correctly; can upgrade Node when convenient

## User Setup Required

None - no external service configuration required. `npm run dev` starts without environment variables for the scaffold.

## Next Phase Readiness

- web/ project is fully configured and `npm run build` succeeds
- Providers (Redux, TanStack Query, Toaster) wired in root layout — Plans 13-03/13-04 can use them immediately
- TypeScript types in `src/types/api.ts` ready for use in auth route handlers and API client
- Playwright configured — Plans 13-03/13-04 remove `test.skip()` and implement E2E test bodies
- No blockers for Plan 13-03 (auth Route Handlers and apiClient)

---
*Phase: 13-web-foundation-and-auth*
*Completed: 2026-03-16*
