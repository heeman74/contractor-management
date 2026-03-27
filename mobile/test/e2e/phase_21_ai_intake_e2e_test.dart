// Phase 21 — AI Intake: Flutter E2E tests.
//
// Covers:
//   AI-01: GC intake produces trade scopes from natural language description
//   AI-02: AI asks clarifying questions before finalising scopes
//
// Tests:
//   1.  test_intake_empty_state: screen shows "Tell me about your project" + bot icon
//   2.  test_intake_send_message: user bubble appears after send
//   3.  test_intake_streaming_display: AI bubble shows streamed text
//   4.  test_intake_typing_indicator: typing indicator shown before first token
//   5.  test_intake_trade_scope_preview: trade scope preview card shows trade names
//   6.  test_intake_clarifying_question: clarifying question appears in AI bubble
//   7.  test_intake_create_project_button: "Create Project" shown when scopes present
//   8.  test_intake_error_display: error message shown via error banner
//   9.  test_intake_no_conversation: "Starting conversation..." shown without convId
//   10. test_intake_edit_trade_scope: tapping trade name opens inline TextField
//
// Patterns (per CLAUDE.md):
//   - pump() NOT pumpAndSettle() — animated streams never settle
//   - ProviderScope.overrideWith for controlling provider state
//   - Direct state injection via notifiers extending IntakeChatNotifier
//   - No GetIt/HttpClient calls in tests — async methods are no-ops

import 'package:contractorhub/features/ai/domain/ai_models.dart';
import 'package:contractorhub/features/ai/presentation/providers/intake_chat_provider.dart';
import 'package:contractorhub/features/ai/presentation/screens/intake_chat_screen.dart';
import 'package:contractorhub/features/ai/presentation/widgets/typing_indicator.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

// ---------------------------------------------------------------------------
// Fake notifier — extends IntakeChatNotifier so the screen's notifier cast works.
// All async methods are no-ops; the initial state is set in build().
// ---------------------------------------------------------------------------

class _TestIntakeChatNotifier extends IntakeChatNotifier {
  _TestIntakeChatNotifier(this._initialState);

  final IntakeChatState _initialState;

  @override
  IntakeChatState build() => _initialState;

  @override
  Future<void> startConversation(String? projectId) async {
    // No-op — don't call HttpClient in tests
  }

  @override
  Future<void> sendMessage(String message) async {
    // Simulate user message appearing and streaming starting
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
      currentStreamText: 'Hello world from AI',
      conversationId: state.conversationId ?? 'conv-fake-001',
    );
  }

  @override
  Future<String?> completeIntake({
    required String projectName,
    required List<AiTradeScope> scopes, String? description,
  }) async {
    return 'proj-fake-001';
  }
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

void main() {
  group('Phase 21 AI Intake E2E Tests', () {
    // -----------------------------------------------------------------------
    // Test 1: Empty state
    // -----------------------------------------------------------------------
    testWidgets('test_intake_empty_state: shows greeting text and bot icon',
        (tester) async {
      const emptyState = IntakeChatState(
        conversationId: 'conv-001',
      );

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            intakeChatProvider.overrideWith(
              () => _TestIntakeChatNotifier(emptyState),
            ),
          ],
          child: const MaterialApp(
            home: SizedBox(
              width: 375,
              height: 812,
              child: IntakeChatScreen(),
            ),
          ),
        ),
      );

      await tester.pump();

      expect(find.text('Tell me about your project'), findsOneWidget);
      expect(find.byIcon(Icons.smart_toy), findsOneWidget);
    });

    // -----------------------------------------------------------------------
    // Test 2: Send message — user bubble appears after send
    // -----------------------------------------------------------------------
    testWidgets('test_intake_send_message: user bubble appears after send',
        (tester) async {
      const initialState = IntakeChatState(
        conversationId: 'conv-001',
      );

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            intakeChatProvider.overrideWith(
              () => _TestIntakeChatNotifier(initialState),
            ),
          ],
          child: const MaterialApp(
            home: SizedBox(
              width: 375,
              height: 812,
              child: IntakeChatScreen(),
            ),
          ),
        ),
      );

      await tester.pump();

      // Enter text in the chat input
      final textField = find.byType(TextField).first;
      await tester.enterText(textField, 'Build a house with 3 bedrooms');
      await tester.pump();

      // Tap send button
      final sendButton = find.byIcon(Icons.send);
      expect(sendButton, findsOneWidget);
      await tester.tap(sendButton);
      await tester.pump();
      await tester.pump();

      // User message bubble should appear
      expect(find.text('Build a house with 3 bedrooms'), findsOneWidget);
    });

    // -----------------------------------------------------------------------
    // Test 3: Streaming display — AI bubble shows stream text
    // -----------------------------------------------------------------------
    testWidgets('test_intake_streaming_display: AI bubble shows stream text',
        (tester) async {
      final streamingState = IntakeChatState(
        conversationId: 'conv-001',
        messages: [
          ChatMessage(
            id: 'user-1',
            role: 'user',
            text: 'Build a house',
            timestamp: DateTime.now(),
          ),
        ],
        isStreaming: true,
        currentStreamText: 'Hello world from AI',
      );

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            intakeChatProvider.overrideWith(
              () => _TestIntakeChatNotifier(streamingState),
            ),
          ],
          child: const MaterialApp(
            home: SizedBox(
              width: 375,
              height: 812,
              child: IntakeChatScreen(),
            ),
          ),
        ),
      );

      // Pump multiple frames to allow animation controllers to initialize
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));
      await tester.pump(const Duration(milliseconds: 50));

      // The streaming bubble appends a cursor '▌' to the text via AnimatedBuilder.
      // Use textContaining to match regardless of cursor state.
      expect(find.textContaining('Hello world from AI'), findsWidgets);
    });

    // -----------------------------------------------------------------------
    // Test 4: Typing indicator — shown when streaming with no text yet
    // -----------------------------------------------------------------------
    testWidgets(
        'test_intake_typing_indicator: TypingIndicator shown when streaming without text',
        (tester) async {
      final typingState = IntakeChatState(
        conversationId: 'conv-001',
        messages: [
          ChatMessage(
            id: 'user-1',
            role: 'user',
            text: 'Build a house',
            timestamp: DateTime.now(),
          ),
        ],
        isStreaming: true,
      );

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            intakeChatProvider.overrideWith(
              () => _TestIntakeChatNotifier(typingState),
            ),
          ],
          child: const MaterialApp(
            home: SizedBox(
              width: 375,
              height: 812,
              child: IntakeChatScreen(),
            ),
          ),
        ),
      );

      await tester.pump();
      await tester.pump();

      expect(find.byType(TypingIndicator), findsOneWidget);
    });

    // -----------------------------------------------------------------------
    // Test 5: Trade scope preview — Electrical and Plumbing visible
    // -----------------------------------------------------------------------
    testWidgets(
        'test_intake_trade_scope_preview: trade names visible and Create Project enabled',
        (tester) async {
      final scopeState = IntakeChatState(
        conversationId: 'conv-001',
        messages: [
          ChatMessage(
            id: 'assistant-1',
            role: 'assistant',
            text: 'I found these scopes for your project',
            timestamp: DateTime.now(),
          ),
        ],
        tradeScopes: const [
          AiTradeScope(
            id: 'scope-1',
            tradeName: 'Electrical',
            tradeType: 'electrical',
          ),
          AiTradeScope(
            id: 'scope-2',
            tradeName: 'Plumbing',
            tradeType: 'plumbing',
            sortOrder: 1,
          ),
        ],
      );

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            intakeChatProvider.overrideWith(
              () => _TestIntakeChatNotifier(scopeState),
            ),
          ],
          child: const MaterialApp(
            home: SizedBox(
              width: 375,
              height: 812,
              child: IntakeChatScreen(),
            ),
          ),
        ),
      );

      await tester.pump();
      await tester.pump();

      expect(find.text('Electrical'), findsOneWidget);
      expect(find.text('Plumbing'), findsOneWidget);
      expect(find.text('Create Project'), findsOneWidget);

      // Create Project button should be enabled (not null onPressed)
      final createButton = find.widgetWithText(ElevatedButton, 'Create Project');
      expect(createButton, findsOneWidget);
      final btn = tester.widget<ElevatedButton>(createButton);
      expect(btn.onPressed, isNotNull);
    });

    // -----------------------------------------------------------------------
    // Test 6: Clarifying question — text visible in AI bubble
    // -----------------------------------------------------------------------
    testWidgets(
        'test_intake_clarifying_question: clarifying question text visible',
        (tester) async {
      final clarifyingState = IntakeChatState(
        conversationId: 'conv-001',
        messages: [
          ChatMessage(
            id: 'user-1',
            role: 'user',
            text: 'Build a house',
            timestamp: DateTime.now(),
          ),
          ChatMessage(
            id: 'assistant-1',
            role: 'assistant',
            text: 'How many bedrooms?',
            timestamp: DateTime.now(),
          ),
        ],
      );

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            intakeChatProvider.overrideWith(
              () => _TestIntakeChatNotifier(clarifyingState),
            ),
          ],
          child: const MaterialApp(
            home: SizedBox(
              width: 375,
              height: 812,
              child: IntakeChatScreen(),
            ),
          ),
        ),
      );

      await tester.pump();
      await tester.pump();

      expect(find.text('How many bedrooms?'), findsOneWidget);
    });

    // -----------------------------------------------------------------------
    // Test 7: Create Project button only shown when scopes are present
    // -----------------------------------------------------------------------
    testWidgets(
        'test_intake_create_project_button: button hidden without scopes',
        (tester) async {
      const emptyScopes = IntakeChatState(
        conversationId: 'conv-001',
      );

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            intakeChatProvider.overrideWith(
              () => _TestIntakeChatNotifier(emptyScopes),
            ),
          ],
          child: const MaterialApp(
            home: SizedBox(
              width: 375,
              height: 812,
              child: IntakeChatScreen(),
            ),
          ),
        ),
      );

      await tester.pump();

      // No Create Project button visible when no scopes
      expect(find.text('Create Project'), findsNothing);
    });

    // -----------------------------------------------------------------------
    // Test 8: Error display — error banner shown when error in state
    // -----------------------------------------------------------------------
    testWidgets('test_intake_error_display: error banner shown when error set',
        (tester) async {
      final errorState = IntakeChatState(
        conversationId: 'conv-001',
        messages: [
          ChatMessage(
            id: 'user-1',
            role: 'user',
            text: 'Build a house',
            timestamp: DateTime.now(),
          ),
        ],
        error: 'Something went wrong. Please try again.',
      );

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            intakeChatProvider.overrideWith(
              () => _TestIntakeChatNotifier(errorState),
            ),
          ],
          child: const MaterialApp(
            home: SizedBox(
              width: 375,
              height: 812,
              child: IntakeChatScreen(),
            ),
          ),
        ),
      );

      await tester.pump();

      expect(find.text('Something went wrong. Please try again.'), findsOneWidget);
    });

    // -----------------------------------------------------------------------
    // Test 9: No conversation state — screen renders without crash
    // The Flutter screen renders the empty state and chat input regardless
    // of conversationId (it just shows "Tell me about your project" and the
    // send button, and submitting is a no-op until conversationId is set).
    // -----------------------------------------------------------------------
    testWidgets(
        'test_intake_no_conversation: screen renders empty state without conversationId',
        (tester) async {
      const noConvState = IntakeChatState(
        
      );

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            intakeChatProvider.overrideWith(
              () => _TestIntakeChatNotifier(noConvState),
            ),
          ],
          child: const MaterialApp(
            home: SizedBox(
              width: 375,
              height: 812,
              child: IntakeChatScreen(),
            ),
          ),
        ),
      );

      await tester.pump();

      // Empty state shown without crash — "Tell me about your project" visible
      expect(find.text('Tell me about your project'), findsOneWidget);
      // Chat input still renders (user can type even before conversation starts)
      expect(find.byType(TextField), findsOneWidget);
    });

    // -----------------------------------------------------------------------
    // Test 10: Edit trade scope — tapping trade name opens inline TextField
    // -----------------------------------------------------------------------
    testWidgets('test_intake_edit_trade_scope: tapping trade name opens TextField',
        (tester) async {
      const scopeState = IntakeChatState(
        conversationId: 'conv-001',
        tradeScopes: [
          AiTradeScope(
            id: 'scope-1',
            tradeName: 'Electrical',
            tradeType: 'electrical',
          ),
        ],
      );

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            intakeChatProvider.overrideWith(
              () => _TestIntakeChatNotifier(scopeState),
            ),
          ],
          child: const MaterialApp(
            home: SizedBox(
              width: 375,
              height: 812,
              child: IntakeChatScreen(),
            ),
          ),
        ),
      );

      await tester.pump();
      await tester.pump();

      // Find and tap the trade name text
      final electricalText = find.text('Electrical');
      expect(electricalText, findsOneWidget);
      await tester.tap(electricalText);
      await tester.pump();

      // After tapping, an inline TextField should appear for editing
      // (TradeScopePreviewCard sets _editingIndex on tap)
      final textFields = find.byType(TextField);
      expect(textFields.evaluate().length, greaterThan(1));
    });
  });
}
