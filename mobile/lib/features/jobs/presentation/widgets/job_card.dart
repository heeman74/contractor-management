import 'package:flutter/material.dart';

import '../../domain/job_entity.dart';
import '../../domain/job_status.dart';

/// Reusable card widget for displaying a job summary in list and kanban views.
///
/// Color coding per lifecycle stage:
///   Quote      = blue
///   Scheduled  = orange
///   InProgress = amber
///   Complete   = green
///   Invoiced   = purple
///   Cancelled  = grey
///
/// Tapping the card navigates to the job detail screen via [onTap].
class JobCard extends StatelessWidget {
  const JobCard({
    super.key,
    required this.job,
    required this.onTap,
    this.isSelected = false,
    this.inBatchMode = false,
    this.onLongPress,
    this.onSelectionChanged,
  });

  final JobEntity job;
  final VoidCallback onTap;
  final bool isSelected;
  final bool inBatchMode;
  final VoidCallback? onLongPress;
  final ValueChanged<bool>? onSelectionChanged;

  @override
  Widget build(BuildContext context) {
    final status = job.jobStatus;
    final statusColor = _statusColor(status);
    final theme = Theme.of(context);

    return Card(
      elevation: isSelected ? 4 : 1,
      margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: isSelected
            ? BorderSide(color: theme.colorScheme.primary, width: 2)
            : BorderSide.none,
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: inBatchMode
            ? () => onSelectionChanged?.call(!isSelected)
            : onTap,
        onLongPress: onLongPress,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header row: status chip + priority badge
              Row(
                children: [
                  _StatusChip(status: status, color: statusColor),
                  const SizedBox(width: 8),
                  _PriorityBadge(priority: job.priority),
                  const Spacer(),
                  if (inBatchMode)
                    Checkbox(
                      value: isSelected,
                      onChanged: (v) => onSelectionChanged?.call(v ?? false),
                    ),
                ],
              ),
              const SizedBox(height: 8),

              // Description (capped at 2 lines)
              Text(
                job.description,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.bodyMedium?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 4),

              // Trade type
              Row(
                children: [
                  Icon(
                    Icons.build_outlined,
                    size: 14,
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                  const SizedBox(width: 4),
                  Flexible(
                    child: Text(
                      job.tradeType,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),

              // Client and contractor info (if available)
              if (job.clientId != null || job.contractorId != null) ...[
                const SizedBox(height: 4),
                Row(
                  children: [
                    if (job.clientId != null) ...[
                      Icon(
                        Icons.person_outline,
                        size: 14,
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                      const SizedBox(width: 4),
                      Flexible(
                        child: Text(
                          // ID shown until CRM lookup is wired in Plan 07
                          'Client: ${job.clientId!.substring(0, 8)}…',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                    if (job.clientId != null && job.contractorId != null)
                      const SizedBox(width: 12),
                    if (job.contractorId != null) ...[
                      Icon(
                        Icons.engineering_outlined,
                        size: 14,
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                      const SizedBox(width: 4),
                      Flexible(
                        child: Text(
                          'Contractor: ${job.contractorId!.substring(0, 8)}…',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ],
                ),
              ],

              // Tags row (if any)
              if (job.tags.isNotEmpty) ...[
                const SizedBox(height: 6),
                Wrap(
                  spacing: 4,
                  runSpacing: 2,
                  children: job.tags.take(3).map((tag) {
                    return Chip(
                      label: Text(tag),
                      labelStyle: theme.textTheme.labelSmall,
                      padding: EdgeInsets.zero,
                      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      visualDensity: VisualDensity.compact,
                    );
                  }).toList(),
                ),
              ],

              // Footer: created date
              const SizedBox(height: 6),
              Text(
                _formatDate(job.createdAt),
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                  fontSize: 11,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Returns the Material color associated with each [JobStatus].
  static Color _statusColor(JobStatus status) {
    return switch (status) {
      JobStatus.quote => Colors.blue,
      JobStatus.scheduled => Colors.orange,
      JobStatus.inProgress => Colors.amber[700]!,
      JobStatus.complete => Colors.green,
      JobStatus.invoiced => Colors.purple,
      JobStatus.cancelled => Colors.grey,
    };
  }

  String _formatDate(DateTime dt) {
    final now = DateTime.now();
    final diff = now.difference(dt);
    if (diff.inDays == 0) return 'Today';
    if (diff.inDays == 1) return 'Yesterday';
    if (diff.inDays < 7) return '${diff.inDays}d ago';
    return '${dt.day}/${dt.month}/${dt.year}';
  }
}

// ─── Internal sub-widgets ───────────────────────────────────────────────────

class _StatusChip extends StatelessWidget {
  const _StatusChip({required this.status, required this.color});

  final JobStatus status;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withValues(alpha: 0.4)),
      ),
      child: Text(
        status.displayLabel,
        style: TextStyle(
          color: color,
          fontSize: 11,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

class _PriorityBadge extends StatelessWidget {
  const _PriorityBadge({required this.priority});

  final String priority;

  @override
  Widget build(BuildContext context) {
    final (color, icon) = switch (priority) {
      'high' => (Colors.red, Icons.keyboard_double_arrow_up),
      'low' => (Colors.blue, Icons.keyboard_double_arrow_down),
      _ => (Colors.orange, Icons.remove), // medium
    };

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 14, color: color),
        const SizedBox(width: 2),
        Text(
          priority.substring(0, 1).toUpperCase() + priority.substring(1),
          style: TextStyle(
            color: color,
            fontSize: 11,
            fontWeight: FontWeight.w500,
          ),
        ),
      ],
    );
  }
}
