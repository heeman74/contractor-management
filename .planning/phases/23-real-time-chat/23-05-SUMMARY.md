---
phase: 23-real-time-chat
plan: 05
subsystem: ui
tags: [chat, websocket, typescript, react, nextjs, tanstack-query, playwright, e2e-tests]

dependency_graph:
  requires:
    - plan: 23-03
      provides: "Backend REST + WebSocket endpoints for chat threads and messages"
    - plan: 23-04
      provides: "Mobile chat UI patterns and design context"
  provides:
    - web/src/features/chat/types.ts
    - web/src/features/chat/hooks/useChatWebSocket.ts
    - web/src/features/chat/hooks/useChatMessages.ts
    - web/src/features/chat/components/ChatPanel.tsx
    - web/src/features/chat/components/ChatThreadList.tsx
    - web/src/features/chat/components/ChatThreadRow.tsx
    - web/src/features/chat/components/MessageList.tsx
    - web/src/features/chat/components/MessageBubble.tsx
    - web/src/features/chat/components/MessageInput.tsx
    - web/tests/e2e/chat.spec.ts
  affects:
    - 23-06

tech-stack:
  added: []
  patterns:
    - useRef for WebSocket instance (not useState) — prevents re-renders from reconnect cycle
    - Exponential backoff reconnect: 1s→2s→4s→8s→16s→32s→64s cap with pong timeout
    - TanStack useInfiniteQuery cursor pagination by seq for message history
    - appendMessage cache updater via queryClient.setQueryData for optimistic WS updates
    - @mention dropdown anchored above textarea (position:absolute, no Popover component)
    - Auto-grow textarea via el.style.height = "auto" then scrollHeight constrained to 5 lines

key-files:
  created:
    - web/src/features/chat/types.ts
    - web/src/features/chat/hooks/useChatWebSocket.ts
    - web/src/features/chat/hooks/useChatMessages.ts
    - web/src/features/chat/components/ChatPanel.tsx
    - web/src/features/chat/components/ChatThreadList.tsx
    - web/src/features/chat/components/ChatThreadRow.tsx
    - web/src/features/chat/components/MessageList.tsx
    - web/src/features/chat/components/MessageBubble.tsx
    - web/src/features/chat/components/MessageInput.tsx
    - web/src/app/(dashboard)/projects/[id]/chat/page.tsx
    - web/tests/e2e/chat.spec.ts
  modified: []

key-decisions:
  - "WebSocket token via GET /api/auth/ws-token endpoint — browser WebSocket API cannot set headers, so short-lived token in query param is needed; same pattern as backend expects (?token=)"
  - "PopoverContent asChild not available on base-ui Popover — @mention dropdown implemented as absolute-positioned div anchored above textarea instead"
  - "popover and avatar shadcn components already installed — no install needed despite plan instructions"
  - "Test page created at /projects/[id]/chat for E2E test navigation (Playwright needs a real URL)"
  - "9 E2E tests (plan required 8+) — all passing with mocked proxy routes"

requirements-completed: [CHAT-01, CHAT-02, CHAT-03, CHAT-04]

duration: 35min
completed: "2026-03-24"
---

# Phase 23 Plan 05: Web Chat Panel Summary

**React/Next.js chat panel with split thread list, WebSocket reconnect hook, infinite-scroll message query, and 9 passing Playwright E2E tests**

## Performance

- **Duration:** ~35 min
- **Started:** 2026-03-24T21:15:00Z
- **Completed:** 2026-03-24T21:51:51Z
- **Tasks:** 2
- **Files created:** 11

## Accomplishments

- TypeScript types matching backend Pydantic schemas exactly (ChatThread, ChatMessage, WsEvent union)
- useChatWebSocket: useRef-based WebSocket with 7-step exponential backoff (1s→64s), 30s ping/10s pong timeout, cache invalidation on reconnect
- useChatMessages: TanStack useInfiniteQuery cursor pagination by seq, optimistic appendMessage for real-time updates
- ChatPanel: responsive split layout (30/70 desktop, stacked mobile), WS reconnection yellow dot indicator
- ChatThreadList: "Trade Conversations" + "Project Group" sections, sorted by unread count then last message timestamp
- ChatThreadRow: trade color dot cycle, unread badge (99+ overflow), relative timestamps, selected state bg-muted
- MessageBubble: text/photo/PDF/annotated-photo variants, own vs other alignment, status icons (clock/check/double-check), read receipts
- MessageInput: auto-grow textarea (1–5 lines), @mention dropdown, attachment staging with preview, debounced typing emission
- MessageList: IntersectionObserver infinite scroll, date separators, typing indicator (3s auto-hide), scroll-to-bottom FAB

## Task Commits

1. **Task 1: TypeScript types, WebSocket hook, message query hook** - `1b16a0d` (feat)
2. **Task 2: ChatPanel component tree + Playwright tests** - `a01eed4` (feat)

## Files Created

- `web/src/features/chat/types.ts` — ChatThread, ChatMessage, ChatReadReceipt, SendMessagePayload, WsEvent types
- `web/src/features/chat/hooks/useChatWebSocket.ts` — WebSocket hook with backoff reconnect, heartbeat, cache invalidation
- `web/src/features/chat/hooks/useChatMessages.ts` — Infinite query hook with cursor pagination and optimistic append
- `web/src/features/chat/components/ChatPanel.tsx` — Split-panel container with thread fetch and WS state
- `web/src/features/chat/components/ChatThreadList.tsx` — Sectioned thread list with empty state
- `web/src/features/chat/components/ChatThreadRow.tsx` — Thread row with indicator, badge, preview, timestamp
- `web/src/features/chat/components/MessageBubble.tsx` — Message bubble with 4 content variants and status icons
- `web/src/features/chat/components/MessageInput.tsx` — Input with attachment, @mention, auto-grow, send
- `web/src/features/chat/components/MessageList.tsx` — Scrollable list with date separators, FAB, typing indicator
- `web/src/app/(dashboard)/projects/[id]/chat/page.tsx` — Server component page at /projects/[id]/chat
- `web/tests/e2e/chat.spec.ts` — 9 Playwright E2E tests (all passing)

## Decisions Made

1. **@mention as absolute div, not Popover** — base-ui Popover does not support `asChild` prop on its Trigger, and requires a real trigger element. Implemented as position:absolute div anchored above textarea. Same visual/functional result without the component coupling.

2. **WS token via /api/auth/ws-token** — Browser WebSocket API cannot attach custom headers. Backend expects `?token=JWT` query param. Added separate lightweight token endpoint call before WS connect (same token, short-lived, for WS auth only).

3. **Test page at /projects/[id]/chat** — Playwright tests navigate to real URLs. Created minimal server component page to host ChatPanel for E2E testing.

4. **9 tests instead of 8** — Added test_send_button_disabled_when_empty as extra coverage; 9 pass.

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 3 - Blocking] base-ui Popover asChild not supported**
- **Found during:** Task 2 (MessageInput implementation)
- **Issue:** Plan specified `PopoverTrigger asChild` but base-ui Popover's Trigger does not accept `asChild` prop, causing TypeScript error TS2322
- **Fix:** Replaced Popover with a simple absolute-positioned div for the @mention dropdown. Functionally identical — appears above textarea, keyboard navigable, closes on Escape/selection
- **Files modified:** `web/src/features/chat/components/MessageInput.tsx`
- **Verification:** `tsc --noEmit` passes, @mention dropdown functional in Playwright tests
- **Committed in:** a01eed4

---

**Total deviations:** 1 auto-fixed (Rule 3 - blocking)
**Impact on plan:** Minor implementation detail change with identical UX. No scope creep.

## Issues Encountered

None — TypeScript compilation clean on chat files; pre-existing errors in unrelated dialogs were out of scope per deviation rules.

## Next Phase Readiness

- Web chat panel ready for integration into project detail view
- ChatPanel exported and ready for use anywhere in the app with `projectId` + `currentUserId` props
- Plan 06 (mobile testing + web integration polish) can proceed

---
*Phase: 23-real-time-chat*
*Completed: 2026-03-24*
