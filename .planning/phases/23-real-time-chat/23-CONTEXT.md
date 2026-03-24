# Phase 23: Real-Time Chat - Context

**Gathered:** 2026-03-24
**Status:** Ready for planning
**Research:** Connecteam app patterns studied — adopted best practices, offline sync is key differentiator

<domain>
## Phase Boundary

GCs and contractors exchange messages, photos, and files in real time within project-scoped trade threads via WebSocket, with push notifications (FCM) for offline delivery. Two thread types: per-trade-scope (GC ↔ contractor) and project-wide (all contractors + GC). Read receipts, @mentions with forced push, typing indicators, and offline message queuing with sync-on-reconnect. Annotated photos from Phase 22 can be shared in chat. Both mobile (Flutter) and web (Next.js) connect to the same WebSocket endpoint.

</domain>

<decisions>
## Implementation Decisions

### Transport Protocol
- **D-01:** WebSocket for real-time delivery — FastAPI/Starlette native WebSocket support. Bidirectional, sub-second delivery. Both mobile and web connect to the same `ws://api/v1/chat` endpoint with JWT authentication
- **D-02:** Typing indicator only — show "..." when the other party is typing. No online/offline presence status. Field workers don't need to know who's "online"
- **D-03:** Same WebSocket for mobile and web — single backend implementation. Browser WebSocket API is native. Flutter uses `web_socket_channel` package

### Chat Thread Structure
- **D-04:** Per trade scope + project-wide — two thread types: (1) trade scope thread (GC + assigned contractor, auto-created when contractor is assigned), (2) project-wide group chat (all contractors on project + GC for cross-trade coordination)
- **D-05:** Read receipts — show who has read each message with timestamp. GCs need this for accountability (e.g., confirming contractor saw schedule change or safety alert). Inspired by Connecteam's read receipt feature
- **D-06:** @mentions with forced push — @mention a user or @all to force push notification even if thread is muted. Critical for safety alerts and urgent schedule changes on job sites
- **D-07:** Announcement channels deferred — one-way broadcast channels (Connecteam's "Channels" feature) deferred to a future phase. Project-wide group chat covers basic broadcast needs for now
- **D-08:** Server timestamp ordering — server assigns monotonic sequence number per thread on receive. Client displays by server sequence. Dedup by message UUID. Server is single source of truth
- **D-09:** Project-wide chat includes all contractors + GC — every contractor assigned to any trade scope on the project auto-joins the project-wide chat. Enables cross-trade coordination

### File Sharing in Chat
- **D-10:** Photos + PDFs + annotated photos — share photos (inline preview), PDFs (filename + icon), and annotated photos from Phase 22. Reuse existing task attachment upload pattern. No video or GIF — keep it professional for construction
- **D-11:** Share annotated photos from task execution — contractor can share a task's annotated photo into the trade scope chat. GC sees photo + annotation overlay rendered from JSON. Powerful for discussing issues ("see the crack I circled")

### Offline & Sync Behavior
- **D-12:** Queue messages + sync on reconnect — messages typed offline are queued locally in Drift. When connection restores, queue drains in order. Incoming messages sync from server (fetch missed messages since last seen sequence). Consistent with existing sync engine pattern. THIS IS THE KEY DIFFERENTIATOR vs Connecteam (which has NO offline mode)
- **D-13:** Last 100 messages per thread synced locally — sync most recent 100 messages per thread to Drift on login. Paginate older history from server on scroll-up. Balances storage with accessibility
- **D-14:** FCM preview text + sender name — "John D. (Plumbing): Can you check the valve clearance?" Shows sender, trade scope context, and message preview. Tapping opens specific thread. @mention notifications override mute settings

### Claude's Discretion
- WebSocket connection lifecycle (heartbeat interval, reconnect backoff strategy)
- Chat message DB schema design (tables, indexes, RLS policies)
- Message pagination strategy (cursor-based vs offset)
- Chat UI layout and styling (follows existing app design patterns from Phase 22 UI-SPEC)
- File upload endpoint for chat attachments (reuse or separate from task attachments)
- Mute/notification settings per thread
- Message search implementation (full-text or client-side filter)
- WebSocket authentication flow (JWT in query param vs first-message auth)

</decisions>

<canonical_refs>
## Canonical References

**Downstream agents MUST read these before planning or implementing.**

### Real-Time Infrastructure
- `backend/app/features/ai/router.py` — SSE streaming pattern (StreamingResponse). Chat WebSocket can follow similar async generator pattern
- `backend/app/features/ai/service.py` — Async streaming with event types. Pattern for WebSocket message dispatch

### Push Notifications
- `backend/app/features/notifications/service.py` — NotificationService with FCM send, fire-and-forget pattern, device token lookup
- `backend/app/features/notifications/models.py` — DeviceToken model with user_id FK

### File Upload
- `backend/app/features/projects/router.py` — Task attachment upload endpoint (POST /tasks/{id}/attachments). Reusable pattern for chat file uploads
- `backend/app/features/files/router.py` — File upload endpoint pattern (aiofiles, StaticFiles mount)

### Data Model (Trade Scope → Contractor)
- `backend/app/features/projects/models.py` — TradeScope model with contractor_id FK to User. Defines who can chat in which thread
- `backend/app/features/projects/schemas.py` — TradeScope schemas for API responses

### Mobile Patterns
- `mobile/lib/core/database/tables/` — Drift table patterns for local sync
- `mobile/lib/features/ai/data/ai_sse_client.dart` — SSE client using dart:io HttpClient (reference for WebSocket client pattern)
- `mobile/lib/core/database/tables/sync_queue.dart` — Outbox sync pattern for offline message queuing

### Phase 22 Annotation (for sharing annotated photos)
- `mobile/lib/features/projects/domain/annotation_schema.dart` — AnnotationLayer JSON schema
- `web/src/features/tasks/types.ts` — TypeScript AnnotationLayer types

</canonical_refs>

<code_context>
## Existing Code Insights

### Reusable Assets
- **NotificationService**: FCM send with device token lookup. Add chat message notification method
- **AI SSE pattern**: StreamingResponse async generator. WebSocket follows similar async event dispatch
- **Task attachment upload**: Multipart file upload with aiofiles, StaticFiles mount. Reuse for chat file attachments
- **Drift sync queue**: SyncQueue table with CREATE/UPDATE/DELETE operations. Chat messages can follow same outbox pattern
- **AnnotationLayer schema**: JSON annotation format from Phase 22. Chat can render shared annotated photos using same renderers

### Established Patterns
- **AsyncSession + get_db**: All DB operations use dependency injection
- **RLS with company_id**: Chat messages must be company-scoped
- **Soft deletes**: deletedAt on all entities
- **Riverpod StreamProvider.autoDispose.family**: For reactive chat message lists
- **GoRouter with RouteNames**: Navigation constants for chat screens

### Integration Points
- **Trade scope assignment → auto-join chat**: When contractor is assigned to trade scope, auto-create/join the scope's chat thread
- **Task completion → chat notification**: When contractor completes a task, optionally notify GC in scope chat
- **Annotated photo → chat sharing**: Share button on task photo opens chat picker to send into thread

</code_context>

<specifics>
## Specific Ideas

- Connecteam's Smart Groups pattern: trade scope assignment = auto-join chat. No manual group management needed
- Read receipts are critical for GC accountability — "I sent the schedule change and 3 of 5 contractors have read it"
- @mentions with forced push: field workers may mute noisy threads, but @mention pierces mute for urgent safety/schedule messages
- Offline message queuing is THE differentiator vs Connecteam (which has NO offline mode). Field workers on construction sites with spotty Wi-Fi can still compose and queue messages

</specifics>

<deferred>
## Deferred Ideas

- **One-way announcement channels** — Connecteam's "Channels" feature for GC broadcasts without reply noise. Valuable but adds scope. Project-wide group chat covers basics for now
- **Message reactions/emoji** — Quick acknowledgment without typing "OK". Low priority
- **Message threading** — Reply-to-specific-message threading (Slack-style). Connecteam doesn't have this either. Flat chat is simpler for field workers
- **Message search** — Full-text search across chat history. Useful but can be added later
- **Message pinning** — Pin important messages to top of thread. Nice-to-have

</deferred>

---

*Phase: 23-real-time-chat*
*Context gathered: 2026-03-24*
*Research: Connecteam app patterns studied for chat architecture decisions*
