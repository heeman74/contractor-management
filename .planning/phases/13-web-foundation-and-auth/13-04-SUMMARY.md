---
phase: 13-web-foundation-and-auth
plan: "04"
subsystem: ui-shell
tags: [nextjs, typescript, react, shadcn, tailwind, redux, tanstack-query, lucide-react]

# Dependency graph
requires:
  - phase: 13-03
    provides: "apiClient, getServerUser, auth Route Handlers, proxy.ts edge guard"
  - phase: 13-02
    provides: "Next.js 16 scaffold, shadcn/ui components, Redux store"
provides:
  - Login page (split-screen with react-hook-form + zod) at /login
  - Dashboard shell (fixed sidebar + topbar) wrapping all dashboard pages
  - Sidebar with 8 module nav items, collapse, localStorage persistence, Sheet mobile overlay
  - Topbar with breadcrumbs and user dropdown (logout)
  - Dashboard home with 4 KPI cards (real API data) + Recent Activity feed (real job data)
  - KpiCard reusable component
  - StatusBadge reusable component for use in phases 14-18
  - Custom 404 page (not-found.tsx)
  - Custom 500 error boundary (error.tsx)
  - Typed Redux hooks (useAppDispatch, useAppSelector)
affects:
  - phases 14-18 (sidebar, topbar, StatusBadge are shared layout for all dashboard pages)

# Tech tracking
tech-stack:
  added: []  # All packages already in package.json
  patterns:
    - react-hook-form + zod for login form validation
    - TanStack Query useQuery for KPI data fetching with loading/error states
    - "Redux for client UI state: sidebarCollapsed read/written in Sidebar component"
    - localStorage hydration for sidebar collapse state on client mount
    - Sheet (shadcn/ui) for mobile sidebar overlay
    - Breadcrumbs derived from pathname segments (no dynamic titles until later phases)
    - "Error toasts: toast.error() with { duration: Infinity } per project decision"

key-files:
  created:
    - web/src/app/(auth)/login/page.tsx
    - web/src/app/(dashboard)/layout.tsx
    - web/src/app/(dashboard)/page.tsx
    - web/src/components/layout/sidebar.tsx
    - web/src/components/layout/topbar.tsx
    - web/src/components/layout/dashboard-shell.tsx
    - web/src/components/shared/status-badge.tsx
    - web/src/components/shared/kpi-card.tsx
    - web/src/app/not-found.tsx
    - web/src/app/error.tsx
    - web/src/store/hooks.ts
  modified:
    - web/src/app/page.tsx (deleted — replaced by (dashboard)/page.tsx)

key-decisions:
  - "Login always redirects to / (dashboard home) — no redirectTo parameter honored per prior decision"
  - "Error toasts persist until manually dismissed: toast.error(msg, { duration: Infinity })"
  - "BreadcrumbLink uses render prop pattern (base-ui) instead of asChild — Button.asChild not supported"
  - "Removed root app/page.tsx to avoid route conflict with (dashboard)/page.tsx at /"
  - "Sidebar SidebarNav shared between desktop Sidebar and mobile Sheet for DRY layout"

requirements-completed: [AUTH-01, AUTH-05, AUTH-06]

# Metrics
duration: 5min
completed: 2026-03-16
---

# Phase 13 Plan 04: Login Page, Dashboard Shell, and UI Components Summary

**Split-screen login page, collapsible dark sidebar with 8 module nav items, breadcrumb topbar with user dropdown, dashboard home with 4 real-API KPI cards and recent activity feed, reusable StatusBadge, 404/500 error pages**

## Performance

- **Duration:** ~5 min
- **Started:** 2026-03-16T07:16:34Z
- **Completed:** 2026-03-16
- **Tasks:** 2 of 3 (Task 3 is human-verify checkpoint)
- **Files modified:** 11

## Accomplishments

- Login page: split-screen layout (indigo gradient left, form right), react-hook-form + zod validation, show/hide password, inline error banner with AlertCircle icon, session_expired notice on mount, always redirects to "/" (no redirectTo), dispatches setAuthUser to Redux on success
- Dashboard shell: DashboardShell (client component) uses Redux sidebarCollapsed to apply ml-60/ml-16 offset with 300ms CSS transition
- Sidebar: 8 nav items with Lucide icons, active item highlighted with indigo-600, collapse toggle writes to localStorage, hydrated on mount from localStorage; Sheet-based mobile overlay at <768px
- Topbar: Breadcrumb trail from pathname segments, company name display, DropdownMenu for logout, MobileSidebar hamburger on mobile
- Dashboard home: TanStack Query useQuery for 4 KPI endpoints + recent jobs; Skeleton loading states; empty state for no jobs; client-side sort + slice to 10 most recent
- StatusBadge: semantic color map covering green/yellow/red/blue/gray states — ready for phases 14-18
- KpiCard: Link-wrapped Card with loading skeleton
- 404/500 error pages with Go to Dashboard navigation

## Task Commits

1. **Task 1: Login page, error pages, Redux hooks** — `ffcd5ce`
2. **Task 2: Dashboard shell, sidebar, topbar, KPI cards, status badge** — `d8f5fc4`

## Files Created/Modified

- `web/src/app/(auth)/login/page.tsx` — Split-screen login; react-hook-form + zod; inline error banner; always redirects to /
- `web/src/app/(dashboard)/layout.tsx` — Wraps children in DashboardShell
- `web/src/app/(dashboard)/page.tsx` — 4 KPI cards + Recent Activity feed with real job data
- `web/src/components/layout/sidebar.tsx` — Fixed dark sidebar (240px/64px), 8 nav items, collapse, localStorage, Sheet mobile
- `web/src/components/layout/topbar.tsx` — Sticky header with breadcrumbs, user avatar dropdown, hamburger
- `web/src/components/layout/dashboard-shell.tsx` — Layout wrapper that offsets main content based on sidebarCollapsed
- `web/src/components/shared/status-badge.tsx` — Semantic color badge (green/yellow/red/blue/gray) by status string
- `web/src/components/shared/kpi-card.tsx` — Clickable card with icon, value, Skeleton loading
- `web/src/app/not-found.tsx` — 404 page with Go to Dashboard link
- `web/src/app/error.tsx` — "use client" error boundary with Try Again + Go to Dashboard
- `web/src/store/hooks.ts` — Typed useAppDispatch / useAppSelector / useAppStore

## Decisions Made

- Login page always redirects to "/" on success — no `?redirectTo` query parameter honored (per prior project decision)
- `Button.asChild` not supported by `@base-ui/react/button` — used plain `<Link>` with Tailwind classes for Go-to-Dashboard buttons
- Root `app/page.tsx` removed to eliminate route conflict with `(dashboard)/page.tsx` at "/"
- SidebarNav extracted as internal component shared by both desktop Sidebar and mobile Sheet for DRY reuse
- Breadcrumbs: simple pathname-segment approach for Phase 13; dynamic entity titles will be added in later phases

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 1 - Bug] Button `asChild` prop not supported by @base-ui**
- **Found during:** Task 1
- **Issue:** `@base-ui/react/button` does not support the `asChild` prop pattern used in shadcn/ui
- **Fix:** Used plain `<Link>` elements with Tailwind classes for navigation buttons in 404/500 pages
- **Files modified:** `web/src/app/not-found.tsx`, `web/src/app/error.tsx`
- **Impact:** Visual result identical; no behavior change

**2. [Rule 3 - Blocking] Root page.tsx conflicted with (dashboard)/page.tsx**
- **Found during:** Task 2
- **Issue:** Both `src/app/page.tsx` and `src/app/(dashboard)/page.tsx` resolve to route "/"
- **Fix:** Deleted root `src/app/page.tsx` (it was the Next.js scaffold placeholder page)
- **Files modified:** `web/src/app/page.tsx` (deleted)
- **Impact:** "/" now correctly renders the dashboard home via the route group

**3. [Rule 3 - Blocking] Missing typed Redux hooks file**
- **Found during:** Task 1
- **Issue:** Login page imported `useAppDispatch` from `@/store/hooks` but the file did not exist
- **Fix:** Created `web/src/store/hooks.ts` with typed `useAppDispatch`, `useAppSelector`, `useAppStore`
- **Files modified:** `web/src/store/hooks.ts` (created)
- **Impact:** Required for all client components using Redux

## Awaiting Human Verification (Task 3 Checkpoint)

Task 3 is a `checkpoint:human-verify`. The following needs human visual verification:
1. Visit http://localhost:3000 — should redirect to /login
2. Login with valid admin credentials — should land on dashboard home
3. Verify 4 KPI cards, sidebar nav items, collapse toggle, breadcrumbs
4. Logout flow + 404 page

---
*Phase: 13-web-foundation-and-auth*
*Completed: 2026-03-16*

## Self-Check: PASSED

- FOUND: web/src/app/(auth)/login/page.tsx
- FOUND: web/src/app/(dashboard)/layout.tsx
- FOUND: web/src/app/(dashboard)/page.tsx
- FOUND: web/src/components/layout/sidebar.tsx
- FOUND: web/src/components/layout/topbar.tsx
- FOUND: web/src/components/layout/dashboard-shell.tsx
- FOUND: web/src/components/shared/status-badge.tsx
- FOUND: web/src/components/shared/kpi-card.tsx
- FOUND: web/src/app/not-found.tsx
- FOUND: web/src/app/error.tsx
- FOUND: web/src/store/hooks.ts
- FOUND commit ffcd5ce (Task 1: login page, error pages, Redux hooks)
- FOUND commit d8f5fc4 (Task 2: dashboard shell, sidebar, topbar, KPI cards, status badge)
