---
phase: 21
plan: 04
subsystem: mobile
tags: [flutter, drift, riverpod, sse, ai-chat, streaming]
dependency_graph:
  requires: [21-02]
  provides: [mobile-ai-chat-ui, drift-schema-v9, sse-client]
  affects: [mobile-routing, project-list-screen, trade-scope-detail-screen]
tech_stack:
  added: []
  patterns: [dart-io-sse-streaming, notifier-family-pattern, draggable-scrollable-sheet]
key_files:
  created:
    - mobile/lib/core/database/tables/ai_conversations.dart
    - mobile/lib/core/database/tables/ai_messages.dart
    - mobile/lib/features/ai/data/ai_conversation_dao.dart
    - mobile/lib/features/ai/data/ai_sse_client.dart
    - mobile/lib/features/ai/domain/ai_models.dart
    - mobile/lib/features/ai/presentation/providers/intake_chat_provider.dart
    - mobile/lib/features/ai/presentation/providers/interview_chat_provider.dart
    - mobile/lib/features/ai/presentation/widgets/chat_bubble.dart
    - mobile/lib/features/ai/presentation/widgets/typing_indicator.dart
    - mobile/lib/features/ai/presentation/widgets/chat_input_bar.dart
    - mobile/lib/features/ai/presentation/widgets/trade_scope_preview_card.dart
    - mobile/lib/features/ai/presentation/widgets/task_preview_list.dart
    - mobile/lib/features/ai/presentation/screens/intake_chat_screen.dart
    - mobile/lib/features/ai/presentation/screens/interview_chat_screen.dart
    - mobile/test/unit/ai_sse_client_test.dart
  modified:
    - mobile/lib/core/database/app_database.dart
    - mobile/lib/core/database/app_database.g.dart
    - mobile/lib/core/di/service_locator.dart
    - mobile/lib/core/routing/route_names.dart
    - mobile/lib/core/routing/app_router.dart
    - mobile/lib/features/projects/presentation/screens/project_list_screen.dart
    - mobile/lib/features/projects/presentation/screens/trade_scope_detail_screen.dart
decisions:
  - dart:io HttpClient used for SSE streaming — flutter_client_sse does not support POST body; Dio cannot handle text/event-stream responses
  - parseSseEvent extracted as top-level function (not class method) to enable independent unit testing without constructing AiSseClient
  - InterviewChatNotifier uses Riverpod 3 family pattern with constructor injection (factory (arg) => Notifier(arg)) — no FamilyNotifier class exists in Riverpod 3
  - Sync Notifier (not AsyncNotifier) used for both chat providers — build() is synchronous, all async ops in methods per CLAUDE.md guidance
  - GetIt used inside Riverpod notifiers for AiSseClient and AiConversationDao — documented tradeoff per CLAUDE.md
metrics:
  duration_seconds: 1195
  completed_date: "2026-03-23"
  tasks_completed: 3
  tasks_total: 3
  files_created: 15
  files_modified: 7
---

# Phase 21 Plan 04: Flutter Mobile AI Chat UI Summary

## One-liner

Drift schema v9 with AI conversation tables, dart:io SSE client bypassing Dio for token-by-token streaming, Riverpod notifiers for intake and interview chat flows, and full Material 3 chat UI with DraggableScrollableSheet preview cards.

## What Was Built

### Task 1: Data layer + SSE client + providers

**Drift schema v9** — Added `AiConversations` and `AiMessages` tables to the existing schema v8, with migration block `if (from < 9)`. Generated Drift code via `build_runner`.

**AiSseClient** — Bypasses Dio entirely using `dart:io` HttpClient with `Accept: text/event-stream`. The `parseSseEvent(eventLine, dataLine)` function is a top-level function to enable independent unit testing. Handles chunked SSE: splits on `\n`, tracks `event:` and `data:` lines, yields on blank line (event boundary). Supports all 4 event types: `token`, `tool_call`, `done`, `error`.

**AiConversationDao** — Drift DAO for transcript caching (D-31). Provides `upsertConversation`, `upsertMessages`, `watchMessagesByConversation`, and `getActiveForProject/Scope` queries.

**GetIt registrations** — `AiSseClient` registered as lazy singleton with `API_BASE_URL` from `--dart-define` (defaults to `http://10.0.2.2:8000`). `AiConversationDao` registered as singleton.

**IntakeChatNotifier** — Sync `Notifier<IntakeChatState>` managing GC intake flow: starts conversation, streams tokens from SSE, handles `create_trade_scope` and `ask_clarifying_question` tool calls, syncs transcript to Drift on completion.

**InterviewChatNotifier** — Same pattern but for contractor interview flow. Uses `NotifierProvider.autoDispose.family<..., String>` pattern. Handles `create_task` tool calls, supports `restartInterview()`.

**Unit tests** — 11 tests for `parseSseEvent` covering: token event, tool_call with nested input, done event, error event, empty data returns null, empty event type defaults to 'message', invalid JSON returns empty map, multiline delta, create_task with materials list, SseEvent.toString, SseEvent.dataJson.

### Task 2: Chat widgets + screens + navigation

**ChatBubble** — User messages: right-aligned primary color. AI messages: left-aligned surfaceVariant with ContractorHub AI avatar (CircleAvatar + smart_toy icon). Streaming mode: blinking `▌` cursor via AnimationController. SelectableText for copy support. Image thumbnail with fullscreen InteractiveViewer. Accessibility Semantics wrapper.

**TypingIndicator** — Three dots with staggered sine-wave bounce via AnimationController (1.4s repeat). Left-aligned with AI avatar. `liveRegion: true` for accessibility.

**ChatInputBar** — Multi-line TextField (1-4 lines), offline banner above input with wifi_off icon, Send button disabled when empty/streaming/offline, Attach button, 48px minimum touch targets.

**TradeScopePreviewCard** — ReorderableListView of scope rows with drag handles, color swatches, inline editable names, delete buttons. Create Project CTA enabled when scopes.isNotEmpty.

**TaskPreviewList** — ReorderableListView of editable task cards. Each card: title (TextField), description (TextField), priority chip (tap-to-cycle), estimated hours, materials wrap. Restart Interview shows AlertDialog per UI spec with error-color destructive button.

**IntakeChatScreen** — ListView of ChatBubbles with auto-scroll. DraggableScrollableSheet (initialChildSize: 0.4, max: 0.8) for TradeScopePreviewCard. Empty state with bot icon. Project name dialog on Create Project.

**InterviewChatScreen** — Same structure with TaskPreviewList in the sheet. context.pop() on Accept Plan.

**Navigation** — Added `/ai-intake` and `/ai-interview/:scopeId` routes to GoRouter. RouteNames constants + `aiInterviewPath()` helper. ProjectListScreen FAB updated to navigate to AI intake. TradeScopeDetailScreen empty state adds "Start AI Interview" button.

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 3 - Blocking] flutter_client_sse not used — dart:io HttpClient used instead**
- **Found during:** Task 1 — `flutter_client_sse` does not support POST body, which is required for the AI endpoints
- **Fix:** Used `dart:io` HttpClient directly for SSE streaming. This is exactly what the plan describes as the fallback approach.
- **Files modified:** `mobile/lib/features/ai/data/ai_sse_client.dart`
- **Commit:** f593935

**2. [Rule 3 - Blocking] Worktree was at schema v5 (phase 6 finish) — merged master before implementation**
- **Found during:** Pre-task inspection
- **Fix:** `git merge master` to bring worktree to schema v8 state with all v3.0 code
- **Commit:** Merge commit (pre-task)

**3. [Rule 1 - Bug] FamilyNotifier does not exist in Riverpod 3**
- **Found during:** Task 1 flutter analyze
- **Fix:** Changed to `Notifier<State>` with constructor injection per Riverpod 3 family pattern: `factory (arg) => Notifier(arg)`. Documented in STATE.md decisions.
- **Files modified:** `mobile/lib/features/ai/presentation/providers/interview_chat_provider.dart`
- **Commit:** f593935

## Auth Gates

None — no auth gates encountered during execution.

## Verification

- `flutter analyze` reports 0 errors (714 info/warnings from pre-existing code)
- `flutter test test/unit/ai_sse_client_test.dart` passes (11/11 tests)
- `dart run build_runner build --delete-conflicting-outputs` succeeded (schema v9 generated)
- Task 3 (human-verify) approved by user — visual verification passed

## Self-Check: PASSED

All created files verified on disk. All task commits verified in git log.
- f593935 (Task 1): Drift schema v9, SSE client, DAO, providers, unit tests
- f527119 (Task 2): Chat widgets, screens, navigation routes
