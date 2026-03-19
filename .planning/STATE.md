---
gsd_state_version: 1.0
milestone: v2.0
milestone_name: Web Admin Dashboard
status: unknown
stopped_at: Phase 18 context gathered
last_updated: "2026-03-19T13:07:22.958Z"
progress:
  total_phases: 6
  completed_phases: 5
  total_plans: 22
  completed_plans: 22
---

# Project State

## Project Reference

See: .planning/PROJECT.md (updated 2026-03-15)

**Core value:** Clients always know exactly what's happening with their job — no more chasing contractors for updates, no more scheduling conflicts, no more missed appointments.
**Current focus:** Phase 17 — crm-clients-and-contractors

## Current Position

Phase: 17 (crm-clients-and-contractors) — COMPLETE
Plan: 5 of 5

## Accumulated Context

### Decisions

- v2.0: Next.js 16 App Router + React 19 + TypeScript strict for web layer
- v2.0: TanStack Query owns all server/API state; Redux Toolkit owns client UI state only (sidebar, filters, auth display metadata)
- v2.0: Tokens stored in httpOnly cookies via Next.js Route Handler proxy — never localStorage
- v2.0: Redux makeStore factory pattern (never module-level singleton) to prevent cross-request tenant data leakage in SSR
- v2.0: Backend changes are additive-only — no existing Pydantic fields renamed or removed (protects mobile app)
- v2.0: Phase 16 (Quotes/Invoices) depends only on Phase 13 and may be parallelized with Phases 14-15
- [Phase 13-web-foundation-and-auth]: Bearer header takes priority over access_token cookie in get_current_user — mobile unaffected, web uses cookie fallback
- [Phase 13-web-foundation-and-auth]: client_type nullable column (no backfill) enables session attribution for web vs mobile clients
- [Phase 13]: Redux makeStore factory pattern (never module-level singleton) prevents cross-request tenant data leakage in SSR
- [Phase 13]: Error toasts persist with duration Infinity — all toast.error() calls must include { duration: Infinity }
- [Phase 13]: Playwright test stubs use test.skip() to satisfy ship-with-feature requirement without false failures during scaffold phase
- [Phase 13-web-foundation-and-auth]: proxy.ts checks cookie existence only — optimistic guard, real validation at FastAPI on each API call
- [Phase 13-web-foundation-and-auth]: Refresh cookie scoped to path=/api/auth/refresh — browser only sends it to that endpoint, reducing attack surface
- [Phase 13-web-foundation-and-auth]: Login page always redirects to / (dashboard home) — no redirectTo parameter honored
- [Phase 13-web-foundation-and-auth]: StatusBadge reusable component with semantic color map ready for phases 14-18
- [Phase 14-job-management]: useQueries for parallel per-status count queries avoids hooks-in-loop violation
- [Phase 14-job-management]: Requests tab badge shows pending-only count via client-side filter
- [Phase 14-job-management]: Suspense boundary wraps useSearchParams consumer — required by Next.js App Router for static page generation
- [Phase 14-job-management]: Static requests segment before [requestId] prevents Next.js route shadowing; approve fires immediately without confirmation dialog
- [Phase 14-job-management]: base-ui DropdownMenuTrigger has no asChild prop — styled inline with Tailwind matching Button outline/sm
- [Phase 14-job-management]: Cancel note creation fires inside transitionMutation onSuccess callback — ensures note only created after successful transition
- [Phase 15-scheduling-calendar]: page.tsx requires use client for ssr:false dynamic import in Next.js App Router — Server Components cannot use ssr:false
- [Phase 15-scheduling-calendar]: base-ui Button has no asChild prop — use buttonVariants + Link pattern for link-styled buttons in web layer
- [Phase 15-scheduling-calendar]: react-big-calendar EventProps adapter wrapper pattern needed to bridge library types to custom event component props
- [Phase 15]: EventInteractionArgs.start/end are stringOrDate — coerce to Date before use to satisfy TypeScript strict mode
- [Phase 15]: Conflict pre-check fires before any optimistic update — only apply optimistic update when no conflicts or user confirms
- [Phase Phase 15-scheduling-calendar]: SlotInfo.resourceId coerced with String() before contractor lookup — react-big-calendar types it as string|number|undefined
- [Phase 15-scheduling-calendar]: sa_inspect guard in _job_with_client_name() prevents lazy-raise MissingGreenlet after db.refresh() while still populating client_name from already-loaded relationships
- [Phase 15-scheduling-calendar]: client_name is additive-only on JobResponse — no existing fields renamed or removed (protects mobile Dart models)
- [Phase 16-quotes-and-invoices]: GET /quotes/ inserts before for-job route to avoid FastAPI path parameter shadowing
- [Phase 16-quotes-and-invoices]: apiFetchRaw mirrors apiClient retry/refresh pattern but returns raw Response for PDF blob downloads
- [Phase 16-quotes-and-invoices]: Quotes list fetches all quotes once + filters client-side; jobs lookup map resolves client_name without N+1 requests
- [Phase 16-quotes-and-invoices]: Generate Invoice button gated on job.status === complete; extend expiry uses POST /quotes/{id}/extend with { new_expiry_date } body
- [Phase 16-quotes-and-invoices]: Draft tab maps to finalized_at === null invoices since InvoiceStatus has no draft backend value
- [Phase 16-quotes-and-invoices]: Jobs fetched separately at /invoices list to resolve client_name and description (no join on invoices endpoint)
- [Phase 16-quotes-and-invoices]: Select<string> generic annotation required for template loader to handle null from base-ui Select onValueChange
- [Phase 16-quotes-and-invoices]: Documents card in job detail shown for quote/complete/invoiced statuses to cover full document lifecycle
- [Phase 16]: Payment summary assertions use raw toFixed(2) values without comma formatting (matching actual page output)
- [Phase 17-crm]: Lazy import of Job model inside list_client_profiles to avoid circular ORM mapper init (Job -> Booking ref triggers before scheduling models loaded)
- [Phase 17-crm]: contractor_name is additive-only on JobResponse — no existing fields renamed (protects mobile Dart models)
- [Phase 17-crm]: TYPE_CHECKING guard for ClientProfileModel alias in schemas.py avoids circular import while satisfying ruff F821
- [Phase 17-crm]: Client list sorts client-side after server fetch — jobs_count sort not supported server-side; row navigates via user_id (not profile id)
- [Phase 17-crm]: Two-column detail layout grid-cols-1 lg:grid-cols-[1fr_360px] gap-8 established as CRM page pattern for client and contractor detail pages
- [Phase 17-crm]: Per-property expand/collapse uses local useState — lightweight for read-only properties list, no accordion library needed
- [Phase 17-crm]: Batch availability POST uses paged contractor IDs only (not all contractors) to limit request payload
- [Phase 17-crm]: Active Jobs count on contractor list shows "—" to avoid N+1; actual count on profile page from query data
- [Phase 17-crm]: Contractor profile Quick Stats uses inline cards (not KpiCard) — KpiCard requires mandatory href navigation target
- [Phase 17-04]: Select<string> generic annotation on base-ui Select to handle null from onValueChange (consistent with Phase 16 pattern)
- [Phase 17-04]: changedDays Set accumulates during drag; all per-day saves fire in single pointerUp handler to avoid mid-drag API churn
- [Phase 17]: contractor_name added to Job TypeScript interface — additive field matching backend JobResponse (mirrors backend additive-only rule)
- [Phase 17]: [Phase 17-05]: ContractorLaneHeader Link uses e.stopPropagation() to prevent react-big-calendar drag-start on link click
- [Phase 17]: [Phase 17-05]: Backend CRM integration tests use tenant_a_client fixture; role assignment via /api/v1/users/{user_id}/roles with {user_id, role} body

### Pending Todos

None yet.

### Blockers/Concerns

- Verify Next.js exact stable version on npmjs.com before Phase 13 scaffolding (research flagged 16 from blog source — confirm against official Vercel release notes)
- Phase 13: client_type DB migration requires coordinated backend deploy with mobile regression tests — plan rollback procedure before shipping to production
- Phase 15: react-big-calendar resources prop + drag-and-drop addon + TanStack Query optimistic rollback is highest-risk UI component — spike recommended during Phase 15 planning

## Session Continuity

Last session: 2026-03-19T13:07:22.950Z
Stopped at: Phase 18 context gathered
Resume file: .planning/phases/18-reporting-dashboard/18-CONTEXT.md
