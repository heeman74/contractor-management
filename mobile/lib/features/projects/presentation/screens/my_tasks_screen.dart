import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/database/app_database.dart'
    hide UserRole, BookingDao, NoteDao, AttachmentDao, TimeEntryDao,
        QuoteDao, InvoiceDao;
import '../../../../core/routing/route_names.dart';
import '../../../../features/auth/domain/auth_state.dart';
import '../../../../features/auth/presentation/providers/auth_provider.dart';
import '../providers/project_providers.dart';
import '../widgets/task_checklist_card.dart';
import '../widgets/task_scope_group_header.dart';

/// Contractor cross-scope task checklist.
///
/// Shows ALL incomplete tasks assigned to the current contractor,
/// grouped by trade scope with collapsible section headers.
///
/// Sort order within each group:
/// 1. Overdue tasks first (dueDate < now)
/// 2. Priority order (urgent → high → medium → low)
/// 3. Due date ASC, nulls last
///
/// Collapsed state lives in widget state — not persisted to Drift.
class MyTasksScreen extends ConsumerStatefulWidget {
  const MyTasksScreen({super.key});

  @override
  ConsumerState<MyTasksScreen> createState() => _MyTasksScreenState();
}

class _MyTasksScreenState extends ConsumerState<MyTasksScreen> {
  /// Tracks which scope groups are collapsed.
  /// Key: tradeScopeId, Value: true = collapsed
  final Map<String, bool> _collapsed = {};

  @override
  Widget build(BuildContext context) {
    final authState = ref.watch(authNotifierProvider);

    if (authState is! AuthAuthenticated) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    final userId = authState.userId;
    final companyId = authState.companyId;

    final tasksAsync = ref.watch(myTasksProvider(userId));
    final scopeMapAsync = ref.watch(scopeNameMapProvider(companyId));

    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'My Tasks',
          style: TextStyle(fontWeight: FontWeight.w600),
        ),
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
            return _EmptyTasksState();
          }

          final scopeMap = scopeMapAsync.value ?? {};

          // Group tasks by tradeScopeId
          final grouped = <String, List<ProjectTask>>{};
          for (final task in tasks) {
            grouped.putIfAbsent(task.tradeScopeId, () => []).add(task);
          }

          // Sort tasks within each group
          for (final entry in grouped.entries) {
            entry.value.sort(_compareTaskOrder);
          }

          // Build the list sections
          final sectionKeys = grouped.keys.toList();

          return ListView.builder(
            padding: const EdgeInsets.only(bottom: 24),
            itemCount: sectionKeys.length,
            itemBuilder: (context, index) {
              final scopeId = sectionKeys[index];
              final scopeTasks = grouped[scopeId]!;
              final tradeName = scopeMap[scopeId] ?? 'Trade Scope';
              final completedCount =
                  scopeTasks.where((t) => t.status == 'complete').length;
              final isCollapsed = _collapsed[scopeId] ?? false;

              return Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TaskScopeGroupHeader(
                    tradeName: tradeName,
                    completedCount: completedCount,
                    totalCount: scopeTasks.length,
                    isCollapsed: isCollapsed,
                    onToggle: () {
                      setState(() {
                        _collapsed[scopeId] = !isCollapsed;
                      });
                    },
                  ),
                  if (!isCollapsed)
                    ...scopeTasks.map(
                      (task) => TaskChecklistCard(
                        task: task,
                        onTap: () => context
                            .push(RouteNames.taskDetailPath(task.id)),
                      ),
                    ),
                ],
              );
            },
          );
        },
      ),
    );
  }

  /// Compare tasks for display order within a scope group.
  ///
  /// Order: overdue first → priority (urgent=0 … low=3) → dueDate ASC nulls last
  static int _compareTaskOrder(ProjectTask a, ProjectTask b) {
    final now = DateTime.now();
    final aOverdue = a.dueDate != null && a.dueDate!.isBefore(now);
    final bOverdue = b.dueDate != null && b.dueDate!.isBefore(now);

    if (aOverdue && !bOverdue) return -1;
    if (!aOverdue && bOverdue) return 1;

    final aPriority = _priorityOrder(a.priority);
    final bPriority = _priorityOrder(b.priority);
    if (aPriority != bPriority) return aPriority.compareTo(bPriority);

    if (a.dueDate == null && b.dueDate == null) return 0;
    if (a.dueDate == null) return 1;
    if (b.dueDate == null) return -1;
    return a.dueDate!.compareTo(b.dueDate!);
  }

  static int _priorityOrder(String priority) {
    return switch (priority) {
      'urgent' => 0,
      'high' => 1,
      'medium' => 2,
      'low' => 3,
      _ => 4,
    };
  }
}

class _EmptyTasksState extends StatelessWidget {
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
              Icons.task_alt,
              size: 72,
              color: colorScheme.onSurface.withValues(alpha: 0.3),
            ),
            const SizedBox(height: 16),
            Text(
              'No tasks assigned',
              style: textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w600,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              'You have no pending tasks. Check back after your project manager assigns work.',
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
