import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/database/app_database.dart' show TradeScope;
import '../../../../core/routing/route_names.dart';
import '../providers/project_providers.dart';
import '../widgets/project_status_badge.dart';
import '../widgets/task_thumbnail_row.dart';

/// Trade scope detail screen — shows the task list for a trade scope.
///
/// Displays:
/// - AppBar with trade name
/// - ListView of task rows with priority left border, title, status badge, due date
/// - Task detail bottom sheet (stub) on task tap
/// - Empty state when no tasks exist
class TradeScopeDetailScreen extends ConsumerWidget {
  const TradeScopeDetailScreen({
    required this.projectId,
    required this.scopeId,
    super.key,
  });

  final String projectId;
  final String scopeId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Get scope info from the parent project's scopes provider
    final scopesAsync = ref.watch(tradeScopesProvider(projectId));
    final tasksAsync = ref.watch(tasksProvider(scopeId));

    // Extract scope from cached async state without triggering loading indicator
    TradeScope? scope;
    if (scopesAsync is AsyncData<List<TradeScope>>) {
      scope = scopesAsync.value
          .where((s) => s.id == scopeId)
          .firstOrNull;
    }

    final scopeName = scope?.tradeName ?? 'Trade Scope';

    return Scaffold(
      appBar: AppBar(
        title: Text(scopeName),
      ),
      body: tasksAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) => Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Text(
              'Error loading tasks: $error',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: Theme.of(context).colorScheme.error,
                  ),
            ),
          ),
        ),
        data: (tasks) {
          if (tasks.isEmpty) {
            return _EmptyTasksState(
              scopeId: scopeId,
              tradeName: scopeName,
            );
          }
          return ListView.builder(
            padding: const EdgeInsets.symmetric(vertical: 8),
            itemCount: tasks.length,
            itemBuilder: (context, index) {
              final task = tasks[index];
              return _TaskRow(
                taskId: task.id,
                title: task.title,
                status: task.status,
                priority: task.priority,
                dueDate: task.dueDate,
                description: task.description,
                onTap: () => _showTaskDetailStub(context, task.title, task.description),
              );
            },
          );
        },
      ),
    );
  }

  void _showTaskDetailStub(
      BuildContext context, String title, String? description) {
    showModalBottomSheet<void>(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) => Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
            ),
            if (description != null && description.isNotEmpty) ...[
              const SizedBox(height: 8),
              Text(
                description,
                style: Theme.of(context).textTheme.bodyMedium,
              ),
            ],
            const SizedBox(height: 16),
            Text(
              'Task detail — coming soon',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Theme.of(context)
                        .colorScheme
                        .onSurface
                        .withValues(alpha: 0.5),
                  ),
            ),
            const SizedBox(height: 24),
          ],
        ),
      ),
    );
  }
}

/// A single task row in the scope detail list (GC read-only view).
///
/// Has a 4px priority left border:
/// - urgent: red
/// - high: orange
/// - medium: blue
/// - low: grey
///
/// Per D-15: shows [TaskThumbnailRow] below the title/status line so the GC
/// can see quick visual progress without opening each task.
class _TaskRow extends StatelessWidget {
  const _TaskRow({
    required this.taskId,
    required this.title,
    required this.status,
    required this.priority,
    required this.onTap,
    this.dueDate,
    this.description,
  });

  final String taskId;
  final String title;
  final String status;
  final String priority;
  final DateTime? dueDate;
  final String? description;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final colorScheme = Theme.of(context).colorScheme;
    final priorityColor = _priorityColor(priority);

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      elevation: 1,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(10),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(10),
          child: IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Priority left border — 4px wide
                Container(
                  width: 4,
                  color: priorityColor,
                ),
                // Task content
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 12, vertical: 12),
                    child: Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                title,
                                style: textTheme.bodyMedium?.copyWith(
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                              if (dueDate != null) ...[
                                const SizedBox(height: 4),
                                Text(
                                  'Due ${_formatDate(dueDate!)}',
                                  style: textTheme.bodySmall?.copyWith(
                                    color: colorScheme.onSurface
                                        .withValues(alpha: 0.5),
                                  ),
                                ),
                              ],
                              // D-15: Photo thumbnails for quick visual progress
                              const SizedBox(height: 4),
                              TaskThumbnailRow(taskId: taskId),
                            ],
                          ),
                        ),
                        const SizedBox(width: 8),
                        ProjectStatusBadge(status: status),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  static Color _priorityColor(String priority) {
    return switch (priority) {
      'urgent' => const Color(0xFFD32F2F), // red
      'high' => const Color(0xFFF57C00), // orange
      'medium' => const Color(0xFF1565C0), // blue
      'low' => const Color(0xFF9E9E9E), // grey
      _ => const Color(0xFF9E9E9E),
    };
  }

  static String _formatDate(DateTime dt) {
    return '${dt.day}/${dt.month}/${dt.year}';
  }
}

class _EmptyTasksState extends StatelessWidget {
  const _EmptyTasksState({
    required this.scopeId,
    required this.tradeName,
  });

  final String scopeId;
  final String tradeName;

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
              Icons.check_circle_outline,
              size: 64,
              color: colorScheme.onSurface.withValues(alpha: 0.3),
            ),
            const SizedBox(height: 16),
            Text(
              'No tasks yet',
              style: textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w600,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              'Use AI Interview to generate a detailed task plan for this trade scope.',
              style: textTheme.bodyMedium?.copyWith(
                color: colorScheme.onSurface.withValues(alpha: 0.6),
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),
            // Start Interview button — visible when no tasks exist
            ElevatedButton.icon(
              onPressed: () {
                context.push(
                  '${RouteNames.aiInterviewPath(scopeId)}?tradeName=${Uri.encodeComponent(tradeName)}',
                );
              },
              icon: const Icon(Icons.smart_toy),
              label: const Text('Start AI Interview'),
            ),
          ],
        ),
      ),
    );
  }
}
