# Phase 13: Web Foundation and Auth - Context

**Gathered:** 2026-03-15
**Status:** Ready for planning

<domain>
## Phase Boundary

Company admins can securely access the web dashboard and navigate all modules. Delivers: Next.js scaffold, httpOnly cookie auth with the existing FastAPI backend, session management with transparent token refresh, and the global navigation shell (sidebar + topbar + dashboard home). No module content beyond the dashboard home page — job management, scheduling, quotes, etc. are separate phases.

</domain>

<decisions>
## Implementation Decisions

### Dashboard layout
- Fixed sidebar with collapse toggle — expanded (240px with icons + labels) and collapsed (64px icon-only mini sidebar)
- Dark sidebar background (slate/gray-900), light content area
- Sidebar collapse state persisted to localStorage across sessions
- Flat module list (no section groupings) with divider before user menu at bottom
- Active nav item uses filled background accent highlight
- Module order by workflow frequency: Dashboard > Jobs > Schedule > Quotes > Invoices > Clients > Contractors > Reports
- Lucide icons for all module nav items (shadcn/ui default)

### Topbar
- Left side: breadcrumb trail (Dashboard > Jobs > Job #1042)
- Right side: company name + user avatar dropdown (profile, logout)

### Login page
- Split-screen layout: left panel with blue gradient (indigo-600 to blue-500) + ContractorHub branding/tagline, right panel with login form
- Login errors displayed as inline red alert banner above the form fields, clears on next attempt
- Client-side validation errors shown inline per field (red text below each invalid field)
- "Forgot password?" link shown but stubbed — displays "Contact your admin" or "Coming soon" when clicked
- Show password toggle (eye icon) in the password field
- Sign In button: disables + shows spinner + text changes to "Signing in..." during auth request
- After successful login: always redirect to dashboard home

### Dashboard home
- Top row: KPI summary cards — Active Jobs, Pending Quotes, Overdue Invoices, Today's Schedule count
- KPI cards are clickable — each links to its respective module page
- Below cards: recent activity feed showing last 10 items (new job requests, status changes, payments)
- Real API data from existing backend endpoints (not placeholder/mock data)

### Error handling
- Global errors (server, network): toast notifications in bottom-right corner (shadcn/ui Sonner)
  - Success toasts auto-dismiss after 5 seconds
  - Error toasts persist until manually dismissed
- Session expiry (401): silent token refresh attempt first, redirect to /login with "Session expired" message only on refresh failure
- Form validation: inline per-field error messages (red text below field)
- Custom branded 404 and 500 error pages with "Go to Dashboard" button

### Loading states
- Skeleton screens for data loading (shadcn/ui Skeleton component) — shapes match real content layout
- NProgress-style thin top progress bar for route transitions between pages
- Both combined: top bar for instant route feedback + skeletons for content placeholder

### Responsive behavior
- Desktop-first admin tool
- Desktop (>1024px): full expanded sidebar + content
- Tablet (768-1024px): auto-collapse to mini sidebar + content
- Mobile (<768px): hamburger button triggers sidebar as overlay/drawer
- No content layout reflow needed

### Color and theme
- Primary accent: blue (indigo/blue-600) — buttons, active states, links, interactive elements
- Status badges use semantic colors: green (active/paid/approved), yellow (pending/in-progress), red (overdue/declined), blue (scheduled/sent), gray (draft)

### Claude's Discretion
- Exact skeleton screen shapes per page
- Exact spacing, typography scale, and component sizing
- NProgress library choice vs custom implementation
- Exact Tailwind color values within the blue/indigo family
- Toast duration and animation details
- Breadcrumb truncation behavior for deep nesting

</decisions>

<specifics>
## Specific Ideas

- Login page left panel inspired by professional SaaS tools — blue gradient with logo and tagline
- Dashboard home KPI cards similar to Stripe Dashboard overview — clickable stat cards that navigate to detail
- Sidebar feel like Linear or Vercel — dark, clean, collapsible with icon-only mini mode
- Status badge color system established in Phase 13 and reused consistently across all subsequent phases (14-18)

</specifics>

<code_context>
## Existing Code Insights

### Reusable Assets
- Auth endpoints: `/api/v1/auth/{login,register,refresh,logout}` — returns `TokenResponse` with access + refresh tokens
- `get_current_user` dependency: extracts user from Bearer token, sets RLS tenant context — needs dual extraction (cookie + Bearer)
- `CurrentUser` class: provides `user_id`, `company_id`, `roles` — reuse in web auth
- All module API endpoints already exist from v1.0: jobs, scheduling, quotes, invoices, reports, users, companies

### Established Patterns
- JWT: HS256, 15-min access tokens, 30-day refresh tokens with family rotation
- CORS: `allow_credentials=True`, configurable origins via `CORS_ORIGINS` env var — needs web app origin added
- Rate limiting: auth endpoints rate-limited via slowapi (5/min login, 3/min register)
- Security headers middleware: X-Content-Type-Options, X-Frame-Options, HSTS already applied
- All routers mounted at `/api/v1` prefix

### Integration Points
- `security.py:get_current_user` — must be extended to check cookies in addition to Bearer header (cookie takes priority for web, Bearer for mobile)
- `config.py:Settings` — `cors_origins` env var needs web app URL added
- `main.py` CORS middleware — already supports credentials, just needs origin list updated
- Users model may need `client_type` field to distinguish web vs mobile sessions (for audit/analytics)

</code_context>

<deferred>
## Deferred Ideas

None — discussion stayed within phase scope

</deferred>

---

*Phase: 13-web-foundation-and-auth*
*Context gathered: 2026-03-15*
