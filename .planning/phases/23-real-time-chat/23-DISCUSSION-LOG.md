# Phase 23: Real-Time Chat - Discussion Log

> **Audit trail only.** Do not use as input to planning, research, or execution agents.
> Decisions are captured in CONTEXT.md — this log preserves the alternatives considered.

**Date:** 2026-03-24
**Phase:** 23-real-time-chat
**Areas discussed:** Transport protocol, Chat thread structure, File sharing in chat, Offline & sync behavior
**Research input:** Connecteam app analysis (team management platform) informed several decisions

---

## Transport Protocol

| Option | Description | Selected |
|--------|-------------|----------|
| WebSocket | Bidirectional real-time, sub-second delivery. FastAPI/Starlette native support. | ✓ |
| SSE + HTTP POST | SSE for receiving, POST for sending. Proven in Phase 21. | |
| HTTP polling + FCM push | Connecteam-style. Simplest but higher latency. | |

**User's choice:** WebSocket
**Notes:** Connecteam appears to use push-driven delivery, not WebSocket. We chose WebSocket for better real-time experience.

---

| Option | Description | Selected |
|--------|-------------|----------|
| Typing indicator only | Show "..." when typing. No online/offline presence. | ✓ |
| Full presence + typing | Online/offline/away status + typing. | |
| Neither | No presence features. | |

**User's choice:** Typing indicator only
**Notes:** Field workers don't need to know who's "online"

---

| Option | Description | Selected |
|--------|-------------|----------|
| Same WebSocket for both platforms | Single ws:// endpoint. Browser WebSocket API is native. | ✓ |
| You decide | Claude's discretion. | |

**User's choice:** Same WebSocket

---

## Chat Thread Structure

| Option | Description | Selected |
|--------|-------------|----------|
| Per trade scope | 1 thread per trade scope. GC + contractor. | |
| Per trade scope + project-wide | Trade scope threads + project-wide group chat. | ✓ |
| Free-form 1:1 + groups | Connecteam-style flexible groups. | |

**User's choice:** Per trade scope + project-wide
**Notes:** Two levels of chat — trade-specific and cross-trade coordination

---

| Option | Description | Selected |
|--------|-------------|----------|
| Yes, read receipts | Who read + timestamp. Connecteam has this. | ✓ |
| Delivery receipts only | Delivered but not read. | |
| No receipts | Simplest. | |

**User's choice:** Read receipts
**Notes:** GCs cite accountability as critical. Connecteam feature.

---

| Option | Description | Selected |
|--------|-------------|----------|
| Yes, @mentions | @user or @all forces push even if muted. | ✓ |
| No @mentions | All messages equal notification weight. | |
| You decide | Claude's discretion. | |

**User's choice:** @mentions with forced push
**Notes:** Critical for safety alerts on job sites

---

| Option | Description | Selected |
|--------|-------------|----------|
| Defer to future phase | Focus on bidirectional chat. | ✓ |
| Include in Phase 23 | Project-level announcement channel. | |
| Not needed | Group chat covers it. | |

**User's choice:** Defer announcement channels
**Notes:** Connecteam has one-way Channels — valuable but adds scope

---

| Option | Description | Selected |
|--------|-------------|----------|
| Server timestamp ordering | Server assigns monotonic sequence per thread. Dedup by UUID. | ✓ |
| Client timestamp with reconciliation | Client time, server reorders. | |
| You decide | Claude's discretion. | |

**User's choice:** Server timestamp ordering

---

| Option | Description | Selected |
|--------|-------------|----------|
| All contractors + GC | Everyone on project auto-joins project-wide chat. | ✓ |
| GC + trade leads only | Primary contractor per scope only. | |
| GC selectively invites | Manual control. | |

**User's choice:** All contractors + GC

---

## File Sharing in Chat

| Option | Description | Selected |
|--------|-------------|----------|
| Photos + PDFs + annotated photos | Inline preview, reuse upload pattern. No video/GIF. | ✓ |
| Full media (Connecteam-style) | Photos, video, PDF, GIF, location. | |
| Photos only | Just photos. | |

**User's choice:** Photos + PDFs + annotated photos
**Notes:** Keep it professional for construction. No video/GIF.

---

| Option | Description | Selected |
|--------|-------------|----------|
| Yes, share annotated photos | Share from task into chat with annotation overlay. | ✓ |
| Share original only | Annotations stay on task. | |
| You decide | Claude's discretion. | |

**User's choice:** Share annotated photos from task execution

---

## Offline & Sync Behavior

| Option | Description | Selected |
|--------|-------------|----------|
| Queue messages + sync on reconnect | Offline queue in Drift, drain on reconnect. | ✓ |
| Read-only offline | View cached but can't compose. | |
| Block with message (Connecteam-style) | No offline access. | |

**User's choice:** Queue messages + sync on reconnect
**Notes:** KEY DIFFERENTIATOR vs Connecteam (no offline mode)

---

| Option | Description | Selected |
|--------|-------------|----------|
| Last 100 messages per thread | Paginate older from server. | ✓ |
| All history | Complete offline access. Heavy storage. | |
| Last 7 days | Time-based window. | |

**User's choice:** Last 100 messages per thread

---

| Option | Description | Selected |
|--------|-------------|----------|
| Preview text + sender name | "John D. (Plumbing): Can you check..." | ✓ |
| Silent push + badge count | Data-only push, fetch content locally. | |
| You decide | Claude's discretion. | |

**User's choice:** Preview text + sender name

---

## Claude's Discretion

- WebSocket connection lifecycle (heartbeat, reconnect)
- Chat message DB schema design
- Message pagination strategy
- Chat UI layout and styling
- File upload endpoint design
- Mute/notification settings per thread
- Message search implementation
- WebSocket authentication flow

## Deferred Ideas

- One-way announcement channels (Connecteam's "Channels")
- Message reactions/emoji
- Message threading (reply-to)
- Message search
- Message pinning
