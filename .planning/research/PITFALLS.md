# Pitfalls Research

**Domain:** Adding Next.js web admin dashboard to existing FastAPI + Flutter mobile platform (ContractorHub v2.0)
**Researched:** 2026-03-14
**Confidence:** HIGH (security/auth pitfalls from official CVE disclosures and FastAPI docs; SSR/Redux from official RTK docs and GitHub issues; integration risks from existing codebase analysis)

---

## Critical Pitfalls

### Pitfall 1: Storing JWT Access Tokens in localStorage — XSS Attack Surface

**What goes wrong:**
The web dashboard stores the JWT access token in `localStorage` or `sessionStorage` for convenience. Any third-party script (analytics, a compromised npm dependency, a future XSS vulnerability) can read `localStorage` from JavaScript and exfiltrate the token. An attacker who obtains the access token can impersonate any admin with full company data access including all RLS-scoped records.

**Why it happens:**
localStorage is the first instinct — it persists across tabs, survives page refresh, and is trivial to read/write. Tutorials and quick-start examples almost universally use it. Secure storage (httpOnly cookies) requires server-side involvement that feels like overhead.

**How to avoid:**
Store the access token in a `httpOnly`, `Secure`, `SameSite=Lax` cookie, never in JavaScript-accessible storage. The FastAPI backend must expose a `/auth/web/login` endpoint (or extend existing `/auth/login`) that sets the cookie in the response. The refresh token similarly goes in a separate `httpOnly` cookie with a tighter path (e.g., `Path=/auth/refresh`). Since the mobile app uses Bearer tokens in headers, the backend must support BOTH patterns simultaneously — cookie-based for web, header-based for mobile — using a single auth verification function that checks the cookie first, then falls back to the `Authorization` header.

**Warning signs:**
- `localStorage.setItem('access_token', ...)` anywhere in the Next.js codebase
- Redux auth slice persisted to `localStorage` via `redux-persist` without token exclusion
- Login response stores token client-side in any JavaScript-accessible location

**Phase to address:**
Phase 1: Web Authentication — must be the foundational decision before any other feature code touches auth.

---

### Pitfall 2: CORS Wildcard + allow_credentials Breaks Mobile and Blocks Web

**What goes wrong:**
A developer adds `CORSMiddleware` to FastAPI for the web dashboard and uses `allow_origins=["*"]` with `allow_credentials=True`. This configuration is invalid per the CORS spec and FastAPI will reject it — credentialed requests require explicit origin enumeration. Attempting to fix this by setting `allow_origins=["*"]` without credentials allows the web to work but silently breaks the mobile app's ability to send `Authorization` headers on preflight. Alternatively, over-restricting origins to only the web domain blocks mobile API calls.

**Why it happens:**
The existing FastAPI backend may have no CORS configuration (mobile apps are not browser clients and don't send CORS preflight). The developer adds CORS for the web without understanding that mobile clients using `Authorization: Bearer` headers are also affected by CORS validation if they ever reach a browser-mediated context, or without testing that the existing mobile app still functions correctly after the CORS change.

**How to avoid:**
Configure `CORSMiddleware` with explicit, environment-specific allowed origins — never wildcards when credentials are involved. The `allow_origins` list must include the web dashboard origin (`https://admin.contractorhub.com` for production, `http://localhost:3000` for dev) but mobile apps do not send CORS preflights (they are native clients, not browsers). Set `allow_credentials=True`, enumerate `allow_headers` explicitly (`["Authorization", "Content-Type", "X-Request-ID"]`). Test the mobile app against the updated API before shipping.

```python
# CORRECT
app.add_middleware(
    CORSMiddleware,
    allow_origins=settings.CORS_ORIGINS,   # ["https://admin.contractorhub.com"]
    allow_credentials=True,
    allow_methods=["GET", "POST", "PUT", "PATCH", "DELETE"],
    allow_headers=["Authorization", "Content-Type", "X-Request-ID"],
)

# WRONG — will be rejected by browsers
allow_origins=["*"], allow_credentials=True
```

**Warning signs:**
- `allow_origins=["*"]` in any CORS configuration where `allow_credentials=True`
- CORS origins hardcoded to a single environment's URL
- No test that verifies the mobile app's auth flow still works after CORS changes

**Phase to address:**
Phase 1: Web Authentication — CORS must be configured correctly before any web feature calls the API.

---

### Pitfall 3: Next.js Middleware Auth Bypass (CVE-2025-29927)

**What goes wrong:**
The team implements authentication guards in Next.js middleware (`middleware.ts`) — the standard pattern for protecting routes in the App Router. An attacker sends requests with the `x-middleware-subrequest` header, bypassing all middleware logic. Every protected admin page is accessible without a valid token. All company data is exposed.

**Why it happens:**
CVE-2025-29927 (CVSS 9.1) affects all Next.js versions below 12.3.5 / 13.5.9 / 14.2.25 / 15.2.3. Self-hosted deployments using `next start` or the `standalone` output are vulnerable. Developers rely on middleware as the single auth enforcement point, not realizing it can be bypassed at the infrastructure level.

**How to avoid:**
Two mitigations, both required:
1. Use Next.js 15.2.3+ (patched). Pin the version in `package.json` with an exact version or `>=15.2.3`.
2. Do not rely solely on Next.js middleware for auth enforcement. Every API call from server components and route handlers must independently verify the session by calling the FastAPI backend. Middleware is a UI redirect convenience layer, not a security boundary.

If using a load balancer (nginx, Caddy), add a rule to strip any incoming `x-middleware-subrequest` header before it reaches Next.js.

**Warning signs:**
- Next.js version below 15.2.3 in `package.json`
- Auth logic exists only in `middleware.ts` with no server-side token verification in individual route handlers
- No Dependabot or automated security scanning on the `web/` directory

**Phase to address:**
Phase 1: Web Authentication — version pinning and defense-in-depth auth must be established before any routes are protected.

---

### Pitfall 4: Redux Store as SSR Singleton — Cross-Request State Pollution

**What goes wrong:**
The Redux store is created as a module-level singleton (`const store = configureStore(...)`). On the server side, Next.js runs multiple requests concurrently in the same Node.js process. User A's auth state bleeds into User B's server-rendered page. In the best case, pages render with wrong data. In a multi-tenant SaaS, in the worst case, admin from Company A sees Company B's dashboard data in their server-rendered HTML.

**Why it happens:**
React apps in client-only mode use a single store per browser tab — the singleton pattern is correct there. The same pattern copy-pasted into a Next.js App Router setup shares that singleton across all server-side renders in the process.

**How to avoid:**
Follow the RTK official Next.js pattern exactly: export a `makeStore` factory function, not a store instance. Use RTK's `createStoreRef` / React context approach for App Router, or `next-redux-wrapper` for Pages Router. Never import the store directly into server components — pass data as props from server to client components.

```typescript
// CORRECT — factory pattern
export const makeStore = () => configureStore({ reducer: rootReducer });
export type AppStore = ReturnType<typeof makeStore>;

// WRONG — singleton
export const store = configureStore({ reducer: rootReducer }); // shared across all SSR requests
```

**Warning signs:**
- `export const store = configureStore(...)` at module level in `store.ts`
- Server components that `import { store } from '@/store'` directly
- No `makeStore` factory function in the codebase

**Phase to address:**
Phase 1: Web Foundation — store architecture must be set correctly from the first component, before any feature slices are added.

---

### Pitfall 5: Next.js Router Cache Serving Stale Auth Data After Logout

**What goes wrong:**
Admin logs out. The Next.js App Router has cached the dashboard page in its Router Cache (30-second TTL for dynamic routes, 5 minutes for static). The next user on the same browser session navigates back and sees the previous admin's dashboard — including company-specific data — from the client-side cache, without making a new server request.

**Why it happens:**
The Next.js App Router Router Cache is client-side and cannot be opted out of in older versions. It serves pages from memory without hitting the server during navigation. Developers test logout by redirecting to `/login` and assume the data is gone, but the back button or direct URL access can reveal cached content.

**How to avoid:**
Three complementary approaches:
1. Use Next.js 15+ where the Router Cache default staletime for dynamic routes is 0 (disabled by default). Set `staleTimes: { dynamic: 0 }` in `next.config.ts` for explicit control.
2. Call `router.refresh()` on logout to invalidate the router cache immediately.
3. Use cookie-based sessions — Next.js automatically invalidates Router Cache entries when cookies change (`cookies.delete()` on logout triggers cache invalidation).
4. Add `Cache-Control: no-store` headers on API responses that return sensitive tenant data.

**Warning signs:**
- Logout handler only redirects to `/login` without calling `router.refresh()`
- Next.js version below 15 with no `staleTimes` configuration
- Admin dashboard pages without `no-store` cache headers on their data fetches

**Phase to address:**
Phase 1: Web Authentication — logout flow must include cache invalidation from the start.

---

### Pitfall 6: Web Auth Flow Breaking Existing Mobile Refresh Token Family

**What goes wrong:**
The existing mobile app uses JWT refresh token rotation with family revocation (reuse detection). The web dashboard is added and uses the same `/auth/refresh` endpoint with `httpOnly` cookies instead of Bearer tokens. The refresh endpoint's family revocation logic, designed for a single active client, detects what looks like token reuse (two different clients holding refresh tokens from the same family) and invalidates all sessions — logging out all mobile users of that company when the web admin logs in, or vice versa.

**Why it happens:**
The backend refresh token model assumes one active refresh token per user (one active session). Adding a web client means the same user now has two legitimate sessions: one in the mobile app, one in the browser. If the token family logic uses a shared family ID per user (not per session), the second login triggers the reuse detection cascade.

**How to avoid:**
Extend the refresh token model before shipping web auth. Each session (mobile, web) must belong to an independent token family. Add a `session_id` or `client_type` field to the `refresh_tokens` table. Family revocation fires only within a family, not across all families for that user. Test the scenario: admin logs into web while contractor app is active — verify neither session is terminated.

**Warning signs:**
- `refresh_tokens` table without a `session_id` or `client_type` column
- Family revocation query uses `WHERE user_id = $1` without filtering by `family_id`
- No test that exercises simultaneous mobile + web active sessions for the same user

**Phase to address:**
Phase 1: Web Authentication — must audit and extend the refresh token model before the web login endpoint goes live.

---

### Pitfall 7: API Contract Changes Breaking Mobile Without Detection

**What goes wrong:**
The web admin dashboard requires richer responses from the API — more fields, different shapes, new relationships. A developer adds a new required field to a response schema, renames a field for web clarity, or changes a nullable field to required. The mobile app, which was not updated, silently receives null where it expects a string, causing crashes or data corruption in the Flutter Drift sync layer. The problem surfaces days or weeks later when a mobile user in the field experiences data loss.

**Why it happens:**
Web and mobile share the same FastAPI backend but are developed on different timelines. Without a shared contract test layer, changes to Pydantic response schemas are not validated against the mobile app's deserialization expectations. Flutter's `json_serializable` with `unknownEnumValue` / nullable handling may silently swallow missing fields rather than failing loudly.

**How to avoid:**
Adopt additive-only API changes as a strict rule:
- New response fields must be `Optional` with a default in Pydantic — never suddenly required
- Never rename existing fields — add a new field with the new name, deprecate the old one
- Never remove fields consumed by mobile (check Flutter models before removing)
- Add a contract test in CI: serialize the current Flutter model classes against real API responses and assert no missing required fields

Create a shared OpenAPI schema validation step in CI that runs on every backend PR, generating and diffing the OpenAPI spec against the last committed version, flagging removals or type changes as breaking.

**Warning signs:**
- Pydantic response schemas with new `required` fields added without `Optional` + default
- Backend PRs that rename existing response fields
- No OpenAPI spec diffing in CI
- Flutter `fromJson` methods using `!` (non-null assertion) on fields that might become absent

**Phase to address:**
Phase 1: Web Foundation — OpenAPI contract testing must be in CI before any web-driven API changes land.

---

### Pitfall 8: RTK Query SSR Data Fetching Causing Hydration Mismatches

**What goes wrong:**
A Next.js server component fetches data using RTK Query (or Redux dispatch). The server renders HTML with the fetched data. The client hydrates but the Redux store is empty (client starts fresh) or initializes with different data. React throws a hydration error: "Text content does not match server-rendered HTML." The page flickers, or worse, the mismatch is suppressed with `suppressHydrationWarning` and stale server data is silently shown.

**Why it happens:**
RTK Query is designed for client-side data fetching and caching. Using it in server components without proper store hydration results in a server/client state mismatch. The official RTK docs explicitly state: "RTK Query is for data fetching on the client only" — server components should use plain `fetch` calls.

**How to avoid:**
Separate server-state fetching from client-state management explicitly:
- Server components: use `fetch` directly against the FastAPI backend (with session cookie forwarded), never RTK Query dispatch
- Client components: use RTK Query for interactive data that needs cache invalidation and real-time updates
- Hydrate the Redux store from server-fetched data using the RTK `makeStore` + `PreloadedState` pattern, then let RTK Query take over for subsequent fetches

**Warning signs:**
- `store.dispatch(someApi.endpoints.getData.initiate())` inside a server component or `getServerSideProps`
- Hydration error warnings in the browser console on initial load
- `suppressHydrationWarning={true}` used anywhere in the app

**Phase to address:**
Phase 1: Web Foundation — data fetching architecture must be resolved before the first page component is built.

---

### Pitfall 9: Multi-Tenant RLS Not Applied to Web-Specific Queries

**What goes wrong:**
The web dashboard adds new query patterns not used by the mobile app — aggregate reporting, cross-entity search, bulk export. A developer writes a reporting query without realizing the `SET LOCAL app.current_tenant_id` context variable must be set for every database session that accesses RLS-protected tables. The reporting endpoint returns data from all tenants, or the RLS policy blocks the query entirely.

**Why it happens:**
Mobile-facing endpoints were all written with the tenant context middleware in place. The pattern is established but implicit — a new web-specific endpoint added by a developer unfamiliar with the tenant isolation mechanism may omit the dependency injection, or use a raw SQL query that bypasses the SQLAlchemy session that has the tenant context set.

**How to avoid:**
All new web endpoints must use `Depends(get_current_user)` + the tenant context middleware exactly as existing endpoints do. Any new service methods must inherit from `TenantScopedService`. Add a CI test for every new API endpoint that verifies: (a) a valid token from Company A cannot retrieve Company B's data, and (b) the endpoint returns 403/404 without a token.

**Warning signs:**
- New endpoints without `Depends(get_current_user)`
- Raw `db.execute(text("SELECT ..."))` calls without session-level tenant context
- No cross-tenant isolation tests for web-specific endpoints in the test suite

**Phase to address:**
Every phase — each new web endpoint must include a cross-tenant isolation test. Establish as a PR checklist item.

---

### Pitfall 10: Dual Auth Flow Complexity — Web Cookies vs Mobile Bearer Tokens

**What goes wrong:**
The backend auth middleware is extended to handle both httpOnly cookie auth (web) and Bearer token auth (mobile). A subtle bug in the precedence logic causes mobile `Authorization` headers to be ignored when a cookie is present (or absent), breaking mobile auth for users who have ever used the web dashboard on the same device/browser. Worse, a web session cookie is inadvertently sent by the browser on mobile WebView requests, confusing the auth layer.

**Why it happens:**
Supporting two auth mechanisms in one FastAPI dependency increases complexity. `get_current_user` must try the cookie first, then the header, without throwing on the absence of either until both are exhausted. Error messages that only reference "Bearer token" confuse web users, and vice versa.

**How to avoid:**
Create a single `get_current_user` dependency that checks both sources explicitly:

```python
async def get_current_user(
    request: Request,
    db: AsyncSession = Depends(get_db),
) -> User:
    # 1. Check httpOnly cookie (web)
    token = request.cookies.get("access_token")
    # 2. Fall back to Bearer header (mobile)
    if not token:
        auth_header = request.headers.get("Authorization", "")
        if auth_header.startswith("Bearer "):
            token = auth_header[7:]
    if not token:
        raise HTTPException(status_code=401, detail="Not authenticated")
    return await verify_token(token, db)
```

Write explicit tests: mobile client sends Bearer header → authenticated; web client sends cookie → authenticated; both present → cookie wins; neither present → 401.

**Warning signs:**
- Separate `get_current_user_web` and `get_current_user_mobile` dependencies that share no code
- Auth middleware that only checks one auth mechanism
- No test covering the Bearer-header path after adding cookie support

**Phase to address:**
Phase 1: Web Authentication — unified auth dependency design must precede any endpoint implementation.

---

## Technical Debt Patterns

| Shortcut | Immediate Benefit | Long-term Cost | When Acceptable |
|----------|-------------------|----------------|-----------------|
| Store JWT in localStorage | Trivial implementation | XSS can exfiltrate tokens; admin data exposed | Never for admin dashboard |
| CORS wildcard `*` with credentials | No origin management | Invalid per spec; breaks browser credentialed requests | Never |
| Redux singleton store | Simple setup | Cross-request state pollution in SSR; tenant data leakage risk | Never in Next.js SSR context |
| Middleware-only auth guard | Simple route protection | CVE-2025-29927 bypass; not a security boundary | Never as sole auth mechanism |
| Skip OpenAPI contract testing | Faster CI | Mobile app breaks silently on field removal | Never |
| Shared refresh token family for web+mobile | No model changes | New web session revokes all mobile sessions | Never |
| Copy mobile API endpoints for web without additive review | Faster feature delivery | Field changes break mobile | Never without regression tests |
| RTK Query in server components | Unified data fetching | Hydration mismatches, SSR/client state desync | Never |

---

## Integration Gotchas

| Integration | Common Mistake | Correct Approach |
|-------------|----------------|------------------|
| FastAPI + Next.js CORS | `allow_origins=["*"]` with `allow_credentials=True` | Enumerate origins explicitly; wildcard is invalid with credentials |
| FastAPI refresh tokens + web client | Existing single-family-per-user model conflicts with multi-session | Add `session_id` column; revoke by family, not user |
| FastAPI + httpOnly cookies | Cookie `SameSite=Strict` blocks browser cross-origin API calls during redirects | Use `SameSite=Lax` for auth cookies; `Strict` only for CSRF tokens |
| Redux + Next.js App Router | Module-level store singleton shared across SSR requests | Use `makeStore` factory; never `export const store = ...` at module level |
| RTK Query + server components | Dispatching RTK queries in server components causes hydration mismatch | Server components use `fetch`; RTK Query client components only |
| Next.js Router Cache + logout | Post-logout navigation shows cached authenticated pages | Call `router.refresh()` on logout; use Next.js 15 with `dynamic: 0` staletime |
| OpenAPI schema + Flutter | New required Pydantic fields break Flutter deserialization silently | All new fields `Optional` with defaults; diff OpenAPI spec in CI |
| Playwright E2E + MSW | MSW only intercepts client-side fetch by default; SSR requests bypass it | Use MSW server-side handler integration for Next.js SSR test coverage |

---

## Performance Traps

| Trap | Symptoms | Prevention | When It Breaks |
|------|----------|------------|----------------|
| RTK Query over-fetching on every route change | Dashboard feels slow; excessive API calls visible in network tab | Use RTK Query `keepUnusedDataFor` and cache tags; normalize entity state | Immediately at scale with large data sets |
| Non-normalized Redux state with large contractor/job lists | UI re-renders entire job list on single record update | Use `createEntityAdapter` for all list data; update by ID not by position | 50+ contractors, 200+ jobs per company |
| Unoptimized Next.js bundle including admin-only chart libraries | Initial page load >3s for admin dashboard | Dynamic import heavy charting libs: `dynamic(() => import('recharts'), { ssr: false })` | First page load on slower connections |
| Server component fetches without caching headers | Reporting dashboard refetches on every navigation | Use `fetch` with `{ next: { revalidate: 60 } }` for stable reporting data | Any non-trivial admin data load |
| Polling for real-time dashboard updates | Excessive API load; backend overwhelmed by web dashboard polling | Use polling intervals >30s for non-critical data; long-polling or WebSocket for live scheduling | 10+ simultaneous admin users |

---

## Security Mistakes

| Mistake | Risk | Prevention |
|---------|------|------------|
| Access token in localStorage or sessionStorage | XSS exfiltration of admin JWT; full tenant data access | httpOnly cookie only; never JavaScript-accessible storage |
| Middleware-only auth (CVE-2025-29927) | Authentication bypass via `x-middleware-subrequest` header | Use Next.js ≥15.2.3; verify session in every server component independently |
| CSRF with cookie-based auth | Malicious site triggers state-changing requests using admin's session cookie | Add `SameSite=Lax` to cookies; use double-submit CSRF token for state-changing requests; FastAPI `Depends` on CSRF header check |
| Trusting `company_id` from the web request body | Web admin could submit another company's ID to access their data | Derive `company_id` from authenticated JWT claims only; never from request body or query params |
| Exposing internal error details in web API responses | Stack traces reveal table names, tenant IDs, internal architecture | All errors caught at API boundary; return generic `{"detail": "..."}` only; full errors logged server-side |
| Missing rate limiting on web auth endpoints | Brute-force of admin credentials; credential stuffing | `slowapi` rate limits on `/auth/web/login` and `/auth/refresh` (same limits as mobile); web login additionally protected by CAPTCHA in production |

---

## UX Pitfalls

| Pitfall | User Impact | Better Approach |
|---------|-------------|-----------------|
| No loading skeleton on RTK Query data fetches | Dashboard feels broken / blank on first load | Use RTK Query `isLoading` with Shadcn/Tailwind skeleton components on every data table |
| Web calendar shows all jobs (no company filter) | Admin confused seeing data from wrong context | Derive `company_id` from auth context at page load; never show cross-company data |
| Form submission with stale RTK Query cache | Admin submits quote update; list still shows old status | Invalidate RTK Query tags on mutation; `invalidatesTags: ['Quote']` on every write mutation |
| No optimistic updates on status changes | Job status change feels slow; admin clicks again | Use RTK Query `optimisticUpdate` for job lifecycle transitions; roll back on error |
| Web dashboard mobile-unusable | Admin on tablet gets broken layout | Use responsive Tailwind breakpoints from the start; test at 768px viewport |
| Logout doesn't clear all tabs | Other open browser tabs still show authenticated content | Use `BroadcastChannel` API to signal logout across tabs; each tab subscribes and redirects |

---

## "Looks Done But Isn't" Checklist

- [ ] **Auth security:** Token stored in httpOnly cookie — verify `document.cookie` in browser console cannot read the access token
- [ ] **CORS:** Mobile app's existing auth flow still works after CORS middleware is added — run the mobile app against the dev backend and verify login + token refresh
- [ ] **Middleware bypass:** Next.js version is ≥15.2.3 — verify `package.json` and confirm with `next --version` in CI
- [ ] **SSR store isolation:** Two concurrent server requests render with independent Redux stores — write a test that simulates two requests and asserts no state leak
- [ ] **Logout cache:** Post-logout navigation does not show cached authenticated pages — manually test browser Back button after logout
- [ ] **Token family isolation:** Mobile app session survives web dashboard login — test both sessions remain active simultaneously
- [ ] **API contract:** All new Pydantic response fields are `Optional` with defaults — diff the OpenAPI spec before/after each backend PR
- [ ] **Cross-tenant web:** Web admin endpoints deny cross-company access — automated test with Company A token accessing Company B's resources
- [ ] **CSRF protection:** State-changing web requests rejected without CSRF token — test from a different origin using fetch with credentials
- [ ] **Hydration:** No hydration mismatch warnings in browser console on first load of any dashboard page

---

## Recovery Strategies

| Pitfall | Recovery Cost | Recovery Steps |
|---------|---------------|----------------|
| JWT stored in localStorage exposed | CRITICAL | Force logout all sessions (invalidate all refresh tokens in DB); rotate JWT secret; audit access logs for anomalous access; notify affected admins |
| CORS wildcard breaks mobile auth | MEDIUM | Update CORS config to explicit origins; deploy backend hotfix; verify mobile app auth flow in staging before production deploy |
| Redux SSR singleton leaks tenant data | HIGH | Audit server logs for cross-user renders; refactor to makeStore factory; regression test all SSR paths before redeploy |
| Next.js middleware bypass exploited | CRITICAL | Immediately upgrade Next.js to ≥15.2.3; add load balancer header strip rule; audit server logs for `x-middleware-subrequest` header presence; rotate all admin tokens |
| API contract change breaks mobile | MEDIUM | Revert field change on backend; deploy hotfix; add optional field with default; coordinate mobile client update |
| Web session invalidates all mobile sessions | MEDIUM | Hotfix: add session_id to token family scope; invalidate all current tokens (force re-login); redeploy backend |
| Router cache serving stale data | LOW | Ship Next.js config with `staleTimes: { dynamic: 0 }`; add `router.refresh()` to logout; cache is client-side and self-heals on hard refresh |

---

## Pitfall-to-Phase Mapping

| Pitfall | Prevention Phase | Verification |
|---------|------------------|--------------|
| JWT in localStorage (XSS) | Phase 1: Web Auth | `document.cookie` test; no `localStorage` token writes in codebase search |
| CORS wildcard breaks mobile | Phase 1: Web Auth | Mobile app regression test in CI against backend with CORS enabled |
| Middleware bypass CVE-2025-29927 | Phase 1: Web Auth | `package.json` version check; server-side token verification in every route handler |
| Redux SSR singleton | Phase 1: Web Foundation | Two-request concurrency test; `makeStore` factory confirmed in code review |
| Router cache stale auth data | Phase 1: Web Auth | Manual logout + back button test; `staleTimes` config verified |
| Refresh token family conflict | Phase 1: Web Auth | Simultaneous mobile + web session test; neither session revoked |
| API contract breaking mobile | Phase 1: Web Foundation + every backend-change phase | OpenAPI spec diff in CI; mobile deserialization test on every schema change |
| RTK Query SSR hydration mismatch | Phase 1: Web Foundation | No hydration warnings in CI build output; server component data fetching via `fetch` only |
| RLS not applied to web queries | Every phase adding new endpoints | Cross-tenant isolation test for every new endpoint |
| Dual auth flow complexity | Phase 1: Web Auth | Bearer-header path test + cookie path test + "both present" test |

---

## Sources

- Next.js Official Docs: Authentication — https://nextjs.org/docs/pages/guides/authentication
- Redux Toolkit: Next.js Setup (store per request) — https://redux-toolkit.js.org/usage/nextjs
- RTK Query: Server-Side Rendering — https://redux-toolkit.js.org/rtk-query/usage/server-side-rendering
- FastAPI Official Docs: CORS — https://fastapi.tiangolo.com/tutorial/cors/
- CVE-2025-29927 (Datadog Analysis) — https://securitylabs.datadoghq.com/articles/nextjs-middleware-auth-bypass/
- CVE-2025-29927 (NVD) — https://nvd.nist.gov/vuln/detail/CVE-2025-29927
- Next.js GitHub Discussion: Router Cache Stale Data — https://github.com/vercel/next.js/issues/69979
- Next.js GitHub Discussion: Redux + localStorage Hydration — https://github.com/vercel/next.js/discussions/54350
- RTK GitHub Discussion: App Router + RSC compatibility — https://github.com/reduxjs/redux-toolkit/discussions/4251
- RTK GitHub Issue: SSR memory leak — https://github.com/reduxjs/redux-toolkit/issues/3988
- OWASP: JWT Storage Best Practices (localStorage vs cookies)
- TurboStarter: Complete Next.js Security Guide 2025 — https://www.turbostarter.dev/blog/complete-nextjs-security-guide-2025-authentication-api-protection-and-best-practices
- FastAPI GitHub Issue: CORS wildcard with credentials — https://github.com/fastapi/fastapi/issues/4530
- Next.js Official: Caching Guide — https://nextjs.org/docs/app/guides/caching
- TheWidlarzGroup: Next.js SSR JWT with external backend — https://thewidlarzgroup.com/nextjs-auth/

---
*Pitfalls research for: Adding Next.js web admin dashboard to existing FastAPI + Flutter mobile platform*
*Researched: 2026-03-14*
