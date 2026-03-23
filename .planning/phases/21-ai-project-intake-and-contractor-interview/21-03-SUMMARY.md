---
phase: 21
plan: 03
subsystem: web
tags: [ai, chat, sse, streaming, web]
dependency_graph:
  requires: [21-02]
  provides: [web-ai-chat-ui, sse-proxy, intake-page, interview-page]
  affects: [web-projects]
tech_stack:
  added: [jest, ts-jest, ts-node, scroll-area]
  patterns: [sse-streaming, readablestream-pipe, dnd-kit-sortable, react-hooks-streaming]
key_files:
  created:
    - web/src/app/api/ai-chat/route.ts
    - web/src/features/ai/hooks/useIntakeChat.ts
    - web/src/features/ai/hooks/useInterviewChat.ts
    - web/src/features/ai/hooks/__tests__/useIntakeChat.test.ts
    - web/src/features/ai/components/ChatBubble.tsx
    - web/src/features/ai/components/TypingIndicator.tsx
    - web/src/features/ai/components/ChatInput.tsx
    - web/src/features/ai/components/TradeScopePreviewCard.tsx
    - web/src/features/ai/components/TaskPreviewList.tsx
    - web/src/app/projects/new/ai-intake/page.tsx
    - web/src/app/projects/[id]/interview/[scopeId]/page.tsx
    - web/src/components/ui/scroll-area.tsx
    - web/jest.config.ts
  modified:
    - web/src/app/(dashboard)/projects/page.tsx
    - web/src/app/(dashboard)/projects/components/TradeScopeDetail.tsx
    - web/package.json
decisions:
  - SSE proxy pipes ReadableStream directly via upstreamRes.body — never buffers with .text()
  - parseSSELine exported as pure function for independent unit testing
  - Pages placed outside (dashboard) route group for full-page layout without sidebar
  - Button asChild not available (uses @base-ui/react) — use Link with button classes instead
  - Pre-existing TS errors in contractors/jobs dialogs are out-of-scope; new AI files have zero errors
metrics:
  duration: ~35m
  completed_date: "2026-03-23"
  tasks_completed: 2
  files_created: 13
  files_modified: 3
---

# Phase 21 Plan 03: Web AI Chat UI Summary

**One-liner:** SSE streaming proxy with ReadableStream pipe, chat hooks with token-by-token streaming, 9 unit-tested SSE parse cases, and two full-page chat interfaces for GC intake and contractor interview.

## Tasks Completed

| Task | Name | Commit | Files |
|------|------|--------|-------|
| 1 | SSE proxy route, streaming hooks, chat components | 0401d67 | 13 created |
| 2 | Intake and interview web pages + navigation | 19d220e | 4 files |

## Task 3: Awaiting Human Verification

Task 3 is a `checkpoint:human-verify` gate. Human must verify the streaming UI works visually.

## What Was Built

### SSE Proxy Route (`/api/ai-chat`)
- `force-dynamic` + `maxDuration=60` for long streaming requests
- POST handler: SSRF prevention (path must start with `/api/v1/ai/`), pipes `upstreamRes.body` ReadableStream directly — never buffers
- GET handler: buffered proxy for conversation fetch endpoints
- 401 if access_token cookie missing

### useIntakeChat Hook
- Manages: messages, isStreaming, currentStreamText, tradeScopes, error, conversationId
- `startConversation(projectId?)`: POST to `/api/v1/ai/intake/start`
- `sendMessage(message)`: POST to message endpoint, reads SSE via `TextDecoderStream` + `getReader()`
- Handles token/tool_call/done/error SSE events; on `create_trade_scope` tool_call adds to tradeScopes
- `completeIntake(name, desc, scopes)`: POST to complete endpoint, returns project_id
- `removeTradeScope`, `updateTradeScope`, `reorderTradeScopes` for local state mutations

### useInterviewChat Hook
- Same structure as useIntakeChat but for interview flow
- On `create_task` tool_call: adds to tasks array
- `completeInterview(tasks)`: POST to interview/complete

### parseSSELine (unit-tested)
- Parses SSE event blocks (multi-line: event + data lines)
- Returns null for empty/comment lines
- Defaults event to "message" for data-only lines
- 9 tests: token, tool_call, done, error, empty, comment, partial, whitespace, empty delta

### Chat Components
- `ChatBubble`: user (right, --primary bg) / AI (left, --muted bg, ContractorHub AI avatar, streaming cursor)
- `TypingIndicator`: 3 animated dots with staggered bounce, aria-label="ContractorHub AI is typing"
- `ChatInput`: auto-expand textarea (max 4 rows), offline detection via navigator.onLine, image attach with preview
- `TradeScopePreviewCard`: dnd-kit drag reorder, inline edit on click, color swatch, skeleton loading, "Create Project" CTA
- `TaskPreviewList`: dnd-kit drag reorder, per-task editing (title/desc/hours/materials/priority), "Accept Plan" + "Restart Interview" with confirmation dialog

### Pages
- `/projects/new/ai-intake`: full-page layout (no sidebar), fixed header + ScrollArea + fixed ChatInput, preview section appears when tradeScopes.length > 0
- `/projects/[id]/interview/[scopeId]`: same layout, TaskPreviewList preview
- Navigation: "New AI Project" button on projects dashboard, "Start AI Interview" on TradeScopeDetail when tasks=0

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 3 - Blocking] Jest not installed in web project**
- **Found during:** Task 1 (SSE parse test setup)
- **Issue:** No jest in package.json; plan requires `npx jest` for unit tests
- **Fix:** Installed jest, @types/jest, jest-environment-jsdom, ts-jest, ts-node; created jest.config.ts
- **Files modified:** web/package.json, web/package-lock.json, web/jest.config.ts
- **Commit:** 0401d67

**2. [Rule 1 - Bug] Button component lacks asChild (uses @base-ui/react not Radix)**
- **Found during:** Task 2 TypeScript check
- **Issue:** Plan called for `<Button asChild><Link>` pattern but Button is @base-ui/react which has no asChild prop
- **Fix:** Used `<Link>` with inline button class styles instead of Button wrapper
- **Files modified:** web/src/app/(dashboard)/projects/page.tsx, TradeScopeDetail.tsx
- **Commit:** 19d220e

### Out-of-Scope Pre-existing Issues (logged to deferred)
- 5 TypeScript errors in `contractors` and `jobs` dialogs — pre-existing, not caused by this plan

## Self-Check

Checking files exist:
- web/src/app/api/ai-chat/route.ts: FOUND
- web/src/features/ai/hooks/useIntakeChat.ts: FOUND
- web/src/features/ai/hooks/__tests__/useIntakeChat.test.ts: FOUND
- web/src/app/projects/new/ai-intake/page.tsx: FOUND
- web/src/app/projects/[id]/interview/[scopeId]/page.tsx: FOUND

Commit hashes:
- 0401d67: FOUND (Task 1)
- 19d220e: FOUND (Task 2)

Jest tests: 9 passed
TypeScript (new files): 0 errors

## Self-Check: PASSED
