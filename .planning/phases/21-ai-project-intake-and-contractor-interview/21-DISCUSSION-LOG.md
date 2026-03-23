# Phase 21: AI Project Intake and Contractor Interview - Discussion Log

> **Audit trail only.** Do not use as input to planning, research, or execution agents.
> Decisions are captured in CONTEXT.md — this log preserves the alternatives considered.

**Date:** 2026-03-23
**Phase:** 21-ai-project-intake-and-contractor-interview
**Areas discussed:** AI conversation flow, Claude API architecture, Contractor interview design, Output validation and saving, Chat UI design details, System prompt engineering, Offline behavior

---

## AI Conversation Flow

| Option | Description | Selected |
|--------|-------------|----------|
| Multi-turn chat | GC types description, AI asks clarifying questions, then generates breakdown | ✓ |
| Single prompt + preview | GC types everything upfront, AI generates in one shot | |
| Structured wizard + AI | Step-by-step form with AI filling gaps | |

**User's choice:** Multi-turn chat
**Notes:** Natural conversation feel, handles ambiguity well

| Option | Description | Selected |
|--------|-------------|----------|
| Dedicated page | Full-page chat at /projects/new/ai-intake (web) and Projects tab (mobile) | ✓ |
| Modal overlay | Chat in large modal from projects list | |
| Sidebar panel | Slides in from right on web | |

**User's choice:** Dedicated page

| Option | Description | Selected |
|--------|-------------|----------|
| Streaming tokens | Word-by-word like ChatGPT via SSE | ✓ |
| Complete response | Spinner then full response | |

**User's choice:** Streaming tokens

| Option | Description | Selected |
|--------|-------------|----------|
| Preview card below chat | Structured editable card/table below chat | ✓ |
| Navigate to project detail | AI creates project immediately | |
| Inline editable in chat | Editable fields in message thread | |

**User's choice:** Preview card below chat

| Option | Description | Selected |
|--------|-------------|----------|
| Save full transcript | Chat messages stored in DB linked to project | ✓ |
| Save summary only | AI-generated summary, not individual messages | |
| Don't save | Chat is ephemeral | |

**User's choice:** Save full transcript

| Option | Description | Selected |
|--------|-------------|----------|
| Yes, with context | Reopen chat for existing project, AI loads current trades | ✓ |
| New chat only | AI intake only for new projects | |

**User's choice:** Yes, with context

| Option | Description | Selected |
|--------|-------------|----------|
| Support image uploads | Site photos and blueprints via Claude vision | ✓ |
| Text only for Phase 21 | GC describes in words only | |

**User's choice:** Support image uploads

---

## Claude API Architecture

| Option | Description | Selected |
|--------|-------------|----------|
| Backend only | FastAPI calls Anthropic SDK, streams via SSE | ✓ |
| Frontend direct + backend save | Web calls Anthropic directly | |

**User's choice:** Backend only

| Option | Description | Selected |
|--------|-------------|----------|
| Tool use | Claude tool_use with typed parameters | ✓ |
| JSON in message | Prompt Claude to output JSON blocks | |

**User's choice:** Tool use

| Option | Description | Selected |
|--------|-------------|----------|
| Claude Sonnet | Fast, cost-effective, strong tool use | ✓ |
| Claude Opus | Most capable but slower/costlier | |
| Configurable per company | Companies choose tier | |

**User's choice:** Claude Sonnet

| Option | Description | Selected |
|--------|-------------|----------|
| Full history per request | All messages + system prompt each turn | ✓ |
| Sliding window + summary | Summarize older messages | |

**User's choice:** Full history per request

| Option | Description | Selected |
|--------|-------------|----------|
| Retry with backoff + user message | Auto-retry 2-3x, friendly message | ✓ |
| Immediate error with retry button | Show error, let user retry | |

**User's choice:** Retry with backoff + user message

| Option | Description | Selected |
|--------|-------------|----------|
| Track but don't limit | Log token usage for analytics | ✓ |
| Hard token budget per company | Monthly limits | |
| No tracking | Deal with costs later | |

**User's choice:** Track but don't limit

| Option | Description | Selected |
|--------|-------------|----------|
| Yes, inject trade catalog | System prompt includes company's catalog | ✓ |
| No, AI generates fresh | Rely on Claude's knowledge | |

**User's choice:** Yes, inject trade catalog

---

## Contractor Interview Design

| Option | Description | Selected |
|--------|-------------|----------|
| Adaptive conversation | Trade-specific questions that adapt based on answers | ✓ |
| Fixed questionnaire | Predefined question set per trade | |
| Hybrid | Core questions + adaptive follow-ups | |

**User's choice:** Adaptive conversation

| Option | Description | Selected |
|--------|-------------|----------|
| Full project + trade scope | AI sees full project context | ✓ |
| Own trade scope only | Contractor sees only their scope | |

**User's choice:** Full project + trade scope

| Option | Description | Selected |
|--------|-------------|----------|
| Preview list with edit/approve | Editable task cards after interview | ✓ |
| Chat shows tasks inline | Tasks appear in chat flow | |
| Auto-save, edit after | Tasks saved immediately | |

**User's choice:** Preview list with edit/approve

| Option | Description | Selected |
|--------|-------------|----------|
| Both mobile and web | Same chat on both platforms | ✓ |
| Mobile only | Field workers use mobile | |
| Web only | Build web first | |

**User's choice:** Both mobile and web

| Option | Description | Selected |
|--------|-------------|----------|
| Yes, restart interview | Re-enter to regenerate tasks | ✓ |
| No, edit manually | One-time interview | |

**User's choice:** Yes, restart interview

| Option | Description | Selected |
|--------|-------------|----------|
| Push notification + dashboard | GC notified on completion | ✓ |
| Dashboard only | No push, status on page | |

**User's choice:** Push notification + dashboard update

| Option | Description | Selected |
|--------|-------------|----------|
| AI estimates + contractor edits | Pre-fill hours/materials, contractor adjusts | ✓ |
| Contractor fills manually | AI generates titles only | |

**User's choice:** AI estimates + contractor edits

---

## Output Validation and Saving

| Option | Description | Selected |
|--------|-------------|----------|
| Tool use schema + Pydantic | Tool_use params match existing schemas | ✓ |
| Custom validation layer | Separate service for business rules | |
| Both | Schema + business rules | |

**User's choice:** Tool use schema + Pydantic

| Option | Description | Selected |
|--------|-------------|----------|
| Yes, suggest sequencing | AI suggests trade order using dependency engine | ✓ |
| No, GC adds manually | AI creates scopes without deps | |

**User's choice:** Yes, suggest sequencing

| Option | Description | Selected |
|--------|-------------|----------|
| Yes, same endpoints | Same POST /trade-scopes, /tasks | ✓ |
| Bulk import endpoint | New batch endpoint | |

**User's choice:** Yes, same endpoints

---

## Chat UI Design Details

| Option | Description | Selected |
|--------|-------------|----------|
| Modern chat bubbles | Rounded, right/left aligned, typing indicator | ✓ |
| Slack-style threaded | Stacked with avatars, no bubbles | |

**User's choice:** Modern chat bubbles

| Option | Description | Selected |
|--------|-------------|----------|
| Branded name | "ContractorHub AI" with icon | ✓ |
| Just "AI Assistant" | Generic label | |

**User's choice:** Branded name ("ContractorHub AI")

| Option | Description | Selected |
|--------|-------------|----------|
| Thumbnail in bubble | Tap to full-screen with zoom | ✓ |
| Inline preview with caption | Medium size with AI caption | |

**User's choice:** Thumbnail in bubble + full-screen tap

---

## System Prompt Engineering

| Option | Description | Selected |
|--------|-------------|----------|
| Rich construction context | Trade sequences, task patterns, material categories | ✓ |
| Minimal | Simple "construction planner" prompt | |
| Company-customizable | Admin edits per company | |

**User's choice:** Rich construction context

| Option | Description | Selected |
|--------|-------------|----------|
| Code (version-controlled) | Python constants/text files in repo | ✓ |
| Database (runtime editable) | Stored per company in DB | |

**User's choice:** Code (version-controlled)

---

## Offline Behavior

| Option | Description | Selected |
|--------|-------------|----------|
| Block with clear message | Disable chat input offline | ✓ |
| Queue messages | Send when back online | |

**User's choice:** Block with clear message

| Option | Description | Selected |
|--------|-------------|----------|
| Yes, sync to Drift | Transcript syncs for offline reading | ✓ |
| Online only | Viewable when connected | |

**User's choice:** Yes, sync transcripts to Drift

---

## Claude's Discretion

- SSE streaming implementation details
- Chat message DB schema design
- AI token usage tracking table schema
- Typing indicator animation
- System prompt text content (construction knowledge)
- Image upload flow details
- Trade sequence suggestion algorithm

## Deferred Ideas

- Company-customizable system prompt templates — future phase
- AI-generated zone lists — Phase 22+
- AI conflict resolution suggestions — future
- Hard token budget with billing — monetization phase
- Video uploads in chat — future media enhancement
