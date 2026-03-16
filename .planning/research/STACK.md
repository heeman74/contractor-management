# Stack Research

**Domain:** Contractor management SaaS — Flutter mobile + Python backend + Next.js web admin dashboard
**Researched:** 2026-03-14
**Confidence:** HIGH (web additions verified via WebSearch against npm/official docs; Flutter/backend sections carried from prior research at 2026-03-04)

---

## Recommended Stack

### Core Technologies — Existing (DO NOT CHANGE)

These are already built, tested, and validated in v1.0. Do not replace or re-research.

| Technology | Version | Purpose | Status |
|------------|---------|---------|--------|
| Flutter | 3.32+ (SDK) | Android mobile app (contractors + clients) | Shipped v1.0 |
| FastAPI | 0.115+ | Python backend API (shared by mobile + web) | Shipped v1.0 |
| PostgreSQL | 13 | Primary database with RLS multi-tenancy | Shipped v1.0 |
| SQLAlchemy | 2.0 async | ORM + async DB access | Shipped v1.0 |
| JWT (python-jose) | 3.3+ | Access tokens (15 min) + refresh rotation (30 days) | Shipped v1.0 |

---

### Core Technologies — New (Web Admin Dashboard)

| Technology | Version | Purpose | Why Recommended |
|------------|---------|---------|-----------------|
| Next.js | 16.x | Web framework (App Router) | App Router + React Server Components enable server-side rendering for fast initial page loads. Version 16 is stable in 2026. Vercel's official framework for React, with built-in caching, route handlers (API proxying for auth), and middleware for JWT auth guards. Use over Create React App (abandoned) or Vite SPA (no SSR) because admin dashboards benefit from SSR for analytics pages. |
| React | 19.x | UI library | Required by Next.js 16. React 19 ships with improved Suspense batching, the `use()` hook for async data, and concurrent features that reduce perceived load time on complex admin views. |
| TypeScript | 5.x | Type safety | Required. Admin dashboards have complex data shapes (jobs, quotes, invoices). TypeScript catches mismatches between API response shapes and UI expectations at compile time, not runtime. |
| Redux Toolkit | 2.11.x | Client-side state management | RTK is the mandated choice per PROJECT.md. Use for server-actionable client state: currently selected company/tenant context, auth session (user, roles, token), active sidebar/filter state, and optimistic updates. RTK 2.x ships with Immer 11 (~30% faster mutations). Do NOT use for server data — that is TanStack Query's job. |
| React-Redux | 9.x | Redux ↔ React bindings | Required peer of Redux Toolkit. Version 9 ships alongside RTK 2.0/Redux 5.0. |
| TanStack Query | 5.90.x | Server state / data fetching | Handles all API data: caching, background refetch, stale-while-revalidate, pagination, and optimistic updates for mutations. Removes the need to manually manage loading/error states in Redux for server data. Works alongside Redux: TQ owns server state, Redux owns client state. |
| Tailwind CSS | v4.x | Utility-first CSS | v4 is the correct choice for new Next.js 16 projects. v4 uses CSS-first configuration (`@theme` directive), produces ~70% smaller production CSS than v3, and builds 5x faster. shadcn/ui officially supports Tailwind v4. |
| shadcn/ui | latest (copy-paste) | Component system | The dominant React admin UI library in 2026 (shipped 600+ components in Feb 2026). Zero runtime dependency — components are copied into your project as local TypeScript files. No version lock, no breaking upgrades. Provides DataTable, Sidebar, Card, Dialog, Form, Chart wrappers, Command palette, and all primitives needed for admin dashboards. Built on Radix UI (accessibility) + Tailwind CSS. Use over MUI (too opinionated, large bundle) or Ant Design (outdated aesthetics). |

---

### Supporting Libraries — Web Admin

#### Authentication

| Library | Version | Purpose | Why |
|---------|---------|---------|-----|
| (None — custom implementation) | — | JWT session management | Do NOT use Auth.js/NextAuth for this project. The existing FastAPI backend issues its own JWT access + refresh tokens with a specific rotation protocol. Auth.js adds a translation layer that fights your existing token format. Instead: implement a thin custom auth layer using Next.js Route Handlers as an API proxy, store tokens in httpOnly cookies (not localStorage — XSS protection), and use Next.js Middleware to guard routes by checking cookie presence. This is 50 lines of code, not a library. |
| jose | 5.x | JWT decode (client-side, no verify) | Decodes JWT claims in Next.js Middleware and Server Components to extract user roles/company_id without network round-trips. Do not use for verification — the FastAPI backend verifies tokens. |

#### Forms and Validation

| Library | Version | Purpose | Why |
|---------|---------|---------|-----|
| react-hook-form | 7.71.x | Form state management | Industry standard for React forms. Uncontrolled-component approach means zero re-renders on keypress. Handles all admin forms: job creation, quote line items, contractor profiles. shadcn/ui Form components are designed for react-hook-form. |
| zod | 3.x | Schema validation | Validates form inputs client-side and API payloads. Share schemas between client validation and (optionally) typed API response parsing. Use `zodResolver` from `@hookform/resolvers` to connect with react-hook-form. |
| @hookform/resolvers | 3.x | zod ↔ react-hook-form bridge | Connects zod schemas to react-hook-form's validation pipeline. |

#### Data Display

| Library | Version | Purpose | Why |
|---------|---------|---------|-----|
| @tanstack/react-table | 8.21.x | Headless data table engine | Powers sortable, filterable, paginated tables for jobs list, contractor list, invoice list. shadcn/ui's DataTable component is built on TanStack Table. Headless means full control over rendering — no style conflicts. Same library used by Linear and Notion. |

#### Charts and Reporting

| Library | Version | Purpose | Why |
|---------|---------|---------|-----|
| Recharts | 3.8.x | Charts for reporting dashboard | React-native SVG charting library. Version 3.x rewrote state management for better React 19 compatibility. shadcn/ui's Chart components (BarChart, LineChart, AreaChart, PieChart) are thin wrappers over Recharts — using Recharts directly through shadcn/ui gives accessibility, theming, and responsive wrappers for free. Covers all reporting needs: jobs by status (bar), revenue over time (line/area), contractor utilization (bar), job completion rate (pie). 3.6M weekly downloads — well maintained. |

#### Calendar and Scheduling

| Library | Version | Purpose | Why |
|---------|---------|---------|-----|
| react-big-calendar | 1.19.x | Scheduling calendar with drag-and-drop | Google Calendar / Outlook-style calendar component. Supports month, week, and day views. Built-in drag-and-drop addon (`react-big-calendar/lib/addons/dragAndDrop`) for rescheduling jobs by dragging between time slots — mirrors the Flutter drag-and-drop schedule from v1.0. MIT license, no premium tier required. Use `date-fns` as the localizer (not Moment.js). |
| date-fns | 3.x | Date formatting and arithmetic | Required as the localizer for react-big-calendar when avoiding Moment.js. Functional, tree-shakeable, TypeScript-first. Use for all date display formatting in the dashboard (job dates, schedule views, invoice due dates). Prefer over dayjs for this project because shadcn/ui's date picker components are built around date-fns. |

#### HTTP and API

| Library | Version | Purpose | Why |
|---------|---------|---------|-----|
| Native `fetch` | built-in | API calls from Server Components and Route Handlers | Next.js 16's App Router extends native fetch with caching, revalidation tags, and memoization. Axios opts out of this system on the server. Use native fetch in Server Components and Route Handlers. |
| TanStack Query client | 5.90.x | API calls from Client Components | In Client Components (DataTables, forms, real-time updates), use TanStack Query `useQuery`/`useMutation` with native fetch under the hood. This gives automatic caching, background refresh, and stale-while-revalidate. |

#### Utilities

| Library | Version | Purpose | Why |
|---------|---------|---------|-----|
| clsx | 2.x | Conditional class names | Required by shadcn/ui for merging Tailwind classes conditionally. Included in shadcn/ui setup by default. |
| tailwind-merge | 2.x | Tailwind class deduplication | Prevents conflicting Tailwind utilities when merging class strings. Required by shadcn/ui's `cn()` utility. |
| lucide-react | 0.4x+ | Icon library | shadcn/ui's default icon set. Consistent with the component library. MIT licensed. |

---

### Testing Stack — Web Admin

| Library | Version | Purpose | Why |
|---------|---------|---------|-----|
| Vitest | 2.x | Unit + component test runner | 10-20x faster than Jest on large codebases. Native ESM + TypeScript support without Babel. Jest-compatible API means minimal migration cost if team knows Jest. Next.js officially documents Vitest as a supported test runner. |
| @testing-library/react | 16.x | Component test utilities | User-centric assertions (`getByRole`, `getByText`) that mirror how real users interact with the UI. Works with Vitest via `@testing-library/jest-dom` matchers. |
| @testing-library/user-event | 14.x | Realistic user interaction simulation | Simulates real browser events (type, click, tab, keyboard navigation) more accurately than `fireEvent`. Required for testing form flows. |
| Playwright | 1.4x+ | E2E browser testing | Faster than Cypress in CI (290ms vs 420ms per action). Free built-in test sharding (no paid cloud). Supports Chromium, Firefox, and WebKit. TypeScript-first. Next.js has official Playwright integration docs. Use for: full auth flows, job creation wizard, drag-and-drop calendar, calendar conflict detection. |
| MSW (Mock Service Worker) | 2.x | API mocking in tests | Intercepts fetch calls at the network level — no Axios adapter needed. Works in both Vitest (Node environment) and Playwright. Use to mock FastAPI responses in component tests without spinning up the backend. |

---

### Development Tools — Web Admin

| Tool | Purpose | Notes |
|------|---------|-------|
| ESLint | Lint TypeScript + React | Use `eslint-config-next` (bundled with Next.js) — covers React hooks rules, import order, and Next.js-specific rules. |
| Prettier | Code formatting | Set up alongside ESLint. Use `prettier-plugin-tailwindcss` to auto-sort Tailwind class names. |
| TypeScript strict mode | Type checking | Enable `"strict": true` in tsconfig. Next.js 16 defaults to strict mode. Catches API response shape mismatches early. |

---

## Installation

### Next.js App Bootstrap

```bash
# Scaffold with App Router + TypeScript + Tailwind v4
npx create-next-app@latest web --typescript --tailwind --app --turbopack

cd web

# Core state management
npm install @reduxjs/toolkit react-redux @tanstack/react-query

# Auth utilities
npm install jose

# Forms and validation
npm install react-hook-form zod @hookform/resolvers

# Data tables
npm install @tanstack/react-table

# Charts
npm install recharts

# Calendar and dates
npm install react-big-calendar date-fns

# shadcn/ui CLI (installs components on demand)
npx shadcn@latest init

# Icons (pulled in by shadcn init, but explicit)
npm install lucide-react

# Utilities
npm install clsx tailwind-merge

# Dev dependencies
npm install -D vitest @vitejs/plugin-react jsdom
npm install -D @testing-library/react @testing-library/user-event @testing-library/jest-dom
npm install -D msw
npm install -D @playwright/test
npm install -D prettier prettier-plugin-tailwindcss eslint-config-prettier
```

### shadcn/ui Core Components for Admin Dashboard

```bash
# Run after `npx shadcn@latest init`
npx shadcn@latest add button input label card table dialog form
npx shadcn@latest add sidebar navigation-menu dropdown-menu
npx shadcn@latest add data-table chart badge select textarea
npx shadcn@latest add toast sonner calendar date-picker
npx shadcn@latest add command sheet popover
```

---

## Alternatives Considered

| Recommended | Alternative | When to Use Alternative |
|-------------|-------------|-------------------------|
| Next.js 16 (App Router) | Next.js 16 (Pages Router) | Never on a new project. App Router enables Server Components, async/await in components, and Next.js Middleware for route guards. Pages Router is for projects already on it. |
| shadcn/ui | Material UI (MUI) | If the organization has existing MUI design system tokens and wants consistency across multiple apps. MUI is a heavy dependency (~300KB) vs shadcn's zero runtime cost. |
| shadcn/ui | Ant Design | If building a data-heavy internal tool for Chinese enterprise — Ant Design has strong support for that ecosystem. Otherwise shadcn has better React 19/Tailwind v4 support. |
| Recharts (via shadcn) | Chart.js (react-chartjs-2) | Chart.js uses Canvas, which can handle 1M+ data points smoothly. If the reporting dashboard needs to render thousands of data points simultaneously, switch to react-chartjs-2. For ContractorHub's scale (< 10K jobs per company), Recharts SVG is fine. |
| Recharts (via shadcn) | Nivo | Nivo has richer chart types (heatmaps, network graphs, treemaps). Use Nivo if advanced visualization types are required beyond bar/line/area/pie. |
| react-big-calendar | FullCalendar | FullCalendar has more built-in features (timeline view, resource scheduling) but drag-and-drop and resource views require the premium Scheduler package ($200+/year/developer). react-big-calendar covers ContractorHub's needs (week/day drag-and-drop) under MIT for free. |
| TanStack Query | SWR | SWR is simpler but less capable. TanStack Query's mutation API, cache invalidation strategies, and devtools are superior for a complex admin dashboard with many interdependent data entities. |
| Playwright | Cypress | Cypress is better for DX (visual time-travel debugger) but requires paid Cypress Cloud for parallelization. Playwright's free sharding and WebKit support make it the better choice for a full-stack project with limited CI budget. |
| Vitest | Jest | Jest is the legacy choice. Vitest is 10-20x faster and has first-class ESM/TypeScript support. No reason to use Jest for a new Next.js 16 project. |
| Native fetch + TanStack Query | Axios | Axios opts out of Next.js App Router's extended fetch caching system on the server side. Native fetch gets automatic request memoization, revalidation tags, and CDN caching. Use native fetch everywhere; TanStack Query wraps it client-side. |
| Custom JWT auth (httpOnly cookies) | Auth.js / NextAuth | Auth.js is the right choice when you use social OAuth providers (Google, GitHub). For this project, the FastAPI backend is the only auth authority and uses its own JWT format with refresh token rotation. Auth.js would add complexity without benefit. |

---

## What NOT to Use

| Avoid | Why | Use Instead |
|-------|-----|-------------|
| localStorage for JWT storage | JavaScript-accessible storage is vulnerable to XSS attacks. OWASP explicitly recommends against it for session tokens. | httpOnly cookies set by Next.js Route Handler acting as auth proxy |
| Redux for server/API data | Redux reducers for API data require manual loading/error/success state management. RTK Query is an option but TanStack Query has better cache invalidation, devtools, and community support for dashboards. | TanStack Query for server state; Redux for client-only state |
| Moment.js | Effectively unmaintained, ships non-tree-shakeable 300KB bundle. react-big-calendar accepts date-fns as localizer. | date-fns |
| react-chartjs-2 (by default) | Canvas rendering cannot scale to complex SVG-based interactions. For ContractorHub's scale, Recharts is cleaner and integrates with shadcn's Chart primitives. Switch only if rendering 100K+ data points. | Recharts via shadcn/ui Chart |
| Next.js Pages Router (for new features) | Pages Router does not support React Server Components, Server Actions, or Next.js Middleware-based route guards at the granularity needed. | App Router exclusively |
| Client-side JWT verification | JWTs should only be verified by the FastAPI backend. Client-side verification using the secret key requires exposing the secret to the browser. | Decode JWT claims locally with `jose` (no verification); let FastAPI validate on every request. |
| Tailwind CSS v3 | v3 requires a config file and produces larger CSS bundles. v4 is the correct choice for new Next.js 16 projects — official shadcn/ui docs have a dedicated v4 migration guide. | Tailwind CSS v4 |

---

## Integration Points with Existing FastAPI Backend

This section documents exactly how the web admin connects to the existing backend — critical for avoiding duplication.

### Auth Flow (Web)

1. `POST /auth/login` → FastAPI returns `{ access_token, refresh_token }` (existing endpoint, no changes needed)
2. Next.js Route Handler (`/api/auth/login`) receives credentials from the browser, calls FastAPI, then sets httpOnly cookies: `access_token` and `refresh_token`
3. Subsequent requests from Client Components go through Next.js Route Handlers (acting as API proxy) or directly to FastAPI with the access token forwarded from the cookie
4. Token refresh: Next.js Middleware or Route Handler calls `POST /auth/refresh` (existing endpoint) when access token is expired
5. Logout: Route Handler clears cookies and calls `POST /auth/logout` (existing endpoint)

No FastAPI auth changes required. The web dashboard is a new consumer of the existing auth API.

### CORS Configuration (Backend Change Required)

The existing FastAPI CORS config likely allows only the Flutter dev origin. Add the Next.js dev/prod origins:

```python
# backend/app/main.py — add web origins
ALLOWED_ORIGINS = [
    "http://localhost:3000",        # Next.js dev
    "https://admin.contractorhub.com",  # Next.js prod
    # existing mobile origins...
]
```

### company_id / Tenant Context

The existing JWT carries `company_id`. The web admin reads this from the decoded JWT (via `jose`) to:
- Display the correct company name in the nav
- Include in API requests (FastAPI extracts it from the JWT server-side via RLS — the web client does not need to manually inject it)

### API Response Schemas

The existing FastAPI Pydantic schemas are the source of truth. Define TypeScript types in `web/src/types/` that mirror them. Do not redefine business logic — the FastAPI backend owns all validation and conflict detection.

```typescript
// web/src/types/job.ts — mirrors FastAPI JobResponse schema
export interface Job {
  id: string;
  company_id: string;
  title: string;
  status: 'quote' | 'scheduled' | 'in_progress' | 'complete' | 'invoiced';
  scheduled_start: string;   // ISO 8601
  scheduled_end: string;
  contractor_id: string | null;
  client_id: string;
}
```

---

## Stack Patterns by Variant

**For server-rendered analytics/reporting pages:**
- Fetch data in Next.js Server Components (no TanStack Query needed)
- Use native fetch with `{ next: { revalidate: 60 } }` for 1-minute cache
- Render Recharts charts as Client Components (charts require browser APIs)

**For interactive scheduling calendar:**
- Calendar itself is a Client Component (drag-and-drop requires browser events)
- Seed initial calendar data via Server Component → pass as props
- Use TanStack Query `useMutation` to update job times after drag; invalidate calendar query on success

**For data tables (jobs list, contractor list, invoices):**
- Use TanStack Table with server-side pagination (pass `page` and `limit` to FastAPI)
- Use TanStack Query with `keepPreviousData: true` to avoid loading flicker on page change
- Column definitions typed against the TypeScript API types

**For multi-step job creation wizard:**
- Use `react-hook-form` with `useFormContext` to share state across steps
- Each step validates only its own fields before advancing
- Final submission via TanStack Query `useMutation` to `POST /jobs`

---

## Version Compatibility

| Package A | Compatible With | Notes |
|-----------|-----------------|-------|
| Next.js 16 | React 19, TypeScript 5, Tailwind v4 | App Router requires React 19 for full feature set |
| shadcn/ui | Tailwind v4, Radix UI primitives, react-hook-form 7.x | shadcn has dedicated Tailwind v4 docs — follow them exactly |
| Redux Toolkit 2.11 | React-Redux 9.x, Redux 5.x, Reselect 5.x | These must all be at major versions that shipped together (all November 2023+) |
| TanStack Query 5.x | React 18+ (uses useSyncExternalStore) | v5 requires React 18 minimum — React 19 fully supported |
| react-big-calendar 1.19 | date-fns 3.x | Use `dateFnsLocalizer` from `react-big-calendar/lib/localizers/date-fns`. Do NOT use the Moment.js localizer. |
| Recharts 3.x | React 18+, React 19 | Recharts 3.0 rewrote state management for React 19 compatibility |
| Playwright 1.4x | Node 18+ | Install via `npm init playwright@latest` for proper browser binary setup |
| Vitest 2.x | Vite 5+, Next.js 16 | Requires vite config alongside next.config — see Next.js Vitest docs |

---

## Sources

- [Next.js 15/16 features 2026](https://jishulabs.com/blog/nextjs-15-16-features-migration-guide-2026) — Next.js 16 stable confirmed (MEDIUM confidence)
- [Redux Toolkit npm](https://www.npmjs.com/package/@reduxjs/toolkit) — version 2.11.2 verified (HIGH confidence)
- [shadcn/ui 2026 admin dashboard guide](https://adminlte.io/blog/build-admin-dashboard-shadcn-nextjs/) — shadcn/ui as standard choice confirmed (MEDIUM confidence)
- [Tailwind CSS v4 announcement](https://tailwindcss.com/blog/tailwindcss-v4) — v4 performance improvements verified (HIGH confidence)
- [Recharts npm](https://www.jsdocs.io/package/recharts) — version 3.8.0 verified (HIGH confidence)
- [react-big-calendar npm](https://www.npmjs.com/package/react-big-calendar) — version 1.19.4 verified (HIGH confidence)
- [TanStack Query npm](https://www.npmjs.com/package/@tanstack/react-query) — version 5.90.21 verified (HIGH confidence)
- [TanStack Table npm](https://www.npmjs.com/package/@tanstack/react-table) — version 8.21.3 verified (HIGH confidence)
- [react-hook-form npm](https://www.npmjs.com/package/react-hook-form) — version 7.71.2 verified (HIGH confidence)
- [Playwright vs Cypress 2026](https://www.getautonoma.com/blog/playwright-vs-cypress) — Playwright recommended for enterprise (MEDIUM confidence)
- [Vitest Next.js guide](https://nextjs.org/docs/app/guides/testing/vitest) — Official Next.js Vitest docs (HIGH confidence)
- [Next.js FastAPI JWT auth](https://medium.com/@sl_mar/building-a-secure-jwt-authentication-system-with-fastapi-and-next-js-301e749baec2) — httpOnly cookie pattern (MEDIUM confidence)
- [Auth.js FastAPI integration](https://authjs.dev/guides/integrating-third-party-backends) — Auth.js third-party backend guide (HIGH confidence — used to confirm NOT using Auth.js)
- [date-fns vs dayjs comparison](https://github.com/shadcn-ui/ui/discussions/4817) — shadcn recommends date-fns (HIGH confidence)
- [shadcn/ui Tailwind v4 docs](https://ui.shadcn.com/docs/tailwind-v4) — official Tailwind v4 compatibility (HIGH confidence)

---

*Stack research for: ContractorHub — Web Admin Dashboard (Next.js 16 + React 19 + Redux Toolkit + FastAPI backend)*
*Researched: 2026-03-14*
