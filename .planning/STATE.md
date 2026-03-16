---
gsd_state_version: 1.0
milestone: v2.0
milestone_name: Web Admin Dashboard
status: planning
stopped_at: Completed 13-02-PLAN.md
last_updated: "2026-03-16T07:09:20.935Z"
last_activity: 2026-03-15 — v2.0 roadmap created, all 29 requirements mapped across 6 phases
progress:
  total_phases: 6
  completed_phases: 0
  total_plans: 4
  completed_plans: 2
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

### Pending Todos

None yet.

### Blockers/Concerns

- Verify Next.js exact stable version on npmjs.com before Phase 13 scaffolding (research flagged 16 from blog source — confirm against official Vercel release notes)
- Phase 13: client_type DB migration requires coordinated backend deploy with mobile regression tests — plan rollback procedure before shipping to production
- Phase 15: react-big-calendar resources prop + drag-and-drop addon + TanStack Query optimistic rollback is highest-risk UI component — spike recommended during Phase 15 planning

## Session Continuity

Last session: 2026-03-16T07:09:20.930Z
Stopped at: Completed 13-02-PLAN.md
Resume file: None
