# Architecture: v3.0 AI-Driven Construction Management

**Domain:** AI-driven multi-trade construction project management — adding to existing FastAPI + Flutter + Next.js platform
**Researched:** 2026-03-19
**Confidence:** HIGH (existing codebase inspected directly; Claude API and FastAPI SSE patterns verified via official sources)

---

## System Overview

v3.0 adds five new capability clusters onto the existing infrastructure:

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                     NEW: v3.0 CAPABILITY CLUSTERS                           │
│                                                                             │
│  1. AI Agent Service        2. Real-Time Chat      3. Project Hierarchy     │
│   (Claude API + tools)       (WebSocket/SSE)        (Project→Scope→Task)    │
│                                                                             │
│  4. Photo Annotation        5. Cross-Trade Deps    6. Per-Trade Quotes/Inv  │
│   (Canvas overlay)           (DAG engine)           (extends existing)      │
└─────────────────────────────────────────────────────────────────────────────┘
                                    │
                    ┌───────────────┴────────────────┐
                    ▼                                ▼
┌───────────────────────────┐        ┌───────────────────────────────────────┐
│   FLUTTER MOBILE (v1 base)│        │        NEXT.JS WEB (v2 base)          │
│                           │        │                                       │
│  Online-first + offline   │        │  RSC + TanStack Query + Redux         │
│  cache for field tasks    │        │  GC dashboard + AI intake chat        │
│  Drift cache for tasks    │        │  WebSocket chat client                │
│  WebSocket chat client    │        │  Annotation canvas (Konva.js)         │
│  CustomPainter annotation │        │  AI response streaming (SSE)          │
└─────────────┬─────────────┘        └──────────────────┬────────────────────┘
              │  Bearer token (existing)                 │  httpOnly cookie (existing)
              └──────────────┬───────────────────────────┘
                             │ HTTPS REST + SSE + WebSocket
┌────────────────────────────▼────────────────────────────────────────────────┐
│                    FASTAPI BACKEND (shared, extended)                        │
│                                                                             │
│  EXISTING:                              NEW:                                │
│  ┌────────────────────────┐            ┌──────────────────────────────────┐ │
│  │  Auth / JWT / RLS      │            │  AI Agent Service                │ │
│  │  Jobs / Quotes / Inv   │            │  (Claude API wrapper + tools)    │ │
│  │  Scheduling / GIST     │            ├──────────────────────────────────┤ │
│  │  Sync (delta cursor)   │            │  Project / TradeScope / Task     │ │
│  │  Files / Notifications │            │  (new data model + RLS)         │ │
│  │  OOP: Base* patterns   │            ├──────────────────────────────────┤ │
│  └────────────────────────┘            │  Chat Service + WS Manager       │ │
│                                        │  (ConnectionManager per company) │ │
│                                        ├──────────────────────────────────┤ │
│                                        │  Dependency Engine               │ │
│                                        │  (DAG + topological sort)       │ │
│                                        ├──────────────────────────────────┤ │
│                                        │  Annotation Storage              │ │
│                                        │  (JSON overlay + file ref)      │ │
│                                        └──────────────────────────────────┘ │
│                                                                             │
│  ┌─────────────────────────────────────────────────────────────────────┐   │
│  │           PostgreSQL + RLS (company_id isolation — unchanged)        │   │
│  └─────────────────────────────────────────────────────────────────────┘   │
└─────────────────────────────────────────────────────────────────────────────┘
                    │
         ┌──────────┴──────────┐
         ▼                     ▼
┌─────────────────┐   ┌────────────────────────┐
│  Anthropic      │   │  Redis (new)            │
│  Claude API     │   │  - WS pub/sub           │
│  (tool use +    │   │  - AI session state     │
│   streaming)    │   │  - SSE fanout           │
└─────────────────┘   └────────────────────────┘
```

---

## New Data Model: Project Hierarchy

### Why New Models (Not Extending Job)

The existing `Job` model is a single-trade, single-contractor work unit with a booking calendar slot. A project contains multiple trades with inter-dependencies — a fundamentally different structure. `Job` remains unchanged; projects wrap jobs through a foreign key, preserving backward compatibility.

### Entity Relationship

```
Project (TenantScopedModel — NEW)
  id, company_id, name, description, address, status
  ai_session_id (FK → AISession — tracks intake conversation)
  created_by (FK → User — the GC who initiated)
  ├── TradeScope (TenantScopedModel — NEW) [one-to-many]
  │   id, project_id, trade_type, status, ai_interview_session_id
  │   assigned_contractor_id (FK → User), job_id (FK → Job — nullable)
  │   quote_id (FK → Quote — per-trade, nullable)
  │   invoice_id (FK → Invoice — per-trade, nullable)
  │   ├── Task (TenantScopedModel — NEW) [one-to-many]
  │   │   id, trade_scope_id, title, description, status
  │   │   scheduled_date, estimated_hours, materials_needed (JSONB array)
  │   │   sort_order (for checklist ordering)
  │   │   dependencies (JSONB adjacency list: [task_id, ...])
  │   │   ├── TaskNote (TenantScopedModel — NEW) [one-to-many]
  │   │   │   id, task_id, author_id, body, created_at
  │   │   └── TaskAttachment (TenantScopedModel — NEW) [one-to-many]
  │   │       id, task_id, attachment_type (photo/pdf/drawing/annotation)
  │   │       remote_url, annotation_data (JSONB — overlay vectors), caption
  │   └── TradeDependency (NEW — junction table) [many-to-many via edges]
  │       from_scope_id, to_scope_id, dependency_type (finish_to_start, etc.)
  └── ChatRoom (TenantScopedModel — NEW) [one-to-one with Project]
      id, project_id, created_at
      └── ChatMessage (TenantScopedModel — NEW) [one-to-many]
          id, room_id, sender_id, body, attachment_url, attachment_type
          message_type (text/photo/file/system), created_at, read_at

AISession (BaseEntityModel — NEW, NOT tenant-scoped per user)
  id, session_type (project_intake/contractor_interview/schedule_adapt)
  entity_id (FK to Project or TradeScope — polymorphic via type field)
  entity_type (project/trade_scope)
  company_id (for RLS manually), messages (JSONB — conversation history)
  status (active/complete/error), created_at, updated_at
```

### Dependency Graph Storage

Cross-trade dependencies are stored as an edge table (`TradeDependency`) using an adjacency list pattern. Within a trade scope, task-level dependencies are stored as a JSONB array of prerequisite task IDs on the `Task` model. This avoids a separate task-dependency junction table while keeping queries simple for the task counts typical in construction (5-30 tasks per trade scope).

PostgreSQL recursive CTEs traverse the dependency graph for topological sort at schedule-generation time. Cycle detection runs before any edge insert.

---

## Component Boundaries

### Backend: New Services (all follow OOP base pattern)

| Component | Inherits From | Responsibility |
|-----------|--------------|----------------|
| `ProjectService` | `TenantScopedService[Project]` | CRUD for projects; triggers AI intake; aggregates trade status |
| `TradeScopeService` | `TenantScopedService[TradeScope]` | Trade scope CRUD; links jobs/quotes/invoices to trade |
| `TaskService` | `TenantScopedService[Task]` | Task CRUD; daily checklist queries; progress tracking |
| `AIAgentService` | `BaseService[AISession]` | Wraps Anthropic SDK; manages conversation history; executes tool calls |
| `DependencyEngineService` | `TenantScopedService[TradeDependency]` | DAG operations: add edge, cycle detection, topological sort, conflict detection |
| `ChatService` | `TenantScopedService[ChatMessage]` | Persist messages; resolve media URLs; query history |
| `WebSocketManager` | Not a service (singleton) | In-process connection registry; broadcast to room; integrates with Redis pub/sub for multi-worker |
| `AnnotationService` | `TenantScopedService[TaskAttachment]` | Store annotation JSON overlay; serve base image + overlay separately |

### Backend: Modified Components

| Component | Change | Risk |
|-----------|--------|------|
| `SyncService` | Add delta-sync methods for `Task`, `TaskNote`, `TaskAttachment`, `ChatMessage` — same cursor pattern | LOW — additive |
| `NotificationService` | Add notification types: `task_assigned`, `checklist_ready`, `chat_message`, `task_approved`, `task_rejected` | LOW — additive |
| `QuoteService` / `InvoiceService` | Add `trade_scope_id` FK column (nullable, backward-compatible) | LOW — additive field |
| `config.py` (Settings) | Add `anthropic_api_key: str` field (no default — crash on missing) | LOW |

### Mobile: New Drift Tables

```
projects_table         — Project records (cached for offline read)
trade_scopes_table     — TradeScope per project
tasks_table            — Task/checklist items (primary offline entity)
task_notes_table       — Notes added by contractor in field
task_attachments_table — Photo/drawing refs (URL + local cache path)
chat_messages_table    — Chat history (cached, scrollback)
```

Mobile maintains the existing outbox queue for task mutations (status updates, notes, photos). New tasks are read-only from sync; contractors cannot create tasks offline — AI generates them server-side.

### Mobile: Architecture Shift (Online-First)

The v1 outbox-queue pattern remains for task progress mutations (status, notes, photos) because contractors work in basements and job sites with poor connectivity. However:

- Project/AI intake is **online-only** (no queue, fail with UI error)
- Chat is **online-only with local cache** (messages cached in Drift, new sends require connectivity)
- Daily checklist sync is **pull-on-connect** with aggressive Drift caching for offline read

This is a hybrid: online-first for AI/chat, offline-capable for field execution.

---

## Data Flow: AI Project Intake

```
GC opens "New Project" on web or mobile
    │
    v
POST /api/v1/projects/intake/start
  ProjectService.create_intake_session()
    → creates Project(status='intake') + AISession(type='project_intake')
    → returns {project_id, session_id}
    │
    v
GC types project description in chat UI
    │
    v
POST /api/v1/projects/{id}/intake/message
  body: {session_id, message}
    │
    v
AIAgentService.process_intake_message()
  1. Load AISession.messages (conversation history from JSONB)
  2. Call Anthropic API with tool definitions:
       - create_trade_scope(trade_type, description, estimated_duration)
       - set_trade_dependency(from_trade, to_trade, dependency_type)
       - finalize_project_plan(summary)
  3. Receive streaming response (SSE back to client — text_delta events)
  4. If tool_use block in response:
       - Execute tool (create DB records, set dependencies)
       - Append tool_result to conversation history
       - Loop back to Anthropic API (agentic loop, max 10 turns)
  5. Persist updated messages JSONB to AISession
    │
    v
SSE stream returns text chunks to client as they arrive
(EventSourceResponse from sse-starlette library)
    │
    v
Project status transitions: 'intake' → 'planning' → 'active' (after contractor interviews)
```

## Data Flow: AI Contractor Interview (Trade Scope Planning)

```
GC assigns contractor to TradeScope → triggers interview
    │
    v
POST /api/v1/trade-scopes/{id}/interview/start
  AIAgentService.start_contractor_interview()
    → creates AISession(type='contractor_interview', entity_id=trade_scope_id)
    → sends FCM push to contractor: "AI needs your input"
    │
    v
Contractor opens interview on mobile (online required)
    │
    v
POST /api/v1/trade-scopes/{id}/interview/message
  AIAgentService.process_interview_message()
    Tools available:
       - create_task(title, description, estimated_hours, materials, sort_order)
       - add_task_dependency(task_id, depends_on_task_id)
       - set_photo_requirement(task_id, photo_type, required)
       - finalize_trade_plan()
    → Agentic loop creates Task records directly
    → Returns streaming SSE to mobile
    │
    v
Interview complete → TradeScope.status = 'planned'
  → FCM to GC: "{contractor} has finalized {trade} plan — {N} tasks created"
  → GC reviews task list before activating
```

## Data Flow: Real-Time Chat

```
GC or Contractor opens chat for a project
    │
    v
WebSocket connect: WS /api/v1/chat/rooms/{room_id}/ws
  Auth: JWT from query param (WS cannot send headers)
  WebSocketManager.connect(websocket, room_id, user_id)
    │
    v
Message sent (text or photo-url reference):
  Client sends JSON: {type: "message", body: "...", attachment_url: "..."}
    │
    v
WebSocketManager receives → ChatService.create_message()
  → INSERT ChatMessage → flush → get ID
  → WebSocketManager.broadcast_to_room(room_id, message_payload)
    → For each connected WS in room: ws.send_json(payload)
    → Redis PUBLISH to room channel (for other workers)
    │
    v
All connected clients receive message in <100ms
    │
    v
Offline clients: on reconnect, GET /api/v1/chat/rooms/{id}/messages?since={cursor}
  → Drift cache updated → UI shows full history
```

### WebSocket Authentication

Standard HTTP headers are unavailable during the WebSocket handshake from mobile clients. The JWT is passed as a query parameter (`?token=...`) and validated immediately after `websocket.accept()`. If validation fails, the connection is closed with code 4001 (unauthorized). This is a standard WebSocket auth pattern — the token is in the TLS-encrypted URL, not a security risk.

```python
# Pattern for WS auth
@router.websocket("/chat/rooms/{room_id}/ws")
async def websocket_chat(
    websocket: WebSocket,
    room_id: uuid.UUID,
    token: str,  # from query param
    db: AsyncSession = Depends(get_db),
):
    payload = decode_token(token)
    if payload is None:
        await websocket.close(code=4001)
        return
    await websocket.accept()
    ...
```

## Data Flow: Task Progress (Field Execution)

```
Contractor opens daily checklist (offline-capable via Drift cache)
    │
    v
Contractor checks off task / adds note / takes photo
  → Drift local write (immediate)
  → Outbox queue entry: {operation: task_status_update, payload: {...}}
    │
    v
On connectivity: SyncEngine drains outbox
  → PATCH /api/v1/tasks/{id}/progress
    {status, note, attachment_ids}
  → TaskService.update_progress()
    → Updates Task.status, creates TaskNote, links TaskAttachment
    → Evaluates dependency graph: are any tasks now unblocked?
    → Sends FCM to GC if task requires inspection
    │
    v
GC receives inspection request on mobile or web
  → GET /api/v1/tasks/{id} → full task with attachments + annotations
  → GC: approve / reject / flag as punch list item
  → PATCH /api/v1/tasks/{id}/inspection
    → FCM to contractor with decision
```

## Data Flow: Photo Annotation

```
GC or contractor views photo on mobile or web
    │
    v
Image loaded from remote_url (existing /files/ static mount)
    │
    v
User draws annotation (arrows, circles, text, measurements):
  Mobile: Flutter CustomPainter with GestureDetector
    → Strokes accumulated as List<DrawingStroke> in-memory
  Web: Konva.js canvas overlay on <img>
    → Stage JSON serialized in-memory
    │
    v
User taps "Save annotation":
  POST /api/v1/files/annotations/{attachment_id}
  body: {annotation_data: <JSON vector format>}
    → AnnotationService.save()
      → UPDATE TaskAttachment SET annotation_data = :json_data
      → Existing remote_url unchanged (base image never modified)
    │
    v
On next load: GET /api/v1/tasks/{id}/attachments
  Returns attachment with annotation_data field populated
  Client renders base image → overlays annotation vectors on top
  (Non-destructive: base photo preserved, annotations re-rendered client-side)
```

**Annotation JSON format** (stored in `TaskAttachment.annotation_data`):

```json
{
  "version": 1,
  "canvas_width": 1920,
  "canvas_height": 1080,
  "strokes": [
    {"type": "arrow", "x1": 100, "y1": 200, "x2": 300, "y2": 400, "color": "#FF0000", "width": 3},
    {"type": "circle", "cx": 500, "cy": 300, "r": 50, "color": "#FF0000", "width": 2},
    {"type": "text", "x": 150, "y": 180, "content": "Fix this joint", "color": "#FF0000", "fontSize": 16},
    {"type": "measurement", "x1": 100, "y1": 100, "x2": 400, "y2": 100, "label": "2.4m"}
  ]
}
```

Both Flutter and web render the same JSON — Flutter uses `CustomPainter`, web uses Konva.js.

---

## AI Agent Service: Integration with Existing OOP Pattern

```python
# backend/app/features/ai/service.py

class AIAgentService(BaseService[AISession]):
    """Claude API wrapper following OOP base pattern.

    Does NOT inherit TenantScopedService — AISession has company_id
    stored as a plain column, not via RLS policy, because the session
    spans multiple DB operations and needs to be queryable by session_id
    without RLS context set in some background task contexts.
    """
    repository_class = AISessionRepository

    # Tool definitions (sent to Claude API on every call)
    PROJECT_INTAKE_TOOLS: ClassVar[list[dict]] = [
        {
            "name": "create_trade_scope",
            "description": "Create a trade scope within the project being planned",
            "input_schema": {
                "type": "object",
                "properties": {
                    "trade_type": {"type": "string", "enum": ["plumbing", "electrical", "carpentry", ...]},
                    "description": {"type": "string"},
                    "estimated_days": {"type": "integer"},
                },
                "required": ["trade_type", "description", "estimated_days"]
            }
        },
        {
            "name": "set_trade_dependency",
            "description": "Declare that one trade must complete before another starts",
            "input_schema": {
                "type": "object",
                "properties": {
                    "predecessor_trade": {"type": "string"},
                    "successor_trade": {"type": "string"},
                    "dependency_type": {"type": "string", "enum": ["finish_to_start"]}
                },
                "required": ["predecessor_trade", "successor_trade", "dependency_type"]
            }
        },
        {
            "name": "finalize_project_plan",
            "description": "Mark the project planning intake as complete",
            "input_schema": {"type": "object", "properties": {"summary": {"type": "string"}}}
        }
    ]

    async def process_message_streaming(
        self,
        session_id: uuid.UUID,
        user_message: str,
        tools: list[dict],
    ) -> AsyncGenerator[str, None]:
        """Process one turn of conversation, yielding SSE-compatible chunks.

        Implements the Claude tool-use agentic loop:
        1. Append user message to history
        2. Call Anthropic API with streaming
        3. Yield text_delta chunks as SSE events
        4. If tool_use block: execute tool, append tool_result, loop (max 10)
        5. Persist updated history to AISession.messages JSONB
        """
        session = await self.repository.get_by_id(session_id)
        messages = session.messages  # list from JSONB
        messages.append({"role": "user", "content": user_message})

        turn = 0
        while turn < 10:
            turn += 1
            async with anthropic_client.messages.stream(
                model="claude-opus-4-5",
                max_tokens=4096,
                tools=tools,
                messages=messages,
            ) as stream:
                tool_calls = []
                async for event in stream:
                    if event.type == "content_block_delta" and event.delta.type == "text_delta":
                        yield f"data: {json.dumps({'type': 'text', 'chunk': event.delta.text})}\n\n"
                    elif event.type == "content_block_stop" and hasattr(event, "content_block"):
                        if event.content_block.type == "tool_use":
                            tool_calls.append(event.content_block)

                final_message = await stream.get_final_message()
                messages.append({"role": "assistant", "content": final_message.content})

                if not tool_calls or final_message.stop_reason == "end_turn":
                    break

                # Execute tools and append results
                tool_results = []
                for tool_call in tool_calls:
                    result = await self._execute_tool(tool_call.name, tool_call.input)
                    tool_results.append({
                        "type": "tool_result",
                        "tool_use_id": tool_call.id,
                        "content": json.dumps(result),
                    })
                messages.append({"role": "user", "content": tool_results})

        # Persist conversation history
        await self.repository.update(session_id, {"messages": messages, "status": "complete"})
        yield f"data: {json.dumps({'type': 'done'})}\n\n"
```

---

## Dependency Engine

### Storage

Cross-trade dependencies: `trade_dependencies` table (adjacency list):
```sql
CREATE TABLE trade_dependencies (
    from_scope_id UUID NOT NULL REFERENCES trade_scopes(id),
    to_scope_id   UUID NOT NULL REFERENCES trade_scopes(id),
    dependency_type TEXT NOT NULL DEFAULT 'finish_to_start',
    PRIMARY KEY (from_scope_id, to_scope_id)
);
```

Task-level dependencies: `tasks.dependencies` JSONB array of prerequisite task IDs.

### Cycle Detection

```python
async def add_trade_dependency(self, from_id: UUID, to_id: UUID) -> None:
    """Add edge with cycle detection using DFS reachability check.
    Raises 409 if adding this edge would create a cycle.
    """
    # Check if to_id can reach from_id (would create cycle)
    if await self._can_reach(to_id, from_id):
        raise HTTPException(409, "Dependency would create a circular dependency")
    await self.repository.create_edge(from_id, to_id)

async def _can_reach(self, source: UUID, target: UUID) -> bool:
    """BFS reachability using recursive CTE in PostgreSQL."""
    result = await self.db.execute(
        text("""
        WITH RECURSIVE reachable AS (
            SELECT to_scope_id AS id FROM trade_dependencies WHERE from_scope_id = :source
            UNION
            SELECT td.to_scope_id FROM trade_dependencies td
            JOIN reachable r ON td.from_scope_id = r.id
        )
        SELECT EXISTS(SELECT 1 FROM reachable WHERE id = :target)
        """),
        {"source": source, "target": target}
    )
    return result.scalar()
```

### Schedule Conflict Detection

When a task's status changes to `complete`, the dependency engine checks which successor tasks are now unblocked and notifies the relevant contractors. When a task is delayed, the engine recalculates projected completion dates for all successor tasks using topological sort + estimated hours.

---

## WebSocket Manager: Multi-Worker Architecture

The `WebSocketManager` is an in-process singleton per worker. For single-worker development, direct broadcast suffices. For production (multiple Uvicorn workers), Redis pub/sub fans out messages across workers.

```python
# backend/app/features/chat/websocket_manager.py

class WebSocketManager:
    """In-process WebSocket connection registry with Redis fanout.

    Connections are keyed by room_id. Each room maps to a set of
    active WebSocket connections in the current process. Redis pub/sub
    broadcasts to all processes.
    """
    def __init__(self, redis_url: str):
        self._rooms: dict[str, set[WebSocket]] = defaultdict(set)
        self._redis_url = redis_url

    async def connect(self, ws: WebSocket, room_id: str, user_id: str):
        await ws.accept()
        self._rooms[room_id].add(ws)

    async def disconnect(self, ws: WebSocket, room_id: str):
        self._rooms[room_id].discard(ws)

    async def broadcast(self, room_id: str, payload: dict):
        """Broadcast to local connections AND publish to Redis for other workers."""
        message_json = json.dumps(payload)
        # Local fanout
        dead = set()
        for ws in self._rooms.get(room_id, set()):
            try:
                await ws.send_text(message_json)
            except Exception:
                dead.add(ws)
        self._rooms[room_id] -= dead
        # Redis fanout for other workers
        await self._redis.publish(f"chat:{room_id}", message_json)
```

Redis is already referenced in `config.py` (`redis_url` field) — it was added for slowapi rate limiting. The same Redis instance handles pub/sub, requiring no new infrastructure dependency.

---

## Mobile Architecture Changes

### Online-First Shift

```
v1 Architecture:        v3 Architecture:
─────────────────       ─────────────────────────────────────────
All actions → Outbox
Outbox → API            AI/Chat → Direct API (fail if offline)
                        Task progress → Outbox (unchanged)
                        Daily checklist → Drift cache (read offline)
                        Projects/Scopes → Drift cache (read offline)
```

### New Drift Tables

The 19 existing Drift tables gain 6 more: `projects`, `trade_scopes`, `tasks`, `task_notes`, `task_attachments`, `chat_messages`. The `sync` module gains corresponding `SyncHandler` subclasses for each entity, following the existing `SyncRegistry` pattern.

### Chat Client (Flutter)

Uses `web_socket_channel` package (already common in Flutter ecosystem). The chat screen maintains a `WebSocketChannel` connection while visible. On background: channel closed, messages cached in Drift. On foreground return: reconnect + fetch missed messages via REST cursor.

```dart
// Pattern for Flutter WebSocket chat
class ChatNotifier extends AsyncNotifier<List<ChatMessage>> {
  WebSocketChannel? _channel;

  Future<void> connect(String roomId, String token) async {
    _channel = WebSocketChannel.connect(
      Uri.parse('wss://api/api/v1/chat/rooms/$roomId/ws?token=$token'),
    );
    _channel!.stream.listen(
      (data) => _handleMessage(jsonDecode(data)),
      onDone: () => _scheduleReconnect(),
      onError: (e) => _scheduleReconnect(),
    );
  }
}
```

### Photo Annotation (Flutter)

Uses `CustomPainter` with `GestureDetector` over the image widget. Strokes are accumulated in provider state and serialized to the JSON format defined above on save. No third-party annotation library needed — the stroke model is simple (arrow, circle, text, measurement).

```dart
class AnnotationPainter extends CustomPainter {
  final List<DrawingStroke> strokes;
  // Renders each stroke type with Canvas API methods
  // drawLine, drawCircle, drawPath (for arrows), drawParagraph (for text)
}
```

---

## Web Architecture Changes (Next.js)

### New Pages Required

| Route | Type | Purpose |
|-------|------|---------|
| `/projects` | SSR → Client | Project list (GC view) |
| `/projects/[id]` | SSR → Client | Project detail: trade status, timeline, alerts |
| `/projects/[id]/intake` | CSR (Client only) | AI intake chat — streaming SSE, no SSR value |
| `/projects/[id]/trades/[tradeId]` | SSR → Client | Trade scope detail + task list |
| `/projects/[id]/chat` | CSR | Real-time chat room |
| `/projects/[id]/inspection` | CSR | GC task inspection flow |

### AI Streaming in Next.js

The intake chat page streams SSE from FastAPI via the existing `/api/proxy/*` Route Handler pattern. `EventSource` in the browser connects to the Next.js proxy, which forwards the stream from FastAPI. This keeps the auth cookie pattern intact — the browser never calls FastAPI directly.

```typescript
// In intake chat Client Component
const eventSource = new EventSource('/api/proxy/projects/{id}/intake/message', {
  // EventSource with POST requires fetch-based SSE (eventsource-parser)
  // or the Next.js Route Handler does the POST and returns a ReadableStream
});
```

**Note:** `EventSource` is GET-only. For POST-initiated SSE (needed for intake chat), the Next.js Route Handler accepts the POST and returns a `ReadableStream` piped from FastAPI's SSE response. The browser uses `fetch()` with `ReadableStream` processing, not `EventSource`. This is a known pattern for SSE with POST bodies.

### Photo Annotation (Web)

Uses **Konva.js** (React-Konva package) — a canvas-based 2D library. The annotation canvas renders as a Konva stage layered over the base image. Strokes are added to a Konva layer, serialized to the same JSON format as Flutter, and saved via the annotation API. Dynamic import with `ssr: false` (Konva requires browser canvas API).

---

## New vs Extended: Component Summary

### New Backend Components

| Component | Path | Status |
|-----------|------|--------|
| `ProjectService` | `app/features/projects/service.py` | New |
| `TradeScopeService` | `app/features/projects/trade_service.py` | New |
| `TaskService` | `app/features/projects/task_service.py` | New |
| `AIAgentService` | `app/features/ai/service.py` | New |
| `AISessionRepository` | `app/features/ai/repository.py` | New |
| `DependencyEngineService` | `app/features/projects/dependency_service.py` | New |
| `ChatService` | `app/features/chat/service.py` | New |
| `WebSocketManager` | `app/features/chat/websocket_manager.py` | New (singleton) |
| `AnnotationService` | `app/features/files/annotation_service.py` | New (extends files feature) |
| Project/TradeScope/Task models | `app/features/projects/models.py` | New |
| AISession model | `app/features/ai/models.py` | New |
| ChatRoom / ChatMessage models | `app/features/chat/models.py` | New |

### Modified Backend Components

| Component | What Changes | Risk |
|-----------|-------------|------|
| `SyncService` | Add 6 new `get_{entity}_since()` methods | LOW |
| `Quote` / `Invoice` models | Add nullable `trade_scope_id` FK | LOW |
| `NotificationService` | Add 5 new notification types | LOW |
| `config.py` (Settings) | Add `anthropic_api_key` field | LOW |
| `main.py` | Mount new routers (projects, ai, chat) | LOW |

### New Mobile Components

| Component | Type | Status |
|-----------|------|--------|
| 6 new Drift tables | Database schema | New (Drift migration v7) |
| `ChatNotifier` + `ChatRepository` | Riverpod + Drift | New |
| `AnnotationPainter` + `AnnotationNotifier` | Flutter + Riverpod | New |
| `TaskChecklistScreen` | Flutter screen | New |
| `ProjectDetailScreen` | Flutter screen | New |
| `InspectionScreen` (GC) | Flutter screen | New |
| Sync handlers for 6 entities | `SyncRegistry` additions | New |

### New Web Components

| Component | Path | Status |
|-----------|------|--------|
| Projects feature | `web/src/features/projects/` | New |
| AI intake chat | `web/src/features/projects/intake-chat.tsx` | New |
| Chat room | `web/src/features/chat/` | New |
| Annotation canvas | `web/src/features/annotation/` (Konva.js) | New |
| GC monitoring dashboard | `web/src/features/projects/monitoring-dashboard.tsx` | New |

---

## Build Order (Dependency-Constrained)

The key constraint is that AI services, chat, and the dependency engine all depend on the `Project → TradeScope → Task` data model. That model must ship first.

```
Phase 1: Project Data Model (no dependencies — pure DB + API)
  - DB migrations: projects, trade_scopes, tasks, task_notes, task_attachments
  - Models + Repositories + Services (ProjectService, TradeScopeService, TaskService)
  - REST CRUD endpoints (no AI yet)
  - Mobile: 6 new Drift tables + sync handlers
  - Web: projects list + detail pages (static data, no AI)
  Deliverable: GCs can manually create projects and trade scopes

Phase 2: Dependency Engine (depends on Phase 1 — needs task/scope IDs)
  - TradeDependency edge table + DependencyEngineService
  - Cycle detection + topological sort
  - Cross-trade conflict detection
  - API: add/remove dependencies, get ordered schedule
  Deliverable: GCs can define trade sequencing rules

Phase 3: AI Agent Service (depends on Phase 1 — needs entity IDs to write to)
  - AISession model + AIAgentService
  - Claude API integration with streaming SSE
  - Project intake tools (create_trade_scope, set_dependency, finalize)
  - Web: AI intake chat UI (streaming SSE rendering)
  - Mobile: AI contractor interview chat UI (streaming SSE)
  Deliverable: AI-driven project planning end-to-end

Phase 4: Real-Time Chat (depends on Phase 1 — needs project/room IDs)
  - ChatRoom + ChatMessage models
  - ChatService + WebSocketManager
  - Redis pub/sub for multi-worker fanout
  - Mobile: WebSocket chat client + Drift cache
  - Web: Chat room UI
  Deliverable: Bidirectional GC ↔ contractor chat

Phase 5: Photo Annotation (depends on Phase 1 — TaskAttachment.annotation_data)
  - AnnotationService (save/load JSON overlay)
  - Mobile: CustomPainter annotation canvas
  - Web: Konva.js annotation canvas
  Deliverable: Annotated photos on tasks

Phase 6: GC Inspection Flow (depends on Phases 3, 5 — needs tasks + annotations)
  - Task inspection endpoints (approve/reject/flag)
  - Punch list model
  - Mobile: InspectionScreen (GC)
  - Web: Inspection review UI
  - FCM: inspection request + decision notifications
  Deliverable: GC can inspect and approve contractor work

Phase 7: Per-Trade Quotes and Invoices (depends on Phase 1 — needs trade_scope_id)
  - Add trade_scope_id FK to Quote and Invoice (additive migration)
  - QuoteService + InvoiceService extensions
  - Web: per-trade quoting UI + project-level aggregation view
  Deliverable: Full financial lifecycle per trade

Phase 8: AI Schedule Adaptation (depends on Phases 2, 3 — needs DAG + AI)
  - AIAgentService: schedule_adapt session type
  - Delay detection + dependency recalculation
  - AI-generated rescheduling recommendations
  - Web: AI alerts panel on GC dashboard
  Deliverable: Proactive schedule management
```

---

## Scalability Considerations

| Concern | At 10 companies | At 100 companies | At 1000+ companies |
|---------|-----------------|------------------|--------------------|
| AI API costs | Negligible | ~$500/mo estimate | Need caching of identical project types |
| AI response latency | SSE streaming hides latency (first token < 1s) | Same | Same |
| WebSocket connections | In-process dict sufficient | Redis pub/sub required (already in build order) | Redis Cluster or dedicated WS service |
| Conversation history JSONB | 50KB per session, fine | Fine | Archive old sessions to cold storage |
| Dependency graph queries | Recursive CTE fast for <50 nodes | Fast | Fast — construction projects have bounded graph size |
| Chat message history | Drift cache on mobile, paginated on web | Index on room_id + created_at | Partition chat_messages table by created_at |
| Photo storage | Local filesystem (current pattern) | S3/GCS with CDN required | S3/GCS (plan migration in Phase 5) |

---

## Critical Architecture Decisions

| Decision | Recommendation | Rationale |
|----------|---------------|-----------|
| AI conversation history storage | JSONB on AISession model | Simple, no extra table, query by session_id; messages array is append-only; 50-200 turns max for construction intake |
| Task dependency storage | JSONB array on Task for task-level; edge table for trade-level | Task dependencies are bounded (3-10 per task); trade dependencies benefit from join queries |
| WebSocket auth | JWT in query param, validated on accept() | Standard WS pattern; TLS encrypts the URL; no alternative for mobile WS clients |
| AI model choice | claude-opus-4-5 for intake/interview; claude-haiku-3-5 for daily checklist generation | Intake/interview require reasoning; checklist is structured template work |
| Annotation storage | JSON vectors in DB, base image unchanged | Non-destructive; annotations re-renderable client-side; base photo never reprocessed |
| Online vs offline | Online-first for AI/chat; offline-capable for task execution | AI requires API connectivity; field contractors need offline checklists |
| Chat message delivery | WebSocket primary, REST fallback for history | WS for real-time; REST for scrollback and offline sync |
| SSE for AI streaming | `sse-starlette` + `EventSourceResponse` | Standard FastAPI SSE pattern; works with existing auth proxy |

---

## Anti-Patterns to Avoid

### Anti-Pattern 1: Storing Conversation History in a Separate Messages Table

**What people do:** Create a `ai_messages` table with one row per message, join on session_id to reconstruct history.

**Why wrong:** The Anthropic API requires the full conversation history as a messages array on every call. Reconstructing from a SQL join on every AI turn adds latency. The messages structure also contains mixed content types (text, tool_use, tool_result blocks) that map poorly to flat SQL columns.

**Do instead:** JSONB array on `AISession.messages`. Append-only, loaded in one query. Archive sessions older than 90 days to cold storage if storage becomes a concern.

### Anti-Pattern 2: Blocking HTTP Response Until AI Completes

**What people do:** `response = await anthropic_client.messages.create(...)` — wait for full response, return JSON.

**Why wrong:** Claude intake sessions take 10-60 seconds for complex projects with multiple tool calls. HTTP request times out. Users see a loading spinner with no feedback.

**Do instead:** SSE streaming via `EventSourceResponse`. First token arrives in <1 second. Users see Claude typing in real time. The agentic loop (tool calls) is transparent — yield text between tool executions.

### Anti-Pattern 3: Single WebSocket Connection Manager for All Tenants

**What people do:** `manager._rooms` is a flat dict keyed by `room_id` without tenant isolation.

**Why wrong:** In a multi-tenant system, room_id UUIDs are globally unique (PostgreSQL gen_random_uuid()), so collisions are impossible. BUT: the manager should still validate on connect that the user belongs to the company that owns the room. Skipping this check allows any authenticated user to join any room by guessing its UUID.

**Do instead:** On WebSocket connect, query `ChatRoom.company_id` and verify it matches the JWT's `company_id` claim before calling `websocket.accept()`.

### Anti-Pattern 4: Making Annotation Storage Destructive

**What people do:** Apply annotation vectors to the image file (Pillow, ImageMagick), overwrite the stored image with the annotated version.

**Why wrong:** Annotations need to be editable and clearable. Once baked into the pixel data, the original is lost. Different viewers may want to show or hide annotations.

**Do instead:** Store annotation JSON separately in `TaskAttachment.annotation_data`. Base image at `remote_url` is immutable. Client renders the overlay. Clearing annotations is a simple null-write to the JSONB column.

### Anti-Pattern 5: Running the Agentic Loop Without Turn Limits

**What people do:** `while True:` loop calling Anthropic API until `stop_reason == "end_turn"`.

**Why wrong:** A runaway tool-calling loop can exhaust API credits and hang the request indefinitely. Claude may enter loops when tools return unexpected output.

**Do instead:** Hard limit of 10 turns per request (`turn < 10`). If reached, yield an error event and persist session state so the user can continue in a new request.

---

## Sources

- Existing codebase: `backend/app/core/base_service.py`, `base_repository.py`, `base_models.py` — HIGH confidence (direct inspection)
- Existing codebase: `backend/app/features/sync/service.py` — HIGH confidence (direct inspection; delta sync pattern reused for new entities)
- Existing codebase: `backend/app/features/files/router.py` — HIGH confidence (direct inspection; annotation storage extends existing attachment pattern)
- Existing codebase: `backend/app/core/config.py` — HIGH confidence (ANTHROPIC_API_KEY slot identified)
- [Anthropic Claude API: Tool Use Implementation](https://platform.claude.com/docs/en/agents-and-tools/tool-use/implement-tool-use) — HIGH confidence (official Anthropic docs)
- [Anthropic: Fine-Grained Tool Streaming](https://docs.claude.com/en/docs/agents-and-tools/tool-use/fine-grained-tool-streaming) — HIGH confidence (official Anthropic docs)
- [FastAPI: Server-Sent Events](https://fastapi.tiangolo.com/tutorial/server-sent-events/) — HIGH confidence (official FastAPI docs)
- [FastAPI: WebSockets](https://fastapi.tiangolo.com/advanced/websockets/) — HIGH confidence (official FastAPI docs)
- [sse-starlette PyPI](https://pypi.org/project/sse-starlette/) — MEDIUM confidence (library widely used in FastAPI SSE ecosystem)
- [PostgreSQL Recursive CTEs for Graph Algorithms](https://www.fusionbox.com/blog/detail/graph-algorithms-in-a-database-recursive-ctes-and-topological-sort-with-postgres/620/) — MEDIUM confidence (established PostgreSQL pattern)
- [WebSocket/SSE Multi-Worker Architecture](https://blog.greeden.me/en/2025/10/28/weaponizing-real-time-websocket-sse-notifications-with-fastapi-connection-management-rooms-reconnection-scale-out-and-observability/) — MEDIUM confidence (2025 production guide, patterns match FastAPI docs)

---

*Architecture research for: ContractorHub v3.0 — AI-Driven Construction Management*
*Researched: 2026-03-19*
