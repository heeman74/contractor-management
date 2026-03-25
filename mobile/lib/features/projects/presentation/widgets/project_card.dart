import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/database/app_database.dart' show Project;
import '../providers/project_providers.dart';
import '../widgets/project_status_badge.dart';

/// Rich project card for the grid layout.
///
/// Displays: project name, status badge, progress bar with percentage,
/// task count (completed/total), scope count, target dates, and address.
/// Tapping navigates to the project detail screen.
class ProjectCard extends ConsumerWidget {
  const ProjectCard({
    required this.project,
    required this.onTap,
    super.key,
  });

  final Project project;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final textTheme = theme.textTheme;
    final progressAsync = ref.watch(projectProgressProvider(project.id));

    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header with status color strip
            Container(
              height: 6,
              color: _statusColor(project.status),
            ),

            Padding(
              padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Row 1: Project name + status badge
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: Text(
                          project.name,
                          style: textTheme.titleSmall?.copyWith(
                            fontWeight: FontWeight.w700,
                          ),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      const SizedBox(width: 6),
                      ProjectStatusBadge(status: project.status, dense: true),
                    ],
                  ),

                  // Address
                  if (project.address != null &&
                      project.address!.isNotEmpty) ...[
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        Icon(
                          Icons.location_on_outlined,
                          size: 14,
                          color: colorScheme.onSurface.withValues(alpha: 0.5),
                        ),
                        const SizedBox(width: 3),
                        Expanded(
                          child: Text(
                            project.address!,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: textTheme.bodySmall?.copyWith(
                              color: colorScheme.onSurface
                                  .withValues(alpha: 0.55),
                              fontSize: 11,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],

                  const SizedBox(height: 10),

                  // Progress section
                  progressAsync.when(
                    loading: () => _buildProgressPlaceholder(colorScheme),
                    error: (_, __) => _buildProgressPlaceholder(colorScheme),
                    data: (progress) => _buildProgress(
                      progress,
                      textTheme,
                      colorScheme,
                    ),
                  ),

                  const SizedBox(height: 10),

                  // Bottom row: dates + scope count
                  _buildFooter(textTheme, colorScheme),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildProgress(
    ProjectProgress progress,
    TextTheme textTheme,
    ColorScheme colorScheme,
  ) {
    final progressColor = _progressBarColor(progress.fraction);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Progress bar
        Row(
          children: [
            Expanded(
              child: ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: LinearProgressIndicator(
                  value: progress.fraction,
                  minHeight: 7,
                  valueColor: AlwaysStoppedAnimation<Color>(progressColor),
                  backgroundColor:
                      colorScheme.onSurface.withValues(alpha: 0.08),
                ),
              ),
            ),
            const SizedBox(width: 8),
            Text(
              '${progress.percentage}%',
              style: textTheme.labelSmall?.copyWith(
                fontWeight: FontWeight.w700,
                color: progressColor,
              ),
            ),
          ],
        ),
        const SizedBox(height: 6),
        // Task count + scope count
        Row(
          children: [
            Icon(
              Icons.check_circle_outline,
              size: 13,
              color: colorScheme.onSurface.withValues(alpha: 0.5),
            ),
            const SizedBox(width: 3),
            Text(
              '${progress.completedTasks}/${progress.totalTasks} tasks',
              style: textTheme.bodySmall?.copyWith(
                fontSize: 11,
                color: colorScheme.onSurface.withValues(alpha: 0.6),
              ),
            ),
            const SizedBox(width: 12),
            Icon(
              Icons.category_outlined,
              size: 13,
              color: colorScheme.onSurface.withValues(alpha: 0.5),
            ),
            const SizedBox(width: 3),
            Text(
              '${progress.scopeCount} scopes',
              style: textTheme.bodySmall?.copyWith(
                fontSize: 11,
                color: colorScheme.onSurface.withValues(alpha: 0.6),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildProgressPlaceholder(ColorScheme colorScheme) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(4),
      child: LinearProgressIndicator(
        value: 0,
        minHeight: 7,
        backgroundColor: colorScheme.onSurface.withValues(alpha: 0.08),
      ),
    );
  }

  Widget _buildFooter(TextTheme textTheme, ColorScheme colorScheme) {
    final hasStart = project.targetStartDate != null;
    final hasEnd = project.targetEndDate != null;

    String dateLabel = '';
    if (hasStart && hasEnd) {
      dateLabel =
          '${_formatDate(project.targetStartDate!)} - ${_formatDate(project.targetEndDate!)}';
    } else if (hasStart) {
      dateLabel = 'From ${_formatDate(project.targetStartDate!)}';
    } else if (hasEnd) {
      dateLabel = 'Due ${_formatDate(project.targetEndDate!)}';
    }

    if (dateLabel.isEmpty) return const SizedBox.shrink();

    return Row(
      children: [
        Icon(
          Icons.calendar_today_outlined,
          size: 13,
          color: colorScheme.onSurface.withValues(alpha: 0.45),
        ),
        const SizedBox(width: 4),
        Expanded(
          child: Text(
            dateLabel,
            style: textTheme.bodySmall?.copyWith(
              fontSize: 11,
              color: colorScheme.onSurface.withValues(alpha: 0.5),
            ),
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }

  static Color _statusColor(String status) {
    return switch (status) {
      'active' => const Color(0xFF2563EB),
      'complete' => const Color(0xFF388E3C),
      'on_hold' => const Color(0xFFFFA000),
      'cancelled' => const Color(0xFFD32F2F),
      _ => const Color(0xFF9E9E9E), // draft
    };
  }

  static const _months = [
    'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
    'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
  ];

  static String _formatDate(DateTime dt) => '${_months[dt.month - 1]} ${dt.day}';

  static Color _progressBarColor(double fraction) {
    if (fraction >= 1.0) return const Color(0xFF388E3C);
    if (fraction >= 0.67) return const Color(0xFF38BDF8);
    if (fraction >= 0.34) return const Color(0xFF2563EB);
    return const Color(0xFF424299);
  }
}
