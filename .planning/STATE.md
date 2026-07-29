---
gsd_state_version: 1.0
milestone: v4.0
milestone_name: Financial Intelligence
status: verifying
stopped_at: Completed 36-10-PLAN.md
last_updated: "2026-07-29T23:48:13.526Z"
last_activity: 2026-07-29
progress:
  total_phases: 22
  completed_phases: 19
  total_plans: 115
  completed_plans: 112
---

# Project State

## Project Reference

See: .planning/PROJECT.md (updated 2026-07-24)

**Core value:** AI eliminates the chaos of multi-trade coordination — GCs always know where every trade stands, contractors always know what to do today, projects stay on track.
**Current focus:** Phase 36 — ai-profitability-analysis

## Current Position

Phase: 36 (ai-profitability-analysis) — EXECUTING
Plan: 10 of 10
Status: Phase complete — ready for verification
Last activity: 2026-07-29

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
| Phase 33 P01 | 7min | 3 tasks | 4 files |
| Phase 33 P02 | 25min | 2 tasks | 3 files |
| Phase 33 P05 | 13min | 3 tasks | 6 files |
| Phase 33 P04 | 30min | 3 tasks | 9 files |
| Phase 33 P03 | 27min | 2 tasks | 5 files |
| Phase 34 P01 | 13min | 3 tasks | 11 files |
| Phase 34 P02 | 34min | 3 tasks | 6 files |
| Phase 34 P05 | 18min | 3 tasks | 7 files |
| Phase 34 P04 | 28min | 3 tasks | 9 files |
| Phase 34 P03 | 40min | 3 tasks | 6 files |
| Phase 34 P07 | 13min | 3 tasks | 13 files |
| Phase 34 P06 | 27min | 3 tasks | 5 files |
| Phase 34 P08 | 34min | 3 tasks | 6 files |
| Phase 35 P04 | 9min | 3 tasks | 5 files |
| Phase 35-web-financial-dashboard P02 | 54min | 3 tasks | 1 files |
| Phase 35 P01 | 96min | 3 tasks | 7 files |
| Phase 35 P03 | 27min | 3 tasks tasks | 10 files files |
| Phase 35 P05 | 79min | 3 tasks tasks | 6 files files |
| Phase 35 P06 | 11min | 3 tasks | 5 files |
| Phase 35 P09 | 25min | 3 tasks | 10 files |
| Phase 35 P10 | 11min | 3 tasks tasks | 8 files files |
| Phase 35 P07 | 24min | 3 tasks tasks | 6 files files |
| Phase 35 P11 | 23min | 3 tasks tasks | 1 file files |
| Phase 35 P08 | 52 min | 3 tasks | 2 files |
| Phase 36 P02 | 15min | 3 tasks tasks | 9 files files |
| Phase 36 P01 | 20min | 3 tasks tasks | 7 files files |
| Phase 36 P04 | 8min | 3 tasks tasks | 4 files files |
| Phase 36 P03 | 15min | 3 tasks tasks | 3 files files |
| Phase 36 P05 | 12min | 3 tasks tasks | 5 files files |
| Phase 36 P06 | 2h 25m | 2 tasks | 5 files |
| Phase 36 P07 | 26min | 3 tasks tasks | 3 files files |
| Phase 36 P08 | 26min | 2 tasks tasks | 2 files files |
| Phase 36 P09 | 26min | 2 tasks tasks | 4 files files |
| Phase 36 P10 | 46min | 3 tasks tasks | 6 files files |

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
- [Phase 33]: 33-01: discount_for/tax_for keep default banker's-rounding quantize (no ROUND_HALF_UP) — bit-for-bit identical to shipped invoice/quote schema math so existing totals never shift
- [Phase 33]: 33-01: ROUND_HALF_UP applies only in margin_percent_for (one-decimal margin percent); summarize_margin forces revenue_basis to none when revenue is absent (D-07 self-consistent shape)
- [Phase 33]: 33-02: Test fixtures approve quotes via raw SQL (SET LOCAL + UPDATE), never POST /quotes/{id}/approve — the endpoint demands sent/viewed transitions and creates jobs for project-level quotes
- [Phase 33]: 33-02: One shared _to_anchored_amounts row mapper serves invoice and quote aggregates — both queries lead with the same six columns; quote's trailing created_at ignored via row[:6]
- [Phase 33]: 33-04: FinanceFlagChip extracts the one amber honesty-chip recipe; unrated and incomplete-data chips share it so they cannot drift
- [Phase 33]: 33-04: isBreakdownEmpty treats a present margin with revenueBasis != none as non-empty so the state-12 legacy zero-cost job always shows its honesty flag
- [Phase 33]: 33-04: negative margins format sign-before-symbol (-$350.00) via formatMarginDollars since formatCurrency would render $-350.00
- [Phase 33]: MarginSummary nullable fields are optional constructor params (basis stays required) — reconciles the 33-05 plan snippet with its own no-required-margin acceptance criterion
- [Phase 33]: Phase-33 project-variant e2e overrides projectCostBreakdownProvider directly — the real fetch path requires AuthAuthenticated; Dio-level path covered by job/trade-scope surface tests
- [Phase 33]: 33-03: Project margin always fetches both revenue legs; _anchor_revenues discards quotes at invoiced anchors (never conditional query skipping) so mixed invoiced/quoted anchors resolve per D-01
- [Phase 33]: 33-03: _quoted_revenue quantizes the quote leg to cents — SUM(quantity*unit_price) subtotals carry 5 decimals and would serialize as 1500.00000 otherwise
- [Phase 33]: 33-03: InvoiceService.generate_manual fixed to honor the Phase 25 trade_scope_id anchor — scope invoices validate the scope, skip the job status machine, and never mark a job invoiced
- [Phase 34]: 34-01: Alembic revision ID shortened to 0035_budget_alerts_quote_chain — plan's 34-char ID overflowed alembic_version varchar(32); migration filename unchanged
- [Phase 34]: 34-01: alert_types.py is the constants-only single source of dashboard alert_type values; service.py re-imports FINANCIAL_ALERT_TYPES/SCHEDULE_SLIP_ALERT_TYPE so monkeypatch paths and module-global reads keep working
- [Phase 34]: 34-01: budget_math reuses PERCENT_MULTIPLIER (margin_math) and CENTS (labor_derivation); ZERO_MONEY not imported — no use site, unused import fails ruff
- [Phase 34]: 34-02: Single spend definition — project_spend/trade_scope_spend route through _project_cost_side/_build_breakdown grand_total; budget.spent == grand_total by construction, no second SUM
- [Phase 34]: 34-02: D-03 re-arm lives only in BudgetRepository.set_total (raise nulls fired timestamps + refresh after flush so server-updated columns never lazy-load); decrease keeps fired state
- [Phase 34]: 34-02: service<->budget_service cycle broken from the budget_service side — lazy FinanceService import in _finance_service(); schemas.py gained from __future__ import annotations for the forward-referenced budget field
- [Phase 34]: 34-05: Nearing-budget chip requires remaining > 0 (not bare percent >= 80) so exactly-at-budget renders $0.00 plain with no chip per UI-SPEC state 5
- [Phase 34]: 34-05: formatMarginPercent/formatMarginDollars moved to finance_formatters.dart with formatPercentUsed delegating; margin_summary_section re-exports them so shipped Phase 33 imports keep compiling
- [Phase 34]: 34-04: Nearing-budget chip band requires remaining > 0 (not just percent >= 80) so exactly-at-budget shows no chip, per UI-SPEC state-4 spent < total condition
- [Phase 34]: 34-04: Budget figures assert shipped formatCurrency output (no thousands separators) — UI-SPEC comma examples are illustrative; changing formatCurrency would ripple across all Phase 32/33 finance tests
- [Phase 34]: 34-03: exactly-once budget alerts via claim-first atomic UPDATE; alert_context resolved before claiming so a vanished anchor never burns a claim; post-claim ORM expire keeps fired columns honest
- [Phase 34]: 34-03: FCM push scheduling lives only at the tail of evaluate_budget — every trigger (mutation hook, sweep, quote delta) inherits push delivery; recipients resolved in the request session, background task gets primitives + fresh session
- [Phase 34]: 34-03: budget-alert push recipients come from RbacRepository.user_ids_with_permission mirroring effective_permissions (live matrix, never role-name literals)
- [Phase 34]: 34-07: Budget API functions return Promise<void> — rows refresh via cost-entries invalidation, no unused response mapper (dead-code rule)
- [Phase 34]: 34-07: SetBudgetDialog prefill uses a null untouched-sentinel (amount = editedAmount ?? budget?.total) reset in the onOpenChange wrapper — correct after refetch, no useEffect, no remount key
- [Phase 34]: 34-07: Playwright DELETE mocks must fulfill 200 with json null — apiDelete unconditionally parses JSON, a bodyless 204 rejects
- [Phase 34]: 34-06: Mutation hooks use the shipped module-level BudgetService import (cycle already broken from budget_service side in 34-02) — no lazy in-method re-import
- [Phase 34]: 34-06: sweep scope spends come from one grouped scope_spends query quantized to CENTS, pinned to trade_scope_spend by a named equivalence test (soft-deleted entry included) per Pitfall 6
- [Phase 34]: 34-06: PATCH /budgets/{id} evaluates inline after set_total so a below-spend edit fires in the same request (D-10); scheduler add_job calls extracted to _register_jobs for testability
- [Phase 34]: 34-08: quoted_revenue reached from budget_service via lazy in-method import (34-02 cycle convention); apply_quote_delta resolves job anchors with a column-only jobs.project_id lookup, never the ORM-loaded quote.job
- [Phase 34]: 34-08: MINIMUM_BUDGET_TOTAL (0.01) clamp applies ONLY to quote deltas — user budget edits keep the no-floor D-10 behavior; phase test contract is the six VALIDATION selectors incl. mutation, not the plan text's five
- [Phase 35-web-financial-dashboard]: 35-02: Query counter listens on engine.sync_engine before_cursor_execute, not on sessions — SQLAlchemy event API is synchronous by design (same reason tenant.py after_begin is sync); conftest monkey-patches db_module.engine before test modules import, so the import binds the NullPool test engine the ASGI app actually uses
- [Phase 35-web-financial-dashboard]: 35-02: _seed_company_portfolio excludes the labor cost category — A labor-categorised cost entry folds into the derived labor row (Phase 32), which would make grand_total greater than total ambiguous; seeding only materials/subcontractor/other keeps that a clean proof that time entries and rates seeded
- [Phase 35-web-financial-dashboard]: 35-02: Seeded invoices and approved quotes sit on different anchors within a project — Invoices on job[0]/scope[0] and quotes on job[1]/scope[1] make every seeded project resolve revenue_basis mixed, exercising both legs of the D-12 dual traversal instead of letting invoices win everywhere
- [Phase 35-web-financial-dashboard]: 35-03: FinanceGate imports FINANCE_VIEW_PERMISSION from types.ts and never inlines the key, so the render gate and the hooks' enabled branch fail closed on exactly the same string
- [Phase 35-web-financial-dashboard]: 35-03: truncateLabel follows the UI-SPEC formula (slice(0,21) + ellipsis = 22 chars total), not the plan prose's "22 plus ellipsis" — the axis width contract wins
- [Phase 35-web-financial-dashboard]: 35-03: rollUpCategories sums numeric amounts because the Other bucket is a real sum; the CSV still exports one unrolled row per category so the export never inherits the chart's simplification
- [Phase 35-web-financial-dashboard]: 35-05: Five module-level finance query builders/mappers made public so portfolio_repository composes the shipped traversal predicates instead of restating them
- [Phase 35-web-financial-dashboard]: 35-05: PROJECT_KEY is a raw COALESCE expression in WHERE/GROUP BY and a labelled column in SELECT — PostgreSQL groups on the full expression, never an output alias; rows are read by label so 35-07 can append date columns safely
- [Phase 35-web-financial-dashboard]: 35-05: PortfolioService reuses service.py's _build_breakdown/_labor_by_job/_any_anchor_missing_cost_data/ProjectMarginContext directly — restating the labor folding or D-12 anchor flag is exactly the Pitfall-1 drift the equivalence test guards
- [Phase 35-web-financial-dashboard]: 35-05: The D-11 live-threshold test asserts BOTH directions (never-alerted overrun must be listed; stale claim after a soft-delete must not) because the plan's raise-below-spend route is unreachable under 34-06's inline PATCH evaluation
- [Phase 35-web-financial-dashboard]: 35-06: Drill-down reuses FinanceService.rollup_for_project verbatim for the project half — no second definition of spend, margin or the project budget
- [Phase 35-web-financial-dashboard]: 35-06: The scope half is exactly three queries (scopes, active budgets, one grouped scope_spends); the per-scope trade_scope_spend call survives only inside the equivalence test as the reference
- [Phase 35-web-financial-dashboard]: 35-06: project_header runs BEFORE the rollup so missing, soft-deleted and cross-tenant ids share one 404 path without paying for an aggregate
- [Phase 35-web-financial-dashboard]: 35-06: to_labor_cost_summary extracted into schemas.py so the shipped project-rollup route and the drill-down cannot drift on the D-06 basis field
- [Phase 35-web-financial-dashboard]: 35-09: BulletBarRow carries remaining so the shipped budgetTierFill owns the band rule — the chart never re-derives a tier — budgetTierFill is typed on Pick<BudgetVsActual, percentUsed | remaining>; the plan's own fill={budgetTierFill(row)} would not compile otherwise, and a precomputed fill would move the exactly-100%-is-not-amber nuance out of the one shipped helper.
- [Phase 35-web-financial-dashboard]: 35-09: Bullet bars render isAnimationActive={false} and jest mocks ResponsiveContainer to a fixed box exposing the plot height — Recharts renders no rectangle path until its animation starts, so tier fills are untestable in jsdom; the mock's data-height turns the 28px-per-row geometry contract into a real assertion (40 rows equals 1156px) instead of an untested claim.
- [Phase 35-web-financial-dashboard]: 35-09: NEARING_BUDGET_CHIP_LABEL exported from BudgetSummarySection and the incomplete chip is itself the #attention-list anchor — The UI-SPEC forbids one condition carrying two names, so the Phase 34 label is imported rather than retyped; making the anchor carry FINANCE_FLAG_CHIP_CLASS gives the badge exactly one testid and one accessible name.
- [Phase 35-web-financial-dashboard]: 35-10: formatFullMonthLabel added beside formatMonthLabel in financials-format.ts (shared monthParts splitter) rather than a second month table in the chart — the never-new-Date() rule stays in one module
- [Phase 35-web-financial-dashboard]: 35-10: isNotFoundError reads ApiError.status, never the message text, so wrong-tenant / soft-deleted / bad-id all take one 404 path with no bare cast
- [Phase 35-web-financial-dashboard]: 35-10: Custom category pie fills draw from a pool (two reserved custom hues plus any unclaimed system hue) so the six-slice cap can never exhaust or repeat the ramp
- [Phase 35-web-financial-dashboard]: 35-10: A failing trend query degrades to its own empty state instead of blanking the drill-down — two queries, two keys, two failure surfaces
- [Phase 35-web-financial-dashboard]: 35-07: Dated aggregate rows are read BY LABEL (row.issued_at / row.approved_on) through one _to_dated_document mapper, never by the plan's positional date_index — portfolio_repository's own row-access rule forbids positional reads past the shared six columns so an appended column cannot silently shift a value; passing the resolved timestamp as an argument also removes a getattr indirection and any column-name constants
- [Phase 35-web-financial-dashboard]: 35-07: The dated-quote query keeps ORDER BY Quote.created_at DESC rather than ordering by the new approved_on — The first row per anchor is what D-01 resolves against; reordering would make the trend resolve a different quote than rollup_for_project does and break the final-bucket reconciliation that is the trend's only self-check
- [Phase 35-web-financial-dashboard]: 35-07: test_trend_quote_without_approved_at_uses_created_at backdates created_at via SQL instead of relying on insert time — An undated approval created 'now' lands only in the final bucket where every quote lands anyway, so the test would pass vacuously; backdating proves the COALESCE fallback actually dates the quote at an earlier bucket
- [Phase 35-web-financial-dashboard]: 35-07: Margin-trend test fixtures are dated relative to the current UTC month, never to a fixed calendar year like _seed_date — The endpoint's last bucket is always the current UTC month, so hard-coded dates drift out of every window as time passes and the tests quietly stop asserting anything
- [Phase 35-web-financial-dashboard]: 35-11: The SC3 denial test pairs the deny panel with a captured zero-financial-request counter, and an in-file comment says why -- a hard page.goto resets Redux, so the panel alone renders for permitted users too and would keep passing with FinanceGate deleted — Break-it-once verified: removing FinanceGate fails the deny-panel half, removing the hooks enabled gate fails the zero-request half
- [Phase 35-web-financial-dashboard]: 35-11: The margin-trend shared-month proof reads the last-month tooltip (plot located as .recharts-wrapper > svg, raw mouse moves) rather than the CSV export -- ChartCard revokes its blob URL immediately after click, so a download capture would race — The legend icons are svgs too and overlay the plot, so locator("svg").first() and locator.hover both fail
- [Phase 35-web-financial-dashboard]: 35-08: _MAX_COMPANY_ROLLUP_STATEMENTS pinned to the first observed run (13) + 2 headroom = 15, not the plan's estimated ~9-11 — The equality of the 5-project and 25-project counts is the D-03 contract; the absolute is whatever the first run measures. 13 includes the two RLS SET LOCALs and the permission lookup, which run per request and a warm-up cannot exclude.
- [Phase 35-web-financial-dashboard]: 35-08: company rollup latency ceiling committed at 400ms (~2x the middle of three measured medians 127/199/252ms), tightened from the initial 1500ms; no cache or snapshot table added — 1500ms would pass even if the rollup got 6x slower. 2x the idle-best (250ms) reddens under ordinary load; 2x the worst (500ms) gives away the teeth. In-process ASGI + local Postgres is evidence, not a production SLO.
- [Phase 35-web-financial-dashboard]: 35-08: the query-count invariance test is the primary N+1 guard and the wall clock is secondary — verified by mutation (a per-project rollup_for_project loop moved the count 43 -> 163) — A latency ceiling generous enough never to flake on shared CI is also generous enough to hide a reintroduced per-project loop; the statement count is deterministic regardless of machine load.
- [Phase 36]: 36-02: Finding hook tests mock apiGet (the HTTP layer), not the api-module fetcher -- the plan behaviors "exactly one fetch to the finding path" and the snake_case mapping both live inside that fetcher and are unobservable through a module-boundary mock — Driving the real fetcher against a mocked HTTP layer proves the gate, the path and the mapper in one test; the zero-request assertion also becomes stronger (nothing reaches the wire, not merely that a wrapper went uncalled)
- [Phase 36]: 36-02: The finding hook zero-request test is mutation-verified, not merely written -- reducing enabled to !!projectId fails it with one request to the finding path, and restoring the gate returns 140/140 green — A zero-request assertion that was never observed failing can pass for the wrong reason, which is exactly the SC2 trap the UI-SPEC warns about
- [Phase 36]: 36-02: FINANCE_ALERT_CHIP_CLASS extraction confirmed safe by running the shipped Phase 35 suite (134 green), not by assuming byte equality -- the new literal is the same class set in a different token order — The shipped assertions are per-token toHaveClass checks; the composed OVER_BUDGET_BADGE_CLASS and the flat literal differ as strings but not as class sets
- [Phase 36]: 36-01: severity_band is excluded from the upsert set_ alongside alerted_at and found_on — the band is part of the fingerprint, so a band change is a different finding that must resolve-and-reinsert (D-06), never mutate in place
- [Phase 36]: 36-01: the Pitfall 3 alert-type drift guard reads the CheckConstraint expression off DashboardAlert.__table__, not just an ORM insert — a SQLAlchemy CheckConstraint is DDL-only and never runs on flush, and conftest builds the schema via alembic, so an insert proves the migration value list and nothing about models.py (verified by mutation)
- [Phase 36]: 36-01: claim_alert keeps the Phase 34 post-claim ORM expire so a caller that upserts then claims in one session cannot read a stale alerted_at NULL and publish a second alert
- [Phase 36]: 36-01: docker compose up migrate can silently no-op — the migrate service builds from ./backend, so a cached image without the new migration exits 0 at the old revision; use --build after adding a migration
- [Phase 36]: 36-04: incompleteCostData reads breakdown.margin?.incomplete ?? false, not the plan's non-optional access — CostBreakdown.margin is MarginSummary | null, so the literal would fail tsc --noEmit and throw on the shipped null-margin drill-down path; a revenue-less project then falls into the plain empty state, exactly the variant bound the UI-SPEC states
- [Phase 36]: 36-04: the shipped drill-down test's jest.mock hooks factory was extended with useProjectProfitabilityFinding rather than the dashboard importing the hook defensively — jest.mock with a module factory replaces the whole module, so a newly imported hook arrives undefined and 19 shipped tests failed with 'not a function'; hiding that behind an import-time guard would put test scaffolding in production code
- [Phase 36]: 36-04: the findings keystone needs TWO tests -- an errored query and an in-flight query -- because only the in-flight one mutation-catches a widened page loading gate — isError implies isLoading false, so adding finding.isLoading to the gate leaves the error test green; verified by mutation (exactly one test fails, then restored)
- [Phase 36]: 36-04: jest path patterns for route-group directories must escape the parentheses -- npx jest "src/app/\(dashboard\)/financials", not the plan's unescaped form — Jest treats the pattern as a regex, so (dashboard) is a capture group and matches zero files -- the command exits 1 with 'No tests found' and reads like a real failure
- [Phase 36]: 36-03: margin_decline_points indexes buckets[-TREND_LOOKBACK_BUCKETS] (the last two bucket edges), not the plan docstring's third-from-last — The plan's behavior block, D-03, TREND_LOOKBACK_BUCKETS=2, its own len<2 guard and the RESEARCH reference implementation all say the last two; only one docstring line said third-from-last
- [Phase 36]: 36-03: profitability_math prose deliberately avoids the literal tokens ACTIVE_PROJECT_STATUSES, window_slice and anchor_revenues — The task acceptance criteria grep for the ABSENCE of all three to prove detection never reaches those code paths, so the plan's own suggested comments would have failed them; intent preserved in prose instead
- [Phase 36]: 36-03: the Pitfall-5 tautology guard doubles as the empty-comparable-set guard, so quote_implied_gap has one early exit rather than two — any() over an empty set is already False, so a separate emptiness check would be an unreachable branch with no behavior difference
- [Phase 36]: 36-03: candidate_for carries only FIRED signal figures -- a sub-threshold decline is stored as None — The payload is what the AI cites and D-05 validates cited figures, so carrying a 2-point drift would invite the AI to name it as a finding
- [Phase 36]: 36-05: MONEY_PATTERN requires at least one comma group ((?:,\d{3})+, not the plan's *) — regex alternation is first-match-wins, so with * the grouped alternative matches "$320" inside "$3200" and the un-grouped alternative never runs — The plan's own behavior list requires "$3200" to extract as 3200; with + the grouped form takes "$3,200" and un-grouped digits fall through intact
- [Phase 36]: 36-05: the whole-dollar grounding tolerance is one-directional — a cited "$3,200" matches payload Decimal("3200.41"), but a cited "$3,200.41" never matches payload Decimal("3200") — A model dropping cents is formatting (format_alert_money already does it); a model inventing cents is fabrication, which is exactly what SC3 must block
- [Phase 36]: 36-05: two docstrings were reworded away from the plan's literal prose ("imports nothing from app.features" -> "carries no feature-package imports"; "returns a caller-supplied fallback dict" -> "degrades to a caller-supplied default dict") — Both acceptance criteria are token-ABSENCE greps and the plan's own suggested prose contained the exact tokens — same trap as the 36-03 prose decision; meaning preserved, only the greppable tokens changed
- [Phase 36]: 36-05: collect_allowed_values admits only Decimal and non-bool int — strings, bools and floats are all skipped — Strings keep a project named "2026" from making "$2,026" citable; bool is an int subclass so True must not become Decimal("1"); a float in a money payload is a caller bug that should surface as an unmatched figure rather than be admitted under binary-float equality
- [Phase 36]: 36-06: the SC2 Playwright keystone asserts the deny panel AND a zero-request counter on /financials/finding in two auth states (logged-in with permissions resolved, and cold load) -- a non-finance user has no SPA route into the drill-down because the sidebar item is itself gated — Break-it-once verified: deleting FinanceGate fails the panel half; with the gate gone, weakening the hook's enabled to !!projectId fires one request to /financials/finding and fails the counter half. The gate short-circuits the mount, so the request half is only observable once the render half is already broken -- that is what makes it a second independent lock, and the spec says so in-file. The proof that enabled alone holds lives in the 36-02 hook test.
- [Phase 36]: 36-06: mapProfitabilityFinding validates severity through the shipped toKnownValue instead of casting it, backed by a new FINDING_SEVERITIES const — An unknown band indexed the card's SEVERITY_CHIP map with undefined and threw at render, replacing the entire /financials/[projectId] page with the error boundary -- two shipped Phase 35 tests were red on it. Validating at the boundary turns a malformed payload into the finding query's own error, so the card shows its scoped error line and the money dashboard still renders (state 19).
- [Phase 36]: 36-06: the Phase 35 spec gained an explicit finding-route branch returning null rather than having its assertions relaxed — 36-04 added a third drill-down query that Phase 35's shell-chatter fallback answered with [], which is not a finding shape; after the boundary fix it errored and retried mid-test, breaking the trend window's exactly-one-refetch assertion (reproduced 3/3 with --repeat-each=3). A mock needs a real body for every route a new query introduces.
- [Phase 36]: 36-07: _build_payload consumes a PayloadInputs dataclass carrying the batched ProjectCostBlocks, never the plan's ProjectCostRollup — A real rollup means FinanceService.rollup_for_project per project — the per-project rollup loop this plan's own key_links forbid — and it carries raw CostEntry rows the payload must never see; portfolio_service.project_cost_blocks supplies the category mix and folded labor row from the one batched company read instead
- [Phase 36]: 36-07: the revenue-bearing zero-cost project is skipped as NO_COST_DATA, not the plan's expected INCOMPLETE_DATA — The shipped D-01 ladder tests cost <= 0 before margin.incomplete, so NO_COST_DATA is the real verdict; the Pitfall-9 property (a fabricated 100% margin never reaches the AI) holds either way and INCOMPLETE_DATA is covered by the unrated-labor test where cost is positive
- [Phase 36]: 36-07: skip and summary log lines are %-rendered at the call site and asserted through structlog.testing.capture_logs, never caplog — This app binds structlog to the stdlib bridge, which defers %-formatting to the handler: with positional args the values never reach capture_logs, and caplog captures zero records from this configuration at all (verified empirically) — a caplog-based skip-reason assertion would have passed vacuously
- [Phase 36]: 36-07: test fixtures must PATCH a project to active — POST /api/v1/projects silently ignores a status body — ProjectCreate declares no status field, so every project lands in draft and the pre-existing "status": "active" in the POST body was a no-op; D-01 analyzes active projects only, so without _activate_project every eligibility test would have asserted the draft path
- [Phase 36]: 36-08: _within_length_contract documents "rejected whole rather than shortened" -- the task's acceptance grep forbids the token "truncate" anywhere in the service, so the plan's own suggested docstring would have failed it — Third occurrence of this trap in Phase 36 (36-03, 36-05): a token-ABSENCE grep and the plan's suggested prose can contradict each other. Meaning preserved, only the greppable token changed.
- [Phase 36]: 36-08: the service rejects over-length text against profitability_models' MAX_* constants (the DB CHECK source), and a new test pins the prompt module's three copies equal to them — The two literal sets are independent (600/280/280 twice). If the prompt ever advertised a looser bound, every finding written to it would become a silent service-side drop with no failing test.
- [Phase 36]: 36-08: PublishResult.qualifying_fingerprints is built from EVERY candidate (raised calls, over-length drafts, cap drops included), never from published — D-06 keep-set correctness: built from published, a transient Claude failure would resolve a still-true finding, and the next successful night would insert a fresh unalerted row and alert a condition that never cleared (RESEARCH Pitfall 6).
- [Phase 36]: 36-08: a confirmed Claude reply with empty text is dropped as malformed, not published -- the prompt reserves empty strings for a dismissal — Empty strings pass grounding (no figures) and pass the length bounds, so without this guard a malformed reply would persist a finding with a blank card and a blank alert body.
- [Phase 36]: 36-08: cap/length tests hand publish_findings synthetic ProfitabilityCandidates with distinct fingerprints against one seeded project, and the Claude mock answers from payload content rather than call order — The cap and the length rule are orchestration properties, not detection ones; identical fingerprints would upsert onto one open row and make a cap assertion meaningless, and gather_with_concurrency interleaves calls so a positional side_effect list would be flaky. Cap-after-validation is mutation-verified (7 findings and 0 cap logs when the cap is counted before validation).
- [Phase 36]: 36-09: analyze_company builds the D-06 keep-set from result.qualifying_fingerprints, never from the published list -- mutation-verified — Swapping in the published-based keep-set fails exactly test_transient_claude_failure_does_not_resolve_or_realert (1 failed, 5 passed) and restoring returns 6 passed. Under that mutation a raised Claude call empties the keep-set, resolves a still-true finding, and the next successful night inserts a fresh unalerted row and fires a SECOND alert for a condition that never cleared.
- [Phase 36]: 36-09: the lifecycle test fixture starts in the WARNING band (1,200 cost / 10,000 invoiced / 20,000 quoted = exactly 6.0 gap points) and worsens by ADDING COST to 3,000 (15.0 points) — The shipped _seed_analyzable_project is a 33.3-point gap -- already critical on night one, so there is nowhere to escalate to. Both figures land on exact one-decimal values so no rounding boundary is straddled, and the margin stays positive at both cost levels so negative_margin cannot pre-empt the quote-gap signal. Cost is the only lever available: QuoteService.create_quote rejects a job that is not in quote status and _create_invoice marks the job complete, so a second approved quote at the same anchor would 409.
- [Phase 36]: 36-09: the cleared-then-recurring test pauses and re-activates the project instead of billing the gap away — Billing up to the quote amount clears the condition but a later recurrence carries a DIFFERENT fingerprint, which re-alerts through the band-change path keystone 2 already covers. Pausing keeps the fingerprint byte-identical, so the second alert can only come from resolve-then-reinsert -- the D-06 mechanism actually under test.
- [Phase 36]: 36-09: a raised Claude transport error consumes no D-05 grounding retry -- exactly one call on a failing night — The exception propagates out of _draft_for before the retry loop can iterate, and gather_with_concurrency isolates it into a None draft. The first RED assertion expected GROUNDING_RETRY_LIMIT + 1 calls and was wrong about the code, not the reverse.
- [Phase 36]: 36-09: send_profitability_finding_notification gained its own unit tests in test_notification_service.py rather than inheriting the budget sibling's coverage gap — The e2e suite patches the method to assert WHO it addresses, so its body -- token lookup, empty-recipient guard, dispatch loop, credential-free degradation -- would have shipped with zero executed coverage. send_budget_alert_notification has exactly that gap, so copying the precedent would have propagated it.

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
- Phase 35 (v4.0): backend suites run red under parallel agent execution -- conftest.py TRUNCATEs all tables per test, which deadlocks when two pytest processes share contractorhub_test. A deadlock inside seed_two_tenants is contention, not a regression. Consider per-worker test databases if parallel execution stays routine.
- ~~Phase 36: tests/unit/test_finance_scrub.py::test_financial_alert_types_are_the_budget_types RED since 36-01~~ RESOLVED in bb3a151 (relaxed to a subset check); re-verified green during 36-08 (tests/unit: 229 passed).
- Phase 36: web full-suite runs (npm run test-e2e, 175 tests, default workers, one dev server, backend agent running concurrently) are not a trustworthy gate -- four runs returned 16/4/7/24 failures with a shifting set. At --workers=2 --retries=1: 173 passed, 2 failed, 0 flaky. Later web plans should gate on --workers=2. The 2 failures are the pre-existing Phase 21 URL-shape drift already logged in Phase 35's deferred-items.md.

## Session Continuity

Last session: 2026-07-29T23:48:13.517Z
Stopped at: Completed 36-10-PLAN.md
Resume file: None
