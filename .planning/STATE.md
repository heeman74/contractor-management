---
gsd_state_version: 1.0
milestone: v3.0
milestone_name: AI-Driven Construction Management
status: Ready to execute
stopped_at: Completed 21-04-PLAN.md
last_updated: "2026-03-23T19:32:24.923Z"
progress:
  total_phases: 14
  completed_phases: 8
  total_plans: 42
  completed_plans: 41
---

# Project State

## Project Reference

See: .planning/PROJECT.md (updated 2026-03-19)

**Core value:** AI eliminates the chaos of multi-trade coordination — GCs always know where every trade stands, contractors always know what to do today, projects stay on track.
**Current focus:** Phase 21 — ai-project-intake-and-contractor-interview

## Current Position

Phase: 21 (ai-project-intake-and-contractor-interview) — EXECUTING
Plan: 6 of 6

## Performance Metrics

**Velocity:**

- Total plans completed: 54 (v1.0) + 25 (v2.0) = 79 total
- v3.0 plans completed: 0
- v3.0 trend: Not started

**By Phase (v3.0):**

| Phase | Plans | Total | Avg/Plan |
|-------|-------|-------|----------|
| 19-26 | TBD | - | - |
| Phase 19 P02 | 20 | 2 tasks | 16 files |
| Phase 19 P05 | 25 | 3 tasks | 12 files |
| Phase 20-dependency-engine P01 | 16m | 2 tasks | 8 files |
| Phase 20-dependency-engine P04 | 15 | 2 tasks | 9 files |
| Phase 20-dependency-engine P03 | 45 | 2 tasks | 13 files |
| Phase 20-dependency-engine P05 | 2m | 2 tasks | 3 files |
| Phase 20-dependency-engine P06 | 8 | 2 tasks | 2 files |
| Phase 21-ai-project-intake-and-contractor-interview P01 | 5m | 2 tasks | 11 files |
| Phase 21 P02 | 11m | 2 tasks | 5 files |
| Phase 21 P06 | 7 | 2 tasks | 8 files |
| Phase 21 P03 | 35m | 2 tasks | 16 files |
| Phase 21 P04 | 1195s | 2 tasks | 22 files |
| Phase 21 P04 | 20 | 3 tasks | 22 files |

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
- [Phase 21]: [Phase 21 P04]: dart:io HttpClient used for SSE streaming — flutter_client_sse does not support POST body; Dio cannot handle text/event-stream
- [Phase 21]: [Phase 21 P04]: parseSseEvent extracted as top-level function (not class method) to enable independent unit testing without AiSseClient instance

### Pending Todos

None yet.

### Blockers/Concerns

- Phase 21: Confirm ANTHROPIC_API_KEY is provisioned and model IDs (claude-opus-4-5, claude-haiku-3-5) are available before starting AI work
- Phase 23: Confirm REDIS_URL is present in backend config (assumed for slowapi rate limiting) before WebSocket pub/sub design
- Phase 19: Confirm current Drift schema version number to number new migrations correctly

## Session Continuity

Last session: 2026-03-23T19:32:24.916Z
Stopped at: Completed 21-04-PLAN.md
Resume file: None
