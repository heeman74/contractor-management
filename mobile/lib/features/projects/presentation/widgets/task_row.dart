import 'package:flutter/material.dart';

import '../../../../shared/utils/date_format_utils.dart';
import 'project_status_badge.dart';
import 'task_thumbnail_row.dart';

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
class TaskRow extends StatelessWidget {
  const TaskRow({
    required this.taskId,
    required this.title,
    required this.status,
    required this.priority,
    required this.onTap,
    super.key,
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
                                  'Due ${DateFormatUtils.formatNumericDate(dueDate!)}',
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
}
