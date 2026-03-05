# Project Research Summary

**Project:** ContractorHub — Contractor Management SaaS
**Domain:** Field Service Management (offline-first, multi-tenant, mobile-first)
**Researched:** 2026-03-04
**Confidence:** HIGH

## Executive Summary

ContractorHub is a field service management SaaS with three distinguishing constraints that drive nearly every architectural decision: offline-first mobile (contractors work at job sites with poor connectivity), multi-tenant isolation (multiple companies on shared infrastructure), and a three-role unified app (admin, contractor, and client all served from one Flutter codebase). These three constraints are not features that can be added later — they are foundational architectural commitments that must be established before any user-facing work begins. The research is unambiguous on this point: retrofitting offline-first or multi-tenancy onto an online-first or single-tenant system costs as much as a rewrite.

The recommended approach is Flutter (Android-first) + FastAPI + PostgreSQL with Row Level Security, using Drift as the local SQLite ORM and Riverpod for state management. The sync architecture follows the transactional outbox pattern: all writes go to the local SQLite database first, then a background sync engine drains the queue when connectivity is available. PostgreSQL EXCLUDE USING GIST constraints prevent double-booking at the database level, providing the safety net that application-level checks cannot guarantee under concurrent use. This stack is well-documented, all versions are current, and the patterns map directly to the project's requirements.

The primary risks are execution risks, not technology risks. The technology choices are sound. The danger lies in four areas that the research highlights repeatedly: (1) building online-first and deferring offline architecture, (2) forgetting to include tenant context in background tasks (Celery workers, push notification jobs), (3) missing a database-level scheduling constraint and relying on application logic alone, and (4) omitting version columns from the data model, making conflict resolution impossible. Every one of these is categorized as non-recoverable without a rewrite or a production data incident. They must all be addressed in the foundation phase, not after.

---

## Key Findings

### Recommended Stack

The stack is Flutter 3.32+ / Dart 3.8+ for the cross-platform mobile app and FastAPI 0.135.1 on Python for the backend, connected via HTTPS REST/JSON. PostgreSQL 16+ is the only appropriate database due to its Row Level Security support and the EXCLUDE USING GIST exclusion constraint needed for scheduling. SQLAlchemy 2.0 with asyncpg provides the async database access layer that FastAPI's async endpoints require; psycopg2 (synchronous) must not be used.

For Flutter, Drift 2.32 provides type-safe reactive SQLite queries with a full migration framework — this replaces raw sqflite, which offers no type safety or migration path. Riverpod 3.2 manages UI state with compile-time provider safety, tying directly into Drift's reactive streams. Celery + Redis handle background jobs (conflict resolution batches, notification dispatch) on the backend side. All versions were verified against pub.dev and PyPI as of the research date.

**Core technologies:**
- Flutter 3.32+ / Dart 3.8+: cross-platform mobile (Android + iOS) — single codebase for all three roles
- FastAPI 0.135.1: Python async API — ASGI-native, automatic OpenAPI, lowest boilerplate
- PostgreSQL 16+: primary database — RLS for tenant isolation, GIST exclusion for scheduling
- SQLAlchemy 2.0 + asyncpg: async ORM — required for FastAPI async endpoints without blocking
- Drift 2.32: local SQLite ORM — type-safe, reactive streams, migration framework
- Riverpod 3.2: Flutter state management — compile-time safe, no BuildContext dependency
- Celery + Redis: background task queue — async jobs outside HTTP request lifecycle
- workmanager: Flutter background sync scheduling — only option for background Dart on both platforms

**What to avoid:** Provider (superseded by Riverpod), GetX (tight coupling, breaks testing), Hive (unmaintained), raw sqflite (no type safety), psycopg2 (blocks async event loop), separate database per tenant at launch (operational catastrophe at scale).

See `.planning/research/STACK.md` for full dependency list, version compatibility matrix, and alternatives considered.

### Expected Features

The feature research cross-referenced seven major competitors (Jobber, Housecall Pro, ServiceTitan, Tradify, Fergus, Workiz, FieldPulse). ContractorHub's differentiation lies in areas where all competitors fall short: advanced conflict detection with travel time awareness, true offline-first architecture, a unified three-role app, first-class multi-day job support, and multi-tenant SaaS from day one. No competitor delivers all of these.

**Must have (table stakes — v1):**
- Multi-tenant company workspace — must be established before any feature is built
- Three user roles (admin, contractor, client) — core to the product; all three views required
- Customer/client CRM — minimum data model for job creation
- Job creation with lifecycle stages (Quote → Scheduled → In Progress → Complete)
- Contractor availability tracking + conflict detection — the scheduling differentiator
- Drag-and-drop calendar scheduling — every competitor has this; absence makes it feel incomplete
- Multi-day job support — first-class, not an afterthought; genuine differentiator
- Travel time awareness built into conflict detection — no competitor does this pre-scheduling
- Job notes + photo capture (offline-capable) — contractor field workflow
- Client portal with real-time job status and progress photos — core stated value proposition
- Client notifications (job scheduled, started, completed) — pull clients into the loop
- Dual job flow: client-initiated requests + company-assigned jobs
- Offline-first mobile with background sync — non-negotiable for trade contractors

**Should have (v1.x — after core loop is validated):**
- Digital quoting and estimate approval
- Digital invoicing
- Time tracking (clock in/out per job)
- Basic reporting dashboard
- Contractor self-managed availability
- Authentication and user accounts (required before production launch)

**Defer to v2+:**
- Payment processing (PCI compliance required; defer until billing is mature)
- Inventory/materials tracking (major complexity; Fergus spent years on this)
- QuickBooks/Xero integration (brittle bidirectional sync; needs invoicing first)
- Web dashboard (doubles surface area; mobile-first first)
- AI/route optimization (requires historical data that doesn't exist at launch)
- Real-time GPS tracking (battery drain, contractor privacy objections, platform cost)

See `.planning/research/FEATURES.md` for the full prioritization matrix and competitor feature comparison.

### Architecture Approach

The architecture is a three-tier system: Flutter mobile app (local-first, role-gated), FastAPI backend (async, tenant-aware), and PostgreSQL (shared, RLS-enforced). The Flutter app follows clean architecture with feature-first directory structure (domain → data → presentation per feature). The foundational pattern is repository-with-offline-first-writes: all reads stream from local Drift DB, all writes go to local DB + sync queue atomically within a SQLite transaction, and a background sync engine drains the queue. This means the UI is always responsive and never blocked on network.

The backend follows the same feature-first layout with a dedicated scheduling engine module (`engine.py`) isolated from routing so it can be tested as pure business logic. Tenant resolution happens in FastAPI middleware that sets a PostgreSQL session variable (`app.current_company_id`) before any SQL executes. PostgreSQL RLS policies enforce isolation at the database level as defense-in-depth against application bugs.

**Major components:**
1. Flutter Presentation Layer (Riverpod providers) — role-gated screens, never calls DB or HTTP directly
2. Domain Layer (use cases, entity interfaces) — encodes business rules, depends on repository interfaces
3. Data Layer (repository implementations) — merges local and remote; manages sync queue
4. Drift Local DB + Sync Queue — SQLite source of truth; reactive streams; transactional outbox table
5. FastAPI API Routers + Service Layer — HTTP endpoints, business logic per domain feature
6. Scheduling Engine (backend) — conflict detection, slot computation, travel time; isolated module
7. Tenant Middleware — extracts company_id from JWT, sets PostgreSQL session variable per request
8. PostgreSQL RLS + GIST Constraints — database-enforced tenant isolation and overlap prevention

**Build order mandated by dependencies:**
Core infrastructure → Multi-tenant data layer → Offline sync engine → Scheduling engine → Job lifecycle features → Role-specific views → Notifications

See `.planning/research/ARCHITECTURE.md` for component diagrams, data flows, and code examples.

### Critical Pitfalls

The research identified eight significant pitfalls, five of which are categorized as non-recoverable in production without significant data risk or a rewrite.

1. **Offline-first retrofitted instead of architected from day one** — The Flutter app must read exclusively from local SQLite from the first line of code. Any `await http.get()` that directly populates a UI widget is the wrong pattern. Prevention: local DB exists before any API call; sync queue established before any feature is built on top.

2. **Missing tenant context in background tasks** — FastAPI middleware sets `company_id` correctly for HTTP requests, but Celery workers and background tasks run outside the request scope and lose this context. Prevention: serialize `tenant_id` explicitly into every task payload; enforce this contract with a base task class that fails loudly if missing.

3. **Scheduling race condition via application-only conflict check** — Check-then-insert without an atomic database constraint causes double-bookings under concurrent dispatcher usage. Prevention: PostgreSQL EXCLUDE USING GIST constraint is the mandatory safety net; application-level checks are UX only.

4. **Silent data overwrite during sync (no version control)** — Last-write-wins without version columns silently discards concurrent changes. Prevention: every entity needs a `version` integer or `updated_at` UTC timestamp; sync endpoints reject stale writes.

5. **Multi-tenant data leak via missing WHERE clause** — A single missed `tenant_id` filter on any query exposes another company's data. Prevention: PostgreSQL RLS is not optional; it is the mandatory defense-in-depth layer that makes missed application filters non-catastrophic.

6. **Flutter SQLite schema migration breaks existing user data** — `onUpgrade` that calls `onCreate` wipes all locally stored, unsynced data. Prevention: every schema change requires a versioned migration function; never use DROP TABLE in an upgrade path; test migrations by opening old DB version and running upgrade.

7. **Action queue not idempotent — duplicate records on retry** — Network drop after server processes request causes retry that creates duplicate records. Prevention: every sync queue entry carries a client-generated UUID as idempotency key; server stores and deduplicates on this key.

8. **Background sync killed by OS** — Android battery optimization silently kills workmanager tasks on OEM builds (Samsung, Xiaomi, Huawei). Prevention: primary sync trigger must be foreground launch + connectivity restored, not periodic timer alone; sync status indicator required in UI.

See `.planning/research/PITFALLS.md` for the full pitfall-to-phase mapping, recovery strategies, and the "looks done but isn't" testing checklist.

---

## Implications for Roadmap

Based on the combined research, the component dependency chain and pitfall prevention requirements mandate a specific build order. The architecture research explicitly states: "Core infra → Multi-tenant data → Offline sync → everything else. The sync engine must be designed before any features are built on top of it, because retrofitting offline-first onto online-first features is a rewrite, not a refactor."

### Phase 1: Foundation and Multi-Tenant Infrastructure

**Rationale:** Everything depends on this. Multi-tenancy cannot be retrofitted. Offline-first cannot be retrofitted. PostgreSQL RLS policies must be in the initial schema migration. The sync queue must exist before any feature writes a record. Setting this up first is not conservative — it is the only order that avoids a rewrite later.

**Delivers:**
- Flutter project skeleton with Drift DB, Riverpod wiring, go_router, and get_it DI
- FastAPI project skeleton with tenant middleware, JWT placeholder, and Pydantic schemas
- PostgreSQL schema with RLS enabled on all tenant tables; GIST extension installed
- Company, user, and role data models with `version` columns and UUID primary keys
- Alembic migration framework running from the first schema creation
- Docker Compose environment for local backend development
- Tenant isolation verified by tests: Tenant A cannot access Tenant B's data via API

**Features from FEATURES.md:** Multi-tenant workspace, three user roles (data models only)
**Avoids:** Pitfall 5 (tenant data leak), Pitfall 3 (background task tenant context skeleton), Pitfall 6 (migration discipline established)

**Research flag:** Standard patterns — well-documented. Skip `/gsd:research-phase`. PostgreSQL RLS and FastAPI middleware patterns are high-confidence with code examples in ARCHITECTURE.md.

---

### Phase 2: Offline Sync Engine

**Rationale:** The sync engine is the most complex cross-cutting concern in the app. Building it before features means features can be built correctly the first time — local-first, queue-backed. Building it after features means rewriting every repository. This is the second-highest-risk phase after the foundation.

**Delivers:**
- `sync_queue` table in Drift local DB (transactional outbox)
- `SyncEngine` Flutter service: queue drain with exponential backoff, idempotency keys
- Connectivity detection via `connectivity_plus` with actual HTTP reachability check
- `workmanager` background sync registration with foreground-launch primary trigger
- Delta cursor sync protocol on backend (`GET /api/v1/sync?cursor=<timestamp>`)
- Conflict resolution strategy: server-wins for schedule conflicts, field-merge for status
- Sync status UI indicator: "N items pending," "Syncing...," "All synced"
- Idempotent server endpoints: all mutation endpoints accept and deduplicate `client_id`

**Uses from STACK.md:** Drift, workmanager, connectivity_plus, dio interceptors, Celery + Redis (backend batch endpoints)
**Implements from ARCHITECTURE.md:** Repository-with-offline-first-writes pattern, transactional outbox pattern, delta cursor sync protocol
**Avoids:** Pitfall 1 (offline-first from day one), Pitfall 7 (background sync killed by OS), Pitfall 8 (duplicate records on retry)

**Research flag:** Needs deeper research during planning. The conflict resolution strategy (field-level merge vs. server-wins) needs explicit decisions per entity type. The delta cursor protocol needs endpoint specification before implementation.

---

### Phase 3: Scheduling Engine and Conflict Detection

**Rationale:** The scheduling engine is ContractorHub's core differentiator and the highest technical complexity feature. It must be built as a separate, isolated backend module before any UI is wired to it. The PostgreSQL EXCLUDE USING GIST constraint must be established in this phase's migration. Once this is working correctly, the admin dispatch UI (Phase 4) can be built on top of it with confidence.

**Delivers:**
- Contractor availability model and availability management endpoints
- `schedules` table with EXCLUDE USING GIST overlap constraint (requires `btree_gist` extension)
- Scheduling engine: `get_available_slots()` with travel time buffer subtraction
- Travel time integration: backend fetches from mapping API, caches by (origin, destination) with TTL
- Conflict detection API: returns available slots and flags conflicts before booking
- Multi-day job support: availability blocking across all days of a spanning job
- Concurrent booking safety: load-tested with two simultaneous booking requests proving only one succeeds

**Uses from STACK.md:** PostgreSQL GIST constraints, Redis caching for travel time matrix, optional Celery for pre-computation
**Implements from ARCHITECTURE.md:** Scheduling engine pattern, EXCLUDE USING GIST constraint, application-layer slot computation
**Avoids:** Pitfall 4 (scheduling race condition), "noisy neighbor" performance trap (indexes on `contractor_id, start_time, end_time` from day one)

**Research flag:** Needs deeper research during planning. The travel time integration requires API selection (Google Maps vs. OpenRouteService) and cost modeling. The multi-day availability blocking algorithm needs formal specification before implementation.

---

### Phase 4: Job Lifecycle and Core Field Workflow

**Rationale:** With data isolation, sync, and scheduling in place, the job workflow is the first phase that delivers user-visible value. All job operations are built on top of the sync engine (local-first) and the scheduling engine (conflict-safe). This phase covers both job flows (client-initiated and company-assigned) because they share the same job data model and diverge only at the creation point.

**Delivers:**
- Job CRUD with lifecycle state machine (Quote → Scheduled → In Progress → Complete → Invoiced)
- Job notes with offline capture
- Photo capture: Flutter camera integration, presigned S3 URL upload from device, URL stored in backend
- Client CRM: client profiles with job history
- Client-initiated job request flow: submission, review queue, admin conversion to job
- Company-assigned job flow: admin creates job, assigns contractor
- Both flows visible in unified job pipeline

**Uses from STACK.md:** Drift DAOs for job tables, Freezed models for Job entity, json_serializable for API DTOs
**Implements from ARCHITECTURE.md:** Job lifecycle service, photo presigned URL pattern (Flutter direct to S3, never proxied through API)
**Avoids:** N+1 query trap (eager-load assignments with jobs), full table scan for job list (composite indexes on `(company_id, status, created_at)`)

**Research flag:** Standard patterns. Job CRUD and photo upload patterns are well-established. Skip `/gsd:research-phase`.

---

### Phase 5: Role-Specific Views and Client Portal

**Rationale:** With the job lifecycle working, the three role-specific views can be built on top. The admin calendar (dispatch board), contractor job list, and client portal all read from the same underlying job and schedule data — the difference is filtering, presentation, and permitted actions. The client portal's real-time feel comes from the sync engine already built in Phase 2 delivering background updates.

**Delivers:**
- Admin view: drag-and-drop calendar with travel time buffer visualization, team availability overview, conflict indicators
- Contractor view: "my jobs" list (offline-capable), availability management, job status transitions
- Client portal: live job status with progress percentage, chronological photo timeline, ETA display
- go_router role guards: redirect unauthorized roles, separate navigation trees per role
- Client notifications: push notifications (FCM) on job scheduled, started, completed

**Uses from STACK.md:** go_router for role-based routing, Riverpod providers for role-gated state, FCM for push notifications
**Implements from ARCHITECTURE.md:** Role-specific UI layers, FCM as sync trigger (reduces polling frequency), read flow from Drift streams
**Avoids:** Scheduling view not showing travel time gaps (visually render buffer zones), conflict resolved silently (surface conflict UI explicitly)

**Research flag:** Standard patterns for role-based routing and Flutter UI. FCM integration is well-documented. Calendar drag-and-drop UI may need research into Flutter calendar library options during planning.

---

### Phase 6: Validation Features and Production Readiness

**Rationale:** The core scheduling + client transparency loop is working after Phase 5. This phase adds the features needed to close the workflow loop for real-world use and prepare for actual user onboarding. Authentication is explicitly listed as v1.x (required before production launch) in the feature research.

**Delivers:**
- Authentication and user accounts: JWT issuance with `tenant_id` claim, registration, login, password reset
- Digital quoting and estimate approval: branded templates, line items, client approval flow
- Digital invoicing: auto-generated from completed job, customizable templates
- Time tracking: clock in/out per job from mobile
- Basic reporting dashboard: jobs by status, revenue summaries, exportable
- Contractor self-managed availability: contractors mark personal blocks visible to dispatcher

**Uses from STACK.md:** python-jose for JWT, Pydantic for schema validation
**Avoids:** JWT without tenant claim (include `tenant_id` at issuance), raw DB errors in API responses

**Research flag:** Authentication needs planning-phase research on the specific flow (magic link vs. email/password, multi-tenant login UX). Invoicing/quoting template design is a UX research question.

---

### Phase Ordering Rationale

- **Dependency chain drives order:** Multi-tenancy (Phase 1) must precede every feature. Sync engine (Phase 2) must precede every mobile feature. Scheduling (Phase 3) must precede dispatch UI (Phase 5).
- **Pitfall prevention governs grouping:** The five non-recoverable pitfalls (offline-first, tenant context in tasks, scheduling race, version columns, RLS) are all addressed in Phases 1-3. No user-visible feature is built before these are in place.
- **Risk front-loading:** The highest-complexity, highest-consequence components (sync engine, scheduling engine) are built before the lower-complexity UI work. This inverts the common mistake of building UI first and discovering infrastructure complexity too late.
- **Feature research confirms ordering:** FEATURES.md explicitly states "Multi-company SaaS must be first" and "Offline requires complete job workflow" — both align with the phase structure.
- **Architecture research confirms ordering:** ARCHITECTURE.md's "Build Order Implications" section maps directly to this phase structure (Core infra → Multi-tenant data → Offline sync → Scheduling → Job lifecycle → Role views → Notifications).

### Research Flags

Phases needing deeper research during planning (use `/gsd:research-phase`):
- **Phase 2 (Sync Engine):** Conflict resolution strategy per entity type needs explicit decisions; delta cursor protocol endpoint specification needed; workmanager background execution behavior on OEM Android builds needs device-specific documentation
- **Phase 3 (Scheduling Engine):** Travel time API selection (Google Maps vs. OpenRouteService) needs cost and quota modeling; multi-day availability blocking algorithm needs formal specification; slot pre-computation vs. on-demand tradeoff needs decision
- **Phase 6 (Auth):** Multi-tenant login UX (how users identify their tenant at login) needs design research; JWT token lifecycle and refresh strategy

Phases with standard patterns (skip `/gsd:research-phase`):
- **Phase 1 (Foundation):** PostgreSQL RLS, FastAPI middleware, Flutter project setup — all well-documented with code examples in research files
- **Phase 4 (Job Lifecycle):** Job CRUD, photo upload with presigned URLs — established patterns
- **Phase 5 (Role Views):** Role-based routing in go_router, Riverpod state for role gating — standard patterns; FCM integration is well-documented

---

## Confidence Assessment

| Area | Confidence | Notes |
|------|------------|-------|
| Stack | HIGH | All versions verified against pub.dev and PyPI as of 2026-03-04. Version compatibility matrix confirmed. Alternatives evaluated. |
| Features | HIGH | Cross-referenced across 7 competitor products and 14 industry sources. MVP boundary is well-reasoned. Differentiators confirmed against competitor gap analysis. |
| Architecture | HIGH (multi-tenancy, offline sync) / MEDIUM (scheduling engine internals) | Core patterns (RLS, outbox, Riverpod + Drift) are well-documented with code examples. Scheduling engine internals (pre-computation strategy, conflict resolution branching) have moderate confidence. |
| Pitfalls | MEDIUM-HIGH | Core patterns (RLS gaps, sync idempotency, migration discipline) are well-documented. Flutter OEM background execution behavior is community-sourced. |

**Overall confidence:** HIGH

### Gaps to Address

- **Scheduling engine algorithm detail:** The available-slot computation algorithm and multi-day blocking logic need formal specification before Phase 3 begins. The research provides the pattern but not the implementation specification.
- **Travel time API selection:** Google Maps vs. OpenRouteService vs. self-hosted OSRM — cost, quota, and terms of service need evaluation before Phase 3 planning.
- **Conflict resolution strategy per entity:** The research recommends "server-wins for schedules, field-merge for status updates" as a starting point, but the full decision matrix across all entity types needs to be defined in Phase 2 planning.
- **Multi-tenant login UX:** How a user identifies their company tenant at login (subdomain, company code, email domain) is not specified in the research and must be designed before Phase 6.
- **iOS background execution constraints:** iOS has more restrictive background execution than Android. The research notes workmanager supports iOS but does not detail iOS-specific constraints. This needs documentation review before Phase 2 finalization.
- **Calendar drag-and-drop library:** The research recommends building a drag-and-drop calendar but does not evaluate specific Flutter calendar packages. Library selection needs research before Phase 5 planning.

---

## Sources

### Primary (HIGH confidence)

- pub.dev — All Flutter package versions verified (flutter_riverpod 3.2.1, drift 2.32.0, go_router 17.1.0, dio 5.9.2, workmanager 0.9.0+3, freezed 3.2.5, patrol 4.2.0)
- pypi.org — All Python package versions verified (fastapi 0.135.1, sqlalchemy 2.0.48, pydantic 2.12.5, alembic 1.18.4, pytest 9.0.2, httpx 0.28.1)
- docs.flutter.dev/app-architecture/design-patterns/offline-first — Flutter offline-first patterns
- developer.android.com/topic/architecture/data-layer/offline-first — Android offline-first guidance
- aws.amazon.com/blogs/database/multi-tenant-data-isolation-with-postgresql-row-level-security — PostgreSQL RLS for SaaS
- fastapi.tiangolo.com/advanced/async-tests — Async testing patterns

### Secondary (MEDIUM confidence)

- getjobber.com, tooleduppro.com, fieldpulse.com, contractorplus.app, capterra.com — Competitor feature analysis (7 products, 14 sources cross-referenced)
- medium.com/@koushiksathish3 — FastAPI multi-tenancy patterns
- dinkomarinac.dev — Riverpod + Drift + PowerSync integration patterns
- codewithandrea.com — Flutter clean architecture with Riverpod
- betterstack.com — PostgreSQL EXCLUDE USING GIST for scheduling
- sachith.co.uk — Offline sync conflict resolution patterns (Feb 2026)
- geekyants.com — Offline-first Flutter implementation blueprint

### Tertiary (LOW confidence / needs validation)

- medium.com/@sparkleo — Flutter SQLite migration pitfalls (community source, validate during Phase 1)
- medium.com/@fourstrokesdigital — Flutter background task limitations on OEM Android (validate with device testing in Phase 2)

---

*Research completed: 2026-03-04*
*Ready for roadmap: yes*
