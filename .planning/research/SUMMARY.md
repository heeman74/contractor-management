# Project Research Summary

**Project:** ContractorHub v2.0 — Next.js Web Admin Dashboard
**Domain:** Field Service Management (FSM) — web admin layer added to existing Flutter mobile + FastAPI backend
**Researched:** 2026-03-15
**Confidence:** HIGH

## Executive Summary

ContractorHub v2.0 adds a Next.js 16 web admin dashboard on top of a fully-shipped v1.0 Flutter mobile app and FastAPI + PostgreSQL backend. This is a new frontend, not a new product — every business feature (jobs, scheduling, quotes, invoices, reports, users) already has a working API endpoint. The recommended approach is to treat the backend as a stable contract and build a thin, well-structured Next.js shell around it: App Router with React Server Components for initial page rendering, TanStack Query for client-side data caching, Redux Toolkit for UI state only, and shadcn/ui for the component layer. Competitor analysis (Jobber, ServiceTitan, Housecall Pro) confirms the drag-and-drop scheduling calendar with contractor lanes is the product's core differentiator and must be prioritized accordingly.

The most significant risk is not feature complexity — it is the auth integration boundary between the new web layer and the existing mobile backend. Three concerns must be resolved before any feature page is built: JWT token storage in httpOnly cookies (never localStorage), a unified `get_current_user` FastAPI dependency that handles cookie-based web auth and Bearer-header mobile auth simultaneously, and a DB migration to scope refresh token family revocation per client type (web vs. mobile) so that web login does not revoke active mobile sessions. These are Phase 1 decisions that cannot be retrofitted later without rebuilding the auth layer.

The second major risk is the API contract with the existing Flutter mobile app. Any Pydantic response schema change that removes or renames a field will silently break mobile deserialization. The rule is additive-only changes: new fields must be `Optional` with defaults, and an OpenAPI spec diff must run in CI on every backend PR. With these two risks managed, the remaining phases follow well-documented React/Next.js patterns with high confidence.

---

## Key Findings

### Recommended Stack

The web layer is built with Next.js 16 (App Router, React Server Components), React 19, TypeScript 5, Tailwind CSS v4, and shadcn/ui. For state management, the split is explicit: TanStack Query v5 owns all server/API state (caching, background refetch, optimistic updates), and Redux Toolkit 2.x owns client-only UI state (sidebar, filters, active modals, auth display metadata). This separation is the single most important architectural decision — mixing API data into Redux creates hundreds of lines of boilerplate and fragile manual cache management. The existing FastAPI + PostgreSQL backend requires only minimal changes: a CORS env-var update, a `get_current_user` extension for cookie auth, and a `client_type` DB migration on the refresh tokens table.

**Core technologies:**
- **Next.js 16 (App Router):** Web framework — SSR for fast initial page loads on data-heavy admin views; Middleware for UX route guards; Route Handlers as auth proxy
- **React 19 + TypeScript 5:** UI layer — improved Suspense batching; TypeScript catches API shape mismatches at compile time
- **Redux Toolkit 2.11 + React-Redux 9:** Client UI state only — sidebar, filters, auth display metadata; never for server data
- **TanStack Query 5.90:** Server state — jobs, quotes, contractors, reports with caching and optimistic updates
- **Tailwind CSS v4 + shadcn/ui:** Component system — zero runtime cost; DataTable, Sidebar, Chart wrappers, all admin primitives built-in
- **react-big-calendar 1.19 + date-fns 3:** Scheduling calendar — drag-and-drop week/day views matching Flutter v1.0 behavior; MIT license (no paid tier)
- **Recharts 3.8 (via shadcn/ui Chart):** Reporting charts — SVG-based, React 19 compatible, covers all 4 backend metrics
- **react-hook-form 7.71 + zod 3:** Form state and validation — zero re-renders on keypress; `zodResolver` connects both
- **Playwright 1.4x + Vitest 2.x + MSW 2.x:** Testing stack — E2E browser tests; unit/component tests; network-level API mocking
- **jose 5.x:** JWT decode (no verify) — extracts claims for display; verification stays on FastAPI

**What NOT to use:** localStorage for tokens (XSS exposure), Auth.js/NextAuth (fights existing FastAPI token format), Redux for API data, Axios (opts out of Next.js fetch caching), Tailwind v3, Pages Router, module-level Redux store singleton.

See `.planning/research/STACK.md` for full version compatibility matrix and installation commands.

### Expected Features

The v1.0 backend already exposes all required API endpoints. The web dashboard maps directly onto them — no new backend business-logic endpoints are needed for v2.0 beyond the auth changes described above.

**Must have (table stakes for v2.0 launch):**
- JWT login + httpOnly cookie session management — prerequisite for all other features
- Dashboard home with 4 reporting charts (revenue by month, jobs by status, contractor utilization, quote conversion)
- Jobs list with status filter tabs, search, and server-side pagination
- Job detail page with status transitions and notes
- Job request review queue (approve/decline inbound client requests)
- Calendar week view with contractor lanes and drag-and-drop rescheduling
- Conflict detection on booking (leverages existing GIST constraint infrastructure)
- Quotes list, create/edit form with line items, send, and approval status tracking
- Invoices list, payment recording, and PDF download
- Client list with search and job history (CRM)
- Contractor list with profile view and weekly schedule editor
- Global sidebar navigation with breadcrumb support

**Should have (v2.1 — after core is stable):**
- Unassigned jobs queue panel on calendar — dispatch UX improvement
- Multi-day booking UI — backend API is ready; UI deferred from launch
- Quote-to-job conversion flow — cross-cutting, build after all three base pages are stable
- Date override management per contractor
- Availability-aware date suggestions (POST `/scheduling/suggest-dates`)

**Defer (v3+):**
- In-app payment processing (Stripe/PCI compliance domain)
- Bulk job status changes
- CSV/Excel export
- Dark mode (cosmetic; adds no business value for v2.0)
- Super admin multi-company console (different product)
- WebSocket real-time updates (30-second polling is invisible to users in practice)
- Offline mode on web (web admin is always connected; no Service Worker complexity needed)

See `.planning/research/FEATURES.md` for full competitor analysis, feature dependency graph, and prioritization matrix.

### Architecture Approach

The architecture follows a strict server/client boundary. Page files are React Server Components that fetch initial data from FastAPI via `serverApiClient()` (reads httpOnly cookie, forwards as Bearer header). They pass data as props to Client Components that use TanStack Query with `initialData` — giving fast first render from SSR and interactive client-side updates thereafter. All FastAPI calls from Client Components go through Next.js Route Handlers acting as an API proxy, so the access token never touches JavaScript. A thin `apiClient()` fetch wrapper handles 401 responses by silently refreshing the token and retrying. Redux is constrained to two slices: `auth` (user display info decoded from JWT claims) and `ui` (sidebar state, active filters). Charts (Recharts) and the calendar (react-big-calendar) are dynamically imported as Client Components with `ssr: false` because they require browser APIs.

**Major components:**
1. **Next.js Middleware (`middleware.ts`):** UX redirect guard — cookie presence check + role decode; NOT a security boundary (every server component independently verifies via FastAPI)
2. **Route Handlers (`/api/auth/*`):** Auth proxy — receive credentials, call FastAPI, set httpOnly cookies; the only place raw tokens exist
3. **React Server Components:** Initial data fetch per page via `serverApiClient()`; rendered to HTML with real data before client hydration
4. **TanStack Query Hooks (`features/*/hooks/`):** All server state per feature domain; cache invalidation on mutations
5. **Redux Store (`makeStore` factory):** Client UI state only; created per browser session via `StoreProvider` with `useRef` — never a module-level singleton
6. **FastAPI `get_current_user` (modified):** Cookie-first auth with Bearer header fallback; all 40+ existing endpoints inherit the change automatically via dependency injection
7. **`refresh_tokens` table (migration):** `client_type` column scopes family revocation — web login cannot revoke mobile sessions

See `.planning/research/ARCHITECTURE.md` for full build order, data flow diagrams, SSR vs. CSR decision matrix, and code patterns for all 6 architectural patterns.

### Critical Pitfalls

1. **JWT in localStorage (XSS attack surface)** — Store access and refresh tokens exclusively in httpOnly cookies set by Next.js Route Handlers. Verify with `document.cookie` in browser console — the token must be invisible to JavaScript. This is a non-negotiable decision before any feature code.

2. **Redux store singleton in SSR (cross-request tenant data leakage)** — Use `export const makeStore = () => configureStore(...)` factory pattern, never `export const store = configureStore(...)` at module level. A singleton store in Next.js SSR shares state across concurrent server requests — in a multi-tenant SaaS this means Company A can see Company B's data in server-rendered HTML.

3. **CVE-2025-29927 Next.js Middleware auth bypass (CVSS 9.1)** — Pin Next.js to ≥15.2.3. Treat middleware as a UX redirect layer only — every Server Component must independently verify the session by calling FastAPI. Never rely on middleware alone for auth enforcement.

4. **Web login breaks existing mobile sessions (refresh token family conflict)** — Add `client_type VARCHAR(10)` column to `refresh_tokens` before shipping web auth. Scope family revocation to `(family_id, client_type)`. Test simultaneous mobile + web sessions — neither should be revoked when the other logs in.

5. **API contract changes silently breaking mobile** — All new Pydantic response fields must be `Optional` with defaults. Never rename or remove existing fields. Add OpenAPI spec diffing to CI that flags breaking changes before merge.

See `.planning/research/PITFALLS.md` for all 10 critical pitfalls, integration gotchas table, security mistakes, performance traps, and recovery strategies.

---

## Implications for Roadmap

Based on combined research, the build order is determined by two hard constraints: (1) the auth/foundation layer is a prerequisite for every authenticated page, and (2) the scheduling calendar is the most complex page and depends on jobs and contractors being complete. Reporting is fully standalone and safe to build after the feature pages.

### Phase 1: Backend Prep and Web Foundation

**Rationale:** All 10 critical pitfalls trace back to the auth integration boundary and SSR architecture decisions. The backend changes are small but must precede every web feature. Zero web features can be built correctly without the auth proxy, httpOnly cookies, and unified `get_current_user` in place. The Redux `makeStore` pattern and fetch wrapper architecture must also be established from the first component — retrofitting these is a full rewrite.

**Delivers:**
- FastAPI: `client_type` DB migration on `refresh_tokens`; `get_current_user` extended for cookie auth; `LoginRequest` schema extended with `client_type` field; CORS origins updated in env
- Next.js project scaffold (`web/`): App Router, TypeScript strict mode, Tailwind v4, shadcn/ui init
- Redux `makeStore` factory (not singleton) + `StoreProvider` with `useRef`
- TanStack `QueryClient` provider setup
- `apiClient` + `serverApiClient` fetch wrappers with 401 retry and cookie forwarding
- Next.js Middleware for UX route guards
- Route Handlers: `/api/auth/login`, `/api/auth/refresh`, `/api/auth/logout`
- Login page (react-hook-form + zod) and logout flow with `router.refresh()`
- Dashboard shell layout (sidebar, topbar, breadcrumbs)
- TypeScript type definitions mirroring all FastAPI Pydantic schemas
- OpenAPI spec diffing in CI (prevents mobile contract breaks)

**Avoids:** Pitfall 1 (localStorage XSS), Pitfall 3 (CVE-2025-29927), Pitfall 4 (Redux SSR singleton), Pitfall 5 (router cache stale auth), Pitfall 6 (mobile session revocation), Pitfall 8 (RTK Query SSR hydration mismatch)

**Research flag:** Standard patterns — httpOnly cookie auth proxy from Next.js official docs; RTK `makeStore` from official Redux Toolkit docs. No additional research needed.

---

### Phase 2: Jobs and Job Requests

**Rationale:** Jobs are the central entity and appear on every subsequent page (calendar references jobs, invoices generated from jobs, quotes convert to jobs). Building jobs first establishes the Server Component + Client DataTable + TanStack Query mutation pattern that all other feature pages replicate. This pattern should be proven and stable before it is applied to 5 more domains.

**Delivers:**
- Jobs list page: Server Component initial fetch → Client DataTable with status filter tabs, column sort, server-side pagination
- Job detail page: status, contractor assignment, client info, notes, time tracking display
- Job status transition actions (PATCH `/jobs/{id}/transition`)
- Job creation wizard (multi-step react-hook-form with `useFormContext`)
- Job request review queue (GET `/jobs/requests`, POST approve/decline)
- Job status badge component (reused across all pages)
- Cross-tenant isolation tests for every jobs endpoint

**Uses:** TanStack Table v8, TanStack Query `useMutation` with `invalidateQueries`, Server Component + Client Component split pattern, shadcn/ui DataTable + Dialog

**Avoids:** Pitfall 9 (RLS cross-tenant isolation test for every endpoint), Pitfall 7 (no new required Pydantic fields)

**Research flag:** Standard patterns — data table + mutation flow is well-established in ARCHITECTURE.md. No additional research needed.

---

### Phase 3: Scheduling Calendar

**Rationale:** The calendar is the product's core differentiator and the highest-complexity page. It depends on both contractors (to populate contractor lanes) and jobs (to populate calendar events). Building it third ensures both dependencies exist and the auth layer is proven stable. The drag-and-drop + conflict detection combination is the key differentiator over all 7 FSM competitors analyzed.

**Delivers:**
- Week view calendar with per-contractor lanes (react-big-calendar with `resources` prop)
- Drag-and-drop rescheduling with optimistic updates and 409 conflict rollback
- Conflict detection display (POST `/scheduling/conflicts` pre-check before confirming drag)
- Booking create/delete modals
- Week navigation with keyboard shortcuts (arrow keys)

**Uses:** react-big-calendar 1.19 with `dateFnsLocalizer`, `dragAndDropAddon`, TanStack Query `useMutation` with optimistic update + rollback, dynamic import with `ssr: false`

**Avoids:** Pitfall 9 (all scheduling endpoints need cross-tenant tests)

**Research flag:** Needs research-phase during planning. The react-big-calendar `resources` prop (per-contractor lanes) combined with drag-and-drop and TanStack Query optimistic update rollback is non-trivial. Verify the `onEventDrop` / `onSelectSlot` callback signatures and `dragAndDropAddon` integration pattern before committing to the implementation plan.

---

### Phase 4: Quotes and Invoices

**Rationale:** Quotes and invoices are closely related in the workflow (quote converts to job converts to invoice) but are standalone pages that can be built after the calendar stabilizes. Desktop form entry for quotes is a key UX advantage over mobile — react-hook-form with `useFieldArray` for line items is far more comfortable on a large screen.

**Delivers:**
- Quotes list with status indicators and filter tabs
- Quote create/edit form with line items, taxes, and client selector
- Send quote action + approval status tracking
- Quote PDF download (inline iframe preview as enhancement)
- Invoices list with payment status
- Invoice detail with payment recording (PATCH `/invoices/{id}/payment`)
- Invoice PDF download
- Invoice generate from completed job (POST `/invoices/generate/{job_id}`)

**Uses:** react-hook-form `useFieldArray` for line items, TanStack Query mutations, shadcn/ui Sheet for detail sidepane, shadcn/ui Command for client search-select

**Avoids:** Pitfall 7 (quote/invoice Pydantic schemas must remain mobile-safe), Pitfall 9 (cross-tenant tests for all endpoints)

**Research flag:** Standard patterns — quotes and invoices follow the same data table + form pattern established in Phase 2. No additional research needed.

---

### Phase 5: CRM (Clients and Contractors)

**Rationale:** Client and contractor management pages follow the same list + detail + form pattern as jobs and quotes. They are placed in Phase 5 because the contractor profile page embeds a schedule view that is more meaningful after the scheduling calendar (Phase 3) is proven, and the client detail page links to job history from the completed Phase 2 jobs domain.

**Delivers:**
- Client list with search and server-side pagination
- Client detail page with full job history (GET `/jobs?client_id=`)
- Contractor list with availability summary
- Contractor profile page with assigned jobs and weekly schedule summary
- Weekly schedule editor grid (PUT `/scheduling/schedules/{id}/weekly/{dow}`)

**Uses:** Same DataTable + TanStack Query pattern as Phase 2; schedule editor is a custom grid component (no shadcn/ui primitive — custom implementation required)

**Avoids:** Pitfall 9 (all CRM endpoints need cross-tenant tests)

**Research flag:** Standard patterns for list/detail. The weekly schedule grid is a custom component — confirm PUT endpoint request schema before building the UI, but no broader research needed.

---

### Phase 6: Reporting Dashboard

**Rationale:** Reporting is fully standalone — it depends only on auth (Phase 1) and requires none of the feature pages. It is placed last because the 4 report metrics (`revenue_by_month`, `jobs_by_status`, `contractor_utilization`, `quote_conversion`) are more meaningful once the rest of the dashboard is populated with real data. All backend endpoints already exist.

**Delivers:**
- Reporting page with 4 Recharts charts (AreaChart for revenue, BarChart for jobs by status, BarChart for utilization, PieChart for quote conversion)
- Date range filter with TanStack Query-driven refetch
- Revenue vs. target comparison (paid vs. unpaid breakdown)
- All charts dynamically imported with `ssr: false`

**Uses:** Recharts 3.8 via shadcn/ui Chart wrappers, Server Component initial fetch with `{ cache: 'no-store' }`, date-fns for date range formatting, shadcn/ui DatePicker for range selector

**Avoids:** Performance trap — reporting aggregate queries are the most expensive; use `{ next: { revalidate: 60 } }` for stable non-date-filtered metrics

**Research flag:** Standard patterns — shadcn/ui Chart components are thin wrappers over Recharts with documented `ssr: false` import pattern. No additional research needed.

---

### Phase Ordering Rationale

- **Auth and foundation must come first** — all 10 critical pitfalls in PITFALLS.md trace back to Phase 1 decisions. A wrong auth decision discovered in Phase 3 requires retrofitting every page.
- **Jobs before calendar** — react-big-calendar is the most complex component and requires the jobs and contractor data models to be proven in isolation before combining them on the calendar.
- **Feature pages before reporting** — reporting benefits from the rest of the dashboard being complete and the data models being settled before the summary charts are finalized.
- **Calendar before CRM** — contractor profile (Phase 5) embeds a schedule reference; building the calendar first makes that view consistent with the main scheduling page.
- **Quotes/invoices are parallel-safe** — they share no hard dependency on the scheduling calendar and could be built in parallel with Phase 3 by a second developer if team size allows.

### Research Flags

**Needs research-phase during planning:**
- **Phase 3 (Scheduling Calendar):** react-big-calendar `resources` prop (contractor lane rendering) combined with drag-and-drop addon and TanStack Query optimistic rollback is the highest-risk UI component in the project. A 1-2 day spike before Phase 3 planning is recommended.

**Standard patterns (skip research-phase):**
- **Phase 1 (Auth + Foundation):** httpOnly cookie auth proxy, RTK `makeStore` factory, Next.js Middleware — all from official docs with HIGH confidence sources.
- **Phase 2 (Jobs):** DataTable + TanStack Query mutation pattern — standard, established in ARCHITECTURE.md code examples.
- **Phase 4 (Quotes/Invoices):** Same pattern as Phase 2 with `useFieldArray` for line items — documented.
- **Phase 5 (CRM):** Same list/detail pattern as Phase 2. Custom schedule grid uses clear backend schema.
- **Phase 6 (Reporting):** shadcn/ui Chart + Recharts with `ssr: false` — documented and straightforward.

---

## Confidence Assessment

| Area | Confidence | Notes |
|------|------------|-------|
| Stack | HIGH | All library versions verified against npm registries; official Next.js, RTK, TanStack, and shadcn/ui docs consulted directly |
| Features | HIGH | Competitor analysis cross-referenced against 6 FSM platforms; all v2.0 features mapped to existing backend endpoints via direct codebase inspection |
| Architecture | HIGH | Auth proxy pattern, RTK `makeStore`, Server/Client component split — all from official RTK and Next.js docs; existing `security.py` and `main.py` inspected directly |
| Pitfalls | HIGH | CVE-2025-29927 from NVD + Datadog analysis; CORS wildcard from official FastAPI docs + GitHub issues; token storage from OWASP; SSR singleton from official RTK docs |

**Overall confidence:** HIGH

### Gaps to Address

- **Next.js 16 stability:** STACK.md notes "Next.js 16 stable confirmed (MEDIUM confidence)" based on a blog source, not official Vercel release notes. Verify the exact latest stable version on npmjs.com before scaffolding. If Next.js 16 is not yet stable, use Next.js 15.2.3+ — the App Router patterns are identical and the CVE is patched.
- **react-big-calendar resource lane + drag-and-drop:** The calendar is the highest-risk UI component. A spike on the `resources` prop and drag-and-drop addon behavior with multiple contractor lanes is flagged for Phase 3 research.
- **Refresh token migration deployment window:** The `client_type` DB migration requires a coordinated backend deploy with mobile app regression tests. Plan the migration window and rollback procedure before Phase 1 ships to production.
- **CSRF protection for cookie-based auth:** PITFALLS.md flags CSRF as a security concern. `SameSite=Lax` mitigates most vectors, but confirm whether FastAPI's existing CSRF protection covers the web cookie flow before Phase 1 ships.

---

## Sources

### Primary (HIGH confidence)
- Redux Toolkit official docs — `makeStore` factory pattern, Next.js App Router setup
- Next.js official docs — Authentication guide, Project structure, Caching guide, Vitest guide
- TanStack Query official docs — comparison vs RTK Query, server-side rendering
- FastAPI official docs — CORS configuration
- CVE-2025-29927 (NVD + Datadog Security Labs) — Next.js middleware bypass (CVSS 9.1)
- npmjs.com — Redux Toolkit 2.11.2, TanStack Query 5.90.21, TanStack Table 8.21.3, react-hook-form 7.71.2, Recharts 3.8.0, react-big-calendar 1.19.4 version verification
- shadcn/ui official docs — Tailwind v4 compatibility guide
- Tailwind CSS official blog — v4 performance improvements
- Existing codebase: `backend/app/core/security.py`, `backend/app/features/auth/models.py`, `backend/app/main.py` — direct inspection

### Secondary (MEDIUM confidence)
- jishulabs.com — Next.js 16 stable confirmation (blog source; verify against official Vercel release notes before use)
- adminlte.io — shadcn/ui as standard admin dashboard choice in 2026
- getautonoma.com — Playwright vs. Cypress comparison for enterprise projects
- medium.com — Next.js + FastAPI JWT auth with httpOnly cookie pattern
- shadcn/ui GitHub discussions — date-fns vs. dayjs recommendation

### Tertiary (MEDIUM confidence — competitor analysis)
- contractorplus.app — HouseCall Pro vs Jobber vs ServiceTitan feature comparison
- fieldpulse.com — Jobber vs Housecall Pro comparison 2026
- servicetitan.com — Dispatch software features
- mhelpdesk.com — Drag-and-drop calendar feature analysis
- help.getjobber.com — Jobber dashboard feature documentation

---
*Research completed: 2026-03-15*
*Ready for roadmap: yes*
