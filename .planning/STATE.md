---
gsd_state_version: 1.0
milestone: v1.0
milestone_name: milestone
status: executing
stopped_at: Completed 05-02-PLAN.md
last_updated: "2026-03-09T18:59:34.554Z"
last_activity: 2026-03-05 — WorkManager dispatcher, sync status provider, app bar subtitle, pull-to-refresh on 3 screens
progress:
  total_phases: 8
  completed_phases: 4
  total_plans: 31
  completed_plans: 27
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
| Phase 04-job-lifecycle P05 | 5min | 2 tasks | 15 files |
| Phase 04-job-lifecycle P01 | 18min | 2 tasks | 11 files |
| Phase 04-job-lifecycle P03 | 4min | 2 tasks | 4 files |
| Phase 04-job-lifecycle P02 | 5min | 2 tasks | 2 files |
| Phase 04-job-lifecycle P07 | 15min | 2 tasks | 15 files |
| Phase 04-job-lifecycle P06 | 90 | 2 tasks | 14 files |
| Phase 04-job-lifecycle P04 | 11min | 2 tasks | 7 files |
| Phase 04-job-lifecycle P08 | 120min | 2 tasks | 8 files |
| Phase 04-job-lifecycle P09 | 2min | 2 tasks | 5 files |
| Phase 05-calendar-and-dispatch-ui P01 | 13min | 2 tasks | 14 files |
| Phase 05-calendar-and-dispatch-ui P02 | 13min | 3 tasks | 11 files |

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
- [Phase 04-job-lifecycle]: JSON TEXT columns for statusHistory/tags in Drift (SQLite has no JSONB); decoded at domain layer
- [Phase 04-job-lifecycle]: DioClient.pushWithIdempotency extended with method param (default POST) enabling PATCH/DELETE sync ops
- [Phase 04-job-lifecycle]: Job.bookings relationship uses primaryjoin with foreign() string expression — Booking.job_id has no ORM-level ForeignKey() (FK lives only in DB via migration 0008 ALTER TABLE)
- [Phase 04-job-lifecycle]: StrEnum chosen for JobStatus/Priority/Urgency/Direction — type-safe comparisons and accurate OpenAPI schema generation
- [Phase 04-job-lifecycle]: _create_job_row helper added to scheduling conftest — bookings_job_id_fkey (migration 0008) requires real jobs rows; seed_contractor provisions one stub job per test run
- [Phase 04-job-lifecycle]: RequestService._accept_request creates Job directly (not via JobService) — avoids circular service import while still pre-filling all fields from request
- [Phase 04-job-lifecycle]: _validate_rating_window: no 'complete' entry in status_history treated as open window — supports invoiced-without-complete flow without blocking ratings
- [Phase 04-job-lifecycle]: Anonymous request submission with submitted_email creates new User+UserRole(client) inline — reuses same User model creation pattern from Phase 1 UserService
- [Phase 04-job-lifecycle]: cancel_job_bookings uses single bulk UPDATE statement (not a loop) to soft-delete bookings
- [Phase 04-job-lifecycle]: original_status captured before job.status mutation to correctly detect backward direction in booking cancellation
- [Phase 04-job-lifecycle]: soft_delete_job sets deleted_at (admin removal) distinct from transition_status(cancelled) which sets status only keeping job visible
- [Phase 04-job-lifecycle]: Admin screen re-export pattern: features/admin/presentation/screens/ files re-export from features/jobs/ — router import paths remain stable while implementation follows feature-first structure
- [Phase 04-job-lifecycle]: Accept backend-only job creation: POST /api/v1/jobs/requests/{id}/review with action=accepted; no client-side job creation — backend does atomic job + request status update
- [Phase 04-job-lifecycle]: StreamProvider.autoDispose.family used for job detail — FamilyAsyncNotifier does not exist in Riverpod 3
- [Phase 04-job-lifecycle]: StateProvider imported from package:riverpod/legacy.dart — moved out of flutter_riverpod main export in Riverpod 3
- [Phase 04-job-lifecycle]: InternetConnection().hasInternetAccess used directly in wizard — ConnectivityService not designed for one-shot queries
- [Phase 04-job-lifecycle]: CRM screens (ClientCrmScreen, ClientDetailScreen, RequestReviewScreen) implemented in Plan 06 ahead of Plan 07 — required by router
- [Phase 04-job-lifecycle]: scheduling.models side-effect import must precede CrmService import in router — crm_repository.py triggers configure_mappers() via joinedload at class definition time before Booking is in the mapper registry
- [Phase 04-job-lifecycle]: response_model=None required on all status_code=204 DELETE routes in FastAPI 0.115 to avoid AssertionError
- [Phase 04-job-lifecycle]: isort: split comment preserves mandatory import ordering when side-effect imports must precede configure_mappers() trigger
- [Phase 04-job-lifecycle P08]: Route ordering in FastAPI: /jobs/requests* and /jobs/request/{company_id} must be declared BEFORE /jobs/{job_id} or FastAPI matches "requests" as UUID path param (422)
- [Phase 04-job-lifecycle P08]: Web form RLS: set_current_tenant_id(company_id) must be called in submit_job_request_form before service call to enable anonymous User creation under RLS without JWT
- [Phase 04-job-lifecycle P08]: CrmRepository.soft_delete_property method required because inherited soft_delete targets ClientProfile (repository model type), not ClientProperty
- [Phase 04-job-lifecycle P08]: Seed idempotency: SET LOCAL RLS context before SELECT COUNT existence checks — RLS hides rows from appuser without app.current_company_id set
- [Phase 04-job-lifecycle P08]: asyncpg SET LOCAL incompatibility: parameterized SET commands fail with PostgresSyntaxError; use f-string formatting with UUID values (safe — UUIDs from PostgreSQL not user input)
- [Phase 04-job-lifecycle]: image_picker ^1.1.2 added as production dependency; no try/catch around pickImage per CLAUDE.md; jobRequestForm as sibling route in Branch 6; context.go() for portal-to-form navigation
- [Phase 05-calendar-and-dispatch-ui]: Drift schema v4: Bookings + JobSites tables added via migration from v3
- [Phase 05-calendar-and-dispatch-ui]: JobSiteSyncHandler is pull-only — push() throws StateError (job sites are read-only on mobile)
- [Phase 05-calendar-and-dispatch-ui]: delay endpoint declared BEFORE GET /jobs/{job_id} to prevent FastAPI route shadowing
- [Phase 05-calendar-and-dispatch-ui]: bookings/job_sites fields in SyncResponse default to empty list for Phase 4 client backwards compatibility
- [Phase 05-calendar-and-dispatch-ui]: PageView replaced with contractorPageIndexProvider StateProvider pagination — avoids ScrollController lifecycle complexity across pages
- [Phase 05-calendar-and-dispatch-ui]: UserDao accessed via AppDatabase.userDao (not registered in GetIt) — matches user_providers.dart pattern
- [Phase 05-calendar-and-dispatch-ui]: Default 06:00–18:00 blocked intervals are placeholders in ContractorLane — Plan 03 wires real ContractorWeeklySchedule data
- [Phase 05-calendar-and-dispatch-ui]: ScheduleScreen re-export pattern: shared/screens/schedule_screen.dart re-exports from feature-first path to keep router imports stable

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

Last session: 2026-03-09T18:59:34.546Z
Stopped at: Completed 05-02-PLAN.md
Resume file: None
