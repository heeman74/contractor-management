# Project Research Summary

**Project:** ContractorHub v3.0 — AI-Driven Multi-Trade Construction Management
**Domain:** SaaS construction management platform with AI planning, real-time coordination, and multi-trade project hierarchy
**Researched:** 2026-03-19
**Confidence:** HIGH

## Executive Summary

ContractorHub v3.0 transforms an established single-trade contractor management platform (jobs, quoting, invoicing, scheduling, mobile field execution) into an AI-driven multi-trade coordination system. The addition is not a rewrite — the existing FastAPI + Flutter + Next.js infrastructure is sound and carries forward unchanged. The v3.0 work adds five new capability clusters on top: an AI agent service (Claude API tool use + streaming), a real-time chat layer (FastAPI WebSocket + Redis pub/sub), a new three-level project hierarchy (Project → Trade Scope → Task), photo annotation, and a cross-trade dependency graph engine. All new backend components follow the existing OOP base pattern (TenantScopedService, TenantScopedRepository) and PostgreSQL RLS multi-tenancy model. Stack additions are minimal: `anthropic`, `sse-starlette`, `redis`, `networkx` on the backend; `web_socket_channel` and `pro_image_editor` on Flutter; `fabric` (canvas annotation) on the web.

The entire v3.0 feature set is gated on a single foundational dependency: the Project → Trade Scope → Task data model must ship first. Every other v3.0 feature — AI intake, contractor interviews, daily checklists, chat, inspection workflow, per-trade billing — either stores data in or reads data from this hierarchy. There is no shortcut around this ordering. Research from both FEATURES.md and ARCHITECTURE.md consistently identified the same 8-phase build order, converging from feature dependency analysis and architectural constraint analysis independently.

The primary risks are not technical — they are design decisions that must be made before first implementation: AI conversation token budget strategy (unbounded history costs can exceed $1,500/week per company at production scale), tenant isolation of AI conversation state (in-memory Python caches are invisible to RLS and create GDPR exposure), WebSocket session validity (JWT expiry mid-session leaves revoked contractors with persistent chat access), and the domain boundary between AI-owned and client-owned entities in the offline outbox (mixing them causes data corruption on sync). Each of these risks is avoidable with explicit design-before-code discipline. The research does not reveal any unsolvable problems — only patterns that require upfront decisions.

## Key Findings

### Recommended Stack

The existing stack (FastAPI 0.115, Flutter 3.32, Next.js 16, PostgreSQL 13, SQLAlchemy 2.0 async) is carried forward without modification. New additions are targeted and minimal.

**Core technology additions:**

- `anthropic` 0.86.0 (Python): Official Anthropic SDK — use `AsyncAnthropic` to keep FastAPI's event loop unblocked; native tool-use agentic loop, streaming via `client.messages.stream()`, Pydantic-native structured outputs in public beta
- `sse-starlette` 3.3.3 (Python): Server-Sent Events for streaming AI responses token-by-token to web clients; correct protocol for unidirectional AI text streaming (WebSocket is overkill here)
- `redis` 7.1.1 (Python): WebSocket pub/sub for multi-worker fanout via `redis.asyncio`; reuses the existing Redis instance already present for slowapi rate limiting
- `networkx` 3.x (Python): DAG algorithms — cycle detection, topological sort, critical path calculation for the cross-trade dependency engine; pure Python, no C extensions
- `web_socket_channel` 3.0.3 (Flutter): Google's official Dart WebSocket client; integrates naturally as a Riverpod `StreamProvider` for the GC ↔ contractor chat channel
- `pro_image_editor` 12.0.7 (Flutter): Full-featured photo annotation editor; exports composited PNGs; MIT licensed; most actively maintained Flutter annotation package as of March 2026
- `fabric` 7.2.0 (npm): Canvas-based photo annotation for the web dashboard; JSON vector serialization shared with Flutter renderer; MIT license
- `@xyflow/react` 12.x (npm): Interactive dependency graph visualization on web (optional — only if graph view is built)

**Critical technology exclusions:**
- Do NOT use LangChain or LlamaIndex — direct Anthropic SDK is 50 lines vs 500 with worse observability; frameworks fight Claude's native tool use and structured output APIs
- Do NOT add PowerSync or Supabase Realtime — existing transactional outbox handles offline sync for the cases that require it; a third data layer fights PostgreSQL RLS
- Do NOT use `aioredis` (deprecated, merged into `redis` package as `redis.asyncio`)
- AI conversation history belongs in PostgreSQL (JSONB on `AISession.messages`), never in Python module-level dicts or `app.state`

See `.planning/research/STACK.md` for full version compatibility matrix, installation commands, and alternatives considered.

### Expected Features

FEATURES.md establishes that the entire v3.0 feature set is gated on the Project Model (Project → Trade Scope → Task with dependency graph). This is the critical dependency chain — every feature either depends on it or extends it.

**Must have (table stakes for v3.0 core value):**
- Project model with multi-trade hierarchy — nothing else works without it
- AI project intake via chat — GC describes project in natural language; AI structures it by trade with sequencing
- AI contractor interview + task plan generation — eliminates guesswork on scope definition per trade
- AI daily checklist push — morning FCM with personalized tasks, materials, photo requirements; primary retention mechanic
- Task-level progress tracking — notes + photos per task, offline-capable via existing outbox
- GC cross-trade monitoring dashboard (web) — GC's primary value; all trades simultaneously
- GC ↔ contractor bidirectional chat — project-scoped; coordination without leaving the platform
- GC inspection workflow (approve/reject/flag) — closes the loop from task execution to GC sign-off
- Photo annotation on mobile — arrows, circles, text, measurements on task photos; required for inspection documentation
- Per-trade quoting and invoicing — extend existing Quote/Invoice system with `trade_scope_id` FK

**Should have (differentiators — deferrable to v3.1):**
- Gantt-style unified timeline view with dependency connectors — high rendering complexity; table/list view sufficient for MVP
- Cross-trade dependency push notifications — show blocked state in MVP without push notification
- Punch list auto-feed back to AI planning — requires mature inspection data to be meaningful
- AI schedule adaptation — requires weeks of historical progress data; ship after projects run for several weeks

**Specifically do not build in v3.0:**
- Change order workflow, in-app payment processing, QuickBooks/Xero integration
- iOS support (Android priority per PROJECT.md), BIM/CAD import, video calling, GPS live tracking
- Real-time collaborative editing of AI plans (CRDT complexity), on-device/local AI, AI voice assistant

See `.planning/research/FEATURES.md` for full dependency graph, competitor analysis (Procore, Fieldwire, Buildertrend, Siteline, Knowify, Bluebeam), and complexity assessment matrix.

### Architecture Approach

The architecture follows a strict layered extension model: new capability clusters attach to the existing FastAPI OOP hierarchy without modifying existing services. All new models inherit `TenantScopedModel`, services inherit `TenantScopedService`, repositories inherit `TenantScopedRepository`. The one exception is `AIAgentService`, which inherits `BaseService` (not `TenantScopedService`) because AI sessions span multiple DB operations and need `company_id` as a direct column rather than via RLS context variable. The mobile architecture shifts from fully offline-first to a hybrid: online-only for AI/chat (fail with UI error if offline), offline-capable for field task execution (existing outbox pattern unchanged), and aggressive Drift caching for read-only daily checklists.

**Major components (new):**

1. `AIAgentService` — wraps Anthropic SDK; manages tool-use agentic loop (max 10 turns); streams SSE responses via `sse-starlette`; persists conversation history as JSONB; handles project intake and contractor interview session types
2. `DependencyEngineService` — DAG operations over the trade dependency graph; PostgreSQL recursive CTE for in-database cycle detection; topological sort and critical path via NetworkX computed in-memory per request
3. `ChatService` + `WebSocketManager` — DB-first delivery model (persist before broadcast); in-process connection registry with Redis pub/sub for multi-worker fanout; periodic JWT re-validation
4. `ProjectService` / `TradeScopeService` / `TaskService` — CRUD and state machine for the three-level hierarchy; aggregation queries for GC monitoring dashboard
5. `AnnotationService` — non-destructive annotation storage (base photo URL unchanged; annotation JSON vectors in `TaskAttachment.annotation_data` JSONB column; client re-renders overlay)
6. Six new Drift tables (mobile) — `projects`, `trade_scopes`, `tasks`, `task_notes`, `task_attachments`, `chat_messages` — with corresponding `SyncHandler` subclasses in the existing `SyncRegistry`

**Key architectural decisions established by research:**
- AI conversation history stored in JSONB (one query to load; append-only; 50–200 turns max for construction intake) — not a separate messages table with row-per-message
- Task-level dependencies stored as JSONB array on `Task`; cross-trade dependencies stored as edge table (`trade_dependencies`) — different storage strategies because query patterns differ
- WebSocket auth via JWT in query param, validated immediately after `websocket.accept()` — standard pattern, TLS encrypts the URL
- Annotation storage is non-destructive — base photo immutable, annotation JSON in separate JSONB column, rendered client-side by both Flutter `CustomPainter` and web Fabric.js

See `.planning/research/ARCHITECTURE.md` for full data flow diagrams, code patterns, build order, and anti-patterns.

### Critical Pitfalls

1. **Outbox conflicts with AI-owned entities** — The existing offline outbox must never queue `entity_type = 'project'`, `'trade_scope'`, or `'task'` for creation or structural updates. These are server-owned. Client outbox handles only progress/completion records. Add `plan_version` to Task from day one; completion records carry the version they were created against; server rejects stale completions with 409.

2. **AI conversation state tenant isolation** — Never store conversation history in Python module-level dicts, `app.state`, or any in-memory cache. Store all AI session state in a `ai_sessions` table with `company_id` + RLS policy. Test: Company B token + Company A session ID must return 403, not Company A's project data.

3. **Unbounded AI token costs** — Project intake and contractor interview are one-time finite conversations; store the structured output only, never replay full message history for adaptation requests. AI schedule adaptation must be a stateless request (current task states + delay snapshot). Log token usage per call type; alert when any call exceeds 20,000 input tokens. Production cost can exceed $1,500/week per company without this discipline.

4. **Missing RLS on new tables** — Every new table (`projects`, `trade_scopes`, `tasks`, `chat_messages`, `task_notes`, `task_attachments`) requires an explicit RLS policy before any data is inserted. Add a CI check that lists tables without RLS enabled. Write a cross-tenant isolation test for every new endpoint (Company B token + Company A resource ID returns 404).

5. **WebSocket JWT expiry mid-session** — JWT validated at WebSocket handshake expires in 15 minutes; connection stays open. Revoked contractors retain chat access until disconnect. Implement periodic server-side re-validation (every 5 minutes); close with code 4401 on expiry; Flutter client handles 4401 by refreshing token and reconnecting. Maintain user-keyed connection registry for forced disconnect on deactivation.

See `.planning/research/PITFALLS.md` for 14 specific pitfalls with detection criteria, phase assignments, recovery strategies, and a "looks done but isn't" checklist.

## Implications for Roadmap

Based on combined research, the following 8-phase structure is recommended. The ordering is determined by hard dependency constraints: the data model must precede AI; AI must precede inspection; the dependency engine enables daily checklists. This structure is consistent across both ARCHITECTURE.md's build order and FEATURES.md's feature dependency chain — both arrived at the same ordering independently.

### Phase 1: Project Data Model Foundation

**Rationale:** Every single v3.0 feature stores data in or reads from the Project → Trade Scope → Task hierarchy. This has zero dependencies on other v3.0 work and is the only valid starting point. Building anything else first is wasted effort — AI, chat, inspection, and billing all require these entity IDs to exist.
**Delivers:** GCs can manually create projects, assign trade scopes, and create tasks. No AI yet — proves the data layer and RLS discipline before AI complexity is added.
**Addresses:** Project hierarchy (table stakes), task-level data model, per-trade FK structure
**Avoids:** Pitfall 2 (RLS on new tables) — establish RLS discipline and CI check here before any other tables ship
**Must include:** RLS policies on all new tables, cross-tenant isolation tests per endpoint, Drift schema migration from v6 with full migration chain test, `plan_version` field on Task from day one, 6 new Drift tables + `SyncRegistry` handlers

### Phase 2: Cross-Trade Dependency Engine

**Rationale:** The dependency graph is pure backend logic — no AI, no UI complexity beyond CRUD edges. Building it immediately after the data model means it is validated and available when AI intake ships in Phase 3. AI can create dependencies against a tested engine rather than against code written concurrently.
**Delivers:** GCs can define finish-to-start dependencies between trade scopes; cycle detection prevents invalid graphs (409 on circular); topological sort determines valid execution order for daily checklists
**Uses:** NetworkX, PostgreSQL recursive CTEs, `DependencyEngineService`
**Implements:** Edge table (`trade_dependencies`), cycle detection via DFS reachability, task-level dependency storage as JSONB array on `Task`
**Avoids:** Pitfall 12 (circular dependency not detected) — cycle detection is in the engine from first implementation, before AI or human overrides can create cycles

### Phase 3: AI Project Intake and Contractor Interview

**Rationale:** AI intake creates the trade scope structure and contractor interview generates the task plans that feed every downstream v3.0 feature (daily checklists, inspection, monitoring dashboard). This is the central v3.0 differentiator. Its token budget strategy, Pydantic validation discipline, and tenant isolation must be correct from first implementation — retrofitting is a rewrite.
**Delivers:** Full AI-driven project planning loop: GC describes project in chat → AI structures by trade with dependencies → contractors answer interview questions → AI generates per-trade task plans with daily breakdowns
**Uses:** `anthropic` 0.86.0 (`AsyncAnthropic`), `sse-starlette` (SSE streaming to web), `AIAgentService`, tool-use agentic loop
**Implements:** Agentic loop with max 10 turns, SSE streaming to web via Next.js proxy, REST completion response to mobile, DB-backed conversation state with RLS
**Avoids:** Pitfall 3 (token cost explosion), Pitfall 4 (AI parsing failures silently corrupt task plans), Pitfall 6 (AI tenant isolation), Pitfall 11 (rate limit cascades)
**Must include:** Token budget strategy in design doc before first line of AI code; Pydantic validation + referential integrity check on every AI response before DB write; exponential backoff on all Anthropic calls; model version pinned (not `claude-*-latest`)

### Phase 4: Real-Time Chat

**Rationale:** Chat is a standalone capability with no AI dependency, but depends on the project hierarchy (chat rooms are project-scoped). Shipping it after Phase 3 means the project model is validated with realistic data from AI intake, giving meaningful test scenarios for chat. Chat does not block any subsequent phase.
**Delivers:** Bidirectional GC ↔ contractor chat scoped to projects; DB-first delivery (persisted before broadcast); FCM push for offline delivery; message history via REST on reconnect; Drift cache for chat scrollback on mobile
**Uses:** FastAPI native WebSocket, `WebSocketManager`, `redis.asyncio` pub/sub, `web_socket_channel` (Flutter), `ChatService`
**Implements:** DB-first delivery model, ACK protocol (server assigns `message_id` + sends ACK event; client retries via REST after 10s without ACK), periodic JWT re-validation, forced disconnect on user deactivation
**Avoids:** Pitfall 5 (WS auth expiry), Pitfall 9 (WebSocket-only delivery with no persistence), Pitfall 14 (chat attachments mixed with job photos — `chat_attachments` is a separate entity and upload endpoint)

### Phase 5: Photo Annotation

**Rationale:** Annotation depends on existing task attachments (added in Phase 1). It is a self-contained capability with no AI or chat dependency. Building it in Phase 5 means annotated photos are available for Phase 6 (GC inspection), which requires them as evidence. The layered canvas architecture decision (separate static/dynamic `RepaintBoundary` layers) must be made before first implementation.
**Delivers:** Non-destructive annotation layer on task photos (arrows, circles, text, measurements); same JSON vector format rendered on Flutter (`CustomPainter`) and web (Fabric.js); base photo immutable in storage
**Uses:** `pro_image_editor` 12.0.7 (Flutter), Fabric.js 7.2.0 (web), `AnnotationService` (JSONB storage on `TaskAttachment.annotation_data`)
**Implements:** Non-destructive storage pattern, shared annotation JSON schema (version-tagged for future compatibility)
**Avoids:** Pitfall 8 (UI thread blocking on large photos) — separate `RepaintBoundary` layers, cached `ui.Image`, test with real 4000x3000px device photos from day one; never test only on simulator

### Phase 6: GC Inspection Workflow

**Rationale:** Inspection depends on task progress data (Phase 1 task model), annotated photos (Phase 5), and produces punch list items. This closes the field execution loop: contractor completes task → GC inspects → approve/reject/flag → contractor notified via FCM.
**Delivers:** GC can approve, reject, or flag tasks with annotated photo evidence; rejected/flagged tasks generate punch list items; FCM notifications to contractors on GC decision; `InspectionScreen` on mobile for GC role
**Implements:** Task inspection state machine, punch list model, 5 new FCM notification types (additive to existing `NotificationService`)
**Avoids:** Breaking changes to `NotificationService` that could affect existing push flows — all new notification types are additive

### Phase 7: Per-Trade Quoting and Invoicing

**Rationale:** Financial lifecycle extension is the lowest technical risk item — purely additive FK changes to existing, proven Quote and Invoice models. Deferred until Phase 7 because it benefits from the project hierarchy being stable (Phase 1) and the team having established schema migration discipline across prior phases.
**Delivers:** Trade-scoped quotes and invoices linked to trade scopes; project-level financial aggregation view on web; existing single-trade job workflow unchanged
**Implements:** Additive nullable `trade_scope_id` FK on existing Quote and Invoice models; new `TradeQuote` model alongside existing `Quote` (not instead of it); project-level invoice summary
**Avoids:** Pitfall 7 (breaking existing Quote approval flow) — all new fields are `Optional` with defaults; existing single-trade jobs use Quote unchanged; mobile deserialization test against updated schema must pass before shipping

### Phase 8: AI Daily Checklist and Cross-Trade Monitoring

**Rationale:** The daily checklist push requires task plans (Phase 3) and dependency graph data (Phase 2) to determine which tasks are unblocked today. The GC monitoring dashboard requires all prior phases' data to be meaningful. Shipping these last ensures all inputs are stable and the system has real project data to demonstrate value.
**Delivers:** Morning FCM with AI-personalized daily task list per contractor (which tasks are unblocked, materials needed, photo requirements); GC cross-trade status dashboard showing all trades simultaneously; AI conflict alerts when dependencies are at risk
**Uses:** Claude API as stateless request per contractor per day (no conversation history — input is task plan + dependency state + today's date), FCM infrastructure, TanStack Query for dashboard refresh
**Implements:** Daily checklist generation (stateless AI call per contractor), cross-trade dependency completion notifications, AI conflict alert detection logic, GC timeline/status view on web

### Phase Ordering Rationale

- Phases 1 and 2 are pure infrastructure — no external dependencies, no user-facing AI. They establish the data layer and graph engine that all subsequent phases write to. Getting RLS and `plan_version` right here prevents cascading security and data integrity issues in all later phases.
- Phase 3 (AI) precedes Phase 4 (chat) because AI generates the task plans that give chat meaningful project context. Chat without project tasks is a generic messaging app.
- Phase 5 (annotation) precedes Phase 6 (inspection) because GC inspection without annotated photo evidence is just a binary approve/reject button — the annotation is what makes inspection actionable.
- Phase 7 (billing) is relatively isolated — it could be slid to Phase 5 or 6 if business priorities require billing earlier, with minimal coordination cost.
- Phase 8 is additive capability on top of a complete system. An alternative ordering: daily checklist as Phase 4.5 (unlocks field contractor value earlier), monitoring dashboard remains Phase 8 — valid if field adoption metrics matter more than GC overview completeness.

### Research Flags

Phases requiring deeper research during planning:

- **Phase 3 (AI Agent Service):** Claude tool-use agentic loop prompt engineering for construction domain is novel. The system prompts for project intake (what questions to ask, how to structure trade scopes) and contractor interview (trade-specific questions per trade type) require iteration with real construction professionals before finalizing. Research the exact tool schema structure and turn limit behavior for complex projects before implementation.
- **Phase 4 (Real-Time Chat):** WebSocket JWT re-validation patterns with Riverpod `AsyncNotifier` reconnect flows need detailed design. Redis pub/sub integration with the existing slowapi Redis instance requires configuration audit — confirm Redis is present and `REDIS_URL` is already in the backend config.
- **Phase 5 (Photo Annotation):** Flutter `CustomPainter` layer separation architecture (RepaintBoundary + cached `ui.Image`) has multiple valid approaches. Spike the exact implementation pattern before committing — retrofitting the layered architecture after the performance cliff is hit is expensive.

Phases with well-documented patterns (research-phase can be skipped):

- **Phase 1 (Data Model):** Standard SQLAlchemy + PostgreSQL RLS pattern; identical to existing 15-entity model. Follow existing `TenantScopedModel` conventions exactly.
- **Phase 2 (Dependency Engine):** PostgreSQL recursive CTEs and NetworkX DAG algorithms are fully documented. ARCHITECTURE.md provides working pseudocode for both cycle detection and topological sort.
- **Phase 6 (Inspection):** State machine + FCM notification pattern follows existing job status transition model. Additive only.
- **Phase 7 (Per-Trade Billing):** Additive FK extension to proven models. Standard SQLAlchemy migration pattern.

## Confidence Assessment

| Area | Confidence | Notes |
|------|------------|-------|
| Stack | HIGH | All new libraries verified against npm/PyPI/pub.dev at specific versions as of March 2026; `anthropic` 0.86.0 released 5 days before research date; official Anthropic SDK and FastAPI SSE docs consulted directly |
| Features | HIGH | Cross-referenced against 10+ competitor platforms (Procore, Fieldwire, Buildertrend, Siteline, Knowify, Bluebeam, SafetyCulture, ConstructionOnline) plus PROJECT.md as source of truth; feature dependency graph is internally consistent |
| Architecture | HIGH | Existing codebase inspected directly (base_service.py, base_repository.py, sync/service.py, files/router.py); Claude API tool-use and FastAPI SSE patterns from official docs; PostgreSQL RLS side-channel risk from PostgreSQL wiki |
| Pitfalls | HIGH | 14 specific pitfalls with detection criteria, recovery strategies, and phase assignments; sources include official PostgreSQL RLS docs, Anthropic streaming docs, Ably WebSocket best practices, AWS multi-tenant AI guidance, and production cost data from Mem0 |

**Overall confidence: HIGH**

### Gaps to Address

- **AI prompt quality for construction domain:** Research identifies the tool schema structure and parameter constraints, but actual system prompts for project intake and contractor interview will require iteration with real tradespeople. Flag Phase 3 for user research before finalizing prompts — prompt engineering is not a coding task.
- **Redis availability in existing backend:** ARCHITECTURE.md assumes Redis is already present for slowapi rate limiting. Confirm `REDIS_URL` exists in the backend config before Phase 4 begins. If Redis is not present, it is a new infrastructure dependency that requires deployment planning.
- **Current Drift schema version:** PITFALLS.md references "Drift v6" as the current production schema version. Confirm the exact current Drift schema version from the existing codebase before Phase 1 mobile work begins to number migration steps correctly.
- **Claude model availability:** ARCHITECTURE.md recommends `claude-opus-4-5` for intake/interview and `claude-haiku-3-5` for daily checklist generation. Validate these specific model IDs are available in the Anthropic API before Phase 3 begins. Pin to specific versions, not `claude-*-latest`.
- **AI cost budget per company:** PITFALLS.md provides order-of-magnitude estimates ($500–$1,500/week with naive history replay). Actual token budget limits per company are a product decision that should be defined before the token budget strategy is implemented in Phase 3.

## Sources

### Primary (HIGH confidence)

- `backend/app/core/base_service.py`, `base_repository.py`, `base_models.py` — existing OOP pattern (direct codebase inspection)
- `backend/app/features/sync/service.py` — delta sync pattern reused for new entities (direct codebase inspection)
- `backend/app/features/files/router.py` — attachment pattern extended by annotation service (direct codebase inspection)
- `backend/app/core/config.py` — `ANTHROPIC_API_KEY` slot identified (direct codebase inspection)
- [anthropic PyPI](https://pypi.org/project/anthropic/) — version 0.86.0, March 18, 2026
- [Anthropic Tool Use docs](https://platform.claude.com/docs/en/agents-and-tools/tool-use/implement-tool-use) — agentic loop and tool schema pattern
- [Anthropic Structured Outputs](https://platform.claude.com/docs/en/build-with-claude/structured-outputs) — Pydantic-native structured outputs, public beta November 2025
- [FastAPI SSE docs](https://fastapi.tiangolo.com/tutorial/server-sent-events/) — official SSE implementation
- [FastAPI WebSockets docs](https://fastapi.tiangolo.com/advanced/websockets/) — WS auth pattern
- [sse-starlette PyPI](https://pypi.org/project/sse-starlette/) — version 3.3.3
- [redis PyPI](https://pypi.org/project/redis/) — version 7.1.1 with `redis.asyncio`
- [NetworkX documentation](https://networkx.org/documentation/stable/) — DAG algorithms (cycle detection, topological sort, critical path)
- [pro_image_editor pub.dev](https://pub.dev/packages/pro_image_editor) — version 12.0.7
- [web_socket_channel pub.dev](https://pub.dev/packages/web_socket_channel) — version 3.0.3
- [fabric npm](https://www.npmjs.com/package/fabric) — version 7.2.0
- [PostgreSQL Wiki: Row-Level Security](https://wiki.postgresql.org/wiki/Row-security) — FK side channel risk
- [Tailwind CSS v4 announcement](https://tailwindcss.com/blog/tailwindcss-v4)
- [Redux Toolkit npm](https://www.npmjs.com/package/@reduxjs/toolkit) — version 2.11.2
- [TanStack Query npm](https://www.npmjs.com/package/@tanstack/react-query) — version 5.90.21

### Secondary (MEDIUM confidence)

- Fieldwire, Procore, Buildertrend, Siteline, Knowify, Bluebeam, SafetyCulture — feature benchmark for table stakes determination
- [AWS Prescriptive Guidance: Tenant isolation for AI agents](https://docs.aws.amazon.com/prescriptive-guidance/latest/agentic-ai-multitenant/enforcing-tenant-isolation.html)
- [Ably: WebSocket Architecture Best Practices](https://ably.com/topic/websocket-architecture-best-practices)
- [Mem0: LLM Chat History Summarization Guide 2025](https://mem0.ai/blog/llm-chat-history-summarization-guide-2025) — token cost explosion production data
- [WebSocket/SSE multi-worker architecture guide 2025](https://blog.greeden.me/en/2025/10/28/weaponizing-real-time-websocket-sse-notifications-with-fastapi-connection-management-rooms-reconnection-scale-out-and-observability/)
- [React Flow (@xyflow/react)](https://reactflow.dev/) — dependency graph visualization
- [Next.js 15/16 features 2026](https://jishulabs.com/blog/nextjs-15-16-features-migration-guide-2026) — Next.js 16 stable confirmed

### Tertiary (LOW confidence)

- AI cost estimates ($500–$1,500/week) are order-of-magnitude extrapolations from published token pricing; actual costs depend on prompt design, project sizes, and usage patterns — validate with real production monitoring data

---
*Research completed: 2026-03-19*
*Ready for roadmap: yes*
