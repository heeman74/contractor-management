---
phase: 21-ai-project-intake-and-contractor-interview
plan: "05"
subsystem: testing
tags: [e2e-tests, flutter, playwright, ai-chat, sse-mocking]
dependency_graph:
  requires: [21-03, 21-04]
  provides: [E2E coverage for AI-01, AI-02, AI-03]
  affects: [phase completion criteria]
tech_stack:
  added: []
  patterns:
    - "Flutter ProviderScope.overrideWith with fake notifier extending real class"
    - "Playwright route interception with SSE body construction"
    - "pump() not pumpAndSettle() for animated streams"
    - "ensureVisible + warnIfMissed:false for DraggableScrollableSheet content"
key_files:
  created:
    - mobile/test/e2e/phase_21_ai_intake_e2e_test.dart
    - mobile/test/e2e/phase_21_ai_interview_e2e_test.dart
    - web/tests/ai-intake.spec.ts
    - web/tests/ai-interview.spec.ts
  modified: []
decisions:
  - "Fake notifiers must extend the real Notifier class (not plain Notifier<State>) — prevents type mismatch when screen casts notifier ref"
  - "ChatBubble with isStreaming:true appends cursor ▌ via AnimatedBuilder — use find.textContaining() not find.text()"
  - "DraggableScrollableSheet buttons can be off-screen in 800x600 test bounds — use tester.ensureVisible + warnIfMissed:false before tap"
  - "TaskPreviewList renders task titles as controlled <input> elements — assert with locator('input[placeholder=Task title]') not getByText"
  - "TanStack Query DevTools overlay intercepts pointer events — use Enter key for form submit, force:true for button clicks"
  - "Playwright testDir is ./tests not ./e2e — spec files placed in web/tests/ to match playwright.config.ts"
metrics:
  duration: "~35m"
  completed_date: "2026-03-23"
  tasks_completed: 2
  files_changed: 4
---

# Phase 21 Plan 05: E2E Tests for AI Intake and Interview — Summary

## One-liner

Flutter widget tests (20 total) and Playwright E2E tests (14 total) for AI intake and interview chat flows using ProviderScope injection and SSE route mocking with no real API calls.

## What Was Built

### Task 1: Flutter E2E Tests (commit `a143a22`)

**`mobile/test/e2e/phase_21_ai_intake_e2e_test.dart`** — 10 testWidgets covering AI-01 and AI-02:
1. Empty state: "Tell me about your project" heading + `Icons.smart_toy`
2. Send message: user bubble appears after tap send
3. Streaming display: AI bubble shows streamed text (via `find.textContaining`)
4. Typing indicator: `TypingIndicator` widget shown when `isStreaming=true` and `currentStreamText=''`
5. Trade scope preview: Electrical + Plumbing visible, Create Project button enabled
6. Clarifying question: AI bubble shows clarifying question text
7. Create Project button hidden when no scopes
8. Error display: error banner shown when `error` field set in state
9. No conversation: renders empty state without crash when `conversationId=null`
10. Edit trade scope: tapping trade name opens inline `TextField`

**`mobile/test/e2e/phase_21_ai_interview_e2e_test.dart`** — 10 testWidgets covering AI-03:
1. Empty state: "Let's build your task plan" heading
2. Send message: user bubble appears
3. Streaming display: AI bubble shows stream text via `textContaining`
4. Typing indicator: shown when streaming without text
5. Task preview: task title inputs visible after `AiTask` list in state
6. Accept Plan button: visible when tasks present
7. Restart Interview button: visible when tasks present
8. Restart dialog: shows `AlertDialog` with destructive content
9. Keep Current Plan: dialog dismissed, tasks remain
10. Restart confirms: state cleared after confirm

### Task 2: Playwright E2E Tests (commit `f636bee`)

**`web/tests/ai-intake.spec.ts`** — 8 tests for `/projects/new/ai-intake`:
1. Empty state: "Tell me about your project" heading
2. User bubble: appears after Enter key send
3. SSE streaming: AI bubble updates with concatenated tokens
4. Trade scope preview: Electrical + Plumbing visible, Create Project button enabled
5. Clarifying question: appears in AI bubble
6. Create Project: calls `/api/v1/ai/intake/complete`, navigates to project page
7. Offline banner: "AI features require an internet connection." shown
8. Error state: error message shown in chat area

**`web/tests/ai-interview.spec.ts`** — 6 tests for `/projects/[id]/interview/[scopeId]`:
1. Empty state: "Let's build your task plan" heading
2. SSE streaming: AI bubble updates with tokens
3. Task preview: `input[placeholder="Task title"]` inputs visible, count=3
4. Accept Plan: calls `/api/v1/ai/interview/complete`, navigates to project page
5. Restart Interview: shows confirmation dialog with destructive content
6. Keep Current Plan: dismisses dialog, task inputs remain

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 3 - Blocking] Flutter fake notifier type incompatibility**
- **Found during:** Task 1
- **Issue:** `_FakeIntakeChatNotifier extends Notifier<IntakeChatState>` caused runtime type mismatch — screen casts the notifier ref to `IntakeChatNotifier`, which fails if fake uses base `Notifier` class
- **Fix:** Changed all fake notifiers to `extends IntakeChatNotifier` and `extends InterviewChatNotifier` respectively
- **Files modified:** `mobile/test/e2e/phase_21_ai_intake_e2e_test.dart`, `mobile/test/e2e/phase_21_ai_interview_e2e_test.dart`
- **Commit:** `a143a22`

**2. [Rule 1 - Bug] Streaming text cursor in ChatBubble breaks find.text() assertions**
- **Found during:** Task 1
- **Issue:** `ChatBubble` with `isStreaming: true` renders `'${text}▌'` via `AnimatedBuilder` — `find.text('Hello world from AI')` never matches
- **Fix:** Changed all streaming text assertions to `find.textContaining('Hello world from AI')` with `findsWidgets`
- **Files modified:** `mobile/test/e2e/phase_21_ai_intake_e2e_test.dart`, `mobile/test/e2e/phase_21_ai_interview_e2e_test.dart`
- **Commit:** `a143a22`

**3. [Rule 1 - Bug] DraggableScrollableSheet buttons off-screen in test viewport**
- **Found during:** Task 1
- **Issue:** "Restart Interview" button at y=706 in `DraggableScrollableSheet` outside the 800x600 default test bounds — `tap()` warned about missed gesture
- **Fix:** Used `tester.ensureVisible(finder)` before tap + `warnIfMissed: false` to scroll sheet content into view
- **Files modified:** `mobile/test/e2e/phase_21_ai_interview_e2e_test.dart`
- **Commit:** `a143a22`

**4. [Rule 1 - Bug] Playwright testDir mismatch — spec files in wrong directory**
- **Found during:** Task 2
- **Issue:** Plan specified `web/e2e/` but `playwright.config.ts` uses `testDir: "./tests"` — files placed in wrong directory were not discovered
- **Fix:** Placed spec files in `web/tests/` matching the actual config
- **Files modified:** N/A (directory choice corrected during creation)
- **Commit:** `f636bee`

**5. [Rule 1 - Bug] TaskPreviewList task titles in `<input>` elements not text nodes**
- **Found during:** Task 2
- **Issue:** `page.getByText("Install main panel")` returned no matches — titles rendered as controlled `<input value="...">` elements
- **Fix:** Changed assertions to `page.locator('input[placeholder="Task title"]')` with `.first()` and `.toHaveCount(3)` checks
- **Files modified:** `web/tests/ai-interview.spec.ts`
- **Commit:** `f636bee`

**6. [Rule 1 - Bug] `page.getByDisplayValue()` not a Playwright API**
- **Found during:** Task 2
- **Issue:** `page.getByDisplayValue("Install main panel")` threw `TypeError: page.getByDisplayValue is not a function` — that's React Testing Library, not Playwright
- **Fix:** Changed to `page.locator('input[placeholder="Task title"]').toBeVisible()`
- **Files modified:** `web/tests/ai-interview.spec.ts`
- **Commit:** `f636bee`

**7. [Rule 3 - Blocking] TanStack Query DevTools overlay intercepts button clicks**
- **Found during:** Task 2
- **Issue:** `tsqd-parent-container` ellipse SVG at center of screen intercepted pointer events on submit button
- **Fix:** Used `chatInput.press("Enter")` for form submission (no pointer needed); `{ force: true }` for Accept Plan, Restart Interview, Create Project buttons
- **Files modified:** `web/tests/ai-intake.spec.ts`, `web/tests/ai-interview.spec.ts`
- **Commit:** `f636bee`

## Test Results

| Platform | File | Tests | Status |
|----------|------|-------|--------|
| Flutter | phase_21_ai_intake_e2e_test.dart | 10 | All passing |
| Flutter | phase_21_ai_interview_e2e_test.dart | 10 | All passing |
| Playwright | ai-intake.spec.ts | 8 | All passing |
| Playwright | ai-interview.spec.ts | 6 | All passing |
| **Total** | 4 files | **34** | **All passing** |

## Self-Check: PASSED

Files exist:
- `mobile/test/e2e/phase_21_ai_intake_e2e_test.dart` — FOUND
- `mobile/test/e2e/phase_21_ai_interview_e2e_test.dart` — FOUND
- `web/tests/ai-intake.spec.ts` — FOUND
- `web/tests/ai-interview.spec.ts` — FOUND

Commits exist:
- `a143a22` — FOUND (Flutter E2E tests)
- `f636bee` — FOUND (Playwright E2E tests)
