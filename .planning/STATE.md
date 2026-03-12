---
gsd_state_version: 1.0
milestone: v1.0
milestone_name: milestone
status: completed
stopped_at: Completed 06-field-workflow-06-PLAN.md
last_updated: "2026-03-12T01:26:26.400Z"
last_activity: "2026-03-11 — Phase 6 Plan 06: comprehensive test suite for all field workflow features (FIELD-01 through FIELD-04)"
progress:
  total_phases: 8
  completed_phases: 6
  total_plans: 38
  completed_plans: 38
  percent: 97
---

# Project State

## Project Reference

See: .planning/PROJECT.md (updated 2026-03-04)

**Core value:** Clients always know exactly what's happening with their job — no more chasing contractors for updates, no more scheduling conflicts, no more missed appointments.
**Current focus:** Phase 2 — Offline Sync Engine

## Current Position

Phase: 6 of 8 (Field Workflow) — COMPLETE
Plan: 6 of 6 in phase (06) — ALL COMPLETE
Status: Phase 6 Complete — All plans 00-06 completed
Last activity: 2026-03-11 — Phase 6 Plan 06: comprehensive test suite for all field workflow features (FIELD-01 through FIELD-04)

Progress: [█████████▉] 97%

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
| Phase 05-calendar-and-dispatch-ui P03 | 18min | 2 tasks | 8 files |
| Phase 05-calendar-and-dispatch-ui P03 | 18 | 2 tasks | 8 files |
| Phase 05-calendar-and-dispatch-ui P04 | 26min | 2 tasks | 6 files |
| Phase 05-calendar-and-dispatch-ui PP05 | 16min | 2 tasks | 8 files |
| Phase 05-calendar-and-dispatch-ui P06 | 45min | 2 tasks | 6 files |
| Phase 06-field-workflow P01 | 30min | 2 tasks | 13 files |
| Phase 06-field-workflow P00 | 2min | 2 tasks | 13 files |
| Phase 06-field-workflow P02 | 25min | 2 tasks | 17 files |
| Phase 06-field-workflow P05 | 35min | 2 tasks | 8 files |
| Phase 06-field-workflow P04 | 35min | 2 tasks | 8 files |
| Phase 06-field-workflow P06 | 60min | 2 tasks | 13 files |

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
- [Phase 05-calendar-and-dispatch-ui P03]: BookingDragData primitive type (not String) — enables reassign vs create detection via existingBookingId
- [Phase 05-calendar-and-dispatch-ui P03]: Conflict check LOCAL ONLY via Drift stream — instant feedback, works offline, no HTTP during drag
- [Phase 05-calendar-and-dispatch-ui P03]: conflictInfoProvider written on drag rejection, read on pointer-up in schedule_screen — avoids DragTarget/Listener coupling
- [Phase 05-calendar-and-dispatch-ui P03]: DragTarget strips limited to 06:00-20:00 (56 strips per lane) — prevents 96-widget full-24h overhead
- [Phase 05-calendar-and-dispatch-ui P03]: createBooking convenience method on BookingDao accepts primitives — keeps BookingsCompanion construction inside DAO layer
- [Phase 05-calendar-and-dispatch-ui P03]: UndoStack capped at 10 items — prevents unbounded memory growth; oldest dropped on overflow
- [Phase 05-calendar-and-dispatch-ui P03]: MultiDayWizardDialog: internet check before suggest-dates call; offline degrades gracefully (manual entry)
- [Phase 05-calendar-and-dispatch-ui P03]: LongPressDraggable + resize GestureDetector coexist: LPD requires long press, resize uses immediate vertical drag
- [Phase 05-calendar-and-dispatch-ui]: OverdueJobInfo returned as enriched model from overdueJobsProvider replacing raw JobEntity list
- [Phase 05-calendar-and-dispatch-ui]: Report Delay placed in bottomNavigationBar not FAB — visible on all three tabs
- [Phase 05-calendar-and-dispatch-ui]: DelayJustificationDialog.show() static factory reads JobDao from GetIt directly — clean API, avoids provider coupling inside dialog
- [Phase 05-calendar-and-dispatch-ui]: GestureDetector.onHorizontalDragEnd for week/month swipe navigation — avoids PageView scroll controller lifecycle complexity in paginated contractor rows
- [Phase 05-calendar-and-dispatch-ui]: ProviderScope.containerOf(context).read() in GoRouter builder for synchronous role-based screen selection (redirect guarantees auth resolved before builder)
- [Phase 05-calendar-and-dispatch-ui]: _ContractorHeader upgraded from StatelessWidget to ConsumerWidget for admin role check via authNotifierProvider
- [Phase 05-calendar-and-dispatch-ui]: scheduleSettings as top-level GoRoute (not shell branch) — push-accessible from admin calendar long-press and contractor gear icon without branch binding
- [Phase 05-calendar-and-dispatch-ui P06]: Stub notifiers for ProviderScope overrides must extend original notifier class (e.g., class _StubBookingsNotifier extends BookingsForDateNotifier) — Riverpod 3 overrideWith() enforces exact type match
- [Phase 05-calendar-and-dispatch-ui P06]: Ambiguous imports resolved with 'as' prefix alias — jobDaoProvider defined in both job_providers.dart and calendar_providers.dart
- [Phase 05-calendar-and-dispatch-ui P06]: BookingDao Drift tests written correctly against source API but fail dart analyze (pre-existing: build_runner not run, Bookings table missing from .g.dart)
- [Phase 06-field-workflow]: Wave 0 stub naming includes target plan number for traceability (e.g., 'plan 06-02')
- [Phase 06-field-workflow]: Attachments use dedicated binary upload service (no sync_queue text outbox) — AttachmentUploadService handles multipart upload in Plan 06-03
- [Phase 06-field-workflow]: TimeEntryDao.clockIn auto-closes any existing active session before creating new one — one-active-session-per-contractor invariant enforced in DAO layer
- [Phase 06-field-workflow]: GPS columns use addColumn migration (not new table) — GPS is a property of the job, not a separate entity

- [Phase 06-field-workflow P01]: Attachment remote_url stored as /files/{path} matching StaticFiles mount in main.py; uploads/ dir re-exposed at both /uploads and /files
- [Phase 06-field-workflow P01]: GPS geocode non-fatal: broad Exception caught, gps_address=None stored, retry on next sync via update_job_gps
- [Phase 06-field-workflow P01]: create_time_entry auto-transitions job from scheduled->in_progress on first contractor clock-in
- [Phase 06-field-workflow P01]: adjust_time_entry appends to adjustment_log via list replacement (Pitfall 3: never in-place JSONB append)

- [Phase 06-field-workflow P05]: timerNotifierProvider is NOT autoDispose — ticker must survive navigation away from contractor jobs screen
- [Phase 06-field-workflow P05]: Riverpod 3.2.1 uses .value (not .valueOrNull) on AsyncValue<T> — valueOrNull does not exist in this version
- [Phase 06-field-workflow P05]: Clock In/Clock Out in ContractorJobCard navigates to TimerScreen rather than performing inline — session history always visible
- [Phase 06-field-workflow P05]: Status transitions (scheduled→in_progress etc.) via long-press on status badge in ContractorJobCard, not action bar
- [Phase 06-field-workflow P04]: Grid overlay is a separate CustomPaint layer on the Stack — excluded from DrawingController canvas and therefore from PNG export
- [Phase 06-field-workflow P04]: GPS fields (gpsLatitude, gpsLongitude, gpsAddress) added to JobEntity manually in generated files since build_runner unavailable — fields were missing from Plan 02
- [Phase 06-field-workflow P06]: drawing_pad_screen.dart rewritten with native CustomPainter — flutter_drawing_board v1 lacks SimpleLine/Eraser/Rectangle/Circle APIs used in original implementation
- [Phase 06-field-workflow P06]: noteCountProvider changed from StreamProvider to Provider.autoDispose.family — Riverpod 3 StreamProvider has no .stream getter
- [Phase 06-field-workflow P06]: conftest.py clean_tables updated to include attachments, time_entries, job_notes — Phase 6 tables must be truncated to prevent cross-test data pollution
- [Phase 06-field-workflow P06]: Riverpod 3 StreamProvider.family override pattern: provider(id).overrideWith((ref) => Stream.value(data)) — not class-based notifier override

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

Last session: 2026-03-11T00:00:00.000Z
Stopped at: Completed 06-field-workflow-06-PLAN.md
Resume file: None
