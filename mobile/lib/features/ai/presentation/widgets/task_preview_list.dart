import 'package:flutter/material.dart';

import '../../domain/ai_models.dart';

/// Preview list for AI-generated tasks in the contractor interview flow.
///
/// Shows a reorderable list of task cards with editable fields:
/// - Title (editable inline)
/// - Description (editable inline)
/// - Priority chip (high/medium/low)
/// - Estimated hours
/// - Materials list
///
/// Bottom actions: "Restart Interview" (confirmation dialog) and "Accept Plan".
class TaskPreviewList extends StatefulWidget {
  const TaskPreviewList({
    required this.tasks,
    required this.tradeName,
    required this.onTasksChanged,
    required this.onAcceptPlan,
    required this.onRestartInterview,
    super.key,
  });

  final List<AiTaskPreview> tasks;
  final String tradeName;

  /// Called with the updated task list when any task is edited or reordered.
  final Function(List<AiTaskPreview> updatedTasks) onTasksChanged;

  /// Called to finalize and create the tasks.
  final VoidCallback onAcceptPlan;

  /// Called to restart the interview (after confirmation dialog).
  final VoidCallback onRestartInterview;

  @override
  State<TaskPreviewList> createState() => _TaskPreviewListState();
}

class _TaskPreviewListState extends State<TaskPreviewList> {
  late List<AiTaskPreview> _localTasks;

  @override
  void initState() {
    super.initState();
    _localTasks = List.from(widget.tasks);
  }

  @override
  void didUpdateWidget(TaskPreviewList oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.tasks != widget.tasks) {
      _localTasks = List.from(widget.tasks);
    }
  }

  void _updateTask(int index, AiTaskPreview updated) {
    setState(() {
      _localTasks[index] = updated;
    });
    widget.onTasksChanged(List.unmodifiable(_localTasks));
  }

  void _reorderTasks(int oldIndex, int newIndex) {
    setState(() {
      if (newIndex > oldIndex) newIndex--;
      final task = _localTasks.removeAt(oldIndex);
      _localTasks.insert(newIndex, task);
    });
    widget.onTasksChanged(List.unmodifiable(_localTasks));
  }

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final colorScheme = Theme.of(context).colorScheme;

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Task Plan',
              style: textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              '${_localTasks.length} tasks for ${widget.tradeName}',
              style: textTheme.bodySmall?.copyWith(
                color: colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 12),

            if (_localTasks.isEmpty)
              Center(
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  child: Text(
                    'No tasks generated yet',
                    style: textTheme.bodyMedium?.copyWith(
                      color: colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),
              )
            else
              ReorderableListView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: _localTasks.length,
                onReorder: _reorderTasks,
                buildDefaultDragHandles: false,
                itemBuilder: (context, index) {
                  return _TaskCard(
                    key: ValueKey(_localTasks[index].id.isEmpty
                        ? index
                        : _localTasks[index].id),
                    task: _localTasks[index],
                    index: index,
                    onChanged: (updated) => _updateTask(index, updated),
                  );
                },
              ),

            const SizedBox(height: 16),

            // Action buttons row
            Row(
              children: [
                OutlinedButton(
                  onPressed: () => _showRestartDialog(context),
                  child: const Text('Restart Interview'),
                ),
                const Spacer(),
                ElevatedButton(
                  onPressed:
                      _localTasks.isNotEmpty ? widget.onAcceptPlan : null,
                  child: const Text('Accept Plan'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _showRestartDialog(BuildContext context) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Restart Interview?'),
        content: Text(
          'This will replace all ${_localTasks.length} existing tasks for '
          '${widget.tradeName}. This cannot be undone.',
        ),
        actions: [
          OutlinedButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Keep Current Plan'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: Theme.of(context).colorScheme.error,
              foregroundColor: Theme.of(context).colorScheme.onError,
            ),
            child: const Text('Restart Interview'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      widget.onRestartInterview();
    }
  }
}

/// Editable task card within the task preview list.
class _TaskCard extends StatefulWidget {
  const _TaskCard({
    required this.task,
    required this.index,
    required this.onChanged,
    super.key,
  });

  final AiTaskPreview task;
  final int index;
  final Function(AiTaskPreview updated) onChanged;

  @override
  State<_TaskCard> createState() => _TaskCardState();
}

class _TaskCardState extends State<_TaskCard> {
  late TextEditingController _titleController;
  late TextEditingController _descController;

  @override
  void initState() {
    super.initState();
    _titleController = TextEditingController(text: widget.task.title);
    _descController =
        TextEditingController(text: widget.task.description ?? '');
  }

  @override
  void dispose() {
    _titleController.dispose();
    _descController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return Card(
      elevation: 0,
      margin: const EdgeInsets.only(bottom: 8),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8),
        side: BorderSide(color: colorScheme.outlineVariant),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Drag handle
            ReorderableDragStartListener(
              index: widget.index,
              child: Padding(
                padding: const EdgeInsets.only(top: 4, right: 8),
                child: Icon(
                  Icons.drag_handle,
                  color: colorScheme.onSurfaceVariant,
                  size: 20,
                ),
              ),
            ),

            // Task content
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Title
                  TextField(
                    controller: _titleController,
                    style: textTheme.bodyMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                    decoration: const InputDecoration(
                      isDense: true,
                      contentPadding: EdgeInsets.zero,
                      border: InputBorder.none,
                      hintText: 'Task title',
                    ),
                    onChanged: (value) {
                      widget.onChanged(widget.task.copyWith(title: value));
                    },
                  ),
                  const SizedBox(height: 4),

                  // Description
                  TextField(
                    controller: _descController,
                    style: textTheme.bodySmall,
                    maxLines: 2,
                    minLines: 1,
                    decoration: InputDecoration(
                      isDense: true,
                      contentPadding: EdgeInsets.zero,
                      border: InputBorder.none,
                      hintText: 'Description (optional)',
                      hintStyle: textTheme.bodySmall?.copyWith(
                        color: colorScheme.onSurfaceVariant,
                      ),
                    ),
                    onChanged: (value) {
                      widget.onChanged(
                          widget.task.copyWith(description: value));
                    },
                  ),
                  const SizedBox(height: 8),

                  // Priority chip + estimated hours
                  Row(
                    children: [
                      _PriorityChip(
                        priority: widget.task.priority,
                        onChanged: (priority) {
                          widget.onChanged(
                              widget.task.copyWith(priority: priority));
                        },
                      ),
                      const SizedBox(width: 8),
                      if (widget.task.estimatedHours != null)
                        Text(
                          '${widget.task.estimatedHours!.toStringAsFixed(1)}h',
                          style: textTheme.bodySmall?.copyWith(
                            color: colorScheme.onSurfaceVariant,
                          ),
                        ),
                    ],
                  ),

                  // Materials
                  if (widget.task.materials.isNotEmpty) ...[
                    const SizedBox(height: 6),
                    Wrap(
                      spacing: 4,
                      runSpacing: 4,
                      children: widget.task.materials.map((material) {
                        return Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: colorScheme.surfaceContainerHighest,
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Text(
                            material,
                            style: textTheme.bodySmall?.copyWith(
                              color: colorScheme.onSurface,
                            ),
                          ),
                        );
                      }).toList(),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Priority chip with tap-to-cycle through priority levels.
class _PriorityChip extends StatelessWidget {
  const _PriorityChip({
    required this.priority,
    required this.onChanged,
  });

  final String priority;
  final Function(String) onChanged;

  static const _priorities = ['low', 'medium', 'high'];

  Color _priorityColor(BuildContext context) {
    return switch (priority) {
      'high' => Colors.red.shade600,
      'medium' => Colors.orange.shade600,
      _ => Colors.green.shade600,
    };
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () {
        final currentIndex = _priorities.indexOf(priority);
        final nextIndex = (currentIndex + 1) % _priorities.length;
        onChanged(_priorities[nextIndex]);
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
        decoration: BoxDecoration(
          color: _priorityColor(context).withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: _priorityColor(context).withValues(alpha: 0.4),
          ),
        ),
        child: Text(
          priority,
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: _priorityColor(context),
                fontWeight: FontWeight.w600,
              ),
        ),
      ),
    );
  }
}
