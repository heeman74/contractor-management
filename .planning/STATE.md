---
gsd_state_version: 1.0
milestone: v2.0
milestone_name: Web Admin Dashboard
status: planning
stopped_at: Completed 14-job-management/14-02-PLAN.md
last_updated: "2026-03-16T23:14:08.010Z"
last_activity: 2026-03-15 — v2.0 roadmap created, all 29 requirements mapped across 6 phases
progress:
  total_phases: 6
  completed_phases: 2
  total_plans: 7
  completed_plans: 7
  percent: 0
---

# Project State

## Project Reference

See: .planning/PROJECT.md (updated 2026-03-15)

**Core value:** Clients always know exactly what's happening with their job — no more chasing contractors for updates, no more scheduling conflicts, no more missed appointments.
**Current focus:** Phase 13 — Web Foundation and Auth

## Current Position

Phase: 13 of 18 (Web Foundation and Auth)
Plan: — of 4 in current phase
Status: Ready to plan
Last activity: 2026-03-15 — v2.0 roadmap created, all 29 requirements mapped across 6 phases

Progress: [░░░░░░░░░░] 0%

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

### Pending Todos

None yet.

### Blockers/Concerns

- Verify Next.js exact stable version on npmjs.com before Phase 13 scaffolding (research flagged 16 from blog source — confirm against official Vercel release notes)
- Phase 13: client_type DB migration requires coordinated backend deploy with mobile regression tests — plan rollback procedure before shipping to production
- Phase 15: react-big-calendar resources prop + drag-and-drop addon + TanStack Query optimistic rollback is highest-risk UI component — spike recommended during Phase 15 planning

## Session Continuity

Last session: 2026-03-16T23:14:08.005Z
Stopped at: Completed 14-job-management/14-02-PLAN.md
Resume file: None
