import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/database/app_database.dart';
import '../../../../core/logging/app_logger.dart';
import '../../../../core/routing/route_names.dart';
import '../../../../shared/utils/date_format_utils.dart';
import '../../data/checklist_task_item.dart';
import '../providers/checklist_provider.dart';

/// Today's AI-generated daily checklist screen for contractors.
///
/// Shows all checklist items for the current date, parsed from the stored
/// [DailyChecklist.checklistJson]. Items are grouped by project name when
/// multiple projects exist.
///
/// Each item displays:
/// - Priority badge (1=urgent red, 2=high orange, 3=normal blue)
/// - Task title (bold)
/// - Estimated duration (e.g., "~45 min")
/// - Materials needed as chips
/// - Photo required indicator (camera icon)
/// - Dependency status indicator
///
/// Tapping an item navigates to TaskDetailScreen with the task's ID.
/// Pull-to-refresh fetches the latest checklist from the backend API.
class DailyChecklistScreen extends ConsumerStatefulWidget {
  const DailyChecklistScreen({super.key});

  @override
  ConsumerState<DailyChecklistScreen> createState() =>
      _DailyChecklistScreenState();
}

class _DailyChecklistScreenState extends ConsumerState<DailyChecklistScreen> {
  Future<void> _refresh() async {
    final repository = ref.read(checklistRepositoryProvider);
    await repository.fetchTodayChecklist();
  }

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final dateLabel = DateFormatUtils.formatReadableDate(now);
    final checklistsAsync = ref.watch(todayChecklistProvider);

    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              "Today's Checklist",
              style: TextStyle(fontWeight: FontWeight.w600, fontSize: 18),
            ),
            Text(
              dateLabel,
              style: TextStyle(
                fontSize: 13,
                color: Theme.of(context)
                    .colorScheme
                    .onSurface
                    .withValues(alpha: 0.65),
                fontWeight: FontWeight.normal,
              ),
            ),
          ],
        ),
        toolbarHeight: 64,
      ),
      body: checklistsAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) => Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Text(
              'Error loading checklist: $error',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: Theme.of(context).colorScheme.error,
                  ),
            ),
          ),
        ),
        data: (checklists) => RefreshIndicator(
          onRefresh: _refresh,
          child: checklists.isEmpty
              ? _EmptyState()
              : _ChecklistBody(checklists: checklists),
        ),
      ),
    );
  }
}

class _ChecklistBody extends StatelessWidget {
  const _ChecklistBody({required this.checklists});
  final List<DailyChecklist> checklists;

  /// Parse checklist JSON into task items grouped by project name.
  ///
  /// Separated from [build] so jsonDecode is not called on every frame rebuild.
  /// The result is computed once per new [checklists] list (Drift stream emission).
  static Map<String, List<ChecklistTaskItem>> parseChecklists(
    List<DailyChecklist> checklists,
  ) {
    final Map<String, List<ChecklistTaskItem>> byProject = {};

    for (final checklist in checklists) {
      try {
        final raw = jsonDecode(checklist.checklistJson);
        final List<dynamic> tasks;
        if (raw is List) {
          tasks = raw;
        } else if (raw is Map<String, dynamic> && raw['tasks'] is List) {
          tasks = raw['tasks'] as List<dynamic>;
        } else {
          continue;
        }

        for (final task in tasks) {
          if (task is! Map<String, dynamic>) continue;
          final item = ChecklistTaskItem.fromJson(task, checklist);
          final projectName = item.projectName;
          byProject.putIfAbsent(projectName, () => []).add(item);
        }
      } catch (e) {
        AppLogger.warning('DailyChecklistScreen',
            'Parse error for ${checklist.id}', error: e);
      }
    }

    // Sort items within each project by priority (1=urgent first)
    for (final group in byProject.values) {
      group.sort((a, b) => a.priority.compareTo(b.priority));
    }

    return byProject;
  }

  @override
  Widget build(BuildContext context) {
    final byProject = parseChecklists(checklists);

    if (byProject.isEmpty) {
      return _EmptyState();
    }

    final projectNames = byProject.keys.toList();
    final multiProject = projectNames.length > 1;

    return ListView.builder(
      padding: const EdgeInsets.only(bottom: 32),
      itemCount: projectNames.fold<int>(
        0,
        (acc, name) =>
            acc + (multiProject ? 1 : 0) + byProject[name]!.length,
      ),
      itemBuilder: (context, index) {
        // Build a flat list of headers + items
        int cursor = 0;
        for (final projectName in projectNames) {
          if (multiProject) {
            if (index == cursor) {
              return _ProjectSectionHeader(projectName: projectName);
            }
            cursor++;
          }
          final items = byProject[projectName]!;
          for (final item in items) {
            if (index == cursor) {
              return _TaskItemCard(item: item);
            }
            cursor++;
          }
        }
        return const SizedBox.shrink();
      },
    );
  }
}

class _ProjectSectionHeader extends StatelessWidget {
  const _ProjectSectionHeader({required this.projectName});
  final String projectName;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 20, 16, 4),
      child: Text(
        projectName,
        style: Theme.of(context).textTheme.titleSmall?.copyWith(
              color: Theme.of(context).colorScheme.primary,
              fontWeight: FontWeight.w600,
              letterSpacing: 0.4,
            ),
      ),
    );
  }
}

class _TaskItemCard extends StatelessWidget {
  const _TaskItemCard({required this.item});
  final ChecklistTaskItem item;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      child: InkWell(
        onTap: item.taskId.isNotEmpty
            ? () => context.push(RouteNames.taskDetailPath(item.taskId))
            : null,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Row 1: priority badge + title + indicators
              Row(
                children: [
                  _PriorityBadge(priority: item.priority),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      item.title,
                      style: theme.textTheme.bodyLarge?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  if (item.photoRequired)
                    Tooltip(
                      message: 'Photo required',
                      child: Icon(
                        Icons.camera_alt_outlined,
                        size: 18,
                        color: colorScheme.primary,
                      ),
                    ),
                  if (item.isBlocked) ...[
                    const SizedBox(width: 6),
                    Tooltip(
                      message: 'Blocked by dependency',
                      child: Icon(
                        Icons.block_outlined,
                        size: 18,
                        color: colorScheme.error,
                      ),
                    ),
                  ],
                ],
              ),
              // Row 2: duration
              if (item.estimatedDuration.isNotEmpty) ...[
                const SizedBox(height: 4),
                Row(
                  children: [
                    Icon(
                      Icons.timer_outlined,
                      size: 14,
                      color: Colors.grey[600],
                    ),
                    const SizedBox(width: 4),
                    Text(
                      '~${item.estimatedDuration}',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: Colors.grey[600],
                      ),
                    ),
                  ],
                ),
              ],
              // Row 3: materials chips
              if (item.materials.isNotEmpty) ...[
                const SizedBox(height: 8),
                Wrap(
                  spacing: 6,
                  runSpacing: 4,
                  children: item.materials.map((material) {
                    return Chip(
                      label: Text(
                        material,
                        style: const TextStyle(fontSize: 11),
                      ),
                      padding: const EdgeInsets.symmetric(horizontal: 4),
                      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      backgroundColor:
                          colorScheme.surfaceContainerHighest.withValues(alpha: 0.6),
                    );
                  }).toList(),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _PriorityBadge extends StatelessWidget {
  const _PriorityBadge({required this.priority});
  final int priority;

  @override
  Widget build(BuildContext context) {
    final (color, label) = switch (priority) {
      1 => (Colors.red, 'URGENT'),
      2 => (Colors.orange, 'HIGH'),
      _ => (Colors.blue, 'NORMAL'),
    };

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: color.withValues(alpha: 0.4)),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.w700,
          color: color,
          letterSpacing: 0.5,
        ),
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return ListView(
      children: [
        const SizedBox(height: 80),
        Center(
          child: Column(
            children: [
              Icon(
                Icons.check_circle_outline,
                size: 64,
                color: Colors.grey[400],
              ),
              const SizedBox(height: 16),
              Text(
                'No tasks scheduled for today',
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      color: Colors.grey[600],
                    ),
              ),
              const SizedBox(height: 8),
              Text(
                'Pull down to refresh',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: Colors.grey[500],
                    ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
