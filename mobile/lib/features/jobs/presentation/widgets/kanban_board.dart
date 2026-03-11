import 'package:flutter/material.dart';

import '../../domain/job_entity.dart';
import '../../domain/job_status.dart';
import 'job_card.dart';

/// Horizontally scrollable kanban board with one column per lifecycle stage.
///
/// Implements the layout from RESEARCH.md Pattern 7:
///   - Each column is 280 px wide with a fixed-height header + scrollable body.
///   - Cancelled jobs are excluded — shown in the list view only.
///   - Column headers display the status label and a count badge.
///
/// [onJobTap] is forwarded to each [JobCard].
class KanbanBoard extends StatelessWidget {
  const KanbanBoard({
    super.key,
    required this.jobs,
    required this.onJobTap,
  });

  /// All active jobs for the current company (pre-filtered — no deleted items).
  final List<JobEntity> jobs;

  /// Called when a job card is tapped; receives the job ID for navigation.
  final void Function(String jobId) onJobTap;

  // Kanban columns in lifecycle order — Cancelled excluded (list-only).
  static const _columns = [
    JobStatus.quote,
    JobStatus.scheduled,
    JobStatus.inProgress,
    JobStatus.complete,
    JobStatus.invoiced,
  ];

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        return SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: _columns.map((status) {
              final columnJobs = jobs
                  .where((j) => j.jobStatus == status)
                  .toList();

              return _KanbanColumn(
                status: status,
                jobs: columnJobs,
                onJobTap: onJobTap,
                availableHeight: constraints.maxHeight - 16, // minus vertical padding
              );
            }).toList(),
          ),
        );
      },
    );
  }
}

// ─── Column ─────────────────────────────────────────────────────────────────

class _KanbanColumn extends StatelessWidget {
  const _KanbanColumn({
    required this.status,
    required this.jobs,
    required this.onJobTap,
    required this.availableHeight,
  });

  final JobStatus status;
  final List<JobEntity> jobs;
  final void Function(String jobId) onJobTap;
  final double availableHeight;

  static const _columnWidth = 280.0;
  static const _headerHeight = 48.0; // header + spacing

  @override
  Widget build(BuildContext context) {
    final color = _columnColor(status);
    final cardListMaxHeight = availableHeight - _headerHeight;

    return SizedBox(
      width: _columnWidth,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Column header
          _ColumnHeader(status: status, count: jobs.length, color: color),
          const SizedBox(height: 4),

          // Job cards — constrained to the actual available height
          // (not a percentage of full screen which ignores app bar, toolbar, nav bar).
          ConstrainedBox(
            constraints: BoxConstraints(
              maxHeight: cardListMaxHeight.clamp(100, double.infinity),
            ),
            child: jobs.isEmpty
                ? _EmptyColumn(color: color)
                : ListView.builder(
                    shrinkWrap: true,
                    physics: const ClampingScrollPhysics(),
                    itemCount: jobs.length,
                    itemBuilder: (context, index) {
                      final job = jobs[index];
                      return JobCard(
                        job: job,
                        onTap: () => onJobTap(job.id),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }

  static Color _columnColor(JobStatus status) {
    return switch (status) {
      JobStatus.quote => Colors.blue,
      JobStatus.scheduled => Colors.orange,
      JobStatus.inProgress => Colors.amber[700]!,
      JobStatus.complete => Colors.green,
      JobStatus.invoiced => Colors.purple,
      JobStatus.cancelled => Colors.grey,
    };
  }
}

// ─── Column header ───────────────────────────────────────────────────────────

class _ColumnHeader extends StatelessWidget {
  const _ColumnHeader({
    required this.status,
    required this.count,
    required this.color,
  });

  final JobStatus status;
  final int count;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 8),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(
              status.displayLabel,
              style: theme.textTheme.titleSmall?.copyWith(
                color: color,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          // Count badge
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
            decoration: BoxDecoration(
              color: color,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Text(
              '$count',
              style: const TextStyle(
                color: Colors.white,
                fontSize: 12,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Empty column placeholder ────────────────────────────────────────────────

class _EmptyColumn extends StatelessWidget {
  const _EmptyColumn({required this.color});

  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.grey[50],
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: Colors.grey[300]!,
          style: BorderStyle.solid,
        ),
      ),
      child: Center(
        child: Text(
          'No jobs',
          style: TextStyle(
            color: Colors.grey[400],
            fontSize: 13,
          ),
        ),
      ),
    );
  }
}
