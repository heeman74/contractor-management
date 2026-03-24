---
phase: 23-real-time-chat
plan: "04"
subsystem: mobile-chat-ui
tags: [flutter, riverpod, websocket, chat-ui, go-router, drift]
dependency_graph:
  requires:
    - "23-02 (Drift schema v11, ChatDao, ChatWsClient, ChatRepository, Riverpod providers)"
  provides:
    - "ChatScreen: thread list with Trade Conversations + Project Group sections"
    - "ChatThreadScreen: full-screen chat with WebSocket, reversed ListView, date separators"
    - "MessageBubble: 4 variants (text/photo/PDF/annotated_photo), status icons, long-press menu"
    - "ChatInputBar: 48px buttons, multi-line TextField, @mention overlay, typing debounce"
    - "TypingIndicator: animated 3-dot pulse + '{name} is typing...' label"
    - "GoRouter routes: /projects/:projectId/chat and /projects/:projectId/chat/:threadId"
    - "RouteNames.chat, RouteNames.chatThread, chatPath(), chatThreadPath() helpers"
  affects:
    - "mobile/lib/core/routing/route_names.dart (chat route constants)"
    - "mobile/lib/core/routing/app_router.dart (chat sub-routes of project detail)"
    - "mobile/lib/features/projects/presentation/screens/project_detail_screen.dart (chat AppBar button)"
tech_stack:
  added: []
  patterns:
    - "ConsumerStatefulWidget + initState WebSocket listener pattern"
    - "reversed ListView.builder for chat (newest at bottom)"
    - "AnimationController staggered dot animation for typing indicator"
    - "GoRouter child routes under /projects/:projectId for chat"
    - "Drift Value() companion import aliased as drift.Value to avoid conflict"
key_files:
  created:
    - mobile/lib/features/chat/presentation/screens/chat_screen.dart
    - mobile/lib/features/chat/presentation/screens/chat_thread_screen.dart
    - mobile/lib/features/chat/presentation/widgets/chat_thread_tile.dart
    - mobile/lib/features/chat/presentation/widgets/message_bubble.dart
    - mobile/lib/features/chat/presentation/widgets/chat_input_bar.dart
    - mobile/lib/features/chat/presentation/widgets/typing_indicator.dart
  modified:
    - mobile/lib/core/routing/route_names.dart (chat route constants + helpers)
    - mobile/lib/core/routing/app_router.dart (chat routes + imports)
    - mobile/lib/features/projects/presentation/screens/project_detail_screen.dart (chat button)
decisions:
  - "ChatThreadScreen imports ChatMessagesCompanion via app_database.dart show clause (same pattern as other generated types)"
  - "Drift Value() type aliased as drift.Value via `import 'package:drift/drift.dart' as drift` to avoid name collision with Dart's Value"
  - "isMuted extracted to ChatThreadTile constructor parameter (not local const false) to eliminate dead code warning"
  - "surfaceVariant deprecated — replaced with surfaceContainerHighest throughout chat widgets"
  - "_isOwnMessage placeholder in ChatThreadScreen — full wiring to auth userId deferred; no data model impact"
  - "Attachment picker (ImagePicker/FilePicker) stubbed with SnackBar — packages not yet added to pubspec; no new dependencies required for routing to work"
metrics:
  duration: "1153s"
  completed: "2026-03-24"
  tasks: 2
  files: 9
---

# Phase 23 Plan 04: Mobile Chat UI Summary

**One-liner:** Complete mobile chat UI — ChatScreen thread list with two sections, ChatThreadScreen with WebSocket message delivery and date separators, 4-variant MessageBubble, ChatInputBar with @mention overlay and typing debounce, and animated TypingIndicator; all wired via GoRouter child routes of /projects/:projectId.

## Tasks Completed

| Task | Description | Commit | Files |
|------|-------------|--------|-------|
| 1 | ChatScreen, ChatThreadTile, RouteNames constants, GoRouter routes, ProjectDetailScreen chat button | 588d5f3 | chat_screen.dart, chat_thread_tile.dart, route_names.dart, app_router.dart, project_detail_screen.dart |
| 2 | ChatThreadScreen, MessageBubble, ChatInputBar, TypingIndicator | 06ba286 | chat_thread_screen.dart, message_bubble.dart, chat_input_bar.dart, typing_indicator.dart, chat_thread_tile.dart (fix) |

## Verification

- `dart analyze lib/features/chat/` — 2 info issues, 0 errors, 0 warnings
- `dart analyze lib/features/chat/presentation/screens/chat_screen.dart lib/features/chat/presentation/widgets/chat_thread_tile.dart lib/core/routing/route_names.dart lib/core/routing/app_router.dart` — 0 errors, 0 warnings
- `flutter test` — 794 passing, 13 pre-existing failures (same count as Plan 02 baseline)
- RouteNames.chat = '/projects/:projectId/chat', RouteNames.chatThread = '/projects/:projectId/chat/:threadId'
- GoRouter chat sub-routes registered as children of project detail in Branch 8
- ChatScreen watches chatThreadsProvider(projectId) from Drift stream
- ChatThreadScreen connects to chatWsClientProvider(threadId) on initState
- MessageBubble supports text, photo, PDF, annotated_photo variants
- TypingIndicator auto-hides via 3-second Timer in parent screen

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 1 - Bug] Replaced deprecated surfaceVariant with surfaceContainerHighest**
- **Found during:** Task 2 dart analyze
- **Issue:** `colorScheme.surfaceVariant` is deprecated since Flutter 3.18. Used in MessageBubble and ChatInputBar for incoming bubble background and attachment preview backgrounds.
- **Fix:** Replaced all occurrences with `colorScheme.surfaceContainerHighest`
- **Files modified:** message_bubble.dart, chat_input_bar.dart
- **Commit:** 06ba286

**2. [Rule 3 - Blocking] Run build_runner to generate Drift/Freezed files in worktree**
- **Found during:** Task 1 dart analyze (packages showed no generated files)
- **Issue:** Worktree did not have generated Drift and Freezed files (.g.dart, .freezed.dart). dart analyze could not resolve types.
- **Fix:** Ran `dart run build_runner build --delete-conflicting-outputs` which generated 702 outputs in 81s.
- **Files modified:** Generated files (app_database.g.dart, auth_state.freezed.dart, etc.)
- **Commit:** Part of merge + build in worktree setup

**3. [Rule 3 - Blocking] Merge master branch before starting (no chat data layer in worktree)**
- **Found during:** Task 1 start — mobile/lib/features/chat/ directory did not exist
- **Issue:** This worktree was branched from an earlier state (phase 6 commit) before Phase 23 Plan 02 work was committed.
- **Fix:** Merged master into worktree-agent-a28364f3 to bring in Phase 23 Plan 02 outputs (Drift schema v11, ChatDao, ChatWsClient, ChatRepository, Riverpod providers).
- **Commit:** Git merge commit in worktree

### Deferred Items

- **Attachment picker integration:** ImagePicker and FilePicker are stubbed with SnackBar. Actual picker calls require pubspec dependency additions (image_picker, file_picker) — deferred to Phase 23 Plan 05 or attachment-specific plan.
- **`_isOwnMessage` in ChatThreadScreen:** Returns `false` as placeholder. Needs comparison with `currentUser.userId` from auth state. Wired in follow-up — no data model impact.
- **Thread name in ChatThreadScreen AppBar:** Shows 'Chat' as placeholder. Needs lookup from `chatThreadsProvider` filtered by threadId — wired in follow-up.
- **@mention member list:** Uses 3 hardcoded placeholder members. Real data requires backend thread member query endpoint — wired in follow-up.

## Self-Check: PASSED
