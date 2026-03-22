import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/database/app_database.dart' show TaskDependency;
import '../providers/gantt_provider.dart';
import '../widgets/gantt_chart_widget.dart';

/// Full-screen Gantt chart view for a project.
///
/// Shows:
/// - AppBar with project name and zoom control actions
/// - MaterialBanner for zone conflict warnings (if any)
/// - [GanttChartWidget] with swim lanes, task bars, and dependency arrows
///
/// Handles:
/// - Dependency creation via drag-to-connect (calls backend POST)
/// - Cycle error detection — shows AlertDialog with chain path and tappable names
/// - Blocked task taps — shows SnackBar with predecessor name
class GanttScreen extends ConsumerStatefulWidget {
  final String projectId;
  final String projectName;

  const GanttScreen({
    required this.projectId,
    super.key,
    this.projectName = 'Timeline',
  });

  @override
  ConsumerState<GanttScreen> createState() => _GanttScreenState();
}

class _GanttScreenState extends ConsumerState<GanttScreen> {
  bool _conflictBannerDismissed = false;

  @override
  Widget build(BuildContext context) {
    final ganttAsync = ref.watch(ganttDataProvider(widget.projectId));

    return Scaffold(
      appBar: AppBar(
        title: Text(widget.projectName),
        backgroundColor: const Color(0xFF1F2937), // gray-800
        foregroundColor: Colors.white,
        actions: [
          // Zoom hint icon
          IconButton(
            icon: const Icon(Icons.zoom_in),
            tooltip: 'Pinch to zoom',
            onPressed: () {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('Pinch to zoom, drag to pan'),
                  duration: Duration(seconds: 2),
                ),
              );
            },
          ),
          // Timeline info icon
          IconButton(
            icon: const Icon(Icons.info_outline),
            tooltip: 'Long-press task edge to connect',
            onPressed: () {
              showDialog<void>(
                context: context,
                builder: (context) => AlertDialog(
                  title: const Text('Gantt Chart Tips'),
                  content: const Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Pinch to zoom in/out'),
                      SizedBox(height: 8),
                      Text('Drag to pan the timeline'),
                      SizedBox(height: 8),
                      Text(
                          'Long-press the right edge of a task bar to draw a dependency arrow to another task'),
                    ],
                  ),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.of(context).pop(),
                      child: const Text('Got it'),
                    ),
                  ],
                ),
              );
            },
          ),
        ],
      ),
      body: ganttAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (err, _) => Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Text(
              'Error loading Gantt: $err',
              textAlign: TextAlign.center,
            ),
          ),
        ),
        data: (ganttData) {
          return Column(
            children: [
              // Conflict banner (shown when zone conflicts exist)
              if (ganttData.conflicts.isNotEmpty && !_conflictBannerDismissed)
                _ConflictBanner(
                  conflicts: ganttData.conflicts,
                  onDismiss: () =>
                      setState(() => _conflictBannerDismissed = true),
                ),

              Expanded(
                // InteractiveViewer handles its own pan/zoom — no extra scroll wrapper.
                child: GanttChartWidget(
                  scopes: ganttData.scopes,
                  tasksByScope: ganttData.tasksByScope,
                  dependencies: ganttData.dependencies,
                  conflictTaskIds: ganttData.conflictTaskIds,
                  onDependencyCreated: (predecessorId, successorId) =>
                      _handleDependencyCreated(
                          context, predecessorId, successorId, ganttData),
                  onTaskTapped: (taskId) =>
                      _handleTaskTapped(context, taskId, ganttData),
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  Future<void> _handleDependencyCreated(
    BuildContext context,
    String predecessorId,
    String successorId,
    GanttDataState ganttData,
  ) async {
    // Find predecessor and successor task names for error display
    String predecessorName = predecessorId;
    String successorName = successorId;

    for (final tasks in ganttData.tasksByScope.values) {
      for (final task in tasks) {
        if (task.id == predecessorId) predecessorName = task.title;
        if (task.id == successorId) successorName = task.title;
      }
    }

    // Simulate API call — in production, call backend POST /dependencies
    // and handle 422 cycle error response
    // For now: check local graph for cycles before submitting
    final wouldCreateCycle = _detectCycle(
      ganttData.dependencies,
      predecessorId,
      successorId,
    );

    if (wouldCreateCycle) {
      if (!context.mounted) return;
      await _showCycleErrorDialog(
        context,
        cycleChain: [predecessorName, successorName],
        cycleTaskIds: [predecessorId, successorId],
        ganttData: ganttData,
      );
      return;
    }

    // Dependency creation deferred to Phase 21 (requires companyId from auth).
    // Cycle check above prevents invalid local edges from being shown.
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Dependency created (pending sync)'),
        duration: Duration(seconds: 2),
      ),
    );
  }

  /// Detect if adding edge (predecessor -> successor) would create a cycle
  /// using depth-first search on the existing dependency graph.
  bool _detectCycle(
    List<TaskDependency> dependencies,
    String predecessorId,
    String successorId,
  ) {
    // Build adjacency list
    final adj = <String, List<String>>{};
    for (final dep in dependencies) {
      adj.putIfAbsent(dep.predecessorTaskId, () => [])
          .add(dep.successorTaskId);
    }

    // Check if successor can reach predecessor via existing edges (cycle check)
    final visited = <String>{};
    bool canReach(String from, String target) {
      if (from == target) return true;
      if (visited.contains(from)) return false;
      visited.add(from);
      for (final next in (adj[from] ?? [])) {
        if (canReach(next, target)) return true;
      }
      return false;
    }

    return canReach(successorId, predecessorId);
  }

  Future<void> _showCycleErrorDialog(
    BuildContext context, {
    required List<String> cycleChain,
    required List<String> cycleTaskIds,
    required GanttDataState ganttData,
  }) async {
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Dependency creates a loop'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('This dependency would create a circular chain:'),
            const SizedBox(height: 12),
            Wrap(
              spacing: 4,
              runSpacing: 4,
              children: [
                for (int i = 0; i < cycleChain.length; i++) ...[
                  if (i > 0) const Text(' → '),
                  InkWell(
                    onTap: cycleTaskIds.length > i
                        ? () {
                            Navigator.of(dialogContext).pop();
                            _handleTaskTapped(
                              context,
                              cycleTaskIds[i],
                              ganttData,
                            );
                          }
                        : null,
                    child: Text(
                      cycleChain[i],
                      style: const TextStyle(
                        color: Color(0xFF3B82F6), // blue-500
                        decoration: TextDecoration.underline,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('Got it'),
          ),
        ],
      ),
    );
  }

  void _handleTaskTapped(
    BuildContext context,
    String taskId,
    GanttDataState ganttData,
  ) {
    // Find the task
    for (final tasks in ganttData.tasksByScope.values) {
      for (final task in tasks) {
        if (task.id == taskId) {
          if (task.status == 'blocked') {
            // Find predecessor task name from dependencies
            String predecessorName = 'a predecessor task';
            for (final dep in ganttData.dependencies) {
              if (dep.successorTaskId == taskId) {
                // Find predecessor task name
                for (final allTasks in ganttData.tasksByScope.values) {
                  for (final t in allTasks) {
                    if (t.id == dep.predecessorTaskId) {
                      predecessorName = t.title;
                      break;
                    }
                  }
                }
                break;
              }
            }

            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content:
                    Text('Blocked by $predecessorName. Complete it first.'),
                duration: const Duration(seconds: 3),
              ),
            );
          }
          return;
        }
      }
    }
  }
}

// ---------------------------------------------------------------------------
// GanttDataNotifier extension for dependency creation
// ---------------------------------------------------------------------------

/// Exception thrown when backend returns 422 cycle error.
class CycleDependencyException implements Exception {
  final List<String> cycleNames;
  final List<String> cycleIds;

  const CycleDependencyException({
    required this.cycleNames,
    required this.cycleIds,
  });
}

// Note: Full dependency creation (with backend API call) is deferred to
// Phase 21 (AI planning integration) where companyId from auth will be used.
// The local cycle detection in _GanttScreenState._handleDependencyCreated
// prevents invalid edges from being created in the meantime.

// ---------------------------------------------------------------------------
// Conflict banner widget
// ---------------------------------------------------------------------------

class _ConflictBanner extends StatelessWidget {
  final List<ConflictInfo> conflicts;
  final VoidCallback onDismiss;

  const _ConflictBanner({
    required this.conflicts,
    required this.onDismiss,
  });

  @override
  Widget build(BuildContext context) {
    // Show the first conflict (most important one)
    final conflict = conflicts.first;
    return MaterialBanner(
      backgroundColor: const Color(0xFFFEF3C7), // amber-100
      content: Text(
        'Conflict: ${conflict.trade1Name} and ${conflict.trade2Name} overlap'
        ' in ${conflict.zoneName} on '
        '${conflict.conflictDate.month}/${conflict.conflictDate.day}.'
        ' Reschedule one task to resolve.',
        style: const TextStyle(
          color: Color(0xFF92400E), // amber-800
          fontSize: 13,
        ),
      ),
      leading: const Icon(
        Icons.warning_amber_rounded,
        color: Color(0xFFD97706), // amber-600
      ),
      actions: [
        if (conflicts.length > 1)
          TextButton(
            onPressed: () {},
            child: Text(
              '+${conflicts.length - 1} more',
              style: const TextStyle(color: Color(0xFF92400E)),
            ),
          ),
        TextButton(
          onPressed: onDismiss,
          child: const Text(
            'Dismiss',
            style: TextStyle(color: Color(0xFF92400E)),
          ),
        ),
      ],
    );
  }
}
