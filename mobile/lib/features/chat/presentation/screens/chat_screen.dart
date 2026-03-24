import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/database/app_database.dart' show ChatThread;
import '../../../../core/routing/route_names.dart';
import '../../domain/chat_providers.dart';
import '../widgets/chat_thread_tile.dart';

/// Chat thread list screen — shows all conversations for a project.
///
/// Displays two sections:
///   - "Trade Conversations" — threads with threadType == 'scope'
///   - "Project Group" — threads with threadType == 'project_wide'
///
/// Threads are sorted by unread count descending, then lastMessageAt
/// descending. Tapping a thread pushes [ChatThreadScreen] via GoRouter.
/// Long-pressing opens a mute/unmute bottom sheet.
///
/// On init, performs a REST sync via [chatRepositoryProvider.fetchThreads]
/// to hydrate the local Drift cache. Reactive stream from
/// [chatThreadsProvider] drives the list.
class ChatScreen extends ConsumerStatefulWidget {
  const ChatScreen({required this.projectId, super.key});

  final String projectId;

  @override
  ConsumerState<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends ConsumerState<ChatScreen> {
  @override
  void initState() {
    super.initState();
    // Fetch threads from backend on open to hydrate local Drift cache.
    // Fire-and-forget: errors are non-fatal (Drift stream may already have data).
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref
          .read(chatRepositoryProvider)
          .fetchThreads(widget.projectId)
          .catchError((Object e) {
        debugPrint('[ChatScreen] fetchThreads error (non-fatal): $e');
      });
    });
  }

  @override
  Widget build(BuildContext context) {
    final threadsAsync = ref.watch(chatThreadsProvider(widget.projectId));

    return Scaffold(
      appBar: AppBar(
        title: Text(
          'Messages',
          style: Theme.of(context).textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.w600,
              ),
        ),
      ),
      body: threadsAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) => Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Text(
              'Error loading conversations: $error',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: Theme.of(context).colorScheme.error,
                  ),
            ),
          ),
        ),
        data: (threads) {
          if (threads.isEmpty) {
            return const _EmptyThreadsState();
          }

          // Split threads by type and sort each section
          final scopeThreads = threads
              .where((t) => t.threadType == 'scope')
              .toList()
            ..sort(_threadComparator);

          final projectThreads = threads
              .where((t) => t.threadType == 'project_wide')
              .toList()
            ..sort(_threadComparator);

          return ListView(
            children: [
              if (scopeThreads.isNotEmpty) ...[
                const _SectionHeader(label: 'Trade Conversations'),
                ...scopeThreads.indexed.map(
                  (entry) => ChatThreadTile(
                    thread: entry.$2,
                    tradeColorIndex: entry.$1,
                    onTap: () => _openThread(context, entry.$2),
                    onLongPress: () => _showThreadOptions(context, entry.$2),
                  ),
                ),
              ],
              if (projectThreads.isNotEmpty) ...[
                const _SectionHeader(label: 'Project Group'),
                ...projectThreads.map(
                  (t) => ChatThreadTile(
                    thread: t,
                    onTap: () => _openThread(context, t),
                    onLongPress: () => _showThreadOptions(context, t),
                  ),
                ),
              ],
            ],
          );
        },
      ),
    );
  }

  /// Comparator: unread count DESC, then lastMessageAt DESC.
  int _threadComparator(ChatThread a, ChatThread b) {
    if (b.unreadCount != a.unreadCount) {
      return b.unreadCount.compareTo(a.unreadCount);
    }
    final aTime = a.lastMessageAt;
    final bTime = b.lastMessageAt;
    if (aTime == null && bTime == null) return 0;
    if (aTime == null) return 1;
    if (bTime == null) return -1;
    return bTime.compareTo(aTime);
  }

  void _openThread(BuildContext context, ChatThread thread) {
    context.push(
      RouteNames.chatThreadPath(widget.projectId, thread.id),
    );
  }

  void _showThreadOptions(BuildContext context, ChatThread thread) {
    // TODO: persist muted state in Drift/backend when mute feature ships.
    // For now, the bottom sheet is wired but muted state is not stored.
    showModalBottomSheet<void>(
      context: context,
      builder: (_) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.notifications_off),
              title: const Text('Mute Conversation'),
              onTap: () {
                Navigator.of(context).pop();
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('Mute — coming soon'),
                    duration: Duration(seconds: 2),
                  ),
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Private widgets
// ---------------------------------------------------------------------------

/// Section header for the thread list.
class _SectionHeader extends StatelessWidget {
  const _SectionHeader({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final colorScheme = Theme.of(context).colorScheme;

    return Padding(
      padding: const EdgeInsets.only(
        left: 16,
        right: 16,
        top: 24,
        bottom: 4,
      ),
      child: Text(
        label,
        style: textTheme.bodySmall?.copyWith(
          color: colorScheme.onSurface.withValues(alpha: 0.5),
          fontWeight: FontWeight.w400,
        ),
      ),
    );
  }
}

/// Empty state shown when there are no threads for this project.
class _EmptyThreadsState extends StatelessWidget {
  const _EmptyThreadsState();

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final colorScheme = Theme.of(context).colorScheme;

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.chat_bubble_outline,
              size: 64,
              color: colorScheme.onSurface.withValues(alpha: 0.3),
            ),
            const SizedBox(height: 16),
            Text(
              'No conversations yet',
              style: textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w600,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              'Conversations are created automatically when a contractor '
              'is assigned to a trade scope.',
              style: textTheme.bodyMedium?.copyWith(
                color: colorScheme.onSurface.withValues(alpha: 0.6),
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}
