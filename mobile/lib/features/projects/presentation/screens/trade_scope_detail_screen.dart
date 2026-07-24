import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/database/app_database.dart'
    show TradeScope, ProjectTask, PunchListItem;
import '../../../../core/routing/route_names.dart';
import '../../../../features/auth/domain/auth_state.dart';
import '../../../../features/auth/presentation/providers/auth_provider.dart';
import '../../../../shared/models/user_role.dart';
import '../providers/project_providers.dart';
import '../widgets/empty_tasks_state.dart';
import '../widgets/punch_item_detail_sheet.dart';
import '../widgets/punch_list_card.dart';
import '../widgets/scope_billing_section.dart';
import '../widgets/task_row.dart';

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
    final scopesAsync = ref.watch(tradeScopesProvider(projectId));
    final tasksAsync = ref.watch(tasksProvider(scopeId));
    final punchItemsAsync = ref.watch(punchItemsByScopeProvider(scopeId));
    final authState = ref.watch(authNotifierProvider);

    final scopeName = _resolveScopeName(scopesAsync);
    final isGcOrAdmin = authState is AuthAuthenticated &&
        authState.roles.contains(UserRole.admin);

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
          final punchItems = punchItemsAsync.value ?? [];

          if (tasks.isEmpty && punchItems.isEmpty) {
            return EmptyTasksState(
              scopeId: scopeId,
              tradeName: scopeName,
            );
          }

          return _TaskList(
            scopeId: scopeId,
            tasks: tasks,
            punchItems: punchItems,
            scopeName: scopeName,
            isGcOrAdmin: isGcOrAdmin,
            onTaskTap: (taskId) =>
                context.push(RouteNames.taskDetailPath(taskId)),
            onPunchItemTap: (item) =>
                _showPunchItemDetail(context, item, ref, isGcOrAdmin),
          );
        },
      ),
    );
  }

  /// Extract the scope name from cached async state without triggering a
  /// loading indicator.
  String _resolveScopeName(AsyncValue<List<TradeScope>> scopesAsync) {
    if (scopesAsync is AsyncData<List<TradeScope>>) {
      final scope =
          scopesAsync.value.where((s) => s.id == scopeId).firstOrNull;
      return scope?.tradeName ?? 'Trade Scope';
    }
    return 'Trade Scope';
  }

  /// Show a bottom sheet with full punch item details and status update option.
  void _showPunchItemDetail(
    BuildContext context,
    PunchListItem item,
    WidgetRef ref,
    bool isGcOrAdmin,
  ) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => PunchItemDetailSheet(
        item: item,
        ref: ref,
        isGcOrAdmin: isGcOrAdmin,
      ),
    );
  }
}

/// Combined scrollable list: task rows, optional punch list, optional billing.
class _TaskList extends StatelessWidget {
  const _TaskList({
    required this.scopeId,
    required this.tasks,
    required this.punchItems,
    required this.scopeName,
    required this.isGcOrAdmin,
    required this.onTaskTap,
    required this.onPunchItemTap,
  });

  final String scopeId;
  final List<ProjectTask> tasks;
  final List<PunchListItem> punchItems;
  final String scopeName;
  final bool isGcOrAdmin;
  final void Function(String taskId) onTaskTap;
  final void Function(PunchListItem item) onPunchItemTap;

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.symmetric(vertical: 8),
      children: [
        // Regular task rows
        ...tasks.map(
          (task) => TaskRow(
            taskId: task.id,
            title: task.title,
            status: task.status,
            priority: task.priority,
            dueDate: task.dueDate,
            description: task.description,
            onTap: () => onTaskTap(task.id),
          ),
        ),

        // Punch List section — shown only when punch items exist
        if (punchItems.isNotEmpty) ...[
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
            child: Text(
              'Punch List',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
            ),
          ),
          ...punchItems.map(
            (item) => Padding(
              padding: const EdgeInsets.symmetric(
                  horizontal: 16, vertical: 4),
              child: PunchListCard(
                item: item,
                onTap: () => onPunchItemTap(item),
              ),
            ),
          ),
        ],

        // Billing section — GC/admin only (Phase 25)
        if (isGcOrAdmin)
          ScopeBillingSection(
            scopeId: scopeId,
            tradeName: scopeName,
            tasks: tasks,
          ),
      ],
    );
  }
}
