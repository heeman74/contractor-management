# Domain Pitfalls

**Domain:** Adding AI planning, real-time chat, photo annotation, and multi-trade project management to an existing contractor management platform (ContractorHub v3.0)
**Researched:** 2026-03-19
**Confidence:** HIGH (architecture/integration risks from official FastAPI, Anthropic, PostgreSQL, Flutter docs and verified GitHub issues; MEDIUM for cost modeling based on published pricing data; specific patterns verified against existing codebase structure)

---

## Context: What Already Exists and What's Being Added

**Existing (do not break):**
- 15-entity offline-first sync via transactional outbox + Drift
- Job/Quote/Invoice data models with established Flutter deserialization
- PostgreSQL RLS with `SET LOCAL app.current_tenant_id` per session
- JWT auth with refresh token family revocation (mobile Bearer tokens + web httpOnly cookies)
- FastAPI `TenantScopedService` / `TenantScopedRepository` OOP hierarchy

**Being added:**
- Claude API tool-use integration for AI project intake and contractor interviews
- Project → Trade Scope → Task data model hierarchy (new tables, new FK graph)
- Real-time bidirectional chat via WebSockets
- Photo annotation (drawing layer on existing photo infrastructure)
- Architecture shift: offline-first → online-first with offline cache for field execution

All pitfalls below are specific to the integration risk of adding these features to the working system above.

---

## Critical Pitfalls

Mistakes that cause rewrites or major data integrity issues.

---

### Pitfall 1: Offline-First Outbox Conflicts With Online-First AI State

**What goes wrong:**
The existing transactional outbox queues all mutations locally for eventual server sync. The v3.0 AI checklist system generates server-side task plans that the app must display. When a contractor goes offline and completes checklist items locally (outbox mutations), then reconnects, the sync engine replays their outbox while simultaneously receiving a new AI-generated plan update. The outbox processes task completions against a task ID that has since been replaced or reordered by AI schedule adaptation. Result: phantom completions, wrong task status, or sync constraint violations.

**Why it happens:**
The outbox pattern assumes the client is the source of truth for all mutations. AI planning violates this — the server is now also generating and modifying task state. There is no mechanism in the existing 15-entity sync to handle server-initiated entity mutations racing with client outbox replay.

**Consequences:**
Data loss or data corruption for task completion records. AI daily checklists show completed tasks as pending. Progress tracking is unreliable. Trust in the platform collapses.

**Prevention:**
Define explicit domain boundaries before writing any code:
1. **AI-generated entities (read-only on client):** Project, TradeScope, Task — AI owns their structure; clients can never create or structurally modify these.
2. **Client-owned entities (offline-writable):** TaskProgress, TaskNote, TaskPhoto, ChecklistItemCompletion — these are append-only records with stable IDs that do not conflict with AI plan revisions.
3. Never put AI-generated task plan mutations through the outbox. AI plan updates come from server push only (FCM + refresh on reconnect), not from client mutations replayed.
4. Add a `plan_version` field to Task. Client outbox mutations for progress carry the `plan_version` they were created against. Server rejects (409) completions referencing a superseded plan version, and the app prompts the user to review the updated plan.

**Detection:**
- Outbox entries with `entity_type = 'task'` for creation or structural updates (not progress/completion) — red flag, tasks are server-owned.
- No `plan_version` field on task completion records.
- Sync tests that don't exercise concurrent AI update + client outbox replay.

**Phase to address:** The first phase establishing the Project/Task data model (before any AI planning code ships).

---

### Pitfall 2: New Table Hierarchy Orphans Existing RLS Policies

**What goes wrong:**
The new Project → TradeScope → Task hierarchy adds tables (`projects`, `trade_scopes`, `tasks`) that reference existing company data. RLS policies on these new tables are written correctly, but the existing `jobs` table is left with an implicit FK to `trade_scopes` without an RLS policy update. A query joining `jobs` to `tasks` bypasses the project-level RLS because the join uses the job's existing RLS context, not the project's. A GC from Company A can, via a crafted join query, read Task records belonging to Company B's project.

**Why it happens:**
RLS policy authors focus on each new table in isolation. They validate that `SELECT * FROM tasks` is correctly filtered. They don't audit every query path that joins across the old and new table hierarchies. Foreign key constraints between RLS tables don't enforce tenant context — PostgreSQL foreign keys operate at the row level, not at the policy level.

Per the PostgreSQL wiki: "There is no sane and consistent model to make foreign keys make sense between tables with different labels / row security policies."

**Consequences:**
Multi-tenant data isolation breach. Company A reads Company B's project plans. GDPR/SOC2 violation risk. Rewrite of all join queries required under time pressure.

**Prevention:**
1. Every new table (`projects`, `trade_scopes`, `tasks`, `chat_messages`, `task_photos`, `annotations`) must have an explicit RLS policy before any data is inserted.
2. RLS policies on child tables must validate tenant via a JOIN back to the parent's `company_id`, not via a stored `company_id` column that could be spoofed in application code.
3. Write a cross-tenant isolation test for every new endpoint, specifically testing multi-table join queries (e.g., `GET /projects/{id}/tasks` with a Company B token while the project belongs to Company A).
4. Add a CI step that lists all tables without RLS enabled and fails if any new table is missing a policy.

**Detection:**
- Any new table without `ALTER TABLE x ENABLE ROW LEVEL SECURITY`.
- RLS policies that use `company_id = current_setting('app.current_tenant_id')` on a table where `company_id` is not a direct column (i.e., it requires a JOIN to get it) — these policies need verification.
- Missing integration test: "Company B token + Company A project ID returns 404, not 200."

**Phase to address:** Data model migration phase. No new table goes to production without its RLS policy and a cross-tenant test.

---

### Pitfall 3: AI Context Window Grows Unbounded, Costs Explode

**What goes wrong:**
The AI project intake conversation starts with a system prompt (~2,000 tokens), adds the contractor interview exchange (~5,000 tokens), then appends the full project plan for adaptation queries, then adds task completion summaries. By week two of a project, every AI schedule adaptation call sends 40,000–80,000 tokens of context, costing $1–3 per single adaptation request. A company running 10 active projects generates $500–$1,500/week in AI costs with zero revenue uplift — all from a conversation history management design decision made in the first sprint.

Published data: a production support bot handling 10,000 daily conversations can rack up $7,500+/month in token costs from naive conversation history appending.

**Why it happens:**
The first implementation sends the full message history to Claude on every request because it's the simplest pattern. No one thinks about cost until the first invoice. Claude's 200,000-token context window makes it feel like "there's plenty of room" — there is room, but cost scales with input tokens.

**Consequences:**
Unit economics collapse. Either AI features are throttled (degraded UX), costs are passed to customers at uncompetitive rates, or the conversation storage architecture is ripped out and rebuilt under urgency.

**Prevention:**
Design conversation history management before writing the first AI endpoint:
1. **Project intake**: One-time conversation. Store the raw exchange. Never re-send as history — only store the final structured output (JSON plan). The intake is a finite conversation, not an ongoing one.
2. **Contractor interview**: Same — one-time per trade scope. Store structured output only.
3. **AI schedule adaptation**: Does NOT need conversation history. Needs only: current task states + delays + weather/context snapshot. Structure as a stateless request with a compact summary, not a conversation thread.
4. **Daily checklist generation**: Stateless. Input is the task plan + date. No history needed.
5. Token budget per AI call: set `max_tokens` appropriately per use case. Log input + output tokens per call. Alert when a call exceeds 20,000 input tokens.

**Detection:**
- Any AI service method that passes a `messages` array containing unbounded conversation history.
- No `max_tokens` limit set on any Anthropic API call.
- No token usage logging or cost tracking per AI operation type.

**Phase to address:** AI integration phase (first one). Token budget strategy must be in the design doc before implementation begins.

---

### Pitfall 4: AI Structured Output Parsing Failures Silently Corrupt the Task Plan

**What goes wrong:**
Claude returns a JSON task plan via tool use. The parsing code assumes the tool call succeeds and the JSON is valid. In production, under model version updates or edge-case inputs (unusual trade descriptions, non-English input, very large projects), Claude occasionally returns malformed tool calls, partial JSON, or valid JSON with hallucinated fields (e.g., a `dependency_id` referencing a task ID that doesn't exist in the same response). The application stores the partial plan and the user sees a broken task list.

Claude tool use returns valid schema responses 95–99% of the time — not 100%. Anthropic's own docs note that tool use schemas are "hints" unless using strict structured output modes.

**Why it happens:**
Developers test the happy path. The LLM returns perfect JSON during development. Error handling is "I'll add that later." Later never comes before production.

**Consequences:**
Corrupt project plans in the database. Tasks with non-existent dependency IDs cause cascade failures in the dependency graph resolution. AI planning loses user trust after two failures.

**Prevention:**
1. Use Claude tool use with explicit tool definitions. Parse the response with Pydantic validation — never `json.loads()` without schema validation.
2. Validate referential integrity of AI output before persisting: every `dependency_id` in the task plan must reference a task ID that exists in the same response payload.
3. On parse failure or validation failure: do NOT persist partial data. Return a structured error to the client. Queue a retry with a simplified prompt. Log the raw Claude response for debugging.
4. Write a test that deliberately sends Claude responses with missing fields, null IDs, and circular dependencies — verify the application rejects and retries, not stores.
5. Pin Claude model version (`claude-sonnet-4-5`) in the service layer. Update consciously, not by drifting to `claude-sonnet-latest`.

**Detection:**
- `json.loads(response)` without Pydantic model validation in any AI response handler.
- No test for malformed tool call responses.
- `dependency_id` values not validated against the task list before persistence.

**Phase to address:** AI planning phase. Robust parsing must be in the first implementation, not added after the first production failure.

---

### Pitfall 5: WebSocket Auth Uses Initial Handshake Only, Sessions Stay Open Forever

**What goes wrong:**
The chat WebSocket authenticates the user at connection establishment (JWT verified at `ws://...?token=...` or in the first message). The JWT expires 15 minutes later. The WebSocket connection remains open. The user's JWT is now invalid (refresh was needed), but the WebSocket has no mechanism to re-validate. The user continues to send and receive chat messages on an expired session. Worse: a revoked user (fired contractor) retains real-time chat access until their WebSocket disconnects.

**Why it happens:**
REST endpoints validate the JWT on every request automatically. WebSocket connections are stateful — authentication happens once at handshake. Developers don't realize they need a separate token refresh mechanism for the WebSocket layer.

**Consequences:**
Security gap: revoked users retain access. Compliance failure in a multi-tenant B2B system where employee offboarding requires immediate access termination.

**Prevention:**
1. WebSocket connections must validate the JWT at the initial handshake (reject at HTTP 401 before upgrade if invalid).
2. Server must re-validate the session periodically during the WebSocket lifecycle (every 5 minutes) using a server-side session store, not just the JWT expiry. When the JWT would be expired, close the connection with code 4401 and send a reconnect signal.
3. The Flutter client must handle the 4401 close code: refresh the token via the standard auth flow, then reconnect the WebSocket with the new token.
4. On user deactivation/logout: trigger a server-side WebSocket connection close for all active connections belonging to that user. Maintain a connection registry (in-memory or Redis keyed by `user_id`) to enable forced disconnect.

**Detection:**
- WebSocket handler that only validates JWT in the connection event, not periodically.
- No test for "JWT expires mid-session — verify connection is closed and client reconnects."
- No test for "user revoked — verify WebSocket is force-closed server-side."

**Phase to address:** Real-time chat phase, from the first WebSocket endpoint.

---

### Pitfall 6: AI Conversation State Leaks Across Tenants

**What goes wrong:**
The AI project intake service stores conversation state (system prompt + message history) in a Python dict or in-memory cache keyed by `session_id`. Two concurrent project intake sessions from different companies share a server process. If the session state is accidentally keyed by `user_id` only (not `company_id + user_id`), or if a caching library returns state from a prior evicted session for a new user with a recycled ID, tenant A's project description contaminates tenant B's AI planning response.

**Why it happens:**
AI conversation state feels like a simple cache entry. RLS handles database isolation but has no concept of in-memory Python state. Developers who wrote the existing multi-tenant system are expert at RLS but haven't thought about where the AI conversation lives between API calls.

**Consequences:**
Tenant A reads tenant B's proprietary project details via the AI response. Multi-tenant SaaS trust failure. Potentially a GDPR breach.

**Prevention:**
1. Never store AI conversation state in module-level Python variables or shared in-memory stores.
2. Store conversation history in the database (a `ai_conversations` table with `company_id`, `user_id`, `session_id`, RLS policy enabled). Retrieve from DB on every continuation request.
3. The `system_prompt` for every AI call must include the tenant's `company_id` as an identifier. This does not provide security (Claude has no enforcement) but does create an audit trail.
4. AI service methods must be in `TenantScopedService` and receive `company_id` from the authenticated user's JWT, never from request body parameters.
5. Add a test: start intake session as Company A, submit a second request as Company B using Company A's `session_id` — verify 403 or empty, not Company A's data.

**Detection:**
- AI conversation state stored in `app.state` or module-level Python dict.
- `session_id` used as a cache key without `company_id` prefix.
- AI service that accepts `company_id` from request body instead of JWT.

**Phase to address:** AI integration phase. Tenant isolation for AI state must be in the design, not retrofitted.

---

## Moderate Pitfalls

Mistakes that cause significant rework but not data loss.

---

### Pitfall 7: Per-Trade Quote Extension Breaks Existing Quote Approval Flow

**What goes wrong:**
The existing Quote model has a linear approval flow: GC creates quote, client approves/rejects. Extending to per-trade quotes means a project has N trade quotes that aggregate to a project total. The client approval flow is now ambiguous: does the client approve each trade quote individually, or the aggregate? The existing Pydantic `QuoteResponse` schema adds new fields (`trade_scope_id`, `project_id`) without making them `Optional` — the Flutter app deserializing the old schema crashes on the new response shape. The mobile outbox has pending quote-related mutations that process against a schema that no longer exists.

**Why it happens:**
Developers extend the Quote model in-place to add multi-trade fields. They test the web dashboard (which they just updated). They don't test the Flutter app (which has the old deserialization code) or the outbox (which has pending mutations from the old schema).

**Prevention:**
1. New fields on existing Pydantic response schemas MUST be `Optional` with defaults. Never add required fields to an existing response schema — the Flutter app will crash on upgrade lag.
2. Create a new `TradeQuote` model alongside the existing `Quote`, not instead of it. The project-level aggregate is a new concept; individual job quotes retain their existing structure. Existing jobs (non-project) continue using the existing `Quote` flow unchanged.
3. Before shipping the Quote extension: run the mobile test suite against the new API response (response compatibility test). Confirm `QuoteResponse` deserialization in Flutter handles all optional new fields gracefully.
4. Test: outbox with pending quote mutation from old schema replays against new API — verify it succeeds or fails gracefully, not with an unhandled 422.

**Detection:**
- `QuoteResponse` with new non-Optional fields.
- No Flutter deserialization test against the updated API schema.
- No test that exercises the existing mobile quote flow after the per-trade extension.

**Phase to address:** Per-trade quoting phase. Treat the existing Quote model as a public API — additive changes only.

---

### Pitfall 8: Photo Annotation Layer Blocks the Main Flutter UI Thread

**What goes wrong:**
The annotation canvas uses `CustomPaint` with a `List<Annotation>` that grows as the user draws. Each `notifyListeners()` call triggers a repaint of the entire canvas including the background photo. On a high-resolution construction photo (5MB+, 4000x3000px), the canvas repaints the full image on every pointer move event. At 60fps pointer events, this blocks the UI thread, causing jank and dropped frames. The annotation that "works fine in testing" (low-res simulator photos) is unusable in the field (high-res phone photos).

Flutter 2025 best practice: use `PictureRecorder` caching for the static background layer, repaint only the annotation layer. This is not the default `CustomPaint` behavior.

**Why it happens:**
The photo is treated as a static widget behind the canvas. In practice, a `CustomPaint` with `foregroundPainter` still repaints when the parent rebuilds. Image decoding is not cached between paints. The test environment uses small images that hide the performance problem.

**Prevention:**
1. Pre-decode the background photo to a `ui.Image` once (using `decodeImageFromList`). Cache this `ui.Image` and paint it directly with `canvas.drawImage()` — do not use an `Image` widget or rebuild from bytes on each paint.
2. Separate the background layer (static, cached `RepaintBoundary`) from the annotation layer (dynamic `CustomPaint`). Only the annotation layer repaints on pointer events.
3. Use `PointFilterMode` and simplify line paths with Douglas-Peucker algorithm or Bezier smoothing before adding to the `List<Annotation>` — reduce the point count that must be redrawn.
4. Test with real device photos from a Pixel or Samsung (4000x3000px+). Simulator testing with network images is not representative.

**Detection:**
- `CustomPaint` that paints both the background image and annotations in the same painter.
- No `RepaintBoundary` separating the static photo layer from the annotation layer.
- Performance testing only done on simulator or with small test images.

**Phase to address:** Photo annotation phase. Architecture decision must be made before first implementation — layered canvas is harder to retrofit.

---

### Pitfall 9: Chat Message Delivery Guarantees — WebSocket Is Not Reliable Enough Alone

**What goes wrong:**
The chat implementation sends messages over WebSocket only. A contractor sends a site photo in a chat message. The GC's WebSocket connection drops (intermittent field site connectivity) at the exact moment of delivery. The message is lost — no persistence, no retry, no delivery confirmation. The contractor thinks the GC received it. The GC never sees it. A critical safety issue (e.g., photo of cracked foundation) is missed.

**Why it happens:**
WebSocket feels like a reliable channel. It is not — it is a transport layer with no built-in delivery guarantees. "Fire and forget" over WebSocket is fine for low-stakes real-time events, not for business-critical construction communication.

**Prevention:**
1. Chat messages must be persisted to the database (REST endpoint or within WebSocket handler) before they are considered sent. The client should not show "sent" status until server ACK.
2. Use WebSocket for real-time delivery (low latency), but persist to DB on every send. Message recipients fetch chat history via REST on reconnect — they receive anything missed during disconnection.
3. Implement a simple ACK protocol: server assigns `message_id` and sends back an ACK event over the WebSocket. Client tracks unacknowledged messages. After 10 seconds without ACK, client retries via REST POST.
4. FCM push notification for every new chat message (background delivery when WebSocket is not connected). This already has infrastructure from v1.

**Detection:**
- Chat messages that are only sent via WebSocket with no database persistence.
- No delivery ACK mechanism in the WebSocket protocol.
- No FCM push for chat messages.

**Phase to address:** Real-time chat phase. Delivery guarantee architecture must be in the design doc.

---

### Pitfall 10: Drift Schema Migration Required for New Entities — Outbox Schema Also Changes

**What goes wrong:**
The Project, TradeScope, Task, ChatMessage, and TaskAnnotation entities need Drift table definitions for offline caching. Each new Drift table increments the schema version and requires a `MigrationStrategy`. The existing outbox table has a fixed set of `entity_type` values. Adding new entity types to the outbox without a Drift migration causes schema validation errors on existing installs. Users who had the v1.0 app installed and upgrade directly to v3.0 encounter a migration path that must traverse from Drift version 6 to version X without data loss.

**Why it happens:**
The mobile team adds Drift tables alongside new features without coordinating the migration path across the full version range. A migration added for v3.0 phase 2 accidentally references a column added in v3.0 phase 4 — works on fresh installs, fails on upgrade from v1.0.

**Prevention:**
1. Maintain a single `migrations.dart` file with sequential schema version steps. Every step must be tested with the previous version's schema as the starting state.
2. Before shipping any v3.0 phase: test the full migration path from Drift v6 (current production schema) to the new version on a device with production-like data.
3. New outbox `entity_type` values must be added via a Drift migration that adds the value to an enum or removes the constraint, not assumed to exist.
4. Use Drift's `destructiveFallback` only in development. Production migrations must be non-destructive.

**Detection:**
- No test that starts from a prior Drift schema version and validates migration success.
- New entity types added to the outbox without updating the Drift schema.
- `MigrationStrategy` with `destructiveFallback` outside of `kDebugMode`.

**Phase to address:** First v3.0 mobile entity phase. Establish migration discipline before any new Drift table ships.

---

### Pitfall 11: Claude API Rate Limits Cause Cascading UX Failures During Project Intake

**What goes wrong:**
A GC creates three projects in the same hour. Each project intake sends 3–5 Claude API requests (intake conversation + contractor interviews per trade). 15 concurrent API requests hit Anthropic's rate limits (tokens-per-minute limit, not just requests-per-minute). Anthropic returns 429. The application has no retry logic. All three project intakes fail simultaneously, showing users a generic error. The GC tries again — hits rate limits again. Trust in AI planning collapses in the first week of production.

**Why it happens:**
Rate limits are not a problem during development (one developer, occasional requests). They surface under real production multi-user load. Anthropic's rate limits are tiered by account and reset in short windows — hitting them is not an exception condition in production, it's expected behavior that must be handled gracefully.

**Prevention:**
1. Implement exponential backoff with jitter for all Claude API calls. On 429: wait (2^retry_count * 1000ms) + random(0–1000ms), max 3 retries.
2. Queue project intake requests per company (not globally). If Company A is already processing an intake, queue the second intake rather than sending concurrently.
3. Expose rate limit status to the user: "Your project is being planned — this takes 30–60 seconds" rather than a silent spinner or instant failure.
4. Track token usage per company per hour. Alert operators when a company is approaching limits. Future: implement per-company token budget.
5. Structure Claude calls to minimize token usage: short system prompts, focused tool definitions, no unnecessary conversation history (see Pitfall 3).

**Detection:**
- No retry logic on Anthropic API calls.
- Multiple concurrent Claude API requests per user session.
- No user-facing progress indication during AI processing (users retry on slow responses, multiplying the load).

**Phase to address:** AI integration phase. Rate limit handling must be in the first Claude API service, not added after the first production incident.

---

## Minor Pitfalls

Mistakes that cause rework in one area but don't cascade.

---

### Pitfall 12: Dependency Graph Circular Dependency Not Detected at Creation Time

**What goes wrong:**
The task dependency model allows Trade A's final task to depend on Trade B's final task, which depends on Trade A's final task. The AI creates this correctly (it doesn't make circular dependencies). But the human override flow — where a GC manually adjusts dependencies on the web dashboard — has no cycle detection. The DAG becomes a graph with cycles. Schedule calculation hangs or recurses infinitely.

**Prevention:**
On every dependency edge creation (via API or AI generation), run a DFS cycle detection on the task graph before persisting. This is O(V+E) and fast for construction project sizes (rarely >200 tasks). Return 400 with "This dependency creates a circular chain: Task A → Task B → Task A" before saving.

**Detection:**
No cycle detection in the `POST /tasks/{id}/dependencies` endpoint or AI plan persistence service.

**Phase to address:** Task dependency model phase.

---

### Pitfall 13: AI-Generated Task Plans Are Too Granular for Real Field Use

**What goes wrong:**
Claude is given a trade scope description ("install all electrical in a 3-bed house") and generates 47 tasks with 15 subtasks each, 8 material line items per subtask, and photo requirements every 20 minutes. A contractor in the field opens the AI checklist and sees a wall of text. Adoption is zero — contractors ignore the checklist and use their own judgment. The "AI-powered productivity" feature becomes a liability.

**Why it happens:**
The AI is optimized to be thorough, not practical. The system prompt doesn't constrain output to what a field contractor actually needs. No user research with real contractors was done before the prompt was written.

**Prevention:**
1. Prompt engineering test: show the AI output to 2–3 real tradespeople before shipping. Adjust based on their feedback.
2. Constrain task count in the tool definition: `max_tasks_per_trade: 15`, `max_checklist_items_per_task: 5`, `photo_requirements: ["start", "end", "issue_only"]`.
3. Allow contractors to collapse/skip AI subtasks. The AI plan is a suggestion, not a mandate.
4. Add a "plan density" setting that GCs can configure: "detailed" (AI default) vs. "lightweight" (fewer tasks, morning summary only).

**Detection:**
AI plans with >20 tasks per trade scope in test output. No user review of AI output before feature ships.

**Phase to address:** AI contractor interview phase. Prompt constraints must be defined with input from real users.

---

### Pitfall 14: Chat File Sharing Uses the Existing Photo Endpoint, Causing Storage Mix-Up

**What goes wrong:**
The chat feature reuses the existing `/jobs/{id}/photos` endpoint for file sharing in chat. Photos sent in chat are stored alongside job progress photos. The mobile sync layer pulls all job photos — now it also pulls chat photos. Storage costs increase, sync time increases, and the Drift photo cache fills with chat images that the user never requested. Photo annotation (designed for job/task photos) appears on chat photos when the user taps them.

**Why it happens:**
Reusing the existing endpoint feels efficient. The storage infrastructure is already there. Nobody audited what "pulling all job photos" means when chat photos are also in that bucket.

**Prevention:**
Chat file attachments are a separate entity. Create a `chat_attachments` table and a `/chat/{conversation_id}/attachments` upload endpoint. Chat attachments: no Drift sync (online-only), no photo annotation, separate S3 prefix. Task/job photos: existing path, Drift sync, annotation enabled.

**Detection:**
Chat file upload calling `/jobs/{id}/photos` or any endpoint that writes to the job photos entity.

**Phase to address:** Real-time chat phase. Storage separation must be in the design before implementation.

---

## Phase-Specific Warnings

| Phase Topic | Likely Pitfall | Mitigation |
|-------------|---------------|------------|
| Data model migration (Project/Task) | RLS policies missing on new tables | CI check: all tables have RLS; cross-tenant isolation test per endpoint |
| AI project intake | Unbounded token cost | Design token budget before first implementation; stateless adaptation calls |
| AI project intake | Structured output parsing failures | Pydantic validation + referential integrity check on every AI response |
| AI contractor interview | Over-granular task plans | Constrain tool definition; user research before shipping |
| Real-time chat | WebSocket-only delivery (messages lost) | Persist to DB first; ACK protocol; FCM fallback |
| Real-time chat | JWT expiry mid-session | Periodic server-side re-validation; 4401 close code + client reconnect |
| Real-time chat | Chat attachments mixed with job photos | Separate `chat_attachments` entity and storage path |
| Photo annotation | UI thread blocking on large photos | Cache `ui.Image`; separate static/dynamic layers; test with real device photos |
| Per-trade quoting | Breaking existing Quote schema | Additive-only changes; `TradeQuote` alongside existing `Quote`; mobile compat test |
| Offline → online-first shift | Outbox conflicts with AI state | Domain boundary: AI-owned vs client-owned entities; `plan_version` for conflict detection |
| Drift schema migration | Migration path gaps from v1 → v3 | Test full migration chain from Drift v6; no destructiveFallback in production |
| Any new AI endpoint | Tenant context leak in conversation state | Store conversation state in DB with RLS; `TenantScopedService` for all AI services |
| Any new AI endpoint | Rate limit cascades | Exponential backoff; per-company request queue; user-facing progress indication |
| Task dependency model | Circular dependency graph | DFS cycle detection on every edge creation before persisting |

---

## Technical Debt Patterns to Avoid

| Shortcut | Why Teams Take It | Long-term Cost | Decision |
|----------|-------------------|----------------|----------|
| Send full conversation history to Claude on every call | Simplest pattern; works in dev | Cost explosion at production scale | Never — design token budgets from day one |
| Validate AI JSON with `json.loads()` only | Fast to write | Hallucinated fields corrupt the data model | Never — always Pydantic schema validation + referential integrity |
| WebSocket-only chat (no persistence) | Simpler server code | Messages lost on disconnect; no history on reconnect | Never — persist first, deliver second |
| Reuse job photos endpoint for chat | Less code | Storage mix-up; sync overhead; annotation on chat photos | Never — separate entities for separate concerns |
| Add per-trade fields to existing Quote schema as required | Faster than new model | Flutter crash on response deserialization | Never — Optional fields only, or new model alongside old |
| Store AI conversation in Python dict / app.state | Fast prototype | Tenant context leak across companies | Never — DB-backed with RLS |
| Test photo annotation only on simulator | Convenient | Performance cliff on real device photos | Never — always test with 4K+ real photos |
| Validate WebSocket JWT at handshake only | Standard WebSocket tutorial pattern | Revoked users retain access until disconnect | Never — periodic re-validation required |

---

## Integration Gotchas

| Integration | Common Mistake | Correct Approach |
|-------------|----------------|------------------|
| Anthropic API + multi-tenant | Conversation state in shared in-memory cache | DB-backed `ai_conversations` table with `company_id` + RLS |
| Anthropic API + FastAPI async | Synchronous `anthropic.messages.create()` blocking event loop | Use `AsyncAnthropic` client; all Claude calls must be awaitable |
| WebSocket + JWT (15-min TTL) | Auth at handshake only; sessions stay open post-expiry | Periodic server-side session check; 4401 close + client reconnect flow |
| Drift + new v3 entity types | Adding entity types without Drift migration | `MigrationStrategy` with sequential steps; test from v6 → vN |
| Existing outbox + AI-owned entities | Queuing AI plan mutations in the outbox | AI-owned entities are read-only on client; no outbox for plan structure changes |
| Flutter `CustomPaint` + large photos | Repainting background image on every annotation event | Cache `ui.Image`; separate layers with `RepaintBoundary` |
| Per-trade quotes + existing Quote model | Adding required fields to existing `QuoteResponse` | `Optional` fields only; separate `TradeQuote` model for new behavior |
| New tables + existing RLS | FK relationships between tables with different RLS labels | Explicit RLS policy on every new table; CI check for unprotected tables |

---

## "Looks Done But Isn't" Checklist

- [ ] **AI cost:** Token usage is logged per AI call type. No call sends more than 20,000 input tokens without an explicit design reason.
- [ ] **AI parsing:** Every AI response goes through Pydantic validation + referential integrity check before database write.
- [ ] **Tenant isolation:** AI conversation state is in the database with RLS. No Python dict or `app.state` cache for conversation history.
- [ ] **WebSocket auth:** JWT re-validated server-side every 5 minutes. Test: JWT expires mid-session → connection closed → client reconnects.
- [ ] **WebSocket delivery:** Chat message persisted to DB before "sent" status shown to user. ACK protocol implemented.
- [ ] **RLS coverage:** Every new table has an explicit RLS policy. CI fails if a new table without RLS is added.
- [ ] **Cross-tenant isolation:** Integration test for every new endpoint: Company B token + Company A resource ID returns 404.
- [ ] **Mobile schema compatibility:** `QuoteResponse`, `JobResponse`, and all extended schemas — new fields are `Optional` with defaults. Flutter deserialization test passes.
- [ ] **Drift migration:** Full migration chain from Drift v6 tested on a device with real data. No `destructiveFallback` in production builds.
- [ ] **Domain boundary:** No outbox entry has `entity_type` for `Project`, `TradeScope`, or `Task` creation/update (these are server-owned). Client outbox only for progress/completion records.
- [ ] **Photo performance:** Annotation tested with a real 4000x3000px photo on a physical Android device. No frame drops during drawing.
- [ ] **Dependency graph:** Cycle detection runs on every dependency edge creation. Test: circular dependency returns 400.
- [ ] **Chat attachments:** Chat file uploads go to `chat_attachments`, not `job_photos`. Drift sync does not pull chat attachments.
- [ ] **Rate limits:** Anthropic API calls have exponential backoff. Test: mock 429 → verify retry behavior, not crash.

---

## Recovery Strategies

| Pitfall | Recovery Cost | Recovery Steps |
|---------|---------------|----------------|
| AI cost explosion discovered after launch | HIGH — architecture rework under time pressure | Immediate: add `max_tokens` hard limit to all calls. Short-term: move to stateless adaptation requests. Medium-term: rearchitect conversation storage to avoid history replay. |
| Tenant context leak in AI conversations | CRITICAL — potential GDPR breach | Immediately disable AI features. Audit all `ai_conversations` rows for cross-tenant contamination. Migrate conversation state to DB with RLS. Notify affected companies if contamination confirmed. |
| Corrupt task plans from unparsed AI output | HIGH | Identify affected plans via `plan_version` audit. Re-run intake for affected projects. Add Pydantic validation retroactively and backfill integrity checks. |
| Missing RLS on new table discovered post-launch | CRITICAL | Immediately add RLS policy. Audit query logs for cross-tenant access patterns. If breach confirmed, treat as security incident. |
| Outbox conflicts corrupt task completions | HIGH | Identify affected completion records via `plan_version` mismatch audit. Re-sync affected devices. Add domain boundary enforcement retroactively. |
| WebSocket auth gap (revoked user retains access) | MEDIUM | Deploy server-side forced disconnect for known revoked users. Add periodic re-validation. Audit WebSocket logs for access after revocation. |
| Mobile crash from schema change | MEDIUM | Revert breaking field change on backend. Deploy hotfix within one deploy cycle. Add mobile deserialization test to CI before re-shipping. |

---

## Sources

- Anthropic Streaming Docs (tool use, fine-grained streaming) — https://platform.claude.com/docs/en/build-with-claude/streaming
- Mem0: LLM Chat History Summarization Guide 2025 (cost explosion data) — https://mem0.ai/blog/llm-chat-history-summarization-guide-2025
- AWS Prescriptive Guidance: Implementing tenant isolation for AI agents — https://docs.aws.amazon.com/prescriptive-guidance/latest/agentic-ai-multitenant/enforcing-tenant-isolation.html
- PostgreSQL Wiki: Row-Level Security (foreign key side channel) — https://wiki.postgresql.org/wiki/Row-security
- Permit.io: Postgres RLS Implementation Guide — https://www.permit.io/blog/postgres-rls-implementation-guide
- Ably: WebSocket Architecture Best Practices — https://ably.com/topic/websocket-architecture-best-practices
- Flutter Drawing Board package (canvas performance data) — https://pub.dev/packages/flutter_drawing_board
- Flutter 2025 Performance Best Practices — https://flutterexperts.com/flutter-2025-performance-best-practices-what-has-changed-what-still-works/
- DEV Community: Offline-First App Architecture — https://dev.to/odunayo_dada/offline-first-mobile-app-architecture-syncing-caching-and-conflict-resolution-1j58
- Transactional Outbox Pattern (microservices.io) — https://microservices.io/patterns/data/transactional-outbox.html
- Riverpod GitHub Issue: WebSocket connection detection — https://github.com/rrousselGit/riverpod/issues/182
- Medium: WebSocket Reconnection in Flutter — https://medium.com/@punithsuppar7795/websocket-reconnection-in-flutter-keep-your-real-time-app-alive-be289cff46b8
- DEV Community: LLM Structured Output 2026 — https://dev.to/pockit_tools/llm-structured-output-in-2026-stop-parsing-json-with-regex-and-do-it-right-34pk
- Agenta.ai: Guide to structured outputs and function calling — https://agenta.ai/blog/the-guide-to-structured-outputs-and-function-calling-with-llms

---
*Pitfalls research for: ContractorHub v3.0 — Adding AI planning, real-time chat, photo annotation, and multi-trade project management to existing system*
*Researched: 2026-03-19*
