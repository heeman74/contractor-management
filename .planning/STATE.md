---
gsd_state_version: 1.0
milestone: v1.0
milestone_name: milestone
status: executing
stopped_at: "Completed 03-04-PLAN.md (REST API router + 47-test scheduling suite: GIST concurrency, DST correctness, multi-day all-or-nothing, travel time cache)"
last_updated: "2026-03-07T02:35:36.247Z"
last_activity: 2026-03-05 — WorkManager dispatcher, sync status provider, app bar subtitle, pull-to-refresh on 3 screens
progress:
  total_phases: 8
  completed_phases: 3
  total_plans: 16
  completed_plans: 16
  percent: 90
---

# Project State

## Project Reference

See: .planning/PROJECT.md (updated 2026-03-04)

**Core value:** Clients always know exactly what's happening with their job — no more chasing contractors for updates, no more scheduling conflicts, no more missed appointments.
**Current focus:** Phase 2 — Offline Sync Engine

## Current Position

Phase: 2 of 8 (Offline Sync Engine)
Plan: 4 of 5 in current phase — COMPLETE
Status: Phase 2 in progress — Plans 02-01 through 02-04 complete; only 02-05 remaining
Last activity: 2026-03-05 — WorkManager dispatcher, sync status provider, app bar subtitle, pull-to-refresh on 3 screens

Progress: [█████████░] 90%

## Performance Metrics

**Velocity:**
- Total plans completed: 0
- Average duration: —
- Total execution time: —

**By Phase:**

| Phase | Plans | Total | Avg/Plan |
|-------|-------|-------|----------|
| Phase 01-foundation | P01 | 20 min | — |
| Phase 01-foundation | P02 | 6 min | — |

**Recent Trend:**
- Last 5 plans: P01 (20 min), P02 (6 min)
- Trend: Fast

*Updated after each plan completion*
| Phase 01-foundation P03 | 6 | 2 tasks | 20 files |
| Phase 01-foundation P04 | 7min | 2 tasks | 17 files |
| Phase 01-foundation P05 | 7min | 2 tasks | 8 files |
| Phase 02-offline-sync-engine P02 | 4min | 2 tasks | 12 files |
| Phase 02-offline-sync-engine P01 | 5min | 3 tasks | 10 files |
| Phase 02-offline-sync-engine P03 | 5min | 2 tasks | 11 files |
| Phase 02-offline-sync-engine P04 | 5min | 2 tasks | 7 files |
| Phase 02-offline-sync-engine P05 | 7min | 2 tasks | 7 files |
| Phase 02-offline-sync-engine P06 | 3min | 2 tasks | 2 files |
| Phase 02-offline-sync-engine PP07 | 3min | 2 tasks | 4 files |
| Phase 03-scheduling-engine P01 | 18min | 2 tasks | 9 files |
| Phase 03-scheduling-engine P02 | 7min | 2 tasks | 7 files |
| Phase 03-scheduling-engine P03 | 8min | 2 tasks | 2 files |
| Phase 03-scheduling-engine P04 | 45 | 2 tasks | 9 files |

## Accumulated Context

### Decisions

Decisions are logged in PROJECT.md Key Decisions table.
Recent decisions affecting current work:

- Foundation: Flutter 3.32+ / Drift 2.32 / Riverpod 3.2 / go_router chosen; all versions verified against pub.dev 2026-03-04
- Foundation: FastAPI 0.115.12 (latest stable) + SQLAlchemy 2.0 + asyncpg; psycopg2 explicitly excluded (blocks async event loop)
- Foundation: PostgreSQL RLS + EXCLUDE USING GIST constraint mandatory from first migration — non-recoverable if retrofitted
- Foundation: Offline-first from first line of Flutter code — no UI widget may await HTTP directly
- Phase 2: Phase 3 (Scheduling Engine) depends only on Phase 1 — can run in parallel with Phase 2 if needed
- [Phase 01-foundation]: Flutter scaffold: uuid in runtime deps, setupServiceLocator async-ready, generated files excluded from git
- [Phase 01-foundation]: Drift pattern: tables in separate files under tables/, UUID PKs via clientDefault, primaryKey override not customConstraint
- [Phase 01-foundation P02]: pydantic-settings package required (pydantic v2 splits BaseSettings out)
- [Phase 01-foundation P02]: database.py imports tenant.py module to register after_begin listener at module load time
- [Phase 01-foundation P02]: pyproject.toml added for pytest asyncio_mode=auto and ruff config
- [Phase 01-foundation]: TradeType stored as comma-separated text in Drift, ARRAY(String) in PostgreSQL
- [Phase 01-foundation]: company_id excluded from UserCreate — always from TenantMiddleware ContextVar (tenant isolation)
- [Phase 01-foundation]: RoleAssignment uses Literal type for role field — Python type safety and OpenAPI schema accuracy
- [Phase 01-foundation]: StatefulShellRoute.indexedStack used instead of ShellRoute — preserves per-tab navigation stack; navigationShell.goBranch() for tab switching
- [Phase 01-foundation]: ValueNotifier bridge in routerProvider: ref.listen(authNotifierProvider) -> ValueNotifier<AuthState> -> GoRouter.refreshListenable prevents router rebuild on auth state change
- [Phase 01-foundation]: NavigationBar (Material 3) used instead of BottomNavigationBar; consistent with useMaterial3: true theme
- [Phase 01-foundation P05]: Integration tests use real get_db (no override) — full TenantMiddleware -> ContextVar -> SET LOCAL RLS path tested; mock session would bypass RLS proof
- [Phase 01-foundation P05]: Alembic migrations run in test setup (subprocess) — RLS policies are migration SQL; create_all cannot reproduce them
- [Phase 01-foundation P05]: autouse TRUNCATE before each test (not per-test transaction rollback) — multi-request tests require committed data visible across independent sessions
- [Phase 02-offline-sync-engine]: PostgreSQL trigger set_updated_at() used instead of SQLAlchemy onupdate — fires on bulk/raw SQL updates that bypass ORM
- [Phase 02-offline-sync-engine]: Default sync cursor is 2000-01-01T00:00:00Z for full first-launch download without client needing to pass epoch
- [Phase 02-offline-sync-engine]: on_conflict_do_nothing(index_elements=[id]) for idempotent UUID creates — silent on duplicate for sync retry deduplication
- [Phase 02-offline-sync-engine]: Payload serialization: manually build Map<String, dynamic> from Companion fields — toColumns() returns Map<String, Expression> which cannot be JSON-encoded
- [Phase 02-offline-sync-engine]: deleteCompany now performs soft delete (sets deletedAt) not hard delete — required for tombstone propagation across devices
- [Phase 02-offline-sync-engine]: connectivity_plus v7 returns List<ConnectivityResult> — checked with .any((r) => r != ConnectivityResult.none)
- [Phase 02-offline-sync-engine]: Two-phase connectivity check: interface up AND hasInternetAccess — avoids captive portal false positives triggering sync
- [Phase 02-offline-sync-engine]: After max retries (5), reset attemptCount=0 and leave as pending — retry on next connectivity cycle instead of abandoning
- [Phase 02-offline-sync-engine]: AppShell provides shared AppBar with SyncStatusSubtitle — individual screens no longer own their AppBar; always-visible subtitle without per-screen duplication
- [Phase 02-offline-sync-engine]: callbackDispatcher returns Future.value(true) on error — prevents OS WorkManager retry storm from exponential backoff on persistent failures
- [Phase 02-offline-sync-engine]: Stream merging via dart:async StreamController.broadcast() for combining connectivity + engine status streams without RxDart dependency
- [Phase 02-offline-sync-engine]: ConnectivityService refactored to accept optional Connectivity/InternetConnection constructor params for testability without breaking production behavior
- [Phase 02-offline-sync-engine]: SyncQueueDao.getAllItems() added as test/diagnostic helper for asserting parked item state — not used in production code paths
- [Phase 02-offline-sync-engine]: str | None cursor type chosen over datetime | None in sync endpoint — lets Pydantic accept empty string, parsing moved to handler body
- [Phase 02-offline-sync-engine]: Auth-screen redirect added as prefix check in AuthAuthenticated branch before _checkRoleAccess — /splash and /onboarding always redirect authenticated users to /home
- [Phase 02-offline-sync-engine]: Backfill via new migration 0003 (not amending 0002) — keeps migration history clean and auditable
- [Phase 02-offline-sync-engine]: Remove lastEngineStatus variable entirely after removing premature yield — dead code removed to keep provider lean
- [Phase 03-scheduling-engine]: op.execute raw SQL for all scheduling table creation — Alembic autogenerate unreliable for ExcludeConstraint + TSTZRANGE
- [Phase 03-scheduling-engine]: TravelTimeCache inherits Base directly — cache entries have no version/deleted_at columns unlike business entities
- [Phase 03-scheduling-engine]: TRUNCATE scheduling tables explicitly in conftest.py without CASCADE — prevents FK deadlocks from new scheduling table constraints
- [Phase 03-scheduling-engine]: httpx.AsyncClient chosen over openrouteservice-py — the official SDK is synchronous and blocks the async event loop
- [Phase 03-scheduling-engine]: Bidirectional cache key: sort coordinate pairs so A->B == B->A halves ORS API quota usage for scheduling round-trips
- [Phase 03-scheduling-engine]: Expired cache entries served as fallback on API failure — availability calculation degrades gracefully
- [Phase 03-scheduling-engine]: GeocodingProvider returns None on no match vs raises GeocodingError on API failure — callers must handle both explicitly
- [Phase 03-scheduling-engine]: SchedulingRepository encapsulates all DB ops including schedule CRUD helpers, keeping SchedulingService free of raw ORM queries
- [Phase 03-scheduling-engine]: Optional travel_provider in SchedulingService: None skips travel computation for pure-logic unit testing without external API mocking
- [Phase 03-scheduling-engine]: Two-level working hours override: ContractorDateOverride > ContractorWeeklySchedule > SchedulingConfig.default_working_hours with DST-safe zoneinfo conversion
- [Phase 03-scheduling-engine]: Plain APIRouter for scheduling (not CRUDRouter) — custom domain operations, not CRUD
- [Phase 03-scheduling-engine]: asyncio.gather with separate AsyncClient instances for concurrent race tests — each client gets separate DB session via ASGI transport
- [Phase 03-scheduling-engine]: pytest.mark.slow on 50-client load test — CI can filter with -m not slow for fast runs

### Pending Todos

None yet.

### Blockers/Concerns

- Phase 2 (Sync Engine): Conflict resolution strategy per entity type needs explicit decisions before planning — field-merge vs. server-wins decision matrix not fully specified
- Phase 3 (Scheduling Engine): Travel time API selection (Google Maps vs. OpenRouteService vs. OSRM) needs cost/quota modeling before planning
- Phase 3 (Scheduling Engine): Multi-day availability blocking algorithm needs formal specification before planning
- Phase 5 (Calendar UI): Flutter calendar drag-and-drop library not yet selected — needs research during plan-phase
- Phase 6 (Auth — deferred to v2): Multi-tenant login UX (how users identify their company at login) unspecified
- Flutter SDK not installed — flutter pub get and build_runner cannot run until SDK is installed

## Session Continuity

Last session: 2026-03-07T02:29:48.270Z
Stopped at: Completed 03-04-PLAN.md (REST API router + 47-test scheduling suite: GIST concurrency, DST correctness, multi-day all-or-nothing, travel time cache)
Resume file: None
