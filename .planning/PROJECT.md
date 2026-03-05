# ContractorHub

## What This Is

A multi-company SaaS platform for contractor management — builders, electricians, plumbers, and other trade professionals. Company admins manage their contractor teams and job schedules, contractors track their work and availability, and clients stay informed about their job progress. Available as a mobile app (Flutter) with a shared Python backend API.

## Core Value

Clients always know exactly what's happening with their job — no more chasing contractors for updates, no more scheduling conflicts, no more missed appointments.

## Requirements

### Validated

(None yet — ship to validate)

### Active

- [ ] Multi-company SaaS — each contracting company has its own workspace
- [ ] Three user roles: company admin, contractor, client
- [ ] Smart job scheduling with conflict detection (no double-bookings)
- [ ] Contractor availability tracking (who's free when)
- [ ] Multi-day job support (jobs spanning days/weeks)
- [ ] Travel time awareness between job sites
- [ ] Dual job flow: client-initiated requests + company-assigned jobs
- [ ] Job lifecycle: quote → schedule → in-progress → complete
- [ ] Client portal: view job status, progress updates, photos
- [ ] Offline-first: full functionality without internet, sync on reconnect
- [ ] Comprehensive testing: unit + E2E tests with every feature
- [ ] Flutter mobile app (Android first, then iOS)
- [ ] Python backend API (shared across platforms)

### Out of Scope

- Authentication system — deferred until ready to publish
- Payment integration — deferred until ready to publish
- Web dashboard — mobile-first, web later
- Real-time chat — not core to scheduling/management value
- Inventory/materials tracking — adds complexity, defer to v2+

## Context

- Target users are trade contractors (builders, electricians, plumbers, HVAC, etc.)
- Contractors often work at job sites with poor or no internet connectivity — offline-first is essential
- The scheduling engine is the differentiator — must handle real-world complexity (travel time, multi-day jobs, team availability)
- Both inbound (client requests) and outbound (company assigns) job flows must coexist
- The platform is designed to scale from individual contracting companies to many companies (multi-tenant SaaS)
- Testing is a first-class citizen — every feature ships with unit and E2E tests

## Constraints

- **Platform**: Flutter for mobile (Android priority, iOS second) — chosen for cross-platform efficiency, offline support, and built-in test tooling
- **Backend**: Python (FastAPI or Django) — shared API serving both mobile platforms
- **Architecture**: Offline-first with local data and background sync — job sites have unreliable connectivity
- **Testing**: Every feature must include unit tests and E2E tests — no exceptions
- **Scalability**: Multi-tenant architecture from day one — not an afterthought
- **Performance**: Scheduling calculations must be fast even with large contractor teams and complex job calendars

## Key Decisions

| Decision | Rationale | Outcome |
|----------|-----------|---------|
| Flutter for mobile | Cross-platform, great offline support, built-in testing, single codebase | — Pending |
| Python for backend | User preference, good for data-heavy scheduling logic | — Pending |
| Offline-first architecture | Contractors work at job sites with poor connectivity | — Pending |
| Multi-tenant SaaS from start | Avoids costly refactor later, aligns with multi-company vision | — Pending |
| Auth/Payment deferred | Focus on core scheduling value first, add before publish | — Pending |

---
*Last updated: 2026-03-04 after initialization*
