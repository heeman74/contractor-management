import 'dart:async';

import 'package:drift/drift.dart' as drift;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/database/app_database.dart'
    show
        ChatDao,
        ChatMessage,
        ChatMessagesCompanion,
        ChatReadReceiptsCompanion;
import '../../data/chat_ws_client.dart';
import '../../domain/chat_providers.dart';
import '../widgets/chat_input_bar.dart';
import '../widgets/message_bubble.dart';
import '../widgets/typing_indicator.dart';

/// Full-screen chat thread — message list + input bar with WebSocket connection.
///
/// Connects to the backend WebSocket via [ChatWsClient] on initState.
/// Listens to the WS message stream and:
///   - 'message'      → inserts message into Drift via ChatDao
///   - 'typing'       → shows [TypingIndicator]; auto-hides after 3 seconds
///   - 'read_receipt' → upserts read receipt into Drift
///   - 'reconnected'  → fetches missed messages since last seq
///
/// Messages are displayed in a reversed [ListView.builder] (newest at
/// bottom) driven by [chatMessagesProvider] (reactive Drift stream).
///
/// Date separators are inserted between messages from different days.
/// Scrolling past the oldest visible message triggers pagination.
class ChatThreadScreen extends ConsumerStatefulWidget {
  const ChatThreadScreen({
    required this.threadId,
    required this.projectId,
    super.key,
  });

  final String threadId;
  final String projectId;

  @override
  ConsumerState<ChatThreadScreen> createState() => _ChatThreadScreenState();
}

class _ChatThreadScreenState extends ConsumerState<ChatThreadScreen> {
  ChatWsClient? _wsClient;
  StreamSubscription<Map<String, dynamic>>? _wsSub;
  Timer? _typingTimer;
  String? _typingUserName;

  final ScrollController _scrollController = ScrollController();
  bool _isLoadingOlder = false;

  @override
  void initState() {
    super.initState();
    _initWebSocket();
    _scrollController.addListener(_onScroll);
  }

  void _initWebSocket() {
    // Get the per-thread WS client from Riverpod (autoDispose.family).
    // The provider already called connect(threadId) on creation.
    _wsClient = ref.read(chatWsClientProvider(widget.threadId));
    _wsSub = _wsClient!.messages.listen(_onWsMessage);

    // Send read receipt for the current last message on screen enter.
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) return;
      final dao = ref.read(chatDaoProvider);
      final lastSeq = await dao.getLastSeq(widget.threadId);
      if (lastSeq > 0 && mounted) {
        _wsClient?.sendRead(lastSeq);
      }
    });
  }

  Future<void> _onWsMessage(Map<String, dynamic> msg) async {
    if (!mounted) return;
    final type = msg['type'] as String?;

    switch (type) {
      case 'message':
        // Insert into Drift — Riverpod stream will trigger UI rebuild.
        final dao = ref.read(chatDaoProvider);
        await _insertWsMessage(dao, msg);

      case 'typing':
        final senderName = msg['sender_name'] as String? ?? 'Someone';
        setState(() {
          _typingUserName = senderName.split(' ').first;
        });
        _typingTimer?.cancel();
        _typingTimer = Timer(const Duration(seconds: 3), () {
          if (mounted) {
            setState(() => _typingUserName = null);
          }
        });

      case 'read_receipt':
        final dao = ref.read(chatDaoProvider);
        final userId = msg['user_id'] as String?;
        final seq = msg['seq'] as int?;
        if (userId != null && seq != null) {
          await dao.upsertReadReceipt(
            ChatReadReceiptsCompanion(
              userId: drift.Value(userId),
              threadId: drift.Value(widget.threadId),
              lastReadSeq: drift.Value(seq),
              readAt: drift.Value(DateTime.now()),
            ),
          );
        }

      case 'reconnected':
        // Fetch messages missed during the disconnection window.
        final dao = ref.read(chatDaoProvider);
        final lastSeq = await dao.getLastSeq(widget.threadId);
        final repo = ref.read(chatRepositoryProvider);
        await repo.fetchMissedMessages(widget.threadId, lastSeq).catchError(
          (Object e) {
            debugPrint('[ChatThreadScreen] fetchMissedMessages error: $e');
          },
        );
    }
  }

  Future<void> _insertWsMessage(
    ChatDao dao,
    Map<String, dynamic> msg,
  ) async {
    final data = msg['data'];
    if (data is! Map<String, dynamic>) return;
    try {
      await dao.insertMessage(
        ChatMessagesCompanion(
          id: drift.Value(data['id'] as String),
          companyId: drift.Value(data['company_id'] as String? ?? ''),
          threadId: drift.Value(widget.threadId),
          senderId: drift.Value(data['sender_id'] as String? ?? ''),
          senderName: drift.Value(data['sender_name'] as String? ?? ''),
          content: drift.Value(data['content'] as String?),
          seq: drift.Value(data['seq'] as int? ?? 0),
          attachmentUrl: drift.Value(data['attachment_url'] as String?),
          attachmentType: drift.Value(data['attachment_type'] as String?),
          annotationData: drift.Value(data['annotation_data'] as String?),
          mentions: drift.Value((data['mentions'] as String?) ?? '[]'),
          mentionAll: drift.Value((data['mention_all'] as bool?) ?? false),
          status: const drift.Value('sent'),
          createdAt: drift.Value(
            DateTime.tryParse(data['created_at'] as String? ?? '') ??
                DateTime.now(),
          ),
        ),
      );
    } catch (e) {
      debugPrint('[ChatThreadScreen] insertWsMessage error: $e');
    }
  }

  void _onScroll() {
    // Scroll past the "top" of the reversed list → load older messages.
    // In a reversed ListView, maxScrollExtent is the "top" (oldest msgs).
    if (_scrollController.position.pixels >=
            _scrollController.position.maxScrollExtent - 20 &&
        !_isLoadingOlder) {
      _loadOlderMessages();
    }
  }

  Future<void> _loadOlderMessages() async {
    setState(() => _isLoadingOlder = true);
    try {
      final dao = ref.read(chatDaoProvider);
      final messages = await dao.watchMessages(widget.threadId).first;
      if (messages.isEmpty) return;

      final firstSeq = messages.first.seq;
      final repo = ref.read(chatRepositoryProvider);
      await repo
          .fetchMessages(widget.threadId, beforeSeq: firstSeq)
          .catchError((Object e) {
        debugPrint('[ChatThreadScreen] loadOlderMessages error: $e');
      });
    } finally {
      if (mounted) setState(() => _isLoadingOlder = false);
    }
  }

  @override
  void dispose() {
    _wsSub?.cancel();
    _typingTimer?.cancel();
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final messagesAsync = ref.watch(chatMessagesProvider(widget.threadId));

    return Scaffold(
      resizeToAvoidBottomInset: true,
      appBar: AppBar(
        title: Text(
          'Chat',
          style: Theme.of(context).textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w600,
              ),
        ),
      ),
      body: Column(
        children: [
          // Message list (reversed — newest at bottom)
          Expanded(
            child: messagesAsync.when(
              loading: () =>
                  const Center(child: CircularProgressIndicator()),
              error: (error, _) => Center(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Text(
                    'Error loading messages: $error',
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: Theme.of(context).colorScheme.error,
                        ),
                  ),
                ),
              ),
              data: (messages) {
                if (messages.isEmpty && !_isLoadingOlder) {
                  return const Center(
                    child: Text('No messages yet. Say hello!'),
                  );
                }

                // Reversed: index 0 shows newest (at screen bottom)
                final reversed = messages.reversed.toList();
                final typingShown = _typingUserName != null;
                final loadingShown = _isLoadingOlder;
                final itemCount = reversed.length +
                    (typingShown ? 1 : 0) +
                    (loadingShown ? 1 : 0);

                return ListView.builder(
                  controller: _scrollController,
                  reverse: true,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 8,
                  ),
                  itemCount: itemCount,
                  itemBuilder: (context, index) {
                    // Typing indicator is at the bottom (index 0 in reversed)
                    if (typingShown && index == 0) {
                      return TypingIndicator(
                        typingUserName: _typingUserName,
                      );
                    }

                    // Adjust index past typing indicator slot
                    final adjustedIndex = typingShown ? index - 1 : index;

                    // "Load older messages" spinner at the very top
                    if (loadingShown &&
                        adjustedIndex == reversed.length) {
                      return const Padding(
                        padding: EdgeInsets.all(16),
                        child: Center(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              CircularProgressIndicator(),
                              SizedBox(height: 8),
                              Text('Load older messages'),
                            ],
                          ),
                        ),
                      );
                    }

                    if (adjustedIndex < 0 ||
                        adjustedIndex >= reversed.length) {
                      return const SizedBox.shrink();
                    }

                    final message = reversed[adjustedIndex];

                    // Insert date separator between messages on different days
                    final nextIndex = adjustedIndex + 1;
                    bool showDateSeparator = false;
                    if (nextIndex < reversed.length) {
                      showDateSeparator = !_isSameDay(
                        message.createdAt,
                        reversed[nextIndex].createdAt,
                      );
                    }

                    return Column(
                      children: [
                        MessageBubble(
                          message: message,
                          isOwn: _isOwnMessage(message),
                        ),
                        if (showDateSeparator)
                          _DateSeparator(
                            date: reversed[nextIndex].createdAt,
                          ),
                      ],
                    );
                  },
                );
              },
            ),
          ),

          // Chat input bar
          ChatInputBar(
            threadName: 'Chat',
            wsClient: _wsClient,
            threadId: widget.threadId,
          ),
        ],
      ),
    );
  }

  bool _isOwnMessage(ChatMessage message) {
    // TODO: compare message.senderId against current user ID from auth state.
    // Placeholder — wired in a follow-up plan.
    return false;
  }

  bool _isSameDay(DateTime a, DateTime b) {
    return a.year == b.year && a.month == b.month && a.day == b.day;
  }
}

// ---------------------------------------------------------------------------
// Date separator widget
// ---------------------------------------------------------------------------

class _DateSeparator extends StatelessWidget {
  const _DateSeparator({required this.date});

  final DateTime date;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final colorScheme = Theme.of(context).colorScheme;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Row(
        children: [
          Expanded(
            child: Divider(
              color: colorScheme.onSurface.withValues(alpha: 0.15),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
              decoration: BoxDecoration(
                color: colorScheme.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(
                _formatDate(date),
                style: textTheme.bodySmall?.copyWith(
                  color: colorScheme.onSurface.withValues(alpha: 0.6),
                ),
              ),
            ),
          ),
          Expanded(
            child: Divider(
              color: colorScheme.onSurface.withValues(alpha: 0.15),
            ),
          ),
        ],
      ),
    );
  }

  String _formatDate(DateTime dt) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final msgDay = DateTime(dt.year, dt.month, dt.day);
    final diff = today.difference(msgDay).inDays;

    if (diff == 0) return 'Today';
    if (diff == 1) return 'Yesterday';

    const months = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
    ];
    return '${months[dt.month - 1]} ${dt.day}';
  }
}
