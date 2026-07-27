---
gsd_state_version: 1.0
milestone: v4.0
milestone_name: Financial Intelligence
status: verifying
stopped_at: Phase 33 context gathered
last_updated: "2026-07-27T16:13:39.851Z"
last_activity: 2026-07-27
progress:
  total_phases: 22
  completed_phases: 15
  total_plans: 81
  completed_plans: 78
---

# Project State

## Project Reference

See: .planning/PROJECT.md (updated 2026-07-24)

**Core value:** AI eliminates the chaos of multi-trade coordination — GCs always know where every trade stands, contractors always know what to do today, projects stay on track.
**Current focus:** Phase 32 — labor-rates-and-cost-rollup

## Current Position

Phase: 33
Plan: Not started
Status: Phase complete — ready for verification
Last activity: 2026-07-27

## Performance Metrics

**Velocity:**

- Total plans completed: 54 (v1.0) + 25 (v2.0) = 79 total (v3.0/v4.0 plan counts tracked separately below)
- v3.0 plans completed: phases 19-26 complete; phases 27, 29 also completed outside documented v3.0 roadmap scope
- v4.0 plans completed: 0 (roadmap just created)
- v4.0 trend: Not started

**By Phase (v4.0):**

| Phase | Plans | Total | Avg/Plan |
|-------|-------|-------|----------|
| 30-37 | TBD | - | - |
| Phase 30 P01 | 15min | 3 tasks | 3 files |
| Phase 30 P03 | 12min | 2 tasks | 4 files |
| Phase 30 P02 | 25min | 3 tasks | 6 files |
| Phase 30 P04 | 40min | 2 tasks | 1 files |
| Phase 31 P01 | 30min | 3 tasks | 9 files |
| Phase 31 P02 | 15min | 3 tasks | 5 files |
| Phase 31 P03 | 50min | 3 tasks | 13 files |
| Phase 31 P04 | 35min | 3 tasks | 12 files |
| Phase 31-actual-cost-capture P05 | 32min | 3 tasks | 9 files |
| Phase 32 P01 | 21min | 3 tasks | 7 files |
| Phase 32 P03 | 10min | 2 tasks | 7 files |
| Phase 32 P02 | 29min | 3 tasks | 7 files |
| Phase 32 P04 | 45min | 2 tasks | 11 files |
| Phase 32 P05 | 50min | 3 tasks | 10 files |

## Accumulated Context

### Decisions

- v3.0: Online-first architecture (AI requires connectivity), offline cache for daily task execution
- v3.0: Claude API with tool use for structured project planning (no local AI, no LangChain)
- v3.0: Same Flutter app for GC and contractors with role-based views
- v3.0: Project → Trade Scope → Task hierarchy with cross-trade dependency graph
- v3.0: AI conversation history stored in PostgreSQL JSONB — never in-memory dicts or app.state
- v3.0: Annotation storage is non-destructive (base photo immutable; annotation JSON in separate JSONB column)
- v3.0: WebSocket JWT re-validated server-side every 5 minutes; close with 4401 on expiry
- v3.0: Task-level dependencies as JSONB array on Task; cross-trade dependencies as edge table
- v4.0: finance.* permissions for money data — visibility restricted to owner + project_manager by default, backend-enforced via existing RBAC matrix
- v4.0: Roadmap phase ordering is data-dependency constrained — schema+RBAC foundation (30) must land before any cost/margin/budget/AI feature; AI features (36, 37) sequenced after their data inputs are stable (33/34 for profitability analysis, 32 for quote planning)
- v4.0: Effective-dated LaborRate table (not a mutable single column) chosen so historical margins stay reproducible after a worker's rate changes — decided at roadmap stage per research PITFALLS.md
- v4.0: MARG-04 (financial dashboard charts) deliberately sequenced after both margin (33) and budgeting (34) since it visualizes both; kept as its own phase (35) rather than folded into budgeting to keep the dashboard/reporting UI change independently reviewable
- [Phase 19]: ProjectTasks named to avoid class conflict; UserTradeSpecialties uses plain text FKs to avoid cross-feature coupling
- [Phase 19 P04]: watchProjectsForContractor uses two-stream approach (watch scopes → filter projects) — Drift selectOnly+JOIN fails with readTable for joined queries
- [Phase 19 P04]: Riverpod 3 forbids changing override count between pumpWidget calls; split drill-down navigation test into 3 separate testWidgets
- [Phase 19 P04]: Stream.value() in widget tests avoids pending-timer assertion from Drift watch streams
- [Phase 19 P01]: TradeCatalog UNIQUE(company_id,name) with ON CONFLICT DO NOTHING makes data migration idempotent
- [Phase 19 P01]: unnest() in migrations uses lateral join form for PostgreSQL 13 compatibility
- [Phase 19 P03]: ProjectService.create accepts user_id kwarg for status_history audit; routes pass current_user.user_id
- [Phase 19 P03]: FastAPI DELETE 204 endpoints require response_model=None (not response_class=Response)
- [Phase 19 P03]: SET LOCAL in test DB seeding uses f-string UUID (PostgreSQL SET LOCAL rejects parameterized $1)
- [Phase 19 P03]: Contractor specialty matching uses SQLAlchemy case() label .desc() ordering; non-filter queries return has_specialty_match=False
- [Phase 19]: [Phase 19 P05]: AddTradeScopeSheet created in Task 2 alongside ProjectDetail to satisfy import dependencies; Playwright strict mode fixed with first()/getByRole precision
- [Phase 20 P02]: TaskDependencies uses soft FK (no hard FK) from ProjectTasks.zoneId to ProjectZones — keeps table definitions decoupled
- [Phase 20 P02]: TaskDependencyDao.watchByProject joins through ProjectTasks → TradeScopes to filter by projectId — avoids needing a direct project FK on task_dependencies
- [Phase 20-dependency-engine]: ConflictService uses select_from(t1).join(t2, ...) — SQLAlchemy aliased() requires explicit FROM placement for self-joins
- [Phase 20-dependency-engine]: FF dependency type does NOT block successors; only FS/SS/SE set status=blocked
- [Phase 20-dependency-engine]: IntegrityError for duplicate zone names caught in ProjectZoneService → 409 Conflict
- [Phase 20-04]: Riverpod 3 AsyncNotifier.family uses factory (arg) => Notifier(arg) — no FamilyAsyncNotifier class exists
- [Phase 20-04]: InteractiveViewer(constrained: false) must not be wrapped in SingleChildScrollView — causes unbounded height constraints; tests need SizedBox bounds wrapper
- [Phase 20-04]: Phase 20 Gantt dependency creation deferred to Phase 21 — requires companyId from auth; local DFS cycle detection guards UI only
- [Phase 20-dependency-engine]: SVAR Gantt loaded via next/dynamic (ssr:false) to avoid SSR hydration issues; ILink type cast via as ILink['type'] since TLinkType not re-exported
- [Phase 20-dependency-engine]: Playwright route mocks ordered most-specific-first (conflicts/zones exact paths before general project ID substring match)
- [Phase 20-05]: useProjectDependencies uses sorted task ID join as queryKey — ensures stable TanStack Query cache key across re-renders; project-dependencies invalidation uses prefix key (no projectId) to clear all task-ID-keyed entries after dependency creation
- [Phase 20-06]: TaskDependenciesCompanion imported via app_database.dart show clause — Drift-generated companions only accessible via app_database barrel
- [Phase 20-06]: registerFallbackValue required for TaskDependenciesCompanion in mocktail any() matcher — non-nullable custom type needs explicit fallback in setUpAll
- [Phase 21]: anthropic SDK installed via uv pip into venv (pyproject.toml has no [project] section — requirements.txt is canonical)
- [Phase 21]: stream_turn and _call_with_retry are async generators (yield) — callers iterate with async for; retry only on APITimeoutError and RateLimitError
- [Phase 21]: StreamingResponse(text/event-stream) used instead of EventSourceResponse — fastapi.sse module not available in FastAPI 0.115
- [Phase 21]: intake/complete creates placeholder tasks per scope + FS dependency edges to represent D-23 cross-trade sequencing before real tasks are added
- [Phase 21]: AIImageUpload uses ON DELETE CASCADE from ai_conversations; JPEG normalization on upload; image_ref_id lookup returns None on missing image (chat degrades to text-only)
- [Phase 21]: SSE proxy pipes ReadableStream directly via upstreamRes.body — never buffers with .text()
- [Phase 21]: Pages at /projects/new/ai-intake placed outside (dashboard) route group for full-page layout without sidebar
- [Phase 21]: parseSSELine exported as pure function for independent unit testing (9 tests covering token/tool_call/done/error/edge cases)
- [Phase 21]: [Phase 21 P04]: dart:io HttpClient used for SSE streaming — flutter_client_sse does not support POST body; Dio cannot handle text/event-stream
- [Phase 21]: [Phase 21 P04]: parseSseEvent extracted as top-level function (not class method) to enable independent unit testing without AiSseClient instance
- [Phase 21]: Fake notifiers extend real Notifier class (not base Notifier<State>) — screen casts ref to concrete type, so fake must be subtype
- [Phase 21]: TaskPreviewList renders task titles as controlled <input> elements — Playwright assertions use locator('input[placeholder=Task title]') not getByText
- [Phase 21]: ChatBubble isStreaming:true appends cursor via AnimatedBuilder — Flutter tests use find.textContaining() not find.text() for streaming assertions
- [Phase 21]: Migration 0018 uses CREATE TABLE IF NOT EXISTS for idempotency — table existed from worktree without Alembic stamp
- [Phase 22-task-execution-and-photo-annotation]: CurrentUser has no email attribute — completed_by_name falls back to str(user_id); full name lookup deferred to a later plan
- [Phase 22-task-execution-and-photo-annotation]: [Phase 22 P01]: annotation_data accepted as Form JSON string in multipart upload (multipart cannot mix JSON body + UploadFile); parsed with json.loads in endpoint
- [Phase 22-task-execution-and-photo-annotation]: [Phase 22 P01]: TaskNote author_id is soft FK (no hard FK) consistent with project pattern; completed_by_name uses user_id string fallback
- [Phase 22]: TaskAttachmentDao uses sync queue outbox (not binary upload service) for task attachments in Phase 22 — binary upload can be layered on in a later phase
- [Phase 22]: annotationData stored as nullable TEXT on TaskAttachments; base photo immutable; annotation JSON as overlay (non-destructive)
- [Phase 22-task-execution-and-photo-annotation]: AsyncValue.value (not valueOrNull) is the Riverpod 3 pattern for nullable AsyncValue access in widget builds
- [Phase 22-task-execution-and-photo-annotation]: scopeNameMapProvider watches all company scopes for scopeId→tradeName lookup in MyTasksScreen without per-task scope queries
- [Phase 22-task-execution-and-photo-annotation]: url_launcher added for PDF system viewer launch (File URI scheme) in TaskDetailScreen attachment section
- [Phase 22]: Annotation JSON uses normalized 0-1 coordinates — no raw pixel values stored; enables cross-platform rendering at any resolution
- [Phase 22]: useRef (not useState) for annotation array in usePhotoAnnotation — prevents React re-renders from clearing canvas imperatively
- [Phase 22]: crypto.randomUUID() used instead of uuid package — built-in to modern browsers/Node.js; no package needed
- [Phase 22]: ScopeProgress class made public (not private _ScopeProgress) to allow widget-test provider overrides via Stream.value()
- [Phase 22]: tradeScopeProgressProvider uses asyncMap on watchTasksByScope stream — reactive to Drift changes without separate FutureProviders
- [Phase 22]: ScopeProgressCard inner component in React isolates useTasks hook per scope independently
- [Phase 23]: ChatMessage Drift data class conflicts with ai_models.dart ChatMessage; resolved with hide ChatMessage in AI provider imports
- [Phase 23]: ChatWsClient per-thread as Provider.autoDispose.family so WS connection closes when thread screen leaves the widget tree
- [Phase 23 P03]: WS membership check uses direct SELECT on chat_memberships (not list_threads_for_user) — avoids project_id requirement in WS URL context
- [Phase 23 P03]: ChatService.create_scope_thread deduplicates member list with seen set — prevents UniqueViolationError when contractor == gc user
- [Phase 23 P03]: since_seq pagination fetches ASC directly; before_seq fetches DESC then reverses — both return ASC to caller
- [Phase 23]: Drift Value() type aliased as drift.Value via import as drift to avoid name collision
- [Phase 23]: surfaceVariant deprecated — replaced with surfaceContainerHighest in chat widgets
- [Phase 23]: Chat attachment picker (ImagePicker/FilePicker) stubbed — actual picker integration deferred to follow-up plan
- [Phase 23-real-time-chat]: WebSocket token via GET /api/auth/ws-token — browser WS API cannot set headers; short-lived token in ?token= query param
- [Phase 23-real-time-chat]: @mention dropdown as absolute div (not Popover) — base-ui PopoverTrigger does not support asChild prop
- [Phase 23 P06]: _NoOpChatRepository stub prevents GetIt/DioClient lookup in widget tests — chatRepositoryProvider read in ChatScreen.initState post-frame callback
- [Phase 23 P06]: _threadScreenBaseOverrides() helper bundles chatDaoProvider + chatRepositoryProvider overrides for all ChatThreadScreen tests
- [Phase 23 P06]: tester.runAsync() escapes FakeAsync for Drift one-shot .get() queries — watch streams hang in FakeAsync context (testWidgets)
- [Phase 23 P06]: pump(600ms) flushes ChatInputBar 500ms typing debounce Timer — pending timers cause testWidgets framework to hang on teardown
- [Phase 24-gc-inspection-workflow]: [Phase 24 P01]: inspector_id, flagged_by, created_by are soft FKs (no hard FK), consistent with TaskNote.author_id pattern
- [Phase 24-gc-inspection-workflow]: [Phase 24 P01]: reblock_successors only re-blocks FS/SS/SE dependency types — FF does not block
- [Phase 24-gc-inspection-workflow]: [Phase 24 P01]: FCM rejection notification fires via asyncio.create_task — inspect endpoint never waits for FCM
- [Phase 24]: SiteWalkFlagDao.convertFlag performs 4 atomic writes in a single Drift transaction (flag status + sync entry + punch item + sync entry) — ensures consistency between flag and punch list state
- [Phase 24]: PunchListItemDao.watchByScopeId uses caseMatch for priority ordering (urgent=0, high=1, medium=2, low=3) — same pattern as TaskDao
- [Phase 24]: Sync handlers in core/sync/handlers/ (individual files per entity) — project uses this pattern, not a monolithic sync_handlers.dart
- [Phase 24]: UserRole.gc does not exist — GC role is UserRole.admin in this codebase; isGcOrAdmin checks admin role
- [Phase 24]: watchScopeById added to TradeScopeDao to support single-scope stream lookup for inspection checklist loading
- [Phase 24]: Fake DAOs with Stream.value() for Flutter widget tests (avoids Drift pending timer errors)
- [Phase 24]: _get_task_status() helper via list endpoint (no single-task GET exists in tasks API)
- [Phase 25-per-trade-billing]: Pydantic v2 model_validator: combine job/scope linkage + discount validation in single method — Pydantic only runs last validator with same name
- [Phase 25-per-trade-billing]: mark_invoiced uses raw SQL UPDATE ... WHERE is_invoiced=FALSE RETURNING id — atomic double-billing prevention; 0 rows = already invoiced (409 Conflict)
- [Phase 25-per-trade-billing]: [Phase 25 P02]: BillingMilestones uses soft FK for tradeScopeId (no .references()) — keeps table definitions decoupled, consistent with PunchListItems pattern
- [Phase 25-per-trade-billing]: [Phase 25 P02]: jobId made nullable on Invoices/Quotes via alterTable rewrite — SQLite cannot ALTER COLUMN; alterTable rewrites table with current column definitions
- [Phase 25-per-trade-billing]: [Phase 25 P02]: sync handler registered via service_locator.dart + sync_engine.dart entity types list — project uses individual handler files pattern (not monolithic sync_handlers.dart)
- [Phase 25-per-trade-billing]: Drift stream.first must be inside tester.runAsync() in testWidgets — async context required for Drift SQLite queries to resolve
- [Phase 25-per-trade-billing]: BillingMilestoneCreate and QuoteCreate require FK fields in request body — Pydantic validates before endpoint logic can inject URL path params
- [Phase 26]: ChecklistSyncHandler is pull-only — daily checklists are server-generated; push throws UnsupportedError to fail loudly if misused
- [Phase 26]: DailyChecklists deletedAt is TEXT (not DateTimeColumn) to match ISO date string pattern used by checklistDate
- [Phase 26]: todayChecklistProvider uses Future.microtask for background API fetch — avoids blocking the stream while refreshing on subscribe
- [Phase 26]: Non-streaming Claude API for cron batch jobs — streaming SSE is only for interactive chat
- [Phase 26]: FORCE ROW LEVEL SECURITY on daily_checklists and dashboard_alerts — prevents superuser bypass
- [Phase 26]: Checklist upsert via PostgreSQL INSERT ON CONFLICT DO UPDATE — cron re-runs are idempotent
- [Phase 26]: ILink type cast uses 'e2s' string (not numeric 0) to satisfy SVAR ILink['type'] TLinkType constraint
- [Phase 26]: Blocked tasks stay in Claude prompt with dep=blocked annotation — service annotates them rather than filtering them out
- [Phase 26]: Flutter GoRouter navigation tests use structural verification (InkWell presence) rather than triggering actual navigation in widget tests
- [Phase 30]: Finance keys appended as the last catalog group (after Portal), matching UI-SPEC copywriting contract
- [Phase 30]: Admin exclusion implemented via derived _FINANCE_ONLY_KEYS set subtraction (mirrors _OWNER_ONLY_KEYS pattern), not a hand-maintained list
- [Phase 30-03]: finance_scrub helper shipped as tested utility only — not wired into AI dict-builders this phase (nothing to strip yet, avoids dead code per CLAUDE.md)
- [Phase 30-03]: FINANCIAL_ALERT_TYPES ships empty — dashboard alert filter is provably inert today, ready for Phase 36 to populate
- [Phase 30]: [Phase 30 P02]: CostEntry anchors job_id/trade_scope_id (D-04) while Budget anchors project_id/trade_scope_id (D-09) — deliberate asymmetry
- [Phase 30]: [Phase 30 P02]: cost_categories seeded via plain INSERT before ENABLE RLS (new table); company_role_permissions PM finance-key backfill instead loops per-company with SET LOCAL app.current_company_id since that table has carried FORCE RLS since migration 0027
- [Phase 30]: [Phase 30-04]: Simulated pre-migration company via direct SQL (bypassing RbacRepository) since seed_two_tenants companies already get the post-migration default matrix
- [Phase 30]: [Phase 30-04]: Used existing allowed 'dependency_risk' alert type as documented stand-in financial type when monkeypatching FINANCIAL_ALERT_TYPES for the leak-filter test
- [Phase 31]: 31-01: CostEntryUpdate keeps job_id/trade_scope_id anchor immutable — avoids re-deriving XOR consistency on edit
- [Phase 31]: 31-01: cost_receipts is a dedicated table (not a shared polymorphic attachments table), consistent with existing per-domain attachment convention
- [Phase 31]: 31-02: delete_receipt validates receipt.cost_entry_id matches the URL's cost_entry_id (404 on mismatch) — confused-deputy guard on the nested delete route
- [Phase 31]: 31-02: cost-receipts serve_router branch copies task-attachments' RLS-scoped existence-query pattern verbatim (not a UUID-shape check) to enforce cross-tenant 404
- [Phase 31]: 31-03: web CostEntryList ships delete-only (edit deferred, useUpdateCostEntry hook ready) — not required by this plan's must_haves/acceptance criteria
- [Phase 31]: 31-03: cost-capture Playwright E2E drives trade-scope detail via Projects sidebar (not the jobs list) — simpler SPA-nav auth/permissions path, same AddCostDialog/CostEntryList components as job detail
- [Phase 31]: 31-04: Mobile receipts follow Attachment/AttachmentUploadService (not TaskAttachmentDao, which has no registered push handler)
- [Phase 31]: 31-04: CostEntrySyncHandler registered for outbound push only — not added to sync_engine.dart pullDelta entityTypes (cost data stays out of the company-wide /sync delta, Pitfall 2)
- [Phase 31]: 31-04: watchByProject takes an explicit jobIds param since mobile Jobs table has no projectId FK to join through
- [Phase 31-actual-cost-capture]: 31-05: financePermissionProvider is mobile's first fine-grained (finance.*) permission check, backed by GET /me/permissions — not derived from UserRole
- [Phase 31-actual-cost-capture]: 31-05: FinanceRepository.fetchProjectRollup returns total + distinct jobIds (from its own response) to drive CostEntryDao.watchByProject locally — mobile Jobs has no projectId FK
- [Phase 31-actual-cost-capture]: 31-05: Costs create action stays on job/trade-scope screens only; project detail shows a read-only rollup (no anchor-picker create path)
- [Phase 32-01]: PEP 695 type parameters (def f[RateT: EffectiveDatedRate]) instead of module-level TypeVar — ruff UP047 enforces modern generic syntax
- [Phase 32-01]: Labor rate read AND write both gated finance.rates.manage — zero-exception posture (admin and worker 403 even on their own rate)
- [Phase 32-01]: UTC work-day convention (clocked_in_at.astimezone(UTC).date()); users.timezone deliberately unused so labor figures stay reproducible
- [Phase 32-labor-rates-and-cost-rollup]: 32-03: Rate dates render as Mon D, YYYY via string-splitting formatter (no Date()) so date-only ISO strings never shift a day across timezones
- [Phase 32-labor-rates-and-cost-rollup]: 32-03: RateHistoryDialog form resets on close via onOpenChange wrapper, not useEffect — react-hooks/set-state-in-effect forbids reset-on-open effects under --max-warnings 0
- [Phase 32-labor-rates-and-cost-rollup]: 32-03: useAddLaborRate invalidates the labor-rates prefix plus cost-entries so Team column and derived labor breakdowns both refresh after an append
- [Phase 32]: LABOR_CATEGORY_NAME single-sourced in labor_derivation.py — repository/service both import it (repository cannot import from service without a cycle)
- [Phase 32]: Legacy labor-category cost entries fold into the derived labor row on jobs/projects; on trade scopes (labor=None) they stay as an ordinary category row so no money hides
- [Phase 32]: ProjectCostRollup frozen dataclass replaces tuple return from rollup_for_project; labor field carries the folded total so legacy manual labor counts exactly once
- [Phase 32-04]: Playwright job-detail tests log in through the UI then SPA-navigate via the Jobs list row — Redux isAuthenticated is set only by the login page, so direct page.goto leaves usePermissions disabled and finance-gated cards never render
- [Phase 32-04]: orderedCategories filters the reserved labor name so legacy labor-categorized API rows can never render a second Labor row; labor renders only from breakdown.labor
- [Phase 32]: 32-05: Mobile breakdown data is online-fetched only, never persisted to Drift — labor requires server-side rate resolution and rate data never reaches the device
- [Phase 32]: 32-05: costRollupTotalProvider refactored onto a shared _projectRollupFetchProvider (public signature unchanged) so the project total and breakdown share one network call
- [Phase 32]: 32-05: Riverpod 3 Override type must be imported via flutter_riverpod/misc.dart show Override; widget-bearing test files import drift as show Value to avoid the Column name clash

### Pending Todos

None yet. v4.0 roadmap created; next step is `/gsd:plan-phase 30`.

### Blockers/Concerns

- Phase 21: Confirm ANTHROPIC_API_KEY is provisioned and model IDs (claude-opus-4-5, claude-haiku-3-5) are available before starting AI work
- Phase 23: Confirm REDIS_URL is present in backend config (assumed for slowapi rate limiting) before WebSocket pub/sub design
- Phase 19: Confirm current Drift schema version number to number new migrations correctly
- Phase 30 (v4.0): Orphan job / cost-anchor resolution algorithm (jobs with no trade_scope/project link) has no existing research spec — needs a concrete design decision before the cost_entries/budgets migration ships (per research SUMMARY.md gap)
- Phase 32 (v4.0): Burden rate default value not specified by research — labor cost ships unburdened (wage rate only) per v4.0 scope; flag explicitly in UI/AI output per PITFALLS.md
- Phase 32 (v4.0): Mobile scope for trade-scope/task time tracking is an open decision flagged by research — confirm during Phase 32 planning whether v4.0 labor-cost-from-time-entries is job-only or also covers trade-scope/task-level time entries on mobile
- Phase 34 (v4.0): Overrun-alert projection algorithm (trend/velocity-based vs. static threshold) needs a short design pass during Phase 34 planning — research flags this as unspecified
- Phase 36 (v4.0): AI cost-data completeness threshold (minimum cost entries / days elapsed before AI analysis runs) needs a product decision during Phase 34/36 planning

## Session Continuity

Last session: 2026-07-27T16:13:39.843Z
Stopped at: Phase 33 context gathered
Resume file: .planning/phases/33-profit-margin-tracking/33-CONTEXT.md
