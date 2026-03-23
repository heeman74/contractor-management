# Phase 21: AI Project Intake and Contractor Interview - Context

**Gathered:** 2026-03-23
**Status:** Ready for planning

<domain>
## Phase Boundary

GCs describe projects in natural language via a multi-turn AI chat, and AI produces a structured trade scope breakdown with suggested sequencing and dependencies. Each trade contractor completes an AI-guided adaptive interview, and AI generates a detailed task plan with time estimates, materials, and dependencies. Both flows use Claude API with tool use for structured output, streaming responses via SSE, and full conversation persistence.

</domain>

<decisions>
## Implementation Decisions

### GC Intake Conversation Flow
- **D-01:** Multi-turn chat — GC types project description, AI asks 2-4 clarifying questions about trades/scope/timeline, then generates breakdown
- **D-02:** Dedicated page UI — full-page chat screen at `/projects/new/ai-intake` (web) and new screen from Projects tab (mobile)
- **D-03:** Streaming tokens — text streams word-by-word via SSE, feels responsive like ChatGPT
- **D-04:** Preview card below chat — trade breakdown appears as structured editable card/table below chat. GC can edit trade names, reorder, remove scopes, then tap "Create Project"
- **D-05:** Save full transcript — chat messages stored in DB linked to the project for reference/auditing
- **D-06:** Re-entry with context — GC can reopen chat for existing project. AI loads current trades as context for modifications
- **D-07:** Support image uploads — GC can attach site photos or blueprints. AI uses Claude vision to extract context

### Claude API Architecture
- **D-08:** Backend only — FastAPI backend calls Anthropic SDK, streams results to frontend via SSE. API key stays server-side
- **D-09:** Tool use for structured output — Claude uses tool_use to call functions like `create_trade_scope` and `create_task` with typed parameters. Guaranteed structured output
- **D-10:** Claude Sonnet model — fast, cost-effective, strong at tool use. Good balance for interactive chat latency
- **D-11:** Full history per request — send all previous messages + system prompt to Claude on each turn. Simple, works well for 5-10 turn intake chats
- **D-12:** Retry with backoff + user message — auto-retry 2-3 times with exponential backoff. Friendly message on persistent failure
- **D-13:** Track usage but don't limit — log token usage per company/user for analytics. No hard limits in Phase 21
- **D-14:** Inject trade catalog in system prompt — system prompt includes company's trade catalog entries so AI suggests matching trade names

### Contractor Interview Design
- **D-15:** Adaptive conversation — AI asks trade-specific questions based on scope context (fixture types, pipe materials, permits, etc.). Questions adapt based on answers. 5-10 questions per trade
- **D-16:** Full project + trade scope context — AI sees project description, all trade scopes with dependencies, and the specific scope this contractor owns
- **D-17:** Preview list with edit/approve — after interview, AI generates task list as editable cards. Contractor can rename, adjust estimates, reorder, add/remove before "Accept Plan"
- **D-18:** Both mobile and web — same chat interface adapted for each platform
- **D-19:** Re-interview allowed — contractor can restart interview to regenerate tasks. Old tasks replaced with confirmation
- **D-20:** Push notification + dashboard update — GC gets push: "Plumbing contractor completed interview — 12 tasks generated". Project dashboard shows interview status per scope
- **D-21:** AI estimates + contractor edits — AI pre-fills estimated_hours and materials_needed based on interview. Contractor reviews and adjusts

### Output Validation and Saving
- **D-22:** Tool use schema + Pydantic validation — Claude tool_use returns typed parameters matching existing Pydantic schemas (TradeScopeCreate, TaskCreate). Rejects malformed tool calls with error back to AI
- **D-23:** AI suggests trade sequencing — AI suggests execution order using Phase 20's dependency engine (e.g., framing before electrical). GC accepts/modifies in preview
- **D-24:** Same create endpoints — AI-generated data hits same POST /trade-scopes, POST /tasks endpoints. Reuses all existing validation, RLS, sync. AI is just another client

### Chat UI Design
- **D-25:** Modern chat bubbles — rounded bubbles, user right-aligned (brand color), AI left-aligned (gray). Typing indicator (three dots) while AI responds
- **D-26:** Branded AI persona — "ContractorHub AI" with icon/avatar. Professional, clear it's the product's AI
- **D-27:** Image thumbnails in bubbles — uploaded images show as thumbnails in message bubble, tap to view full-screen with zoom/pan

### System Prompt Engineering
- **D-28:** Rich construction context — system prompt includes common residential/commercial trade sequences, typical task patterns per trade, material categories, and estimation heuristics
- **D-29:** Code (version-controlled) — system prompts live as Python constants or text files in backend repo. Updated via deploys. Consistent across companies

### Offline Behavior
- **D-30:** Block with clear message — "AI features require an internet connection." Disable chat input when offline. v3.0 is online-first, don't queue stale AI requests
- **D-31:** Sync transcripts to Drift — after interview completes, transcript syncs to local Drift DB. Contractor can review what was discussed offline

### Claude's Discretion
- SSE streaming implementation details (chunked transfer encoding pattern)
- Chat message DB schema design (conversation table, message table structure)
- AI token usage tracking table schema
- Typing indicator animation implementation
- System prompt text content (specific construction knowledge, heuristics)
- Image upload flow (compress before sending to Claude, max size, accepted formats)
- Trade sequence suggestion algorithm (topological sort from AI output to dependency engine)

</decisions>

<canonical_refs>
## Canonical References

**Downstream agents MUST read these before planning or implementing.**

### Data Model (Phase 19 foundation)
- `backend/app/features/projects/models.py` — Project, TradeScope, Task, TaskAttachment models with all fields AI needs to populate
- `backend/app/features/projects/schemas.py` — TradeScopeCreate, TaskCreate Pydantic schemas (AI tool_use params must match these)
- `backend/app/features/projects/service.py` — ProjectService, TradeScopeService, TaskService (AI calls same create methods)
- `backend/app/features/projects/router.py` — Existing REST endpoints that AI-generated data flows through

### Dependency Engine (Phase 20)
- `backend/app/features/projects/service.py` — DependencyService.create_dependency() for AI-suggested trade sequencing
- `backend/app/features/projects/models.py` — TaskDependency edge table, ProjectZone model

### OOP Architecture (must follow)
- `backend/app/core/base_models.py` — BaseEntityModel, TenantScopedModel inheritance
- `backend/app/core/base_service.py` — BaseService, TenantScopedService patterns
- `backend/app/core/base_repository.py` — BaseRepository, TenantScopedRepository
- `backend/app/core/base_router.py` — CRUDRouter mixin
- `backend/app/core/base_schemas.py` — BaseResponseSchema

### Mobile (Drift + sync)
- `mobile/lib/core/database/app_database.dart` — Current schema version (v8), migration pattern
- `mobile/lib/core/sync/sync_handler.dart` — Abstract SyncHandler for new conversation/message sync
- `mobile/lib/core/sync/sync_registry.dart` — Handler registration

### Web (existing patterns)
- `web/src/app/api/proxy/route.ts` — How frontend communicates with backend (needs SSE extension)
- `web/src/lib/api/projects.ts` — TanStack Query hooks pattern for new AI endpoints

### Notifications
- `backend/app/features/notifications/models.py` — DeviceToken model for FCM push (interview completion notification)

### Requirements
- `.planning/REQUIREMENTS.md` — AI-01 (project intake), AI-02 (clarifying questions), AI-03 (contractor interview)
- `.planning/ROADMAP.md` — Phase 21 success criteria

</canonical_refs>

<code_context>
## Existing Code Insights

### Reusable Assets
- `TradeScopeCreate` / `TaskCreate` schemas — AI tool_use parameters should match these exactly
- `DependencyService.create_dependency()` — for persisting AI-suggested trade sequencing
- Trade catalog reference table — inject into system prompt for consistent naming
- FCM push notification infrastructure — for contractor interview completion alerts
- Existing file upload pattern in `backend/app/features/files/router.py` — aiofiles async writes, adaptable for image uploads

### Established Patterns
- All services inherit from `TenantScopedService` — new AIService must follow
- API proxy at `/api/proxy?path=/api/v1/{endpoint}` — needs SSE streaming extension
- Drift schema migrations with `if (from < N)` pattern — new conversation/message tables
- SyncHandler abstract class for new entity sync

### Integration Points
- Backend: new `backend/app/features/ai/` module with models, service, router, schemas
- AI endpoints under `/api/v1/ai/` (intake, interview, conversations)
- Web: new chat page component under `/projects/new/ai-intake` and `/projects/{id}/interview/{scopeId}`
- Mobile: new chat screen accessible from Projects tab and trade scope detail
- System prompt includes company's trade catalog (fetched at conversation start)
- Anthropic Python SDK (`anthropic` package) added to requirements.txt

</code_context>

<specifics>
## Specific Ideas

- Chat should feel like ChatGPT — streaming tokens, typing indicator, clean bubbles
- AI persona is "ContractorHub AI" with a branded avatar
- GC sees a structured preview card of the trade breakdown they can edit before creating
- Contractor sees editable task cards after interview with pre-filled estimates and materials
- System prompt should be rich with construction domain knowledge (trade sequences, material categories, estimation heuristics)
- Image uploads support site photos and blueprints — Claude vision extracts context

</specifics>

<deferred>
## Deferred Ideas

- Company-customizable system prompt templates (requires prompt editor UI) — future phase
- AI-generated zone lists from project description — possible Phase 22+
- AI conflict resolution suggestions — future AI enhancement
- Passkey/WebAuthn for contractors — separate auth phase
- Video uploads in chat — future media enhancement
- Hard token budget per company with billing — future monetization phase

</deferred>

---

*Phase: 21-ai-project-intake-and-contractor-interview*
*Context gathered: 2026-03-23*
