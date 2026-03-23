import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/routing/route_names.dart';
import '../../domain/ai_models.dart';
import '../providers/intake_chat_provider.dart';
import '../widgets/chat_bubble.dart';
import '../widgets/chat_input_bar.dart';
import '../widgets/trade_scope_preview_card.dart';
import '../widgets/typing_indicator.dart';

/// GC AI Intake chat screen.
///
/// Allows the General Contractor to describe a project in natural language.
/// The AI responds with clarifying questions and ultimately generates a
/// trade breakdown (list of AiTradeScopes) which appears in a
/// DraggableScrollableSheet below the chat.
///
/// Route: RouteNames.aiIntake (with optional projectId query param)
class IntakeChatScreen extends ConsumerStatefulWidget {
  const IntakeChatScreen({
    this.projectId,
    super.key,
  });

  /// Optional: resume/extend an existing project's intake conversation.
  final String? projectId;

  @override
  ConsumerState<IntakeChatScreen> createState() => _IntakeChatScreenState();
}

class _IntakeChatScreenState extends ConsumerState<IntakeChatScreen> {
  final ScrollController _scrollController = ScrollController();
  bool _previewSheetVisible = false;

  @override
  void initState() {
    super.initState();
    // Start conversation after first frame to allow provider initialization
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref
          .read(intakeChatProvider.notifier)
          .startConversation(widget.projectId);
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
    final chatState = ref.watch(intakeChatProvider);

    // Show preview sheet when trade scopes appear
    if (chatState.tradeScopes.isNotEmpty && !_previewSheetVisible) {
      _previewSheetVisible = true;
    }

    // Scroll to bottom on new messages
    ref.listen<IntakeChatState>(intakeChatProvider, (previous, next) {
      if (previous?.messages.length != next.messages.length ||
          previous?.currentStreamText != next.currentStreamText) {
        _scrollToBottom();
      }
    });

    return Scaffold(
      appBar: AppBar(
        title: Text(
          widget.projectId != null ? 'AI Intake' : 'AI Intake',
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
                    ? _EmptyState()
                    : ListView.builder(
                        controller: _scrollController,
                        padding: EdgeInsets.only(
                          top: 8,
                          bottom: _previewSheetVisible ? 200 : 16,
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
                      .read(intakeChatProvider.notifier)
                      .sendMessage(message);
                },
                isStreaming: chatState.isStreaming,
                isOffline: false, // TODO: wire connectivity_plus
                placeholder: 'Describe your project...',
                onAttach: () {
                  // TODO: Phase 22 — image attachment
                },
              ),
            ],
          ),

          // Trade scope preview sheet (slides up when scopes appear)
          if (_previewSheetVisible && chatState.tradeScopes.isNotEmpty)
            DraggableScrollableSheet(
              initialChildSize: 0.4,
              minChildSize: 0.1,
              maxChildSize: 0.8,
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
                    child: _buildTradeScopePreview(context, chatState),
                  ),
                );
              },
            ),
        ],
      ),
    );
  }

  Widget _buildTradeScopePreview(
    BuildContext context,
    IntakeChatState chatState,
  ) {
    // Mutable local copy for editing
    final scopes = List<AiTradeScope>.from(chatState.tradeScopes);

    return TradeScopePreviewCard(
      scopes: chatState.tradeScopes,
      onScopeReordered: (oldIndex, newIndex) {
        if (newIndex > oldIndex) newIndex--;
        final reordered = List<AiTradeScope>.from(scopes);
        final item = reordered.removeAt(oldIndex);
        reordered.insert(newIndex, item);
        // Update provider state via notifier
        // For now, the ordering is reflected in the UI only
        // (server will accept the ordered list on complete)
      },
      onScopeDeleted: (index) {
        // No direct method yet — will be added when needed
      },
      onScopeRenamed: (index, newName) {
        // No direct method yet — will be added when needed
      },
      onCreateProject: () => _showCreateProjectDialog(context, chatState),
    );
  }

  Future<void> _showCreateProjectDialog(
    BuildContext context,
    IntakeChatState chatState,
  ) async {
    final nameController = TextEditingController();
    final confirmed = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Create Project'),
        content: TextField(
          controller: nameController,
          autofocus: true,
          decoration: const InputDecoration(
            labelText: 'Project Name',
            hintText: 'e.g., Office Renovation',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, nameController.text.trim()),
            child: const Text('Create'),
          ),
        ],
      ),
    );

    if (confirmed != null && confirmed.isNotEmpty && context.mounted) {
      final projectId = await ref
          .read(intakeChatProvider.notifier)
          .completeIntake(
            projectName: confirmed,
            scopes: chatState.tradeScopes,
          );

      if (projectId != null && context.mounted) {
        context.go(RouteNames.projectDetailPath(projectId));
      }
    }
  }
}

class _EmptyState extends StatelessWidget {
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
              'Tell me about your project',
              style: textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w600,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              'Describe what you\'re building and I\'ll help break it down into trade scopes.',
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

