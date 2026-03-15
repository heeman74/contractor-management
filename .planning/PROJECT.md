# ContractorHub

## What This Is

A multi-company SaaS platform for contractor management — builders, electricians, plumbers, and other trade professionals. Company admins manage their contractor teams and job schedules, contractors track their work in the field with offline-capable tools, and clients stay informed about their job progress through a dedicated portal. Available as a mobile app (Flutter/Android) with a shared Python backend API (FastAPI + PostgreSQL).

## Core Value

Clients always know exactly what's happening with their job — no more chasing contractors for updates, no more scheduling conflicts, no more missed appointments.

## Requirements

### Validated

- ✓ Multi-company SaaS with PostgreSQL RLS data isolation — v1.0
- ✓ Three user roles: company admin, contractor, client — v1.0
- ✓ Smart job scheduling with GIST-constraint conflict detection — v1.0
- ✓ Contractor availability tracking with weekly schedules and overrides — v1.0
- ✓ Multi-day job support with partial-day segments — v1.0
- ✓ Travel time awareness with ORS integration and cache — v1.0
- ✓ Dual job flow: client-initiated requests + company-assigned jobs — v1.0
- ✓ Job lifecycle: Quote → Scheduled → In Progress → Complete → Invoiced — v1.0
- ✓ Client portal: live job status, progress photos, delay visibility — v1.0
- ✓ Offline-first: local Drift DB, transactional outbox, 15-entity sync — v1.0
- ✓ Flutter mobile app (Android) with Riverpod, Drift, GoRouter — v1.0
- ✓ Python backend API (FastAPI + SQLAlchemy async + PostgreSQL) — v1.0
- ✓ Job notes, photo capture, GPS address, drawing pad — v1.0
- ✓ Time tracking with clock in/out per job — v1.0
- ✓ Digital quoting with line items and approval flow — v1.0
- ✓ Digital invoicing generated from completed jobs — v1.0
- ✓ Reporting dashboard (jobs by status, revenue, utilization) — v1.0
- ✓ Push notification infrastructure (FCM) — v1.0
- ✓ Drag-and-drop calendar with overdue warnings — v1.0
- ✓ Forced delay justification with reason + new ETA — v1.0

### Active

- [ ] User authentication (email/password, OAuth)
- [ ] Password reset via email
- [ ] Session management and token refresh
- [ ] In-app payment processing (Stripe/Square)
- [ ] iOS support
- [ ] Edit invoice functionality (backend ready, UI stubbed)
- [ ] Searchable client selector in job wizard (currently basic dropdown)
- [ ] Contractor messaging (currently placeholder)

### Out of Scope

- Web dashboard — mobile-first, web doubles product surface area
- Real-time chat — job notes + notifications cover communication
- Inventory/materials tracking — adds complexity, use line items instead
- GPS live tracking — battery drain, privacy; job status updates accomplish same value
- AI-powered scheduling — requires historical data; rule-based conflict detection delivers value
- Route optimization — deferred to v2+
- Recurring job automation — deferred to v2+
- QuickBooks/Xero integration — deferred to v2+

## Context

Shipped v1.0 MVP with 143,230 LOC across 609 files in 11 days.
Tech stack: Flutter 3.32+ (Drift, Riverpod 3, GoRouter, GetIt) + FastAPI 0.115 (SQLAlchemy 2.0, asyncpg, PostgreSQL 13 with RLS).
24 requirements satisfied across 12 phases (8 feature + 4 gap closure).
12 items of non-blocking tech debt documented in milestone audit.

### Deployment Requirements
- `ORS_API_KEY` for travel time computation (graceful degradation without)
- `google-services.json` for FCM notifications
- Server libpango/Cairo for PDF generation

## Constraints

- **Platform**: Flutter for mobile (Android priority, iOS second)
- **Backend**: Python FastAPI — shared API serving mobile platforms
- **Architecture**: Offline-first with local Drift DB and background sync
- **Testing**: Every feature ships with unit and E2E tests
- **Scalability**: Multi-tenant with PostgreSQL RLS from day one
- **Performance**: Scheduling calculations fast with large teams

## Key Decisions

| Decision | Rationale | Outcome |
|----------|-----------|---------|
| Flutter for mobile | Cross-platform, offline support, built-in testing | ✓ Good — 143K LOC single codebase |
| FastAPI for backend | Async-first, good for scheduling logic | ✓ Good — clean async with SQLAlchemy 2.0 |
| Offline-first architecture | Job sites have poor connectivity | ✓ Good — 15-entity sync works reliably |
| PostgreSQL RLS for multi-tenancy | Enforces isolation at DB level, not app layer | ✓ Good — tenant isolation proven in tests |
| Auth/Payment deferred | Focus on core scheduling value first | — Pending — needed before publish |
| Drift for local DB | Type-safe SQLite, streams, migrations | ✓ Good — v1→v6 migrations smooth |
| Riverpod 3 for state | Compile-safe, auto-dispose, testable | ✓ Good — some legacy StateNotifier usage |
| Transactional outbox for sync | Reliable offline mutations, idempotent | ✓ Good — no data loss in testing |
| GIST constraint for scheduling | DB-level conflict prevention, no app races | ✓ Good — concurrent booking tests pass |
| WeasyPrint for PDF | Open source, server-side, no browser dependency | ⚠️ Revisit — requires system libs |

---
*Last updated: 2026-03-15 after v1.0 milestone*
