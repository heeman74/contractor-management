# Phase 13: Web Foundation and Auth - Research

**Researched:** 2026-03-15
**Domain:** Next.js 16 App Router, httpOnly cookie auth, FastAPI dual-auth, Redux Toolkit SSR, TanStack Query, shadcn/ui
**Confidence:** HIGH

<user_constraints>
## User Constraints (from CONTEXT.md)

### Locked Decisions

**Dashboard layout**
- Fixed sidebar with collapse toggle — expanded (240px with icons + labels) and collapsed (64px icon-only mini sidebar)
- Dark sidebar background (slate/gray-900), light content area
- Sidebar collapse state persisted to localStorage across sessions
- Flat module list (no section groupings) with divider before user menu at bottom
- Active nav item uses filled background accent highlight
- Module order by workflow frequency: Dashboard > Jobs > Schedule > Quotes > Invoices > Clients > Contractors > Reports
- Lucide icons for all module nav items (shadcn/ui default)

**Topbar**
- Left side: breadcrumb trail (Dashboard > Jobs > Job #1042)
- Right side: company name + user avatar dropdown (profile, logout)

**Login page**
- Split-screen layout: left panel with blue gradient (indigo-600 to blue-500) + ContractorHub branding/tagline, right panel with login form
- Login errors displayed as inline red alert banner above the form fields, clears on next attempt
- Client-side validation errors shown inline per field (red text below each invalid field)
- "Forgot password?" link shown but stubbed — displays "Contact your admin" or "Coming soon" when clicked
- Show password toggle (eye icon) in the password field
- Sign In button: disables + shows spinner + text changes to "Signing in..." during auth request
- After successful login: always redirect to dashboard home

**Dashboard home**
- Top row: KPI summary cards — Active Jobs, Pending Quotes, Overdue Invoices, Today's Schedule count
- KPI cards are clickable — each links to its respective module page
- Below cards: recent activity feed showing last 10 items (new job requests, status changes, payments)
- Real API data from existing backend endpoints (not placeholder/mock data)

**Error handling**
- Global errors (server, network): toast notifications in bottom-right corner (shadcn/ui Sonner)
  - Success toasts auto-dismiss after 5 seconds
  - Error toasts persist until manually dismissed
- Session expiry (401): silent token refresh attempt first, redirect to /login with "Session expired" message only on refresh failure
- Form validation: inline per-field error messages (red text below field)
- Custom branded 404 and 500 error pages with "Go to Dashboard" button

**Loading states**
- Skeleton screens for data loading (shadcn/ui Skeleton component) — shapes match real content layout
- NProgress-style thin top progress bar for route transitions between pages
- Both combined: top bar for instant route feedback + skeletons for content placeholder

**Responsive behavior**
- Desktop-first admin tool
- Desktop (>1024px): full expanded sidebar + content
- Tablet (768-1024px): auto-collapse to mini sidebar + content
- Mobile (<768px): hamburger button triggers sidebar as overlay/drawer

**Color and theme**
- Primary accent: blue (indigo/blue-600) — buttons, active states, links, interactive elements
- Status badges use semantic colors: green (active/paid/approved), yellow (pending/in-progress), red (overdue/declined), blue (scheduled/sent), gray (draft)

**State management**
- TanStack Query owns all server/API state
- Redux Toolkit owns client UI state only (sidebar, filters, auth display metadata)
- Redux makeStore factory pattern (never module-level singleton) to prevent cross-request tenant data leakage in SSR

**Token storage**
- Tokens stored in httpOnly cookies via Next.js Route Handler proxy — never localStorage

**Backend**
- Backend changes are additive-only — no existing Pydantic fields renamed or removed (protects mobile app)

### Claude's Discretion
- Exact skeleton screen shapes per page
- Exact spacing, typography scale, and component sizing
- NProgress library choice vs custom implementation
- Exact Tailwind color values within the blue/indigo family
- Toast duration and animation details
- Breadcrumb truncation behavior for deep nesting

### Deferred Ideas (OUT OF SCOPE)
None — discussion stayed within phase scope
</user_constraints>

<phase_requirements>
## Phase Requirements

| ID | Description | Research Support |
|----|-------------|-----------------|
| AUTH-01 | Admin can log in with email and password via the web dashboard | Next.js Route Handler proxies POST /api/v1/auth/login to FastAPI; stores tokens in httpOnly cookies |
| AUTH-02 | Web session persists across browser refresh using httpOnly cookie tokens | httpOnly `access_token` + `refresh_token` cookies set by Route Handler; proxy.ts reads cookie on each request |
| AUTH-03 | Token refresh happens transparently without interrupting admin workflow | apiClient fetch wrapper catches 401, calls /api/auth/refresh Route Handler, retries original request with new token |
| AUTH-04 | Admin can log out and session is fully invalidated | /api/auth/logout Route Handler calls FastAPI logout (revokes refresh token family), then clears both cookies |
| AUTH-05 | Global sidebar navigation provides persistent access to all modules | Next.js App Router root layout with fixed sidebar component; active route from usePathname |
| AUTH-06 | User-friendly error messages display for auth, validation, conflict, and server errors | Sonner toast for global errors; react-hook-form for inline validation; apiClient normalizes error shapes |
</phase_requirements>

---

## Summary

Phase 13 builds the Next.js 16 web dashboard on top of the existing FastAPI backend. The central pattern is a **Route Handler proxy**: the Next.js app intercepts auth calls (login, refresh, logout), stores JWTs in httpOnly cookies inaccessible to JavaScript, and then forwards all other API requests to FastAPI by reading the access token from the cookie and attaching it as a Bearer header. This keeps the mobile app's existing Bearer token flow completely untouched.

The most important architectural decision is using Next.js 16's `proxy.ts` (formerly `middleware.ts`) for route guards that only check cookie *existence* (no database calls) to redirect unauthenticated users. Real token validation happens in the Route Handlers and server components. For client-side state, Redux Toolkit uses the `makeStore` factory pattern to guarantee per-request store isolation under SSR — a module-level singleton would leak tenant data across requests.

The biggest risk in this phase is the **FastAPI dual-auth change**: `get_current_user` currently only reads Bearer tokens. It must be extended to also read an `Authorization: Bearer` header that the Next.js Route Handler injects after reading the httpOnly cookie — the backend itself never sees the cookie. This is additive (no mobile breakage) and is the first task to implement.

**Primary recommendation:** Build backend dual-auth first (Plan 13-01), then scaffold Next.js (Plan 13-02), then implement the auth Route Handlers and apiClient (Plan 13-03), then build the UI shell (Plan 13-04).

---

## Standard Stack

### Core
| Library | Version | Purpose | Why Standard |
|---------|---------|---------|--------------|
| next | 16.1.6 (latest stable) | App framework — App Router, Route Handlers, proxy.ts, Server Components | Locked decision; confirmed stable on npmjs.com |
| react / react-dom | 19.2 (bundled with Next 16) | UI runtime | Shipped with Next.js 16 |
| typescript | 5.x (strict) | Type safety | Locked decision; Next 16 requires 5.1+ |
| tailwindcss | 4.x | Utility CSS | Locked decision; v4 uses `@import "tailwindcss"` not `@tailwind` directives |
| @tailwindcss/postcss | 4.x | PostCSS plugin for Tailwind v4 | Required by Tailwind v4 (replaces `tailwind.config.js` PostCSS setup) |
| @radix-ui / shadcn/ui | latest | Accessible component primitives | Locked decision; `npx shadcn@latest init -t next` |
| lucide-react | latest | Icon library | Locked decision (shadcn default) |
| @tanstack/react-query | 5.x | Server/API state | Locked decision; v5 only |
| @reduxjs/toolkit + react-redux | 2.x | Client UI state (sidebar, filters, auth metadata) | Locked decision; makeStore pattern required |
| sonner | latest (via shadcn) | Toast notifications | Locked decision; `npx shadcn@latest add sonner` |
| react-hook-form | 7.x | Form state + validation | Standard for forms in this stack; pairs with zod |
| zod | 3.x | Schema validation (forms + API response types) | De facto standard with react-hook-form |

### Supporting
| Library | Version | Purpose | When to Use |
|---------|---------|---------|-------------|
| nextjs-toploader | latest | NProgress-style thin top bar for route transitions | App Router doesn't expose router events; this library wraps that gap via `<Link>` interception |
| @hookform/resolvers | latest | Bridges zod schema → react-hook-form | Every form using zod validation |
| jose | 4.x or 5.x | JWT decode on server (no verification needed) | Decode access token in Route Handlers to extract user metadata for Redux hydration |
| clsx + tailwind-merge | latest | Conditional class composition | All components needing dynamic class logic |

### Alternatives Considered
| Instead of | Could Use | Tradeoff |
|------------|-----------|----------|
| nextjs-toploader | Custom NProgress wrapper | Custom requires a `CustomLink` wrapper and complex hook; nextjs-toploader handles it with zero config |
| react-hook-form + zod | Formik | react-hook-form is significantly faster (uncontrolled inputs); zod gives shared types between client and server |
| shadcn/ui Sonner | react-hot-toast | Sonner is the current shadcn recommendation; hot-toast requires separate install without shadcn integration |

**Installation:**
```bash
# In the web/ directory (new Next.js project)
npx create-next-app@latest web --typescript --eslint --app --tailwind --src-dir --use-npm
cd web
npx shadcn@latest init -t next
npx shadcn@latest add sonner skeleton button input label card avatar dropdown-menu breadcrumb separator
npm install @tanstack/react-query @tanstack/react-query-devtools
npm install @reduxjs/toolkit react-redux
npm install react-hook-form @hookform/resolvers zod
npm install nextjs-toploader
npm install clsx tailwind-merge lucide-react
```

---

## Architecture Patterns

### Recommended Project Structure
```
web/
├── src/
│   ├── app/
│   │   ├── (auth)/
│   │   │   └── login/
│   │   │       └── page.tsx          # Login page (unauthenticated route)
│   │   ├── (dashboard)/
│   │   │   ├── layout.tsx            # Root dashboard layout (sidebar + topbar)
│   │   │   ├── page.tsx              # Dashboard home (KPI cards + activity)
│   │   │   └── [module]/             # Stub pages for future phases
│   │   ├── api/
│   │   │   └── auth/
│   │   │       ├── login/route.ts    # POST — proxies to FastAPI, sets cookies
│   │   │       ├── refresh/route.ts  # POST — exchanges refresh token, rotates cookies
│   │   │       └── logout/route.ts   # POST — revokes family, clears cookies
│   │   ├── error.tsx                 # Global error boundary (500)
│   │   ├── not-found.tsx             # Custom 404 page
│   │   └── layout.tsx                # Root layout (providers, Toaster)
│   ├── components/
│   │   ├── layout/
│   │   │   ├── sidebar.tsx           # Collapsible sidebar (desktop + drawer)
│   │   │   ├── topbar.tsx            # Breadcrumbs + user menu
│   │   │   └── dashboard-shell.tsx   # Combines sidebar + topbar + content
│   │   ├── ui/                       # shadcn/ui generated components
│   │   └── shared/                   # Status badges, page headers, etc.
│   ├── lib/
│   │   ├── api-client.ts             # fetch wrapper: reads cookie → Bearer, 401 retry
│   │   ├── auth.ts                   # Server-only: decode token from cookie, get user
│   │   └── utils.ts                  # cn() helper (clsx + tailwind-merge)
│   ├── store/
│   │   ├── index.ts                  # makeStore factory + type exports
│   │   ├── provider.tsx              # StoreProvider client component
│   │   └── slices/
│   │       ├── ui-slice.ts           # sidebarCollapsed, activeModule
│   │       └── auth-slice.ts         # displayName, companyId, roles (display metadata)
│   └── types/
│       └── api.ts                    # TypeScript types matching backend schemas
├── proxy.ts                          # Auth guard (cookie existence check → redirect)
├── next.config.ts
├── tailwind.css (or globals.css)
└── package.json
```

### Pattern 1: Route Handler as Auth Proxy
**What:** Next.js Route Handlers intercept auth calls, call FastAPI, then store tokens in httpOnly cookies. All subsequent API calls read the cookie and inject `Authorization: Bearer` before proxying to FastAPI.
**When to use:** Every auth endpoint. The browser NEVER directly calls FastAPI for auth.

```typescript
// Source: https://nextjs.org/docs/app/api-reference/functions/cookies
// web/src/app/api/auth/login/route.ts
import { cookies } from "next/headers";
import { NextRequest, NextResponse } from "next/server";

const FASTAPI_BASE = process.env.FASTAPI_URL ?? "http://localhost:8000";

export async function POST(req: NextRequest) {
  const body = await req.json();

  const resp = await fetch(`${FASTAPI_BASE}/api/v1/auth/login`, {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify(body),
  });

  if (!resp.ok) {
    const err = await resp.json();
    return NextResponse.json(err, { status: resp.status });
  }

  const data = await resp.json();
  const cookieStore = await cookies();

  const isProd = process.env.NODE_ENV === "production";

  cookieStore.set("access_token", data.access_token, {
    httpOnly: true,
    secure: isProd,
    sameSite: "lax",
    path: "/",
    maxAge: 15 * 60,            // 15 minutes — matches FastAPI access token expiry
  });

  cookieStore.set("refresh_token", data.refresh_token, {
    httpOnly: true,
    secure: isProd,
    sameSite: "lax",
    path: "/api/auth/refresh",   // Scope refresh token to refresh endpoint only
    maxAge: 30 * 24 * 60 * 60,  // 30 days
  });

  // Return user metadata (NOT tokens) for Redux auth-slice hydration
  return NextResponse.json({
    user_id: data.user_id,
    company_id: data.company_id,
    roles: data.roles,
  });
}
```

### Pattern 2: API Client with 401 Retry (Token Refresh)
**What:** A fetch wrapper that reads the access token cookie on the server or calls the refresh Route Handler on the client, retries once on 401.
**When to use:** Every API call from server components or client components.

```typescript
// Source: https://nextjs.org/docs/app/api-reference/functions/cookies
// web/src/lib/api-client.ts  (client-side version)
export async function apiClient<T>(
  path: string,
  init?: RequestInit,
  retry = true,
): Promise<T> {
  const resp = await fetch(`/api/proxy?path=${encodeURIComponent(path)}`, init);

  if (resp.status === 401 && retry) {
    // Attempt silent refresh
    const refreshResp = await fetch("/api/auth/refresh", { method: "POST" });
    if (!refreshResp.ok) {
      // Refresh failed — redirect to login
      window.location.href = "/login?reason=session_expired";
      throw new Error("Session expired");
    }
    // Retry original request once
    return apiClient<T>(path, init, false);
  }

  if (!resp.ok) {
    const err = await resp.json().catch(() => ({ detail: "Unknown error" }));
    throw new ApiError(resp.status, err.detail ?? "Request failed");
  }

  return resp.json() as Promise<T>;
}
```

### Pattern 3: proxy.ts Auth Guard (Optimistic Cookie Check)
**What:** Next.js 16 `proxy.ts` (renamed from `middleware.ts`) checks for cookie EXISTENCE only — no DB calls, no JWT decoding. Redirect unauthenticated requests to /login.
**When to use:** All protected routes. Real validation happens in Route Handlers and server components.

```typescript
// Source: https://nextjs.org/blog/next-16
// web/proxy.ts  (NOTE: Next.js 16 renamed middleware.ts → proxy.ts)
import { NextRequest, NextResponse } from "next/server";

const PUBLIC_ROUTES = ["/login", "/api/auth/login", "/api/auth/refresh"];

export default function proxy(request: NextRequest) {
  const { pathname } = request.nextUrl;

  const isPublic = PUBLIC_ROUTES.some(
    (r) => pathname === r || pathname.startsWith(r + "/"),
  );

  if (isPublic) return NextResponse.next();

  const hasSession = request.cookies.has("access_token");

  if (!hasSession) {
    const loginUrl = new URL("/login", request.url);
    loginUrl.searchParams.set("redirectTo", pathname);
    return NextResponse.redirect(loginUrl);
  }

  return NextResponse.next();
}

export const config = {
  matcher: ["/((?!_next/static|_next/image|favicon.ico).*)"],
};
```

### Pattern 4: Redux makeStore (SSR-Safe, Per-Request Store)
**What:** Export a `makeStore` factory function, never a singleton store. Use `useRef` in a client StoreProvider to create one instance per component tree.
**When to use:** Required by Redux Toolkit official Next.js App Router docs. Prevents cross-request tenant data leakage.

```typescript
// Source: https://redux-toolkit.js.org/usage/nextjs
// web/src/store/index.ts
import { configureStore } from "@reduxjs/toolkit";
import uiReducer from "./slices/ui-slice";
import authReducer from "./slices/auth-slice";

export const makeStore = () =>
  configureStore({
    reducer: {
      ui: uiReducer,
      auth: authReducer,
    },
  });

export type AppStore = ReturnType<typeof makeStore>;
export type RootState = ReturnType<AppStore["getState"]>;
export type AppDispatch = AppStore["dispatch"];

// web/src/store/provider.tsx
"use client";
import { useRef } from "react";
import { Provider } from "react-redux";
import { makeStore, AppStore } from "./index";

export function StoreProvider({ children }: { children: React.ReactNode }) {
  const storeRef = useRef<AppStore>(undefined);
  if (!storeRef.current) {
    storeRef.current = makeStore();
  }
  return <Provider store={storeRef.current}>{children}</Provider>;
}
```

### Pattern 5: FastAPI Dual-Auth (Cookie + Bearer) — Additive Extension
**What:** Extend `get_current_user` in `security.py` to check `Authorization: Bearer` header first (existing behavior, mobile), then fall back to an `access_token` cookie. In practice the Next.js proxy always sends a Bearer header derived from the cookie, so the cookie fallback is available but the primary path remains Bearer.
**When to use:** Backend Plan 13-01. Must be additive — the existing `HTTPBearer` scheme stays for mobile.

```python
# Source: https://fastapi.tiangolo.com/advanced/response-cookies/
# backend/app/core/security.py (extension only — existing code unchanged)
from fastapi import Cookie

async def get_current_user(
    credentials: HTTPAuthorizationCredentials | None = Depends(_bearer_scheme),
    access_token_cookie: str | None = Cookie(default=None, alias="access_token"),
    db: AsyncSession = Depends(get_db),
) -> CurrentUser:
    # Bearer takes priority (mobile clients); cookie is web fallback
    raw_token = (credentials.credentials if credentials else None) or access_token_cookie

    if raw_token is None:
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Not authenticated",
            headers={"WWW-Authenticate": "Bearer"},
        )
    # ... rest of existing validation logic unchanged ...
```

### Anti-Patterns to Avoid
- **Module-level Redux store singleton:** `export const store = configureStore(...)` in a shared module. In Next.js SSR this store persists across requests and leaks data between tenants. Always use `makeStore`.
- **Storing tokens in localStorage or Redux:** Any JavaScript-accessible storage exposes tokens to XSS. Tokens belong exclusively in httpOnly cookies, set only by server-side Route Handlers.
- **database/JWT validation in proxy.ts:** `proxy.ts` runs on every request including prefetches. Only check cookie existence. Full validation happens in server components and Route Handlers.
- **Sending cookies directly to FastAPI from the browser:** The FastAPI CORS config allows credentials, but the mobile app doesn't use cookies. The Next.js proxy pattern keeps FastAPI using Bearer tokens throughout, protecting the mobile integration.
- **Using `middleware.ts` filename in Next.js 16:** Next.js 16 renamed this to `proxy.ts` with a `proxy` export. `middleware.ts` still works but is deprecated. New projects must use `proxy.ts`.
- **Async `cookies()` without `await` in Next.js 16:** `cookies()`, `headers()`, and `params` are all async in Next.js 16. Missing `await` is a silent bug.

---

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| Toast notifications | Custom toast state + component | shadcn/ui Sonner | Handles queuing, stacking, animation, a11y, persistence, portal mounting |
| Form validation | Manual `onChange` state + error messages | react-hook-form + zod | Performance (uncontrolled inputs), async validation, error focus management, type inference |
| Route transition progress bar | Custom router event subscription | nextjs-toploader | App Router doesn't expose router events; this library uses `<Link>` override and MutationObserver |
| JWT decode | Manual base64 parse | `jose` library `decodeJwt()` | Handles edge cases (padding, encoding variants), type-safe |
| Accessible dropdown/dialog | Custom focus trap + keyboard nav | shadcn/ui (Radix primitives) | ARIA, keyboard nav, portal rendering, screen reader tested |
| Responsive sidebar drawer | Custom overlay + transition | shadcn/ui Sheet | Focus trap, scroll lock, a11y, animation |
| Class merging | Manual string concat | `clsx` + `tailwind-merge` via `cn()` | Handles Tailwind class conflicts (e.g., `bg-red-500` overriding `bg-blue-500`) |

**Key insight:** The shadcn/ui + Radix primitive stack handles all accessibility complexity. Every "I'll just build a simple X" in UI components grows into a 200-line accessibility bug.

---

## Common Pitfalls

### Pitfall 1: Stale Access Token in Cookie After Rotation
**What goes wrong:** The refresh Route Handler issues new tokens, but the `access_token` cookie set with `path: "/"` is updated correctly while an old copy cached by the browser causes 401 loops.
**Why it happens:** Cookie `maxAge` of 15 min doesn't guarantee the browser sends the freshest value if there are duplicate cookies at different paths.
**How to avoid:** Set `access_token` cookie with `path: "/"` always. Never set the same cookie name at multiple paths. Use `cookieStore.set()` to overwrite, not `cookieStore.append()`.
**Warning signs:** Infinite redirect loop between `/login` and dashboard in the browser.

### Pitfall 2: CORS Credentials with Wildcard Origin
**What goes wrong:** FastAPI CORS middleware rejects requests from the Next.js web app because `allow_credentials=True` is incompatible with `allow_origins=["*"]`.
**Why it happens:** CORS spec forbids credentials with wildcard origin.
**How to avoid:** The web app origin (e.g., `http://localhost:3000`) MUST be in the `CORS_ORIGINS` env var. The existing `config.py` already supports `cors_origins` as a comma-separated env var — just add the web origin.
**Warning signs:** Browser console shows "Access-Control-Allow-Origin does not match" or credentials-related CORS error.

### Pitfall 3: Redux Singleton in SSR (Tenant Data Leakage)
**What goes wrong:** A module-level `configureStore()` call creates one store shared across all server requests, so tenant A's data appears in tenant B's dashboard.
**Why it happens:** Node.js module cache persists between requests; the store is only initialized once.
**How to avoid:** Always use `makeStore` factory + `useRef` in `StoreProvider`. Never `export const store = configureStore(...)` at module level.
**Warning signs:** Wrong company name or data shown after switching tenants.

### Pitfall 4: `middleware.ts` vs `proxy.ts` in Next.js 16
**What goes wrong:** Creating `middleware.ts` with `export default function middleware()` works but gets a deprecation warning. If the project is on a Next.js version that enforces `proxy.ts`, auth guards silently stop running.
**Why it happens:** Next.js 16 renamed the file. The `middleware.ts` filename is still processed but deprecated.
**How to avoid:** Create `proxy.ts` at the project root with `export default function proxy()`.
**Warning signs:** Deprecation warnings in `next dev` output.

### Pitfall 5: Async `cookies()` / `headers()` in Next.js 16
**What goes wrong:** `const cookieStore = cookies()` (without `await`) returns a promise object instead of the cookie store. `cookieStore.set()` silently does nothing or throws at runtime.
**Why it happens:** Next.js 16 made these functions async (they returned sync previously in 14/15 with a deprecation warning; in 16 the sync form is removed).
**How to avoid:** Always `const cookieStore = await cookies()`.
**Warning signs:** Cookies not being set after login; auth state not persisting.

### Pitfall 6: Refresh Token Cookie Path Scope
**What goes wrong:** Refresh token cookie is accessible on all routes, allowing any Route Handler to accidentally read it.
**Why it happens:** Default cookie path is `/`.
**How to avoid:** Set `path: "/api/auth/refresh"` on the refresh token cookie. Only the refresh Route Handler can read it. The access token cookie stays at `path: "/"`.
**Warning signs:** Accidental refresh token exposure in unrelated Route Handlers.

### Pitfall 7: TanStack Query Hydration Mismatch with Server Components
**What goes wrong:** Server component prefetches data with `dehydrate(queryClient)`, but the client component uses a different query key, causing a double-fetch or hydration error.
**Why it happens:** Query key inconsistency between server prefetch and client `useQuery` call.
**How to avoid:** Extract query key constants into a shared file (e.g., `queryKeys.ts`). Use identical keys on both server and client.
**Warning signs:** DevTools shows queries fetching twice on page load.

---

## Code Examples

Verified patterns from official sources:

### Tailwind v4 Global CSS Import
```css
/* Source: https://tailwindcss.com/blog/tailwindcss-v4 */
/* web/src/app/globals.css */
@import "tailwindcss";

/* Theme customization (replaces tailwind.config.js extend.colors) */
@theme {
  --color-primary: theme(colors.indigo.600);
}
```

### shadcn/ui Sonner Setup in Root Layout
```typescript
// Source: https://ui.shadcn.com/docs/components/radix/sonner
// web/src/app/layout.tsx
import { Toaster } from "@/components/ui/sonner";

export default function RootLayout({ children }: { children: React.ReactNode }) {
  return (
    <html lang="en">
      <body>
        <StoreProvider>
          <QueryProvider>
            {children}
          </QueryProvider>
        </StoreProvider>
        <Toaster position="bottom-right" richColors />
      </body>
    </html>
  );
}
```

### TanStack Query Provider (Client Component)
```typescript
// Source: https://tanstack.com/query/v5/docs/react/guides/ssr
// web/src/components/providers/query-provider.tsx
"use client";
import { QueryClient, QueryClientProvider } from "@tanstack/react-query";
import { ReactQueryDevtools } from "@tanstack/react-query-devtools";
import { useState } from "react";

export function QueryProvider({ children }: { children: React.ReactNode }) {
  const [queryClient] = useState(
    () =>
      new QueryClient({
        defaultOptions: {
          queries: {
            staleTime: 60 * 1000,      // 60 seconds
            retry: 1,
          },
        },
      }),
  );

  return (
    <QueryClientProvider client={queryClient}>
      {children}
      <ReactQueryDevtools initialIsOpen={false} />
    </QueryClientProvider>
  );
}
```

### cn() Utility (Required by All Components)
```typescript
// Source: shadcn/ui convention
// web/src/lib/utils.ts
import { clsx, type ClassValue } from "clsx";
import { twMerge } from "tailwind-merge";

export function cn(...inputs: ClassValue[]) {
  return twMerge(clsx(inputs));
}
```

### Alembic Migration Template for client_type
```python
# Source: existing backend migration pattern
# backend/migrations/versions/0012_add_client_type_to_users.py
"""Add client_type to users for web vs mobile session tracking."""
from alembic import op
import sqlalchemy as sa

revision = "0012"
down_revision = "0011_business_operations_tables"
branch_labels = None
depends_on = None

def upgrade() -> None:
    op.add_column(
        "users",
        sa.Column(
            "client_type",
            sa.String(),
            nullable=True,
            comment="Session origin: 'web' or 'mobile'. Nullable for historical records.",
        ),
    )

def downgrade() -> None:
    op.drop_column("users", "client_type")
```

---

## State of the Art

| Old Approach | Current Approach | When Changed | Impact |
|--------------|------------------|--------------|--------|
| `middleware.ts` / `export default function middleware()` | `proxy.ts` / `export default function proxy()` | Next.js 16 (Oct 2025) | Must use new filename; `middleware.ts` deprecated |
| `@tailwind base; @tailwind components; @tailwind utilities` directives | `@import "tailwindcss"` single line | Tailwind v4 (Jan 2025) | Simpler config; `tailwind.config.js` optional (use `@theme` in CSS) |
| Sync `cookies()` / `headers()` | `await cookies()` / `await headers()` | Next.js 15→16 | Missing `await` is a runtime bug in Next.js 16 |
| `experimental.turbopack: true` | Turbopack enabled by default | Next.js 16 | No config needed; opt-out with `--webpack` |
| `experimental.ppr` flag | `cacheComponents: true` | Next.js 16 | PPR flag removed; new Cache Components model |
| `next/nprogress-bar` | `nextjs-toploader` | 2025 | `next-nprogress-bar` unmaintained; migrate to `@bprogress/next` or `nextjs-toploader` |

**Deprecated/outdated:**
- `next-nprogress-bar`: Officially unmaintained; migrate to `@bprogress/next` or `nextjs-toploader`
- `tailwind.config.js` with `content` array: Still works but unnecessary with Tailwind v4 (uses CSS-based config via `@theme`)
- Sync `cookies()`/`headers()` calls without `await`: Removed in Next.js 16

---

## Open Questions

1. **Exact latest patch version of Next.js 16**
   - What we know: 16.1.6 confirmed as latest stable (search result from npmjs.com, Feb 2026)
   - What's unclear: Whether 16.2.x canary has any bugs that affect cookie handling in Route Handlers
   - Recommendation: Pin to `next@16.1.6` in `package.json` for stability; upgrade after phase ships

2. **FastAPI `client_type` column scope**
   - What we know: CONTEXT.md says "Users model may need `client_type` field to distinguish web vs mobile sessions"
   - What's unclear: Whether `client_type` is populated at login time (service layer) or at token creation time
   - Recommendation: Add as nullable String column in migration 0012; set to `'web'` in `AuthService.login()` when `client_type` is passed in request; mobile keeps sending no `client_type` (stays NULL) — additive only

3. **CORS origin for production web app**
   - What we know: `CORS_ORIGINS` env var accepts comma-separated origins; `allow_credentials=True` already set
   - What's unclear: Production domain for the web app is not yet defined
   - Recommendation: Add `http://localhost:3000` to `CORS_ORIGINS` for dev; document that production URL must be added to env var before deploy

---

## Validation Architecture

### Test Framework
| Property | Value |
|----------|-------|
| Framework | pytest (backend) + Playwright (web E2E) |
| Config file | `backend/pytest.ini` (existing) / `web/playwright.config.ts` (Wave 0) |
| Quick run command (backend) | `cd backend && uv run python -m pytest tests/integration/test_phase_13_e2e.py -x` |
| Full suite command (backend) | `cd backend && uv run python -m pytest` |
| Quick run command (web E2E) | `cd web && npx playwright test --project=chromium` |
| Full suite command (web E2E) | `cd web && npx playwright test` |

### Phase Requirements → Test Map
| Req ID | Behavior | Test Type | Automated Command | File Exists? |
|--------|----------|-----------|-------------------|-------------|
| AUTH-01 | POST /api/v1/auth/login returns 200 with token pair | integration | `uv run python -m pytest tests/integration/test_phase_13_e2e.py::test_login_success -x` | ❌ Wave 0 |
| AUTH-01 | Login page submits credentials and redirects to dashboard | E2E (Playwright) | `npx playwright test --grep "login success"` | ❌ Wave 0 |
| AUTH-02 | Session persists after browser refresh (cookie present) | E2E (Playwright) | `npx playwright test --grep "session persists"` | ❌ Wave 0 |
| AUTH-03 | 401 triggers silent refresh + retry without user interruption | E2E (Playwright) | `npx playwright test --grep "transparent refresh"` | ❌ Wave 0 |
| AUTH-03 | Refresh endpoint rotates tokens and revokes old family | integration | `uv run python -m pytest tests/integration/test_phase_13_e2e.py::test_token_refresh -x` | ❌ Wave 0 |
| AUTH-04 | POST /api/v1/auth/logout revokes refresh token family | integration | `uv run python -m pytest tests/integration/test_phase_13_e2e.py::test_logout -x` | ❌ Wave 0 |
| AUTH-04 | After logout, protected pages redirect to /login | E2E (Playwright) | `npx playwright test --grep "logout redirect"` | ❌ Wave 0 |
| AUTH-05 | Sidebar renders on all dashboard routes | E2E (Playwright) | `npx playwright test --grep "sidebar visible"` | ❌ Wave 0 |
| AUTH-05 | Sidebar collapse toggles and persists to localStorage | E2E (Playwright) | `npx playwright test --grep "sidebar collapse"` | ❌ Wave 0 |
| AUTH-06 | Invalid login shows inline error banner | E2E (Playwright) | `npx playwright test --grep "login error"` | ❌ Wave 0 |
| AUTH-06 | Server error shows toast notification | E2E (Playwright) | `npx playwright test --grep "toast error"` | ❌ Wave 0 |

### Sampling Rate
- **Per task commit:** `cd backend && uv run python -m pytest tests/integration/test_phase_13_e2e.py -x`
- **Per wave merge:** `cd backend && uv run python -m pytest && cd web && npx playwright test --project=chromium`
- **Phase gate:** Full suite green before `/gsd:verify-work`

### Wave 0 Gaps
- [ ] `backend/tests/integration/test_phase_13_e2e.py` — covers AUTH-01 backend login, AUTH-03 token refresh, AUTH-04 logout/revocation
- [ ] `web/playwright.config.ts` — Playwright config pointing to `http://localhost:3000`
- [ ] `web/tests/auth.spec.ts` — Playwright E2E tests for AUTH-01 through AUTH-06 login/session/logout flows
- [ ] `web/tests/layout.spec.ts` — Playwright tests for AUTH-05 sidebar visibility, collapse, persistence
- [ ] Playwright install: `cd web && npx playwright install chromium` — required before E2E tests run

---

## Sources

### Primary (HIGH confidence)
- https://nextjs.org/blog/next-16 — Official Next.js 16 release blog; confirmed `proxy.ts` rename, async cookies, breaking changes, version details
- https://redux-toolkit.js.org/usage/nextjs — Official Redux Toolkit Next.js guide; confirmed `makeStore` factory pattern
- https://tanstack.com/query/v5/docs/react/guides/ssr — Official TanStack Query v5 SSR docs; HydrationBoundary + dehydrate pattern
- https://ui.shadcn.com/docs/components/radix/sonner — Official shadcn/ui Sonner docs; install command and Toaster placement
- https://tailwindcss.com/blog/tailwindcss-v4 — Official Tailwind v4 release; `@import "tailwindcss"` replaces directives
- https://nextjs.org/docs/app/api-reference/functions/cookies — Official Next.js cookies() async API reference

### Secondary (MEDIUM confidence)
- https://www.npmjs.com/package/next — npmjs.com confirmed 16.1.6 as latest stable (reported via search result, Feb 2026)
- https://workos.com/blog/nextjs-app-router-authentication-guide-2026 — WorkOS auth guide for Next.js App Router 2026; httpOnly cookie pattern details
- https://github.com/TheSGJ/nextjs-toploader — nextjs-toploader library GitHub; confirmed works with Next.js 15+ (16 compatible)

### Tertiary (LOW confidence)
- Search results indicating `next-nprogress-bar` is unmaintained — not verified against official repository; treat as signal to verify before use

---

## Metadata

**Confidence breakdown:**
- Standard stack: HIGH — versions confirmed via official release notes and npmjs.com
- Architecture: HIGH — proxy pattern from official Next.js docs; makeStore from official Redux docs; cookie APIs from official Next.js reference
- Pitfalls: HIGH — `proxy.ts` rename and async cookies confirmed from official Next.js 16 release blog; CORS pitfall from existing backend code review
- FastAPI dual-auth: HIGH — existing `security.py` code reviewed directly; extension pattern is minimal and additive

**Research date:** 2026-03-15
**Valid until:** 2026-04-15 (Next.js 16.x stable; Tailwind v4 stable — these are not fast-moving during patch releases)
