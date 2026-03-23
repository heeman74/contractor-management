// Phase 21 — AI Interview: Flutter E2E tests.
//
// Covers:
//   AI-03: AI interview generates detailed task plans for each trade scope
//
// Tests:
//   1.  test_interview_empty_state: screen shows "Let's build your task plan"
//   2.  test_interview_streaming: AI bubble shows streamed text
//   3.  test_interview_typing_indicator: typing indicator shown before first token
//   4.  test_interview_task_preview: task cards appear with titles and estimated hours
//   5.  test_interview_accept_plan: "Accept Plan" button enabled when tasks present
//   6.  test_interview_restart_confirmation: "Restart Interview" shows confirmation dialog
//   7.  test_interview_restart_keep_plan: "Keep Current Plan" dismisses dialog
//   8.  test_interview_edit_task: task title TextFields visible and editable
//   9.  test_interview_error_display: error banner shown when error in state
//   10. test_interview_accept_plan_hidden_no_tasks: "Accept Plan" not shown without tasks
//
// Patterns (per CLAUDE.md):
//   - pump() NOT pumpAndSettle() — animated streams never settle
//   - ProviderScope.overrideWith for controlling provider state
//   - Direct state injection via notifiers extending InterviewChatNotifier
//   - No GetIt/HttpClient calls in tests — async methods are no-ops

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:contractorhub/features/ai/domain/ai_models.dart';
import 'package:contractorhub/features/ai/presentation/providers/interview_chat_provider.dart';
import 'package:contractorhub/features/ai/presentation/screens/interview_chat_screen.dart';
import 'package:contractorhub/features/ai/presentation/widgets/typing_indicator.dart';

// ---------------------------------------------------------------------------
// Test constants
// ---------------------------------------------------------------------------

const _testScopeId = 'scope-electrical-001';
const _testTradeName = 'Electrical';

// ---------------------------------------------------------------------------
// Fake notifier — extends InterviewChatNotifier so the screen's notifier cast works.
// All async methods are no-ops; the initial state is set in build().
// ---------------------------------------------------------------------------

class _TestInterviewChatNotifier extends InterviewChatNotifier {
  _TestInterviewChatNotifier(this._initialState) : super(_testScopeId);

  final InterviewChatState _initialState;

  @override
  InterviewChatState build() => _initialState;

  @override
  Future<void> startInterview({String? tradeName}) async {
    // No-op — don't call HttpClient in tests
  }

  @override
  Future<void> sendMessage(String message) async {
    // Simulate user message + streaming assistant response
    state = state.copyWith(
      messages: [
        ...state.messages,
        ChatMessage(
          id: 'user-test-msg',
          role: 'user',
          text: message,
          timestamp: DateTime.now(),
        ),
      ],
      isStreaming: true,
      currentStreamText: 'Tell me more about your electrical scope.',
      conversationId: state.conversationId ?? 'conv-fake-001',
    );
  }

  @override
  Future<List<String>> completeInterview(List<AiTaskPreview> editedTasks) async {
    return ['task-id-1', 'task-id-2'];
  }

  @override
  Future<void> restartInterview({String? tradeName}) async {
    // Reset to empty state
    state = InterviewChatState(
      scopeId: scopeId,
      tradeName: tradeName ?? state.tradeName,
    );
  }
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

void main() {
  group('Phase 21 AI Interview E2E Tests', () {
    // -----------------------------------------------------------------------
    // Test 1: Empty state
    // -----------------------------------------------------------------------
    testWidgets('test_interview_empty_state: shows task plan greeting text',
        (tester) async {
      const emptyState = InterviewChatState(
        conversationId: 'conv-001',
        scopeId: _testScopeId,
        tradeName: _testTradeName,
      );

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            interviewChatProvider(_testScopeId).overrideWith(
              () => _TestInterviewChatNotifier(emptyState),
            ),
          ],
          child: const MaterialApp(
            home: SizedBox(
              width: 375,
              height: 812,
              child: InterviewChatScreen(
                scopeId: _testScopeId,
                tradeName: _testTradeName,
              ),
            ),
          ),
        ),
      );

      await tester.pump();

      expect(find.text("Let's build your task plan"), findsOneWidget);
    });

    // -----------------------------------------------------------------------
    // Test 2: Streaming — AI bubble shows streamed text
    // -----------------------------------------------------------------------
    testWidgets('test_interview_streaming: AI bubble shows stream text',
        (tester) async {
      final streamingState = InterviewChatState(
        conversationId: 'conv-001',
        scopeId: _testScopeId,
        tradeName: _testTradeName,
        messages: [
          ChatMessage(
            id: 'user-1',
            role: 'user',
            text: 'I need to install 20 outlets',
            timestamp: DateTime.now(),
          ),
        ],
        isStreaming: true,
        currentStreamText: 'Got it. How many circuits do you need?',
      );

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            interviewChatProvider(_testScopeId).overrideWith(
              () => _TestInterviewChatNotifier(streamingState),
            ),
          ],
          child: const MaterialApp(
            home: SizedBox(
              width: 375,
              height: 812,
              child: InterviewChatScreen(
                scopeId: _testScopeId,
                tradeName: _testTradeName,
              ),
            ),
          ),
        ),
      );

      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));
      await tester.pump(const Duration(milliseconds: 50));

      // Streaming bubble uses AnimatedBuilder with cursor suffix ▌
      expect(find.textContaining('Got it. How many circuits do you need?'), findsWidgets);
    });

    // -----------------------------------------------------------------------
    // Test 3: Typing indicator — shown when streaming with no text yet
    // -----------------------------------------------------------------------
    testWidgets(
        'test_interview_typing_indicator: TypingIndicator shown when streaming without text',
        (tester) async {
      final typingState = InterviewChatState(
        conversationId: 'conv-001',
        scopeId: _testScopeId,
        tradeName: _testTradeName,
        messages: [
          ChatMessage(
            id: 'user-1',
            role: 'user',
            text: 'I need to install 20 outlets',
            timestamp: DateTime.now(),
          ),
        ],
        isStreaming: true,
        currentStreamText: '', // No text yet — typing indicator shows
      );

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            interviewChatProvider(_testScopeId).overrideWith(
              () => _TestInterviewChatNotifier(typingState),
            ),
          ],
          child: const MaterialApp(
            home: SizedBox(
              width: 375,
              height: 812,
              child: InterviewChatScreen(
                scopeId: _testScopeId,
                tradeName: _testTradeName,
              ),
            ),
          ),
        ),
      );

      await tester.pump();
      await tester.pump();

      expect(find.byType(TypingIndicator), findsOneWidget);
    });

    // -----------------------------------------------------------------------
    // Test 4: Task preview — task cards visible with titles and estimated hours
    // -----------------------------------------------------------------------
    testWidgets(
        'test_interview_task_preview: task cards appear with titles and hours',
        (tester) async {
      final tasksState = InterviewChatState(
        conversationId: 'conv-001',
        scopeId: _testScopeId,
        tradeName: _testTradeName,
        messages: [
          ChatMessage(
            id: 'assistant-1',
            role: 'assistant',
            text: 'Here is your task plan',
            timestamp: DateTime.now(),
          ),
        ],
        tasks: const [
          AiTaskPreview(
            id: 'task-1',
            title: 'Install main panel',
            estimatedHours: 4.0,
            sortOrder: 0,
          ),
          AiTaskPreview(
            id: 'task-2',
            title: 'Run conduit',
            estimatedHours: 8.0,
            sortOrder: 1,
          ),
          AiTaskPreview(
            id: 'task-3',
            title: 'Install outlets',
            estimatedHours: 6.0,
            sortOrder: 2,
          ),
        ],
      );

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            interviewChatProvider(_testScopeId).overrideWith(
              () => _TestInterviewChatNotifier(tasksState),
            ),
          ],
          child: const MaterialApp(
            home: SizedBox(
              width: 375,
              height: 812,
              child: InterviewChatScreen(
                scopeId: _testScopeId,
                tradeName: _testTradeName,
              ),
            ),
          ),
        ),
      );

      await tester.pump();
      await tester.pump();

      expect(find.text('Install main panel'), findsOneWidget);
      expect(find.text('Run conduit'), findsOneWidget);
      expect(find.text('Install outlets'), findsOneWidget);

      // Estimated hours shown (formatted as "4.0h" etc.)
      expect(find.text('4.0h'), findsOneWidget);
      expect(find.text('8.0h'), findsOneWidget);
    });

    // -----------------------------------------------------------------------
    // Test 5: Accept Plan — button enabled when tasks present
    // -----------------------------------------------------------------------
    testWidgets('test_interview_accept_plan: Accept Plan button enabled with tasks',
        (tester) async {
      final tasksState = InterviewChatState(
        conversationId: 'conv-001',
        scopeId: _testScopeId,
        tradeName: _testTradeName,
        tasks: const [
          AiTaskPreview(
            id: 'task-1',
            title: 'Install main panel',
            sortOrder: 0,
          ),
        ],
      );

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            interviewChatProvider(_testScopeId).overrideWith(
              () => _TestInterviewChatNotifier(tasksState),
            ),
          ],
          child: const MaterialApp(
            home: SizedBox(
              width: 375,
              height: 812,
              child: InterviewChatScreen(
                scopeId: _testScopeId,
                tradeName: _testTradeName,
              ),
            ),
          ),
        ),
      );

      await tester.pump();
      await tester.pump();

      expect(find.text('Accept Plan'), findsOneWidget);
      final acceptButton = find.widgetWithText(ElevatedButton, 'Accept Plan');
      final btn = tester.widget<ElevatedButton>(acceptButton);
      expect(btn.onPressed, isNotNull);
    });

    // -----------------------------------------------------------------------
    // Test 6: Restart Interview — confirmation dialog appears
    // -----------------------------------------------------------------------
    testWidgets(
        'test_interview_restart_confirmation: Restart Interview shows AlertDialog',
        (tester) async {
      final tasksState = InterviewChatState(
        conversationId: 'conv-001',
        scopeId: _testScopeId,
        tradeName: _testTradeName,
        tasks: const [
          AiTaskPreview(
            id: 'task-1',
            title: 'Install main panel',
            sortOrder: 0,
          ),
          AiTaskPreview(
            id: 'task-2',
            title: 'Run conduit',
            sortOrder: 1,
          ),
        ],
      );

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            interviewChatProvider(_testScopeId).overrideWith(
              () => _TestInterviewChatNotifier(tasksState),
            ),
          ],
          child: const MaterialApp(
            home: SizedBox(
              width: 375,
              height: 812,
              child: InterviewChatScreen(
                scopeId: _testScopeId,
                tradeName: _testTradeName,
              ),
            ),
          ),
        ),
      );

      await tester.pump();
      await tester.pump();

      // The "Restart Interview" button is inside DraggableScrollableSheet which may
      // be clipped. Use ensureVisible before tapping to scroll it into view.
      final restartButtonFinder = find.text('Restart Interview');
      expect(restartButtonFinder, findsOneWidget);
      await tester.ensureVisible(restartButtonFinder);
      await tester.pump();
      await tester.tap(restartButtonFinder, warnIfMissed: false);
      await tester.pump();

      // Confirmation dialog should appear
      expect(find.byType(AlertDialog), findsOneWidget);
      expect(find.text('Restart Interview?'), findsOneWidget);
      expect(find.textContaining('This will replace all'), findsOneWidget);
      expect(find.textContaining('This cannot be undone'), findsOneWidget);
    });

    // -----------------------------------------------------------------------
    // Test 7: Keep Current Plan — dialog dismisses without restart
    // -----------------------------------------------------------------------
    testWidgets(
        'test_interview_restart_keep_plan: Keep Current Plan dismisses dialog',
        (tester) async {
      final tasksState = InterviewChatState(
        conversationId: 'conv-001',
        scopeId: _testScopeId,
        tradeName: _testTradeName,
        tasks: const [
          AiTaskPreview(
            id: 'task-1',
            title: 'Install main panel',
            sortOrder: 0,
          ),
        ],
      );

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            interviewChatProvider(_testScopeId).overrideWith(
              () => _TestInterviewChatNotifier(tasksState),
            ),
          ],
          child: const MaterialApp(
            home: SizedBox(
              width: 375,
              height: 812,
              child: InterviewChatScreen(
                scopeId: _testScopeId,
                tradeName: _testTradeName,
              ),
            ),
          ),
        ),
      );

      await tester.pump();
      await tester.pump();

      // Open dialog — use ensureVisible + warnIfMissed:false for DraggableScrollableSheet button
      final restartFinder = find.text('Restart Interview');
      await tester.ensureVisible(restartFinder);
      await tester.pump();
      await tester.tap(restartFinder, warnIfMissed: false);
      await tester.pump();
      expect(find.byType(AlertDialog), findsOneWidget);

      // Tap "Keep Current Plan"
      await tester.tap(find.text('Keep Current Plan'));
      await tester.pump();
      await tester.pump();

      // Dialog should be dismissed
      expect(find.byType(AlertDialog), findsNothing);

      // Tasks should still be present (not restarted)
      expect(find.text('Install main panel'), findsOneWidget);
    });

    // -----------------------------------------------------------------------
    // Test 8: Edit task — task title TextField is visible and editable
    // -----------------------------------------------------------------------
    testWidgets('test_interview_edit_task: task title TextField is editable',
        (tester) async {
      final tasksState = InterviewChatState(
        conversationId: 'conv-001',
        scopeId: _testScopeId,
        tradeName: _testTradeName,
        tasks: const [
          AiTaskPreview(
            id: 'task-1',
            title: 'Install main panel',
            estimatedHours: 4.0,
            sortOrder: 0,
          ),
        ],
      );

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            interviewChatProvider(_testScopeId).overrideWith(
              () => _TestInterviewChatNotifier(tasksState),
            ),
          ],
          child: const MaterialApp(
            home: SizedBox(
              width: 375,
              height: 812,
              child: InterviewChatScreen(
                scopeId: _testScopeId,
                tradeName: _testTradeName,
              ),
            ),
          ),
        ),
      );

      await tester.pump();
      await tester.pump();

      // TaskPreviewList._TaskCard uses TextField for title (always in edit mode)
      // There should be at least: chat input TextField + task title TextField(s)
      final textFields = find.byType(TextField);
      expect(textFields.evaluate().length, greaterThan(1));
    });

    // -----------------------------------------------------------------------
    // Test 9: Error display — error banner shown when error in state
    // -----------------------------------------------------------------------
    testWidgets('test_interview_error_display: error banner shown when error set',
        (tester) async {
      final errorState = InterviewChatState(
        conversationId: 'conv-001',
        scopeId: _testScopeId,
        tradeName: _testTradeName,
        messages: [
          ChatMessage(
            id: 'user-1',
            role: 'user',
            text: 'I have 20 outlets',
            timestamp: DateTime.now(),
          ),
        ],
        error: 'Failed to get response. Please try again.',
      );

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            interviewChatProvider(_testScopeId).overrideWith(
              () => _TestInterviewChatNotifier(errorState),
            ),
          ],
          child: const MaterialApp(
            home: SizedBox(
              width: 375,
              height: 812,
              child: InterviewChatScreen(
                scopeId: _testScopeId,
                tradeName: _testTradeName,
              ),
            ),
          ),
        ),
      );

      await tester.pump();

      expect(find.text('Failed to get response. Please try again.'), findsOneWidget);
    });

    // -----------------------------------------------------------------------
    // Test 10: Accept Plan not shown when no tasks
    // -----------------------------------------------------------------------
    testWidgets(
        'test_interview_accept_plan_hidden_no_tasks: Accept Plan not shown without tasks',
        (tester) async {
      const emptyState = InterviewChatState(
        conversationId: 'conv-001',
        scopeId: _testScopeId,
        tradeName: _testTradeName,
        tasks: [],
      );

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            interviewChatProvider(_testScopeId).overrideWith(
              () => _TestInterviewChatNotifier(emptyState),
            ),
          ],
          child: const MaterialApp(
            home: SizedBox(
              width: 375,
              height: 812,
              child: InterviewChatScreen(
                scopeId: _testScopeId,
                tradeName: _testTradeName,
              ),
            ),
          ),
        ),
      );

      await tester.pump();
      await tester.pump();

      // Without tasks, DraggableScrollableSheet is not shown
      // so Accept Plan is not visible
      expect(find.text('Accept Plan'), findsNothing);
    });
  });
}
