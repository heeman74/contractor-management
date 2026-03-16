# Architecture Research

**Domain:** Next.js Web Admin Dashboard integrating with existing FastAPI + Flutter mobile platform (ContractorHub v2.0)
**Researched:** 2026-03-15
**Confidence:** HIGH (auth flow, CORS, Redux SSR patterns verified against official RTK docs and Next.js docs; FastAPI integration verified against existing codebase)

---

## Standard Architecture

### System Overview

```
┌──────────────────────────────────────────────────────────────────────┐
│                      NEXT.JS WEB ADMIN DASHBOARD                      │
│                                                                        │
│  ┌─────────────────────────────────────────────────────────────────┐  │
│  │                    Browser (Client Layer)                        │  │
│  │  ┌─────────────┐  ┌──────────────────┐  ┌───────────────────┐  │  │
│  │  │ Redux Store  │  │  TanStack Query  │  │  React Components │  │  │
│  │  │ (client UI  │  │  (server state   │  │  (shadcn/ui,      │  │  │
│  │  │  state only)│  │   cache + fetch) │  │   Tailwind v4)    │  │  │
│  │  └──────┬───────┘  └───────┬──────────┘  └─────────┬─────────┘  │  │
│  │         │                  │                        │            │  │
│  └─────────┼──────────────────┼────────────────────────┼────────────┘  │
│            │                  │                        │               │
│  ┌─────────┼──────────────────┼────────────────────────┼────────────┐  │
│  │         │         Next.js Server Layer               │            │  │
│  │  ┌──────┴────────────────────────────────────────────┴────────┐  │  │
│  │  │          Next.js Middleware (middleware.ts)                 │  │  │
│  │  │   Cookie presence check → redirect to /login if absent     │  │  │
│  │  │   Role check from JWT claims (jose decode, no verify)      │  │  │
│  │  │   NOT the auth security boundary — UX redirect only        │  │  │
│  │  └────────────────────────┬───────────────────────────────────┘  │  │
│  │                           │                                       │  │
│  │  ┌──────────────────────────────────────────────────────────┐   │  │
│  │  │                  Route Handlers (/api/*)                  │   │  │
│  │  │  ┌─────────────────────────────────────────────────┐     │   │  │
│  │  │  │  Auth Proxy (/api/auth/login, /api/auth/refresh) │     │   │  │
│  │  │  │  Forwards credentials to FastAPI, sets httpOnly  │     │   │  │
│  │  │  │  cookies on response. Token never touches JS.    │     │   │  │
│  │  │  └─────────────────────────────────────────────────┘     │   │  │
│  │  └────────────────────────┬─────────────────────────────────┘   │  │
│  │                           │                                       │  │
│  │  ┌──────────────────────────────────────────────────────────┐   │  │
│  │  │               Server Components (RSC)                     │   │  │
│  │  │  Fetch data via native fetch() with forwarded cookie      │   │  │
│  │  │  Render initial HTML → pass as props to Client Components │   │  │
│  │  │  Never use TanStack Query or Redux dispatch here          │   │  │
│  │  └─────────────────────────────────────────────────────────┘   │  │
│  └───────────────────────────────────────────────────────────────┘  │
└──────────────────────────────────────────────────────────────────────┘
                              │ HTTPS REST / JSON
                              │ Authorization: Bearer <token-from-cookie>
                              │   OR Cookie: access_token=<token> (via proxy)
┌──────────────────────────────────────────────────────────────────────┐
│                        FASTAPI BACKEND (existing, shared)             │
│                                                                        │
│  ┌──────────────────────────────────────────────────────────────┐   │
│  │  CORSMiddleware — explicit origins from CORS_ORIGINS env var  │   │
│  └──────────────────────────────┬─────────────────────────────┘   │
│  ┌──────────────────────────────────────────────────────────────┐   │
│  │  get_current_user() dependency — dual auth: cookie + Bearer   │   │
│  │  NEW: check httpOnly cookie first, fallback to Bearer header  │   │
│  │  Sets tenant context (RLS) on every authenticated request     │   │
│  └──────────────────────────────┬─────────────────────────────┘   │
│  ┌──────────────────────────────────────────────────────────────┐   │
│  │  Existing Feature Routers (unchanged)                         │   │
│  │  /auth  /jobs  /quotes  /invoices  /reports  /scheduling      │   │
│  │  /users  /companies  /sync  /files  /notifications            │   │
│  └──────────────────────────────┬─────────────────────────────┘   │
│  ┌──────────────────────────────┼───────────────────────────────┐   │
│  │         PostgreSQL + RLS (company_id isolation)               │   │
│  └──────────────────────────────────────────────────────────────┘   │
└──────────────────────────────────────────────────────────────────────┘
                              |
┌──────────────────────────────────────────────────────────────────────┐
│              FLUTTER MOBILE APP (existing, unchanged)                 │
│              Bearer token in Authorization header                     │
│              Offline-first with Drift + sync queue                    │
└──────────────────────────────────────────────────────────────────────┘
```

### Component Responsibilities

| Component | Responsibility | New vs Existing |
|-----------|---------------|-----------------|
| Next.js Middleware (`middleware.ts`) | Check httpOnly cookie presence; redirect to `/login` if absent; decode JWT claims for role-based routing; UX only, NOT security boundary | New |
| Next.js Route Handlers (`/api/auth/*`) | Auth proxy: receive credentials from browser, call FastAPI, set httpOnly cookies on response; never expose tokens to JavaScript | New |
| React Server Components | Fetch initial page data from FastAPI via `fetch()` with forwarded cookie; render HTML; pass data to client components as props | New |
| Client Components (`"use client"`) | Interactive UI: TanStack Query for data fetching/caching, Redux for UI state (sidebar, filters, modals), react-hook-form for forms | New |
| Redux Store (`makeStore` factory) | Client-only state: auth session metadata (user info from decoded JWT, not the token itself), sidebar state, active filters, tenant display info | New |
| TanStack Query (`QueryClient`) | All server-state: jobs, quotes, contractors, clients, invoices, reports data — with caching, background refetch, optimistic updates | New |
| FastAPI `get_current_user` | Extended to check httpOnly cookie first, then fallback to Bearer header — supports both web and mobile simultaneously | Modified |
| FastAPI `CORSMiddleware` | Already reads from `CORS_ORIGINS` env var — add web dashboard origin to env; no code changes required | Config change only |
| FastAPI Auth Endpoints | `/auth/login`, `/auth/refresh`, `/auth/logout` — consumed by Next.js Route Handlers, no changes to existing endpoints | Unchanged |
| FastAPI Feature Routers | All existing endpoints consumed by web dashboard exactly as mobile consumes them — no changes | Unchanged |
| Refresh Token Model | Add `client_type` column to scope token family revocation per session (web vs mobile) — prevents web login from revoking mobile sessions | Modified (DB migration) |

---

## Recommended Project Structure

```
web/                                    # Next.js app root (new top-level dir)
├── src/
│   ├── app/                            # Next.js App Router pages
│   │   ├── layout.tsx                  # Root layout: ReduxProvider, QueryClientProvider
│   │   ├── page.tsx                    # Root redirect → /dashboard or /login
│   │   ├── (auth)/                     # Route group: unauthenticated routes
│   │   │   ├── login/
│   │   │   │   └── page.tsx            # Login form (Server Component shell)
│   │   │   └── layout.tsx              # Minimal layout (no sidebar)
│   │   ├── (dashboard)/                # Route group: all admin pages (requires auth)
│   │   │   ├── layout.tsx              # Dashboard shell: sidebar, topbar, nav
│   │   │   ├── dashboard/
│   │   │   │   └── page.tsx            # Overview/home page (Server Component)
│   │   │   ├── jobs/
│   │   │   │   ├── page.tsx            # Jobs list (Server Component → Client DataTable)
│   │   │   │   ├── [id]/
│   │   │   │   │   └── page.tsx        # Job detail
│   │   │   │   └── new/
│   │   │   │       └── page.tsx        # New job wizard
│   │   │   ├── scheduling/
│   │   │   │   └── page.tsx            # Drag-and-drop calendar (Client Component)
│   │   │   ├── quotes/
│   │   │   │   ├── page.tsx
│   │   │   │   ├── [id]/page.tsx
│   │   │   │   └── new/page.tsx
│   │   │   ├── invoices/
│   │   │   │   ├── page.tsx
│   │   │   │   └── [id]/page.tsx
│   │   │   ├── contractors/
│   │   │   │   ├── page.tsx
│   │   │   │   └── [id]/page.tsx
│   │   │   ├── clients/
│   │   │   │   ├── page.tsx
│   │   │   │   └── [id]/page.tsx
│   │   │   └── reports/
│   │   │       └── page.tsx            # Charts: Recharts via shadcn/ui (Client Component)
│   │   └── api/                        # Route Handlers (server-side only)
│   │       └── auth/
│   │           ├── login/
│   │           │   └── route.ts        # POST: call FastAPI, set httpOnly cookies
│   │           ├── refresh/
│   │           │   └── route.ts        # POST: call FastAPI /auth/refresh, rotate cookies
│   │           └── logout/
│   │               └── route.ts        # POST: call FastAPI /auth/logout, clear cookies
│   ├── components/                     # Shared, reusable UI components
│   │   ├── ui/                         # shadcn/ui components (auto-generated, do not edit)
│   │   ├── layout/
│   │   │   ├── app-sidebar.tsx         # shadcn Sidebar with nav links
│   │   │   ├── topbar.tsx              # Page header, breadcrumbs, user menu
│   │   │   └── nav-breadcrumb.tsx
│   │   ├── data-table/                 # TanStack Table wrapper
│   │   │   ├── data-table.tsx
│   │   │   ├── data-table-toolbar.tsx  # Search, filters, column visibility
│   │   │   └── data-table-pagination.tsx
│   │   └── charts/
│   │       └── recharts-wrapper.tsx    # Dynamic import of Recharts (ssr: false)
│   ├── features/                       # Feature-specific components and hooks
│   │   ├── auth/
│   │   │   ├── login-form.tsx          # react-hook-form + zod login form
│   │   │   └── logout-button.tsx       # Calls /api/auth/logout, router.refresh()
│   │   ├── jobs/
│   │   │   ├── jobs-table.tsx          # DataTable with job columns
│   │   │   ├── job-status-badge.tsx
│   │   │   ├── job-wizard/             # Multi-step job creation form
│   │   │   │   ├── job-wizard.tsx
│   │   │   │   ├── step-details.tsx
│   │   │   │   ├── step-scheduling.tsx
│   │   │   │   └── step-contractor.tsx
│   │   │   └── hooks/
│   │   │       ├── use-jobs.ts         # TanStack Query hooks for jobs
│   │   │       └── use-job-mutations.ts
│   │   ├── scheduling/
│   │   │   ├── schedule-calendar.tsx   # react-big-calendar wrapper
│   │   │   └── hooks/
│   │   │       └── use-schedule.ts
│   │   ├── quotes/
│   │   ├── invoices/
│   │   ├── contractors/
│   │   ├── clients/
│   │   └── reports/
│   │       ├── revenue-chart.tsx       # AreaChart via recharts/shadcn
│   │       ├── jobs-by-status.tsx      # BarChart
│   │       └── utilization-chart.tsx   # BarChart
│   ├── lib/                            # Utilities, config, infrastructure
│   │   ├── api/
│   │   │   ├── client.ts               # fetch wrapper with auth cookie forwarding
│   │   │   └── query-client.ts         # TanStack QueryClient singleton factory
│   │   ├── auth/
│   │   │   ├── cookies.ts              # Cookie get/set helpers (server-side)
│   │   │   └── decode-jwt.ts           # jose JWT decode (no verify — claims only)
│   │   └── utils.ts                    # cn(), date formatters, etc.
│   ├── store/                          # Redux Toolkit store
│   │   ├── index.ts                    # makeStore factory (NOT singleton)
│   │   ├── provider.tsx                # Client Component StoreProvider with useRef
│   │   └── slices/
│   │       ├── auth.slice.ts           # User display info, company name, roles
│   │       └── ui.slice.ts             # Sidebar open/closed, active filters
│   ├── types/                          # TypeScript interfaces mirroring FastAPI schemas
│   │   ├── job.ts
│   │   ├── quote.ts
│   │   ├── invoice.ts
│   │   ├── contractor.ts
│   │   ├── client.ts
│   │   ├── report.ts
│   │   └── auth.ts
│   └── middleware.ts                   # Route protection (cookie check, role redirect)
├── public/
├── next.config.ts
├── tailwind.config.ts                  # Tailwind v4 — CSS-first via @theme directive
├── tsconfig.json                       # strict: true
├── vitest.config.ts
└── playwright.config.ts
```

### Structure Rationale

- **`(auth)/` and `(dashboard)/` route groups:** Route groups keep URL paths clean (`/login` not `/auth/login`) while allowing separate layouts — the dashboard layout has the full sidebar/nav shell; auth pages have a minimal centered layout.
- **`features/`:** Each feature owns its components AND its TanStack Query hooks. A `jobs/hooks/use-jobs.ts` file contains all query/mutation logic for the jobs domain. This keeps data fetching concerns colocated with the UI that uses the data.
- **`store/slices/`:** Only two slices — auth metadata (display state, not tokens) and UI state (sidebar open/closed). Server state lives in TanStack Query, not Redux. This constraint prevents Redux from bloating with API data.
- **`lib/api/client.ts`:** Centralizes all fetch configuration — base URL from env, error handling, cookie forwarding. All TanStack Query hooks use this wrapper.
- **`types/`:** Single source of truth for TypeScript shapes. Mirror FastAPI Pydantic schemas exactly. If the backend adds a field, update here first. No business logic in types — they are data contracts only.
- **`api/auth/` Route Handlers:** These are the auth proxy. They live in `app/api/` (Next.js convention for Route Handlers) and are the only place that touches raw tokens.

---

## Architectural Patterns

### Pattern 1: Auth Proxy via Route Handlers (httpOnly Cookie Bridge)

**What:** The browser never directly calls FastAPI's `/auth/login`. Instead it calls Next.js's `/api/auth/login` Route Handler. The Route Handler forwards credentials to FastAPI, receives the token pair, and sets httpOnly cookies in the response. The access token and refresh token are stored as httpOnly cookies — JavaScript cannot read them.

**When to use:** Every auth operation: login, token refresh, logout. No exceptions.

**Trade-offs:** Adds one hop for auth operations (browser → Next.js → FastAPI). This is acceptable — auth operations are infrequent. The security gain (tokens inaccessible to JavaScript) eliminates the entire class of XSS token theft vulnerabilities.

**Example:**
```typescript
// src/app/api/auth/login/route.ts
import { NextRequest, NextResponse } from 'next/server';

export async function POST(req: NextRequest) {
  const body = await req.json();

  // Forward to FastAPI
  const fastapiRes = await fetch(`${process.env.FASTAPI_URL}/api/v1/auth/login`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify(body),
  });

  if (!fastapiRes.ok) {
    const error = await fastapiRes.json();
    return NextResponse.json(error, { status: fastapiRes.status });
  }

  const { access_token, refresh_token } = await fastapiRes.json();

  const response = NextResponse.json({ success: true });

  // Set httpOnly cookies — inaccessible to JavaScript
  response.cookies.set('access_token', access_token, {
    httpOnly: true,
    secure: process.env.NODE_ENV === 'production',
    sameSite: 'lax',
    path: '/',
    maxAge: 60 * 15, // 15 minutes — matches FastAPI access token TTL
  });
  response.cookies.set('refresh_token', refresh_token, {
    httpOnly: true,
    secure: process.env.NODE_ENV === 'production',
    sameSite: 'lax',
    path: '/api/auth/refresh', // Scoped — only sent on refresh calls
    maxAge: 60 * 60 * 24 * 30, // 30 days — matches FastAPI refresh token TTL
  });

  return response;
}
```

### Pattern 2: API Client with Cookie Forwarding

**What:** A thin `fetch` wrapper in `lib/api/client.ts` handles base URL configuration and forwards the access token from the httpOnly cookie in the `Authorization` header for FastAPI calls. This decouples all TanStack Query hooks from the token storage mechanism.

**When to use:** All FastAPI calls from Client Components (via TanStack Query hooks). Server Components use a separate server-side variant that reads cookies via Next.js `cookies()`.

**Trade-offs:** Adds a thin abstraction layer. Worth it — all token handling is in one file. Switching from cookie to any other storage mechanism requires changing only this file.

**Example:**
```typescript
// src/lib/api/client.ts
const FASTAPI_BASE = process.env.NEXT_PUBLIC_FASTAPI_URL;

// Client-side: browser sends cookie automatically (same-site cookie)
// Cookie flows to Next.js Route Handler → Route Handler adds Bearer header for FastAPI
export async function apiClient<T>(
  path: string,
  options: RequestInit = {}
): Promise<T> {
  const res = await fetch(`/api/proxy${path}`, {  // Routes through Next.js proxy
    ...options,
    headers: {
      'Content-Type': 'application/json',
      ...options.headers,
    },
    credentials: 'include', // Include cookies
  });

  if (res.status === 401) {
    // Attempt silent token refresh
    const refreshed = await fetch('/api/auth/refresh', { method: 'POST', credentials: 'include' });
    if (refreshed.ok) {
      // Retry original request once
      return apiClient(path, options);
    }
    // Refresh failed — redirect to login
    window.location.href = '/login';
    throw new Error('Session expired');
  }

  if (!res.ok) {
    const error = await res.json().catch(() => ({ detail: 'Unknown error' }));
    throw new Error(error.detail ?? `HTTP ${res.status}`);
  }

  return res.json();
}

// Server-side: read cookie and forward as Bearer header
import { cookies } from 'next/headers';
export async function serverApiClient<T>(path: string, options: RequestInit = {}): Promise<T> {
  const cookieStore = await cookies();
  const token = cookieStore.get('access_token')?.value;

  const res = await fetch(`${FASTAPI_BASE}${path}`, {
    ...options,
    headers: {
      'Content-Type': 'application/json',
      ...(token ? { Authorization: `Bearer ${token}` } : {}),
      ...options.headers,
    },
    cache: 'no-store', // Admin data must be fresh — never cached at CDN level
  });

  if (!res.ok) throw new Error(`HTTP ${res.status}`);
  return res.json();
}
```

### Pattern 3: Redux makeStore Factory (SSR-Safe)

**What:** The Redux store is created via a `makeStore` factory function, never as a module-level singleton. The `StoreProvider` client component uses `useRef` to create the store once per client session. Server components never import the store directly — they pass data as props.

**When to use:** Always — this is the mandatory pattern for Redux in Next.js App Router. A singleton store is a critical bug that causes cross-request state pollution in SSR.

**Trade-offs:** Slightly more boilerplate than `export const store = configureStore(...)`. The boilerplate is non-negotiable for correctness.

**Example:**
```typescript
// src/store/index.ts
import { configureStore } from '@reduxjs/toolkit';
import { authSlice } from './slices/auth.slice';
import { uiSlice } from './slices/ui.slice';

export const makeStore = () =>
  configureStore({
    reducer: {
      auth: authSlice.reducer,
      ui: uiSlice.reducer,
      // NOTE: No API slices here — TanStack Query owns server state
    },
  });

export type AppStore = ReturnType<typeof makeStore>;
export type RootState = ReturnType<AppStore['getState']>;
export type AppDispatch = AppStore['dispatch'];

// src/store/provider.tsx
'use client';
import { useRef } from 'react';
import { Provider } from 'react-redux';
import { makeStore, type AppStore } from './index';

export function StoreProvider({ children }: { children: React.ReactNode }) {
  const storeRef = useRef<AppStore | null>(null);
  if (!storeRef.current) {
    storeRef.current = makeStore(); // Created once per client mount
  }
  return <Provider store={storeRef.current}>{children}</Provider>;
}
```

### Pattern 4: Server Component for Initial Data, Client Component for Interactivity

**What:** Each page follows a split rendering pattern. The page file (`page.tsx`) is a Server Component that fetches the initial data set via `serverApiClient()`. It passes the data as props to a Client Component that wraps TanStack Query's `useQuery` with the server-fetched data as `initialData`. Subsequent interactions (pagination, filtering, mutations) are handled client-side via TanStack Query.

**When to use:** All data-driven pages: jobs list, contractor list, client list, invoices. The pattern is the same for every list page.

**Trade-offs:** Initial page render is fast (SSR data inline in HTML). Interactive operations (filter, paginate, sort) work without full page reloads. The slight complexity of passing `initialData` is worth the performance gain on initial load.

**Example:**
```typescript
// src/app/(dashboard)/jobs/page.tsx — Server Component
import { serverApiClient } from '@/lib/api/client';
import { JobsTable } from '@/features/jobs/jobs-table';
import type { Job } from '@/types/job';

export default async function JobsPage() {
  // Fetches on server — token from cookie, no client-side loading spinner
  const initialJobs = await serverApiClient<Job[]>('/api/v1/jobs');
  return <JobsTable initialData={initialJobs} />;
}

// src/features/jobs/jobs-table.tsx — Client Component
'use client';
import { useQuery } from '@tanstack/react-query';
import { apiClient } from '@/lib/api/client';
import type { Job } from '@/types/job';

export function JobsTable({ initialData }: { initialData: Job[] }) {
  const { data: jobs } = useQuery({
    queryKey: ['jobs'],
    queryFn: () => apiClient<Job[]>('/api/v1/jobs'),
    initialData,                   // SSR data used until background refetch completes
    staleTime: 30_000,             // Background refetch after 30s
  });
  // ... render DataTable with jobs
}
```

### Pattern 5: TanStack Query Mutation with Cache Invalidation

**What:** All write operations (create job, update status, send quote) use TanStack Query `useMutation`. On success, the mutation calls `queryClient.invalidateQueries()` with the relevant query keys to trigger a background refetch of affected data. This keeps all list views fresh after mutations without manual state management.

**When to use:** Every write operation to the FastAPI backend.

**Trade-offs:** Automatic cache invalidation means a small extra network request after each mutation. Acceptable for an admin dashboard. Optimistic updates can be added for status-change operations to make the UI feel instant.

**Example:**
```typescript
// src/features/jobs/hooks/use-job-mutations.ts
import { useMutation, useQueryClient } from '@tanstack/react-query';
import { apiClient } from '@/lib/api/client';

export function useUpdateJobStatus() {
  const queryClient = useQueryClient();

  return useMutation({
    mutationFn: ({ jobId, status }: { jobId: string; status: string }) =>
      apiClient(`/api/v1/jobs/${jobId}/status`, {
        method: 'PATCH',
        body: JSON.stringify({ status }),
      }),
    onSuccess: (_, { jobId }) => {
      // Invalidate both the list and the specific job
      queryClient.invalidateQueries({ queryKey: ['jobs'] });
      queryClient.invalidateQueries({ queryKey: ['job', jobId] });
    },
    onError: (error) => {
      // Surfaces error to the UI via TanStack Query's isError state
      console.error('Failed to update job status:', error);
    },
  });
}
```

### Pattern 6: Unified FastAPI Auth Dependency (Cookie + Bearer)

**What:** The existing `get_current_user` FastAPI dependency is extended to check the httpOnly cookie before falling back to the `Authorization: Bearer` header. Mobile app behavior is unchanged — it never sends cookies, so it always hits the Bearer fallback.

**When to use:** Applied to `get_current_user` once; all 40+ endpoints that depend on it inherit the change automatically.

**Trade-offs:** Minimal complexity increase. The precedence is explicit: cookie first (web), Bearer header second (mobile), 401 if neither present.

**Example:**
```python
# backend/app/core/security.py — modified get_current_user
async def get_current_user(
    request: Request,
    credentials: HTTPAuthorizationCredentials | None = Depends(_bearer_scheme),
    db: AsyncSession = Depends(get_db),
) -> CurrentUser:
    """Supports both httpOnly cookie (web) and Bearer header (mobile)."""
    # 1. Try httpOnly cookie (web dashboard)
    token = request.cookies.get("access_token")
    # 2. Fall back to Bearer header (mobile app)
    if not token and credentials is not None:
        token = credentials.credentials
    if not token:
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Not authenticated",
            headers={"WWW-Authenticate": "Bearer"},
        )
    payload = decode_token(token)
    if payload is None or payload.get("type") != "access":
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Invalid or expired token",
        )
    # ... rest of existing logic unchanged
```

---

## Data Flow

### Auth Flow: Web Login

```
Browser submits login form
    |
    v
POST /api/auth/login  (Next.js Route Handler — same origin as browser)
    |
    v
Route Handler: POST https://api/api/v1/auth/login  (FastAPI)
    |
    v
FastAPI AuthService.login() → validates credentials → creates token pair
    |
    v
FastAPI returns { access_token, refresh_token }  (to Route Handler only)
    |
    v
Route Handler sets httpOnly cookies on response:
  access_token  (httpOnly, Secure, SameSite=Lax, Path=/, maxAge=900s)
  refresh_token (httpOnly, Secure, SameSite=Lax, Path=/api/auth/refresh, maxAge=30d)
    |
    v
Browser receives 200 + Set-Cookie headers (token never in JS)
    |
    v
Client Component: store user display info in Redux auth slice
  (decoded from JWT claims via jose — sub, company_id, roles, name)
    |
    v
Router.push('/dashboard')
```

### Token Refresh Flow

```
TanStack Query hook calls apiClient('/api/v1/jobs')
    |
    v
Next.js proxy Route Handler: reads access_token cookie → forwards as Bearer to FastAPI
    |
    v
FastAPI: 401 (token expired)
    |
    v
apiClient catches 401: calls POST /api/auth/refresh
    |
    v
Next.js Route Handler: reads refresh_token cookie → POST /api/v1/auth/refresh to FastAPI
    |
    v
FastAPI: validates refresh token → issues new token pair (rotation)
    |
    v
Route Handler: overwrites access_token + refresh_token cookies
    |
    v
apiClient retries original request with new access_token cookie
    |
    v
Success: data returned to TanStack Query hook
```

### Scheduling Calendar Drag-and-Drop Flow

```
Admin drags job to new time slot on calendar
    |
    v
react-big-calendar onEventDrop callback
    |
    v
useScheduleMutation.mutate({ jobId, newStart, newEnd })
    |
    v  [optimistic update]
queryClient.setQueryData(['schedule'], updatedCalendarEvents)
    |
    v
PATCH /api/v1/scheduling/{jobId}  via apiClient
    |
    v
FastAPI SchedulingService: checks GIST constraint atomically
    |-- PASS: 200 OK → invalidateQueries(['schedule']) → background refetch
    |-- FAIL: 409 Conflict → rollback optimistic update → toast error "Slot taken"
```

### Reporting Page Data Flow

```
Admin navigates to /reports
    |
    v
Server Component (reports/page.tsx): serverApiClient('/api/v1/reports/summary')
    |
    v
FastAPI ReportsService → queries (RLS-scoped to company_id) → aggregate data
    |
    v
Server Component renders page shell with initial data
    |
    v
Recharts Client Components receive data as props (dynamic import, ssr: false)
    |
    v
Browser: hydrates interactive chart controls (date range picker → TanStack Query refetch)
```

---

## Backend Changes Required

### 1. FastAPI: Extend `get_current_user` (security.py)

**What:** Accept httpOnly cookie as token source in addition to Bearer header.
**Impact:** All existing endpoints automatically support web cookie auth via dependency injection. Mobile unaffected.
**File:** `backend/app/core/security.py`
**Risk:** LOW — only adds a cookie check before the existing Bearer check.

### 2. FastAPI: CORS Configuration (env var update only)

**What:** Add web dashboard origins to the `CORS_ORIGINS` environment variable.
**Impact:** Zero code changes — `main.py` already reads from `settings.cors_origin_list`.
**File:** `.env` / deployment config
```
# Add to CORS_ORIGINS (comma-separated):
CORS_ORIGINS=http://localhost:3000,https://admin.contractorhub.com
```
**Risk:** NONE — additive env var change.

### 3. FastAPI: Refresh Token Model (DB migration + auth service)

**What:** Add `client_type` column to `refresh_tokens` table (`'web'` or `'mobile'`). Scope family revocation to `(family_id, client_type)` pairs so web login does not revoke mobile sessions.
**Impact:** New DB migration required. Auth service `refresh_tokens()` and family revocation query updated.
**Files:** `backend/app/features/auth/models.py`, `backend/alembic/versions/xxxx_add_client_type_to_refresh_tokens.py`, `backend/app/features/auth/service.py`
**Risk:** MEDIUM — requires DB migration and auth service logic change. Requires testing simultaneous mobile + web sessions.

### 4. FastAPI: Web Auth Endpoints (new, additive)

**What:** Add `/auth/web/login` and `/auth/web/refresh` endpoints that accept the same credentials but are called by the Next.js Route Handlers. These exist to allow the Route Handler to pass `client_type='web'` so the refresh token is tagged correctly.
**Alternatively:** Pass `client_type` as a request body field on existing `/auth/login` — simpler but changes the request schema.
**Recommended:** Extend `LoginRequest` schema with `client_type: Literal['web', 'mobile'] = 'mobile'` field. Web Route Handler passes `"client_type": "web"`. Mobile is unaffected (defaults to `'mobile'`).
**Risk:** LOW — additive schema field with default.

---

## SSR vs CSR Decision Matrix

| Page | Rendering | Rationale |
|------|-----------|-----------|
| `/login` | CSR (Client Component) | Form with real-time validation; no SEO needed; no initial data fetch |
| `/dashboard` | SSR → Client hydration | Overview metrics fetched server-side; charts hydrated client-side (browser APIs) |
| `/jobs` | SSR initial data → Client DataTable | Server fetches page 1 of jobs; client handles pagination/sort/filter |
| `/jobs/[id]` | SSR | Job detail fully rendered server-side; status updates via TanStack Query mutation |
| `/jobs/new` | CSR (multi-step wizard) | Multi-step form with local state; no SSR benefit; starts with empty form |
| `/scheduling` | SSR initial events → Client calendar | Server fetches current week's events; react-big-calendar is Client Component (drag events) |
| `/quotes` | SSR initial data → Client DataTable | Same pattern as jobs |
| `/invoices` | SSR initial data → Client DataTable | Same pattern as jobs |
| `/contractors` | SSR initial data → Client DataTable | Same pattern as jobs |
| `/clients` | SSR initial data → Client DataTable | Same pattern as jobs |
| `/reports` | SSR aggregate data → Client charts | Reports data fetched server-side; Recharts components are Client (canvas/SVG requires browser) |

**Rule of thumb:** Server Component for the page shell and initial data fetch. Client Component for anything that uses browser APIs, event handlers, hooks, or real-time interactivity.

---

## Scaling Considerations

| Scale | Architecture Adjustments |
|-------|--------------------------|
| 1-10 companies (current) | Single Next.js instance + existing FastAPI. TanStack Query `staleTime: 30s` on non-critical data. No caching layer needed. |
| 10-100 companies | Add CDN (Vercel Edge or Cloudflare) in front of Next.js. Server Component data fetches with `revalidate: 60` for reports pages. No changes to FastAPI. |
| 100+ companies | Add `revalidate` caching for reporting pages (reports are the heaviest queries). Consider Next.js `unstable_cache` or Redis cache layer for expensive aggregate queries. Reporting queries may need materialized views in PostgreSQL. |

### Scaling Priorities

1. **First bottleneck:** Reporting page aggregate queries. These scan all jobs/invoices for a company. Fix with materialized views on the PostgreSQL side (already well-positioned since the backend handles all query logic).
2. **Second bottleneck:** TanStack Query over-fetching. If admins navigate frequently, many concurrent requests hit FastAPI. Fix with generous `staleTime` on list queries (30s) and `gcTime` on detail queries (5 min).

---

## Anti-Patterns

### Anti-Pattern 1: Redux for Server State

**What people do:** Create Redux slices for `jobsSlice`, `quotesSlice`, etc. with `loading`, `error`, `data` fields. Dispatch async thunks to fetch from FastAPI. Manage cache invalidation manually.

**Why it's wrong:** RTK's official documentation explicitly warns against this. Manual cache management in Redux is error-prone (stale data after mutations), verbose (loading/error/success states on every slice), and re-invents what TanStack Query does better. The result is hundreds of lines of boilerplate that break whenever a mutation doesn't invalidate the right slices.

**Do this instead:** TanStack Query owns all server state. Redux owns only client UI state (sidebar open, active filter labels, modal open/closed). Two slices total: `auth` (display metadata) and `ui` (visual state). If you find yourself putting API response data into Redux, stop and use TanStack Query instead.

### Anti-Pattern 2: Verifying JWT on the Client

**What people do:** Import `jose` or `jsonwebtoken`, call `verify(token, secret)` in the browser to validate the token before showing UI.

**Why it's wrong:** The JWT secret must be exposed to the browser. Once the secret is in JavaScript-accessible code, any attacker can forge tokens. Client-side verification provides false security — it can be bypassed by anyone who reads the source code.

**Do this instead:** Use `jose`'s `decodeJwt()` (no verification) to read claims (user ID, company name, roles) for display purposes only. Verification happens exclusively on the FastAPI backend on every request. The browser decodes but never verifies.

### Anti-Pattern 3: Module-Level Redux Store Singleton

**What people do:** `export const store = configureStore({ reducer: rootReducer })` at the module level in `store/index.ts`.

**Why it's wrong:** In Next.js SSR, multiple server requests share the same Node.js module instance. User A's auth state is in the same store as User B's. In a multi-tenant SaaS, this means admins from different companies can see each other's data in SSR-rendered HTML — a critical security and privacy bug.

**Do this instead:** `export const makeStore = () => configureStore(...)`. The `StoreProvider` client component creates the store with `useRef` so it is created once per browser session but never shared across SSR requests.

### Anti-Pattern 4: Calling FastAPI Directly from Client Components

**What people do:** Client Components fetch `https://api.contractorhub.com/api/v1/jobs` directly with `Authorization: Bearer ${localStorage.getItem('token')}`.

**Why it's wrong:** Requires storing the token in JavaScript-accessible storage (localStorage, sessionStorage, or in-memory state that could be logged). Also bypasses the Next.js auth proxy, making token rotation harder.

**Do this instead:** All Client Component fetches go through Next.js Route Handlers (`/api/proxy/*`) or rely on the same-origin cookie being sent automatically. The Route Handler reads the httpOnly cookie and forwards it as a Bearer header to FastAPI. The client never sees the token.

### Anti-Pattern 5: Skipping Server Component Data Fetching

**What people do:** Every page is a Client Component that calls TanStack Query `useQuery` on mount. The page shows a loading skeleton on every navigation.

**Why it's wrong:** Admin dashboards have complex data that takes time to load. Showing a skeleton on every page load creates a perceived-performance problem. Next.js SSR exists precisely to solve this — render data in HTML before the client hydrates.

**Do this instead:** Page files are Server Components. They fetch initial data synchronously during SSR and pass it as `initialData` to TanStack Query in Client Components. The initial render includes real data. TanStack Query handles background refresh.

---

## Integration Points

### New vs Existing Backend Components

| Component | Status | What Changes |
|-----------|--------|-------------|
| `backend/app/core/security.py` | Modified | `get_current_user` extended for cookie auth |
| `backend/app/features/auth/models.py` | Modified | `client_type` column on `refresh_tokens` |
| `backend/app/features/auth/service.py` | Modified | Family revocation scoped to `client_type` |
| `backend/app/features/auth/schemas.py` | Modified | `client_type` field added to `LoginRequest` |
| `backend/app/main.py` | Unchanged | CORS already reads from env var |
| `.env` (backend) | Config change | Add web origins to `CORS_ORIGINS` |
| All feature routers | Unchanged | Consumed as-is by web dashboard |
| All Pydantic schemas | Additive only | New optional fields only; never remove or rename |

### New Backend DB Migration Required

```sql
-- Alembic migration: add client_type to refresh_tokens
ALTER TABLE refresh_tokens ADD COLUMN client_type VARCHAR(10) NOT NULL DEFAULT 'mobile';
CREATE INDEX ix_refresh_tokens_family_client ON refresh_tokens (family_id, client_type);
```

### New Web Components

| Component | Path | Purpose |
|-----------|------|---------|
| Auth Proxy Route Handlers | `web/src/app/api/auth/` | Login/refresh/logout cookie management |
| Next.js Middleware | `web/src/middleware.ts` | Route protection (UX redirect, not security) |
| Redux Store + Provider | `web/src/store/` | Client UI state only |
| API Client | `web/src/lib/api/client.ts` | Fetch wrapper, token forwarding, 401 retry |
| TypeScript Types | `web/src/types/` | FastAPI schema mirrors |
| Feature Hooks | `web/src/features/*/hooks/` | TanStack Query hooks per feature |

### Build Order (Considering Dependencies)

```
1. Backend Changes (prerequisite for all web features)
   - DB migration: add client_type to refresh_tokens
   - security.py: extend get_current_user for cookie auth
   - auth/service.py: update family revocation scope
   - auth/schemas.py: add client_type to LoginRequest
   - .env: add CORS_ORIGINS for web

2. Web Foundation (prerequisite for all web features)
   - Next.js project scaffold (web/ directory)
   - TypeScript types mirroring FastAPI schemas
   - Redux store + makeStore factory
   - TanStack QueryClient provider
   - API client (fetch wrapper, cookie forwarding, 401 retry)
   - Next.js middleware (route protection)
   - Dashboard shell layout (sidebar, topbar)

3. Web Authentication (prerequisite for all authenticated pages)
   - Route Handlers: /api/auth/login, /api/auth/refresh, /api/auth/logout
   - Login page + form (react-hook-form + zod)
   - Redux auth slice (user display info, roles)
   - Logout flow (cookie clear + router.refresh())
   - Test: mobile + web simultaneous sessions both remain active

4. Feature Pages (parallel after auth + foundation)
   Each feature follows: TypeScript types → TanStack Query hooks →
   Server Component page → Client DataTable/Form
   - Jobs (list, detail, create wizard, status updates)
   - Scheduling calendar (react-big-calendar, drag-and-drop)
   - Quotes (list, detail, create, send)
   - Contractors (list, detail, availability view)
   - Clients (list, detail, CRM notes)
   - Invoices (list, detail, status)

5. Reporting (last — depends on all data models being settled)
   - Reports page with Recharts charts (dynamic import, ssr: false)
   - Date range filters → TanStack Query refetch
```

---

## Security Architecture Summary

Addresses all 10 critical pitfalls from PITFALLS.md:

| Pitfall | Architecture Decision |
|---------|----------------------|
| JWT in localStorage | httpOnly cookies via Route Handler auth proxy — token never in JavaScript |
| CORS wildcard | Explicit origins in `CORS_ORIGINS` env var; code already correct |
| CVE-2025-29927 middleware bypass | Middleware is UX-only redirect; every server component calls FastAPI independently to verify token |
| Redux SSR singleton | `makeStore` factory pattern; `StoreProvider` with `useRef` |
| Router cache stale auth | `router.refresh()` on logout; Next.js 15+ `staleTimes: { dynamic: 0 }` |
| Refresh token family conflict | `client_type` column on `refresh_tokens`; family revocation scoped per client |
| API contract breaking mobile | Additive-only Pydantic changes; all new fields `Optional` with defaults |
| RTK Query SSR hydration mismatch | Server components use `fetch`; TanStack Query used in client components only |
| RLS not applied to web queries | All web endpoints use `Depends(get_current_user)` — same as mobile |
| Dual auth complexity | Single `get_current_user`: cookie first, Bearer fallback; explicit tests for each path |

---

## Sources

- [Redux Toolkit: Next.js Setup (makeStore pattern)](https://redux-toolkit.js.org/usage/nextjs) — HIGH confidence (official RTK docs)
- [RTK GitHub Discussion: App Router + RSC compatibility](https://github.com/reduxjs/redux-toolkit/discussions/3786) — HIGH confidence (official repo)
- [Next.js Official: Authentication Guide](https://nextjs.org/docs/app/guides/authentication) — HIGH confidence (official docs)
- [Next.js Official: Project Structure](https://nextjs.org/docs/app/getting-started/project-structure) — HIGH confidence (official docs)
- [Next.js Official: Caching Guide (staleTimes)](https://nextjs.org/docs/app/guides/caching) — HIGH confidence (official docs)
- [CVE-2025-29927 Datadog Analysis](https://securitylabs.datadoghq.com/articles/nextjs-middleware-auth-bypass/) — HIGH confidence (security advisory)
- [FastAPI CORS Documentation](https://fastapi.tiangolo.com/tutorial/cors/) — HIGH confidence (official FastAPI docs)
- [TanStack Query: Comparison (vs RTK Query)](https://tanstack.com/query/v5/docs/react/comparison) — HIGH confidence (official TanStack docs)
- [Existing codebase: backend/app/core/security.py](../../../backend/app/core/security.py) — HIGH confidence (direct inspection)
- [Existing codebase: backend/app/features/auth/models.py](../../../backend/app/features/auth/models.py) — HIGH confidence (direct inspection)
- [Existing codebase: backend/app/main.py](../../../backend/app/main.py) — HIGH confidence (direct inspection — CORS already env-var driven)

---
*Architecture research for: ContractorHub v2.0 — Next.js Web Admin Dashboard integrating with FastAPI + Flutter mobile platform*
*Researched: 2026-03-15*
