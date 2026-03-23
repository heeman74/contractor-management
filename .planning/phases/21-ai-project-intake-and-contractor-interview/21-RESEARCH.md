# Phase 21: AI Project Intake and Contractor Interview - Research

**Researched:** 2026-03-23
**Domain:** Anthropic Claude API (tool use + streaming SSE), FastAPI SSE, Flutter SSE HTTP client, multi-turn conversation persistence
**Confidence:** HIGH (core SDK patterns verified from official docs; FastAPI SSE verified from official docs; Flutter SSE verified from pub.dev and community sources)

---

<user_constraints>
## User Constraints (from CONTEXT.md)

### Locked Decisions

**GC Intake Conversation Flow**
- D-01: Multi-turn chat — GC types project description, AI asks 2-4 clarifying questions about trades/scope/timeline, then generates breakdown
- D-02: Dedicated page UI — full-page chat screen at `/projects/new/ai-intake` (web) and new screen from Projects tab (mobile)
- D-03: Streaming tokens — text streams word-by-word via SSE, feels responsive like ChatGPT
- D-04: Preview card below chat — trade breakdown appears as structured editable card/table below chat. GC can edit trade names, reorder, remove scopes, then tap "Create Project"
- D-05: Save full transcript — chat messages stored in DB linked to the project for reference/auditing
- D-06: Re-entry with context — GC can reopen chat for existing project. AI loads current trades as context for modifications
- D-07: Support image uploads — GC can attach site photos or blueprints. AI uses Claude vision to extract context

**Claude API Architecture**
- D-08: Backend only — FastAPI backend calls Anthropic SDK, streams results to frontend via SSE. API key stays server-side
- D-09: Tool use for structured output — Claude uses tool_use to call functions like `create_trade_scope` and `create_task` with typed parameters. Guaranteed structured output
- D-10: Claude Sonnet model — fast, cost-effective, strong at tool use. Good balance for interactive chat latency
- D-11: Full history per request — send all previous messages + system prompt to Claude on each turn. Simple, works well for 5-10 turn intake chats
- D-12: Retry with backoff + user message — auto-retry 2-3 times with exponential backoff. Friendly message on persistent failure
- D-13: Track usage but don't limit — log token usage per company/user for analytics. No hard limits in Phase 21
- D-14: Inject trade catalog in system prompt — system prompt includes company's trade catalog entries so AI suggests matching trade names

**Contractor Interview Design**
- D-15: Adaptive conversation — AI asks trade-specific questions based on scope context. 5-10 questions per trade
- D-16: Full project + trade scope context — AI sees project description, all trade scopes with dependencies, and the specific scope this contractor owns
- D-17: Preview list with edit/approve — after interview, AI generates task list as editable cards. Contractor can rename, adjust estimates, reorder, add/remove before "Accept Plan"
- D-18: Both mobile and web — same chat interface adapted for each platform
- D-19: Re-interview allowed — contractor can restart interview to regenerate tasks. Old tasks replaced with confirmation
- D-20: Push notification + dashboard update — GC gets push: "Plumbing contractor completed interview — 12 tasks generated". Project dashboard shows interview status per scope
- D-21: AI estimates + contractor edits — AI pre-fills estimated_hours and materials_needed based on interview. Contractor reviews and adjusts

**Output Validation and Saving**
- D-22: Tool use schema + Pydantic validation — Claude tool_use returns typed parameters matching existing Pydantic schemas (TradeScopeCreate, TaskCreate). Rejects malformed tool calls with error back to AI
- D-23: AI suggests trade sequencing — AI suggests execution order using Phase 20's dependency engine
- D-24: Same create endpoints — AI-generated data hits same POST /trade-scopes, POST /tasks endpoints

**Chat UI Design**
- D-25: Modern chat bubbles — rounded bubbles, user right-aligned, AI left-aligned
- D-26: Branded AI persona — "ContractorHub AI" with icon/avatar
- D-27: Image thumbnails in bubbles — uploaded images show as thumbnails, tap to view full-screen

**System Prompt Engineering**
- D-28: Rich construction context — system prompt includes common residential/commercial trade sequences, typical task patterns per trade, material categories, and estimation heuristics
- D-29: Code (version-controlled) — system prompts live as Python constants or text files in backend repo

**Offline Behavior**
- D-30: Block with clear message — disable chat input when offline
- D-31: Sync transcripts to Drift — after interview completes, transcript syncs to local Drift DB

### Claude's Discretion
- SSE streaming implementation details (chunked transfer encoding pattern)
- Chat message DB schema design (conversation table, message table structure)
- AI token usage tracking table schema
- Typing indicator animation implementation
- System prompt text content (specific construction knowledge, heuristics)
- Image upload flow (compress before sending to Claude, max size, accepted formats)
- Trade sequence suggestion algorithm (topological sort from AI output to dependency engine)

### Deferred Ideas (OUT OF SCOPE)
- Company-customizable system prompt templates (requires prompt editor UI) — future phase
- AI-generated zone lists from project description — possible Phase 22+
- AI conflict resolution suggestions — future AI enhancement
- Passkey/WebAuthn for contractors — separate auth phase
- Video uploads in chat — future media enhancement
- Hard token budget per company with billing — future monetization phase
</user_constraints>

---

<phase_requirements>
## Phase Requirements

| ID | Description | Research Support |
|----|-------------|-----------------|
| AI-01 | GC can describe a project in natural language and AI breaks it into trade scopes with suggested sequencing | Anthropic tool_use with `create_trade_scope` tool definition; SSE streaming for token-by-token display; Pydantic validation before DB write |
| AI-02 | AI asks follow-up questions to clarify project scope before generating trade breakdown | Multi-turn message history sent on each API call; Claude instructed via system prompt to ask 2-4 clarifying questions before calling `create_trade_scope` tool |
| AI-03 | AI interviews each trade contractor with trade-specific questions to generate detailed task plans | Separate contractor interview flow with `create_task` tool; same chat architecture; trade scope + project context injected into system prompt |
</phase_requirements>

---

## Summary

Phase 21 introduces two AI-powered chat flows: the GC project intake (AI produces trade scopes) and the contractor interview (AI produces tasks). Both flows share the same underlying architecture: an Anthropic Claude API call on the FastAPI backend, streaming SSE tokens to the frontend, with `tool_use` to produce structured output that passes through existing Pydantic validation before hitting existing REST endpoints.

The core technical challenge is the SSE proxy: the current `web/src/app/api/proxy/route.ts` buffers responses with `await upstreamRes.text()` and returns a complete NextResponse. This must be replaced with a streaming SSE route that pipes the `ReadableStream` directly from the FastAPI backend. On mobile, Dio cannot stream SSE; the standard `dart:io` HttpClient or `http.Request.send()` approach must be used for the chat endpoints.

The second challenge is the multi-turn conversation pattern: each turn must append the AI's response (including any `tool_use` blocks) and the `tool_result` to the message history before the next Claude call. The backend must persist this history to PostgreSQL per conversation, keyed by `conversation_id`, so re-entry works and transcripts survive.

**Primary recommendation:** Build `backend/app/features/ai/` as a new TenantScopedService module. Use `AsyncAnthropic` with `client.messages.stream()` context manager in an async generator that feeds a FastAPI `EventSourceResponse`. For tool_use, do NOT stream tool calls — collect the full `tool_use` block via `stream.get_final_message()`, validate with Pydantic, write to DB, then send a `tool_result` SSE event to the frontend signalling that structured data is ready.

---

## Standard Stack

### Core
| Library | Version | Purpose | Why Standard |
|---------|---------|---------|--------------|
| anthropic | 0.86.0 (Mar 2026) | Claude API Python SDK | Official Anthropic SDK; async support; tool_use; streaming context manager |
| fastapi[standard] | 0.115.12 (pinned) | SSE endpoint host | Already in use; `EventSourceResponse` built into FastAPI 0.115+ |
| asyncpg | 0.30.0 (pinned) | Async PostgreSQL driver | Already in use for all DB work |

### Supporting
| Library | Version | Purpose | When to Use |
|---------|---------|---------|-------------|
| aiofiles | 24.1.0 (pinned) | Async image file read for base64 encoding | When GC uploads blueprint/photo for vision |
| firebase-admin | 6.6.0 (pinned) | FCM push notification on interview complete | Already in use for D-20 push notification |
| flutter_client_sse (pub.dev) | latest | Dart SSE client for token streaming | Mobile chat screen only; Dio cannot stream SSE |

### Alternatives Considered
| Instead of | Could Use | Tradeoff |
|------------|-----------|----------|
| FastAPI built-in EventSourceResponse | sse-starlette library | sse-starlette is redundant; FastAPI 0.115 includes EventSourceResponse natively |
| anthropic SDK stream() | httpx direct streaming | SDK abstracts retry, event accumulation, tool_use helpers — use SDK |
| flutter_client_sse | Dio streaming | Dio does not support SSE; flutter_client_sse uses dart:io HttpClient correctly |

**Installation:**
```bash
# Backend
cd backend && uv add anthropic

# Mobile (pubspec.yaml)
flutter_client_sse: ^1.0.0
```

**Version verification:** `anthropic` 0.86.0 confirmed via GitHub releases (Mar 18, 2026). `fastapi` EventSourceResponse confirmed in 0.115.x official docs.

---

## Architecture Patterns

### Recommended Project Structure

```
backend/app/features/ai/
├── __init__.py
├── models.py           # Conversation, AIMessage, AITokenUsage models
├── schemas.py          # ConversationCreate, MessageCreate, AIMessageResponse
├── repository.py       # ConversationRepository, AIMessageRepository
├── service.py          # AIService (TenantScopedService) — Claude calls, tool dispatch
├── router.py           # POST /ai/intake/start, POST /ai/intake/message,
│                       # POST /ai/interview/start, POST /ai/interview/message
└── prompts/
    ├── intake_system.py         # GC intake system prompt constant
    └── interview_system.py      # Contractor interview system prompt constant

mobile/lib/features/ai/
├── data/
│   ├── ai_conversation_dao.dart     # Drift DAO for local transcript cache
│   └── ai_service.dart              # DIO-free HTTP SSE client for chat endpoints
├── presentation/
│   ├── providers/
│   │   ├── intake_chat_provider.dart
│   │   └── interview_chat_provider.dart
│   ├── screens/
│   │   ├── intake_chat_screen.dart
│   │   └── interview_chat_screen.dart
│   └── widgets/
│       ├── chat_bubble.dart
│       ├── typing_indicator.dart
│       └── trade_scope_preview_card.dart

web/src/features/ai/
├── api/                            # SSE streaming Next.js route (replaces proxy)
│   └── chat/
│       └── route.ts                # ReadableStream proxy to FastAPI SSE
├── components/
│   ├── ChatBubble.tsx
│   ├── TypingIndicator.tsx
│   ├── TradeScopePreviewCard.tsx
│   └── TaskPreviewList.tsx
└── hooks/
    ├── useIntakeChat.ts
    └── useInterviewChat.ts
```

### Pattern 1: AsyncAnthropic Streaming with Tool Use (Backend)

**What:** FastAPI SSE endpoint that streams Claude tokens and signals tool_use completion.
**When to use:** All AI chat turns — both intake and contractor interview.

The two-phase approach: stream text tokens in real-time, then collect the full final message to handle any `tool_use` blocks synchronously before persisting to DB.

```python
# Source: Official Anthropic SDK docs (docs.anthropic.com) + FastAPI SSE docs
from anthropic import AsyncAnthropic
from collections.abc import AsyncIterable
from fastapi.sse import EventSourceResponse, ServerSentEvent
import json

client = AsyncAnthropic()  # reads ANTHROPIC_API_KEY from env

async def stream_claude_turn(
    messages: list[dict],
    tools: list[dict],
    system_prompt: str,
) -> AsyncIterable[ServerSentEvent]:
    """Stream a single Claude turn as SSE events.

    Event types emitted:
    - "token"      : {"delta": "text chunk"} — live text stream
    - "tool_call"  : {"tool": "create_trade_scope", "input": {...}} — when tool_use fires
    - "done"       : {"stop_reason": "end_turn" | "tool_use"} — stream complete
    - "error"      : {"message": "..."} — on failure
    """
    async with client.messages.stream(
        model="claude-sonnet-4-6",  # D-10: Claude Sonnet
        max_tokens=4096,
        system=system_prompt,
        tools=tools,
        messages=messages,
    ) as stream:
        async for event in stream:
            if event.type == "content_block_delta":
                if event.delta.type == "text_delta":
                    yield ServerSentEvent(
                        data=json.dumps({"delta": event.delta.text}),
                        event="token",
                    )
        # Collect final message — gets tool_use blocks
        final_msg = await stream.get_final_message()

    # Emit tool_call events after text stream completes
    for block in final_msg.content:
        if block.type == "tool_use":
            yield ServerSentEvent(
                data=json.dumps({"tool": block.name, "input": block.input}),
                event="tool_call",
            )

    yield ServerSentEvent(
        data=json.dumps({"stop_reason": final_msg.stop_reason}),
        event="done",
    )
```

FastAPI route:
```python
@router.post("/ai/intake/message", response_class=EventSourceResponse)
async def intake_message(
    req: ChatMessageRequest,
    current_user: CurrentUser = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
) -> AsyncIterable[ServerSentEvent]:
    # Load conversation, validate ownership, build message history
    # ...
    return EventSourceResponse(
        stream_claude_turn(messages, intake_tools, system_prompt)
    )
```

### Pattern 2: Tool Use Schema Matching Pydantic (D-09, D-22)

**What:** Claude `tool_use` input_schema mirrors existing TradeScopeCreate and TaskCreate Pydantic schemas exactly.
**When to use:** When Claude finishes the intake interview and is ready to commit structured data.

```python
# Source: Anthropic tool use docs + projects/schemas.py
INTAKE_TOOLS = [
    {
        "name": "create_trade_scope",
        "description": "Create a trade scope with suggested sequencing after gathering project details. Call once per trade.",
        "input_schema": {
            "type": "object",
            "properties": {
                "trade_name": {"type": "string", "description": "Trade name (match from catalog if possible)"},
                "trade_color": {"type": "string", "description": "Hex color code, e.g. #4CAF50"},
                "sort_order": {"type": "integer", "description": "Suggested execution order (0-indexed)"},
            },
            "required": ["trade_name", "sort_order"],
        },
    },
    {
        "name": "ask_clarifying_question",
        "description": "Ask the GC a clarifying question before generating trade scopes. Use when project description is ambiguous.",
        "input_schema": {
            "type": "object",
            "properties": {
                "question": {"type": "string"},
            },
            "required": ["question"],
        },
    },
]

INTERVIEW_TOOLS = [
    {
        "name": "create_task",
        "description": "Create a task for this trade scope. Call once per task after the interview is complete.",
        "input_schema": {
            "type": "object",
            "properties": {
                "title": {"type": "string", "maxLength": 300},
                "description": {"type": "string"},
                "priority": {"type": "string", "enum": ["low", "medium", "high", "urgent"]},
                "estimated_hours": {"type": "number"},
                "sort_order": {"type": "integer"},
                "materials_needed": {
                    "type": "array",
                    "items": {
                        "type": "object",
                        "properties": {
                            "name": {"type": "string"},
                            "quantity": {"type": "number"},
                            "unit": {"type": "string"},
                        },
                    },
                },
            },
            "required": ["title", "sort_order"],
        },
    },
]
```

### Pattern 3: Multi-Turn Message History (D-11)

**What:** Every Claude API call includes the full conversation history. Tool results are appended as `user` role messages with `tool_result` content.

```python
# Source: Anthropic multi-turn tool use docs
def build_claude_messages(db_messages: list[AIMessage]) -> list[dict]:
    """Convert persisted AIMessage rows to Claude API message format.

    DB stores role + content_json. Tool use blocks are stored as JSON
    and reconstructed into the proper format for Claude.
    """
    result = []
    for msg in db_messages:
        content = json.loads(msg.content_json)
        result.append({"role": msg.role, "content": content})
    return result

def append_tool_result(
    messages: list[dict],
    tool_use_id: str,
    tool_name: str,
    result_content: str,
) -> list[dict]:
    """Append tool_result after AI's tool_use block (required by Claude API)."""
    return messages + [
        {
            "role": "user",
            "content": [
                {
                    "type": "tool_result",
                    "tool_use_id": tool_use_id,
                    "content": result_content,
                }
            ],
        }
    ]
```

### Pattern 4: Web SSE Proxy (New Route — Replaces Generic Proxy)

**What:** Next.js route that pipes FastAPI SSE stream directly to the browser. The existing `proxy/route.ts` buffers responses; AI chat needs a streaming-aware route.

```typescript
// Source: Upstash blog + Next.js App Router docs
// web/src/app/api/ai-chat/route.ts
export const dynamic = "force-dynamic";

export async function POST(request: Request): Promise<Response> {
  const cookieStore = await cookies();
  const accessToken = cookieStore.get("access_token")?.value;
  if (!accessToken) {
    return Response.json({ detail: "Not authenticated" }, { status: 401 });
  }

  const body = await request.text();
  const upstreamUrl = `${FASTAPI_URL}/api/v1/ai/intake/message`;

  const upstreamRes = await fetch(upstreamUrl, {
    method: "POST",
    headers: {
      "Authorization": `Bearer ${accessToken}`,
      "Content-Type": "application/json",
    },
    body,
  });

  // Pipe ReadableStream directly — do NOT call .text() (buffers entire stream)
  return new Response(upstreamRes.body, {
    status: upstreamRes.status,
    headers: {
      "Content-Type": "text/event-stream; charset=utf-8",
      "Cache-Control": "no-cache, no-transform",
      "Connection": "keep-alive",
    },
  });
}
```

Client hook pattern:
```typescript
// Token-by-token streaming via fetch + ReadableStream reader
async function streamChatTurn(payload: ChatTurnRequest, onToken: (t: string) => void) {
  const res = await fetch("/api/ai-chat", { method: "POST", body: JSON.stringify(payload) });
  const reader = res.body!.pipeThrough(new TextDecoderStream()).getReader();
  while (true) {
    const { value, done } = await reader.read();
    if (done) break;
    // Parse SSE "data:" lines
    for (const line of value.split("\n")) {
      if (line.startsWith("data: ")) {
        const json = JSON.parse(line.slice(6));
        if (json.delta) onToken(json.delta);
      }
    }
  }
}
```

### Pattern 5: Flutter SSE HTTP Streaming (Mobile)

**What:** Dart HTTP streaming for SSE — Dio cannot handle SSE. Use `http.Request.send()` or `flutter_client_sse` package.

```dart
// Source: flutter_client_sse pub.dev docs + dart:io HTTP pattern
import 'package:flutter_client_sse/flutter_client_sse.dart';

Stream<SSEModel> streamChatTurn({
  required String conversationId,
  required String message,
  required String accessToken,
}) {
  return SSEClient.subscribeToSSE(
    method: SSERequestType.POST,
    url: 'https://api.contractorhub.com/api/v1/ai/intake/message',
    header: {
      'Authorization': 'Bearer $accessToken',
      'Content-Type': 'application/json',
      'Accept': 'text/event-stream',
    },
    body: jsonEncode({
      'conversation_id': conversationId,
      'message': message,
    }),
  );
}
```

### Pattern 6: Conversation DB Schema (Claude's Discretion)

**What:** PostgreSQL schema for persisting conversation state.

```sql
-- Migration 0017_ai_conversations.py
CREATE TABLE ai_conversations (
    id          UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    company_id  UUID NOT NULL REFERENCES companies(id),
    project_id  UUID REFERENCES projects(id) ON DELETE SET NULL,
    scope_id    UUID REFERENCES trade_scopes(id) ON DELETE SET NULL,
    user_id     UUID NOT NULL REFERENCES users(id),
    conv_type   TEXT NOT NULL CHECK (conv_type IN ('intake','interview')),
    status      TEXT NOT NULL DEFAULT 'active' CHECK (status IN ('active','complete','abandoned')),
    version     INTEGER NOT NULL DEFAULT 1,
    created_at  TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at  TIMESTAMPTZ NOT NULL DEFAULT now(),
    deleted_at  TIMESTAMPTZ
);

CREATE TABLE ai_messages (
    id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    company_id      UUID NOT NULL REFERENCES companies(id),
    conversation_id UUID NOT NULL REFERENCES ai_conversations(id) ON DELETE CASCADE,
    role            TEXT NOT NULL CHECK (role IN ('user','assistant')),
    content_json    JSONB NOT NULL,  -- stores Claude message content array verbatim
    sequence_num    INTEGER NOT NULL, -- ordering within conversation
    version         INTEGER NOT NULL DEFAULT 1,
    created_at      TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at      TIMESTAMPTZ NOT NULL DEFAULT now(),
    deleted_at      TIMESTAMPTZ,
    UNIQUE (conversation_id, sequence_num)
);

CREATE TABLE ai_token_usage (
    id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    company_id      UUID NOT NULL REFERENCES companies(id),
    conversation_id UUID NOT NULL REFERENCES ai_conversations(id),
    user_id         UUID NOT NULL REFERENCES users(id),
    model           TEXT NOT NULL,
    input_tokens    INTEGER NOT NULL,
    output_tokens   INTEGER NOT NULL,
    created_at      TIMESTAMPTZ NOT NULL DEFAULT now()
    -- No deleted_at — usage records are immutable
);
```

### Anti-Patterns to Avoid
- **Streaming tool_use blocks:** Do not try to stream `tool_use` JSON incrementally. The input JSON arrives as partial JSON deltas. Use `stream.get_final_message()` to get the complete parsed tool input, then validate synchronously.
- **Storing messages in app.state / in-memory dicts:** CLAUDE.md + STATE.md: "AI conversation history stored in PostgreSQL JSONB — never in-memory dicts or app.state". Every message must be persisted before the next turn.
- **Proxying via the generic `/api/proxy` route for SSE:** The generic proxy buffers `await upstreamRes.text()`. AI chat requires a dedicated streaming route that pipes `ReadableStream` directly.
- **Using Dio for SSE in Flutter:** Dio cannot handle SSE `text/event-stream` streaming. Use `flutter_client_sse` or `http.Request.send()` with stream listening.
- **Calling existing service methods inside the AI SSE generator:** Service methods use `AsyncSession` from FastAPI DI. Inside an async generator that outlives the request lifecycle, the session may be closed. Load all context (conversation, project, scopes) before starting the stream, pass as pre-loaded data.
- **Sending full message history without checking context window:** For 5-10 turn chats, full history is safe. Add a `max_messages` guard (e.g., keep last 20 messages) if conversation grows beyond expected scope.

---

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| Streaming SSE to browser | Manual chunked transfer encoding | `EventSourceResponse` (FastAPI built-in) | Handles keep-alive pings, Cache-Control, X-Accel-Buffering automatically |
| SSE client in Flutter | Dio streaming workaround | `flutter_client_sse` package | Dio issue #1279 — SSE fundamentally broken in Dio's interceptor chain |
| Structured JSON output from Claude | Custom JSON extraction via regex | Claude `tool_use` with `strict: true` | Tool use guarantees schema conformance; regex breaks on edge cases |
| Conversation history management | Rolling window in application code | Send full history (D-11 decision) | 5-10 turn chats are well within Claude context window |
| Token streaming accumulation | Manual SSE event parser | `stream.get_final_message()` (Anthropic SDK) | SDK accumulates all events and returns the complete typed `Message` object |
| Push notification on interview complete | Custom Firebase call | Existing `NotificationService.send_push()` | Already battle-tested; fire-and-forget with UnregisteredError cleanup |

**Key insight:** The Anthropic SDK's `tool_use` + `stream()` combination makes structured output trivially reliable. The two hardest problems (JSON schema conformance, partial streaming) are solved by the SDK. The main engineering effort is in the conversation state machine and SSE proxy.

---

## Common Pitfalls

### Pitfall 1: SSE Proxy Buffering in Next.js
**What goes wrong:** The Next.js proxy reads `await upstreamRes.text()` which buffers the entire stream in memory before sending. User sees no tokens until Claude finishes.
**Why it happens:** The generic proxy was built for JSON REST responses, not streaming.
**How to avoid:** Create a dedicated `/api/ai-chat/route.ts` that returns `new Response(upstreamRes.body, {...})` — pipes the `ReadableStream` directly.
**Warning signs:** If the frontend only updates after a 5-10 second pause (no incremental tokens), the proxy is buffering.

### Pitfall 2: Tool Use Blocks in Multi-Turn History
**What goes wrong:** When Claude responds with `tool_use`, the assistant message contains both text blocks and tool_use blocks. If you only append the text to history and omit the tool_use blocks, the next Claude call fails with "tool_use block without matching tool_result".
**Why it happens:** Claude API requires that every `tool_use` in the assistant message is followed by a `tool_result` in the next user message.
**How to avoid:** Always persist `final_message.content` (the full content array, including tool_use blocks) as the assistant message in the DB. On re-entry, reconstruct the full content array.
**Warning signs:** `anthropic.BadRequestError: tool_use block without matching tool_result`.

### Pitfall 3: Nested AsyncSession in SSE Generator
**What goes wrong:** FastAPI's `get_db` dependency yields a session scoped to the request lifetime. An async generator that continues streaming after returning to the client may find the session closed.
**Why it happens:** FastAPI's `AsyncSession` context manager closes on generator exit in some configurations.
**How to avoid:** Load all DB state (conversation, project, trade scopes, catalog) before starting the SSE generator. Pass pre-loaded objects into the generator, not DB sessions.
**Warning signs:** `sqlalchemy.exc.InvalidRequestError: Session is closed` inside the SSE stream.

### Pitfall 4: Image Upload Size for Claude Vision
**What goes wrong:** Sending a 12MB blueprint PNG to Claude API — API rejects files over the base64 size limit (approx 5MB per image, 20MB total per request).
**Why it happens:** Claude vision has a 5MB per-image limit (base64 encoded). A 4MB file becomes ~5.3MB after base64 encoding.
**How to avoid:** Compress images to max 1280x1280px and 1MB before base64 encoding. Use `flutter_image_compress` on mobile (already in pubspec). Use PIL/Pillow on backend as a server-side guard.
**Warning signs:** `anthropic.BadRequestError: image too large`.

### Pitfall 5: Flutter SSE with Dio
**What goes wrong:** Attempting to stream SSE responses using Dio's `ResponseType.stream` or `ResponseType.bytes`. The interceptor chain (`QueuedInterceptor`) does not support the streaming lifecycle correctly, and token events are batched or dropped.
**Why it happens:** Dio was designed for request/response cycles, not long-lived streaming connections.
**How to avoid:** Use `flutter_client_sse` or `dart:io`'s `HttpClient` directly for the AI chat endpoints. Use Dio only for all other API calls.
**Warning signs:** Chat bubbles update in batches instead of word-by-word.

### Pitfall 6: Drift Schema Version Must Increment
**What goes wrong:** Adding Drift tables (`AiConversations`, `AiMessages`) without incrementing `schemaVersion` in `app_database.dart`. On first run with new tables, the database is not migrated and Drift throws `SqliteException: no such table`.
**Why it happens:** Drift uses `onUpgrade` only when schema version changes.
**How to avoid:** Current schema version is 8. New AI tables require schema version 9. Add `if (from < 9)` block in `onUpgrade`.
**Warning signs:** `SqliteException: no such table: ai_conversations`.

### Pitfall 7: Re-interview Without Cleanup
**What goes wrong:** When a contractor re-interviews (D-19), the old tasks are not deleted before the new `create_task` tool calls write new tasks. Result: duplicate tasks in the scope.
**Why it happens:** AI creates tasks via tool use; there is no automatic cleanup of prior tasks.
**How to avoid:** On "Accept Plan" (not on interview start), soft-delete all existing tasks for the scope before writing new ones. On interview start, mark conversation as `abandoned`; old tasks remain until explicit acceptance.
**Warning signs:** Trade scope shows double the expected tasks after re-interview.

---

## Code Examples

### Defining the AIService Class (Backend OOP Architecture)

```python
# Source: backend/app/core/base_service.py pattern
# backend/app/features/ai/service.py

from app.core.base_service import TenantScopedService
from app.features.ai.models import AIConversation
from app.features.ai.repository import AIConversationRepository
from anthropic import AsyncAnthropic

_anthropic_client = AsyncAnthropic()  # module-level singleton; reads env

class AIService(TenantScopedService[AIConversation]):
    repository_class = AIConversationRepository

    async def get_or_create_conversation(
        self, project_id: uuid.UUID, conv_type: str, user_id: uuid.UUID
    ) -> AIConversation:
        company_id = self._require_tenant_id()
        # ... look up existing active conversation or create new one
```

### FastAPI EventSourceResponse (Verified Pattern)

```python
# Source: FastAPI 0.115 SSE docs (fastapi.tiangolo.com/tutorial/server-sent-events/)
from collections.abc import AsyncIterable
from fastapi.sse import EventSourceResponse, ServerSentEvent

@router.post("/ai/intake/message", response_class=EventSourceResponse)
async def intake_message(
    req: ChatTurnRequest,
    current_user: CurrentUser = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
) -> AsyncIterable[ServerSentEvent]:
    # Load all context before entering async generator
    service = AIService(db)
    conversation, messages, context = await service.load_conversation_context(
        req.conversation_id, current_user
    )
    return EventSourceResponse(
        _generate_tokens(conversation, messages, context)
    )
```

### Drift Table for AI Conversations (Schema v9)

```dart
// mobile/lib/core/database/tables/ai_conversations.dart
import 'package:drift/drift.dart';
import 'package:uuid/uuid.dart';
import 'companies.dart';

class AiConversations extends Table {
  TextColumn get id => text().clientDefault(() => const Uuid().v4())();
  TextColumn get companyId => text().references(Companies, #id)();
  TextColumn get projectId => text().nullable()();
  TextColumn get scopeId => text().nullable()();
  TextColumn get userId => text()();
  TextColumn get convType => text()();  // 'intake' | 'interview'
  TextColumn get status => text().withDefault(const Constant('active'))();
  // Full transcript as JSON array — synced from backend after interview complete (D-31)
  TextColumn get transcriptJson => text().withDefault(const Constant('[]'))();
  IntColumn get version => integer().withDefault(const Constant(1))();
  DateTimeColumn get createdAt => dateTime()();
  DateTimeColumn get updatedAt => dateTime()();
  DateTimeColumn get deletedAt => dateTime().nullable()();

  @override
  Set<Column> get primaryKey => {id};
}
```

---

## State of the Art

| Old Approach | Current Approach | When Changed | Impact |
|--------------|------------------|--------------|--------|
| LangChain / custom chains | Direct Anthropic SDK with tool_use | 2024-2025 | Simpler, fewer abstractions, better latency |
| HTTP polling for AI responses | SSE streaming (text/event-stream) | Standard now | Word-by-word display; ChatGPT-like UX |
| Prompt engineering for JSON | Claude `tool_use` with strict schemas | Anthropic GA v0.27.0 (May 2024) | Guaranteed schema compliance; no regex parsing |
| WebSocket for AI chat | SSE (server-push only) | Ongoing | SSE simpler for read-only server-push; WebSocket not needed |
| On-device models | Claude API (server-side) | Explicit decision in STATE.md | Quality + structured output; offline caches AI-generated plans |

**Deprecated/outdated:**
- `LangChain`: Not in this project. STATE.md explicitly decided "Claude API with tool use, no LangChain".
- `response_model` on SSE endpoints: FastAPI SSE endpoints use `response_class=EventSourceResponse`, not `response_model`.

---

## Open Questions

1. **ANTHROPIC_API_KEY provisioning**
   - What we know: The key must come from environment; noted as blocker in STATE.md (Phase 21 section)
   - What's unclear: Whether the key is provisioned for the development environment
   - Recommendation: Planner should add Wave 0 task to verify `ANTHROPIC_API_KEY` in `.env` and confirm `claude-sonnet-4-6` model availability before any AI tasks execute

2. **SSE in Next.js App Router with Vercel deployment**
   - What we know: `ReadableStream` piping works in Node.js runtime; Vercel has SSE support
   - What's unclear: Whether the project deploys to Vercel (where function timeout limits apply)
   - Recommendation: Add `export const dynamic = "force-dynamic"` and `export const maxDuration = 60` to the SSE route; use `runtime = "nodejs"` not `edge`

3. **Image upload pipeline for Claude vision (D-07)**
   - What we know: Claude has a ~5MB per-image limit; `flutter_image_compress` is in pubspec; existing `aiofiles` handles file writes
   - What's unclear: Whether images go to disk first then base64 to Claude, or directly in memory
   - Recommendation: Accept image as `UploadFile` in a separate `/ai/intake/image` endpoint, compress server-side to max 1024x1024 / 500KB, convert to base64, return an `image_ref_id` the client includes in the next chat message

4. **flutter_client_sse package maturity**
   - What we know: Package exists on pub.dev; multiple results confirm Flutter SSE via HTTP (not Dio)
   - What's unclear: Whether `flutter_client_sse` supports POST requests (some versions only support GET)
   - Recommendation: Verify POST support in `flutter_client_sse` before committing. If POST is not supported, use `dart:io HttpClient` directly with `StreamTransformer` for line splitting.

---

## Validation Architecture

### Test Framework
| Property | Value |
|----------|-------|
| Framework | pytest 8.3.4 (backend) + flutter_test (mobile) |
| Config file | `backend/pyproject.toml` (pytest section) |
| Quick run command | `cd backend && uv run python -m pytest tests/test_ai_service.py -x` |
| Full suite command | `cd backend && uv run python -m pytest && cd ../mobile && flutter test` |

### Phase Requirements → Test Map
| Req ID | Behavior | Test Type | Automated Command | File Exists? |
|--------|----------|-----------|-------------------|-------------|
| AI-01 | GC sends project description, receives SSE stream with tokens, then tool_call event for each trade scope | integration | `pytest tests/test_phase_21_e2e.py::test_intake_produces_trade_scopes -x` | ❌ Wave 0 |
| AI-01 | Trade scope tool_use input validates against TradeScopeCreate Pydantic schema | unit | `pytest tests/test_ai_service.py::test_tool_input_validates_trade_scope_create -x` | ❌ Wave 0 |
| AI-02 | When project description is ambiguous, Claude calls ask_clarifying_question tool before create_trade_scope | integration | `pytest tests/test_phase_21_e2e.py::test_intake_asks_clarifying_questions -x` | ❌ Wave 0 |
| AI-03 | Contractor submits interview answers, receives SSE stream, tasks are created and persisted | integration | `pytest tests/test_phase_21_e2e.py::test_interview_produces_tasks -x` | ❌ Wave 0 |
| AI-03 | Task tool_use input validates against TaskCreate Pydantic schema | unit | `pytest tests/test_ai_service.py::test_tool_input_validates_task_create -x` | ❌ Wave 0 |
| D-22 | Malformed tool_use input is rejected with error back to AI (not written to DB) | unit | `pytest tests/test_ai_service.py::test_malformed_tool_input_rejected -x` | ❌ Wave 0 |
| D-05 | Conversation messages are persisted to DB with correct role and content_json | unit | `pytest tests/test_ai_repository.py::test_message_persistence -x` | ❌ Wave 0 |

### Sampling Rate
- **Per task commit:** `cd backend && uv run python -m pytest tests/test_ai_service.py -x`
- **Per wave merge:** `cd backend && uv run python -m pytest tests/ && cd ../mobile && flutter test`
- **Phase gate:** Full suite green before `/gsd:verify-work`

### Wave 0 Gaps
- [ ] `backend/tests/test_ai_service.py` — unit tests for AIService tool validation
- [ ] `backend/tests/test_ai_repository.py` — conversation/message persistence tests
- [ ] `backend/tests/test_phase_21_e2e.py` — full intake + interview E2E tests
- [ ] `mobile/test/e2e/phase_21_ai_intake_e2e_test.dart` — Flutter chat UI E2E tests
- [ ] `backend/app/features/ai/` directory structure — does not exist yet
- [ ] `anthropic` package not in `requirements.txt` — must add: `uv add anthropic`
- [ ] Alembic migration `0017_ai_conversations.py` — new tables for conversations, messages, token_usage
- [ ] Drift schema v9 — `AiConversations` table + `onUpgrade if (from < 9)` block

---

## Sources

### Primary (HIGH confidence)
- Official Anthropic streaming docs: https://platform.claude.com/docs/en/api/messages-streaming — SSE event types, tool_use delta format, async stream() usage
- Official Anthropic tool use docs: https://platform.claude.com/docs/en/build-with-claude/tool-use/overview — tool definition format, multi-turn cycle, stop_reason=tool_use
- FastAPI SSE docs: https://fastapi.tiangolo.com/tutorial/server-sent-events/ — EventSourceResponse, ServerSentEvent, keep-alive behavior
- anthropic-sdk-python GitHub: https://github.com/anthropics/anthropic-sdk-python — v0.86.0 (Mar 18, 2026), async stream() context manager, get_final_message()
- Existing codebase: `backend/app/features/projects/schemas.py` — TradeScopeCreate, TaskCreate schema field names verified
- Existing codebase: `web/src/app/api/proxy/route.ts` — current proxy pattern (confirmed buffering issue)
- Existing codebase: `mobile/pubspec.yaml` — confirmed flutter_client_sse not yet in deps; Dio v5.9.2 present

### Secondary (MEDIUM confidence)
- Upstash blog (SSE + LLM in Next.js): https://upstash.com/blog/sse-streaming-llm-responses — verified ReadableStream piping pattern works with Next.js App Router
- flutter_client_sse pub.dev: https://pub.dev/packages/flutter_client_sse — confirms SSE-via-HTTP approach; POST support needs verification

### Tertiary (LOW confidence — flag for validation)
- flutter_client_sse POST method support: pub.dev page reviewed but version changelog not read in full. Verify POST body support before implementation.
- Claude vision image size limits: ~5MB per image stated from Anthropic community sources. Verify exact current limit in official vision docs before implementing image upload handler.

---

## Metadata

**Confidence breakdown:**
- Standard stack: HIGH — anthropic SDK v0.86.0 confirmed; FastAPI EventSourceResponse confirmed in 0.115.x official docs
- Architecture: HIGH — tool_use flow verified against official docs; DB schema derived from existing project patterns
- Pitfalls: HIGH — SSE buffering pitfall observed from codebase inspection (proxy route); tool_use multi-turn requirement from official docs; Drift schema version from codebase inspection
- Flutter SSE: MEDIUM — flutter_client_sse confirmed as standard approach but POST support needs validation

**Research date:** 2026-03-23
**Valid until:** 2026-04-23 (Anthropic SDK moves fast; re-verify model ID "claude-sonnet-4-6" before coding)
