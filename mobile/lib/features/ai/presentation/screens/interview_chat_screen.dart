import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../domain/ai_models.dart';
import '../providers/interview_chat_provider.dart';
import '../widgets/chat_bubble.dart';
import '../widgets/chat_input_bar.dart';
import '../widgets/task_preview_list.dart';
import '../widgets/typing_indicator.dart';

/// Contractor AI Interview chat screen.
///
/// The contractor answers AI questions about their trade scope.
/// The AI generates a task plan (list of AiTaskPreviews) which appears
/// in a DraggableScrollableSheet below the chat.
///
/// Route: RouteNames.aiInterview + /:scopeId
class InterviewChatScreen extends ConsumerStatefulWidget {
  const InterviewChatScreen({
    required this.scopeId,
    this.tradeName,
    super.key,
  });

  /// Trade scope ID — drives the interview conversation.
  final String scopeId;

  /// Display name of the trade (shown in AppBar and copy).
  final String? tradeName;

  @override
  ConsumerState<InterviewChatScreen> createState() =>
      _InterviewChatScreenState();
}

class _InterviewChatScreenState extends ConsumerState<InterviewChatScreen> {
  final ScrollController _scrollController = ScrollController();
  bool _taskSheetVisible = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref
          .read(interviewChatProvider(widget.scopeId).notifier)
          .startInterview(tradeName: widget.tradeName);
    });
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final chatState = ref.watch(interviewChatProvider(widget.scopeId));
    final displayTradeName =
        chatState.tradeName ?? widget.tradeName ?? 'Trade Interview';

    // Show task sheet when tasks appear
    if (chatState.tasks.isNotEmpty && !_taskSheetVisible) {
      _taskSheetVisible = true;
    }

    // Scroll to bottom on new messages or stream updates
    ref.listen<InterviewChatState>(
        interviewChatProvider(widget.scopeId), (previous, next) {
      if (previous?.messages.length != next.messages.length ||
          previous?.currentStreamText != next.currentStreamText) {
        _scrollToBottom();
      }
    });

    return Scaffold(
      appBar: AppBar(
        title: Text(
          'AI Interview - $displayTradeName',
          style: Theme.of(context).textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w600,
              ),
        ),
        centerTitle: false,
      ),
      body: Stack(
        children: [
          // Main chat area
          Column(
            children: [
              // Error banner
              if (chatState.error != null)
                _ErrorBanner(message: chatState.error!),

              // Message list
              Expanded(
                child: chatState.messages.isEmpty && !chatState.isStreaming
                    ? _EmptyState(tradeName: displayTradeName)
                    : ListView.builder(
                        controller: _scrollController,
                        padding: EdgeInsets.only(
                          top: 8,
                          bottom: _taskSheetVisible ? 200 : 16,
                        ),
                        itemCount: chatState.messages.length +
                            (chatState.isStreaming ? 1 : 0),
                        itemBuilder: (context, index) {
                          // Streaming bubble (appended at end)
                          if (chatState.isStreaming &&
                              index == chatState.messages.length) {
                            if (chatState.currentStreamText.isNotEmpty) {
                              return ChatBubble(
                                message: ChatMessage(
                                  id: 'streaming',
                                  role: 'assistant',
                                  text: chatState.currentStreamText,
                                ),
                                isStreaming: true,
                              );
                            }
                            return const TypingIndicator();
                          }
                          return ChatBubble(
                            message: chatState.messages[index],
                          );
                        },
                      ),
              ),

              // Chat input bar
              ChatInputBar(
                onSend: (message) {
                  ref
                      .read(interviewChatProvider(widget.scopeId).notifier)
                      .sendMessage(message);
                },
                isStreaming: chatState.isStreaming,
                isOffline: false, // TODO: wire connectivity_plus
                placeholder: 'Answer the AI\'s questions...',
              ),
            ],
          ),

          // Task preview sheet (slides up when tasks appear)
          if (_taskSheetVisible && chatState.tasks.isNotEmpty)
            DraggableScrollableSheet(
              initialChildSize: 0.4,
              minChildSize: 0.1,
              maxChildSize: 0.85,
              builder: (context, scrollController) {
                return Container(
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.surface,
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.1),
                        blurRadius: 8,
                        offset: const Offset(0, -2),
                      ),
                    ],
                    borderRadius: const BorderRadius.vertical(
                      top: Radius.circular(16),
                    ),
                  ),
                  child: SingleChildScrollView(
                    controller: scrollController,
                    child: TaskPreviewList(
                      tasks: chatState.tasks,
                      tradeName: displayTradeName,
                      onTasksChanged: (updatedTasks) {
                        // Tasks are edited locally in TaskPreviewList widget state
                        // and passed to completeInterview on Accept Plan
                      },
                      onAcceptPlan: () =>
                          _handleAcceptPlan(context, chatState.tasks),
                      onRestartInterview: () => ref
                          .read(interviewChatProvider(widget.scopeId).notifier)
                          .restartInterview(tradeName: widget.tradeName),
                    ),
                  ),
                );
              },
            ),
        ],
      ),
    );
  }

  Future<void> _handleAcceptPlan(
    BuildContext context,
    List<AiTaskPreview> tasks,
  ) async {
    final taskIds = await ref
        .read(interviewChatProvider(widget.scopeId).notifier)
        .completeInterview(tasks);

    if (taskIds.isNotEmpty && context.mounted) {
      // Navigate back to trade scope detail
      context.pop();
    }
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.tradeName});

  final String tradeName;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.smart_toy,
              size: 48,
              color: colorScheme.primary,
            ),
            const SizedBox(height: 16),
            Text(
              'Let\'s build your task plan',
              style: textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w600,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              'I\'ll ask you a few questions about your $tradeName scope to create a detailed task plan.',
              style: textTheme.bodyMedium?.copyWith(
                color: colorScheme.onSurfaceVariant,
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}

class _ErrorBanner extends StatelessWidget {
  const _ErrorBanner({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Container(
      width: double.infinity,
      color: colorScheme.errorContainer,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Row(
        children: [
          Icon(Icons.error_outline, size: 16, color: colorScheme.error),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              message,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: colorScheme.onErrorContainer,
                  ),
            ),
          ),
        ],
      ),
    );
  }
}
