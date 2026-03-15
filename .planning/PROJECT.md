# ContractorHub

## What This Is

A multi-company SaaS platform for contractor management — builders, electricians, plumbers, and other trade professionals. Company admins manage their contractor teams and job schedules via a web dashboard (Next.js) and mobile app (Flutter/Android), contractors track their work in the field with offline-capable mobile tools, and clients stay informed about their job progress through a dedicated portal. Shared Python backend API (FastAPI + PostgreSQL).

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

- [ ] Web admin dashboard (Next.js + React + Redux) — full admin capabilities on desktop
- [ ] Web auth: JWT login, session management, token refresh for web
- [ ] Web quoting: create, edit, send quotes with line items
- [ ] Web contractor management: profiles, availability, assignments
- [ ] Web job scheduling: calendar view, conflict detection, drag-and-drop
- [ ] Web job management: lifecycle tracking, status updates
- [ ] Web client/CRM management
- [ ] Web invoicing and payment views
- [ ] Web reporting dashboard with charts and data tables

#### Carried from v1.0
- [ ] In-app payment processing (Stripe/Square)
- [ ] iOS support
- [ ] Edit invoice functionality (backend ready, UI stubbed)
- [ ] Searchable client selector in job wizard (currently basic dropdown)
- [ ] Contractor messaging (currently placeholder)

### Out of Scope

- ~~Web dashboard~~ — NOW IN SCOPE for v2.0 (admin-only web dashboard)
- Real-time chat — job notes + notifications cover communication
- Inventory/materials tracking — adds complexity, use line items instead
- GPS live tracking — battery drain, privacy; job status updates accomplish same value
- AI-powered scheduling — requires historical data; rule-based conflict detection delivers value
- Route optimization — deferred to v2+
- Recurring job automation — deferred to v2+
- QuickBooks/Xero integration — deferred to v2+

## Current Milestone: v2.0 Web Admin Dashboard

**Goal:** Give company admins a full-featured desktop web experience for managing their contracting business — quoting, contractor management, scheduling, jobs, clients, invoicing, and reporting — powered by the existing backend API.

**Target features:**
- Next.js web app with React + Redux state management
- JWT authentication with the existing FastAPI backend
- Quoting workflow (create, edit, send, track approvals)
- Contractor management (profiles, availability, team assignments)
- Job scheduling with calendar and conflict detection
- Job lifecycle management and status tracking
- Client/CRM management
- Invoicing and payment tracking
- Reporting dashboard with charts

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

- **Platform**: Flutter for mobile (Android priority, iOS second); Next.js for web (admin dashboard)
- **Backend**: Python FastAPI — shared API serving mobile and web platforms
- **Architecture**: Offline-first with local Drift DB and background sync (mobile); server-rendered + client hydration (web)
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
| Next.js + Redux for web admin | SSR performance, Redux for complex admin state, same API backend | — Pending |

---
*Last updated: 2026-03-14 after v2.0 milestone start*
