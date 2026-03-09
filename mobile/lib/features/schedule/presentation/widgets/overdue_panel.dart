import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/routing/route_names.dart';
import '../../domain/overdue_service.dart';
import '../providers/calendar_providers.dart';
import '../providers/overdue_providers.dart';

/// Expandable panel listing all overdue jobs with tiered severity indicators.
///
/// Visibility is controlled by [showOverduePanelProvider] — toggling that
/// provider expands or collapses the panel.
///
/// Items are sorted by severity (critical first) then by days overdue
/// (most overdue first). Each item shows:
///   - job description
///   - contractor ID (future: resolved name)
///   - days overdue count
///   - severity tier color indicator
///   - latest delay reason (if a delay was reported)
///   - quick action buttons: View Job, Contact Contractor (placeholder)
///
/// Empty state shows a check-mark icon and "No overdue jobs" message.
///
/// The panel renders as an AnimatedContainer overlay that slides down from
/// the calendar header when [showOverduePanelProvider] is true.
class OverduePanel extends ConsumerWidget {
  const OverduePanel({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isVisible = ref.watch(showOverduePanelProvider);
    final overdueJobs = ref.watch(overdueJobsProvider);

    return AnimatedContainer(
      duration: const Duration(milliseconds: 250),
      curve: Curves.easeInOut,
      height: isVisible ? null : 0,
      clipBehavior: Clip.hardEdge,
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        border: Border(
          bottom: BorderSide(
            color: Theme.of(context).colorScheme.outlineVariant,
          ),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.08),
            blurRadius: 4,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: isVisible
          ? _PanelContent(overdueJobs: overdueJobs)
          : const SizedBox.shrink(),
    );
  }
}

// ─── Panel content ────────────────────────────────────────────────────────────

class _PanelContent extends StatelessWidget {
  final List<OverdueJobInfo> overdueJobs;

  const _PanelContent({required this.overdueJobs});

  @override
  Widget build(BuildContext context) {
    if (overdueJobs.isEmpty) {
      return _EmptyState();
    }

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _PanelHeader(count: overdueJobs.length),
        const Divider(height: 1),
        ConstrainedBox(
          constraints: const BoxConstraints(maxHeight: 320),
          child: ListView.separated(
            shrinkWrap: true,
            padding: const EdgeInsets.symmetric(vertical: 4),
            itemCount: overdueJobs.length,
            separatorBuilder: (_, __) => const Divider(height: 1, indent: 56),
            itemBuilder: (context, index) =>
                _OverdueJobItem(info: overdueJobs[index]),
          ),
        ),
      ],
    );
  }
}

// ─── Panel header ─────────────────────────────────────────────────────────────

class _PanelHeader extends StatelessWidget {
  final int count;

  const _PanelHeader({required this.count});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Row(
        children: [
          Icon(
            Icons.warning_amber_rounded,
            color: Theme.of(context).colorScheme.error,
            size: 18,
          ),
          const SizedBox(width: 8),
          Text(
            '$count overdue ${count == 1 ? 'job' : 'jobs'}',
            style: Theme.of(context).textTheme.titleSmall?.copyWith(
                  color: Theme.of(context).colorScheme.error,
                  fontWeight: FontWeight.w600,
                ),
          ),
        ],
      ),
    );
  }
}

// ─── Empty state ──────────────────────────────────────────────────────────────

class _EmptyState extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.check_circle_outline,
            color: Theme.of(context).colorScheme.primary,
            size: 20,
          ),
          const SizedBox(width: 8),
          Text(
            'No overdue jobs',
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
          ),
        ],
      ),
    );
  }
}

// ─── Overdue job list item ────────────────────────────────────────────────────

class _OverdueJobItem extends ConsumerWidget {
  final OverdueJobInfo info;

  const _OverdueJobItem({required this.info});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final severityColor = _severityColor(context, info.severity);
    final severityLabel = _severityLabel(info.severity);

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Severity color indicator
          Container(
            width: 4,
            height: 56,
            decoration: BoxDecoration(
              color: severityColor,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(width: 10),
          // Job info
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        info.description,
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                              fontWeight: FontWeight.w600,
                            ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    const SizedBox(width: 8),
                    // Days overdue badge
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 6,
                        vertical: 2,
                      ),
                      decoration: BoxDecoration(
                        color: severityColor.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(
                          color: severityColor.withValues(alpha: 0.4),
                        ),
                      ),
                      child: Text(
                        '${info.daysOverdue}d overdue',
                        style: Theme.of(context).textTheme.labelSmall?.copyWith(
                              color: severityColor,
                              fontWeight: FontWeight.w600,
                            ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 2),
                Row(
                  children: [
                    if (info.contractorName != null) ...[
                      Icon(
                        Icons.person_outline,
                        size: 12,
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                      const SizedBox(width: 2),
                      Text(
                        info.contractorName!,
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              color: Theme.of(context)
                                  .colorScheme
                                  .onSurfaceVariant,
                            ),
                      ),
                      const SizedBox(width: 8),
                    ],
                    // Severity chip
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 4,
                        vertical: 1,
                      ),
                      decoration: BoxDecoration(
                        color: severityColor.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(
                        severityLabel,
                        style: Theme.of(context).textTheme.labelSmall?.copyWith(
                              color: severityColor,
                            ),
                      ),
                    ),
                  ],
                ),
                // Latest delay reason
                if (info.hasDelayReport && info.latestDelayReason != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Row(
                      children: [
                        Icon(
                          Icons.schedule_send_outlined,
                          size: 12,
                          color:
                              Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                        const SizedBox(width: 2),
                        Expanded(
                          child: Text(
                            'Delay: ${info.latestDelayReason}',
                            style: Theme.of(context)
                                .textTheme
                                .bodySmall
                                ?.copyWith(
                                  color: Theme.of(context)
                                      .colorScheme
                                      .onSurfaceVariant,
                                  fontStyle: FontStyle.italic,
                                ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          // Quick action buttons
          Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // View job button
              IconButton(
                icon: const Icon(Icons.open_in_new, size: 18),
                tooltip: 'View job',
                style: IconButton.styleFrom(
                  minimumSize: const Size(32, 32),
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
                onPressed: () => _navigateToJob(context, ref),
              ),
              // Contact contractor button (placeholder)
              IconButton(
                icon: const Icon(Icons.chat_bubble_outline, size: 18),
                tooltip: 'Contact contractor',
                style: IconButton.styleFrom(
                  minimumSize: const Size(32, 32),
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
                onPressed: () {
                  // Placeholder: contractor messaging not yet implemented.
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Contractor messaging coming soon'),
                      duration: Duration(seconds: 2),
                    ),
                  );
                },
              ),
            ],
          ),
        ],
      ),
    );
  }

  Color _severityColor(BuildContext context, OverdueSeverity severity) {
    return switch (severity) {
      OverdueSeverity.critical => Theme.of(context).colorScheme.error,
      OverdueSeverity.warning => Colors.orange,
      OverdueSeverity.none => Theme.of(context).colorScheme.onSurfaceVariant,
    };
  }

  String _severityLabel(OverdueSeverity severity) {
    return switch (severity) {
      OverdueSeverity.critical => 'CRITICAL',
      OverdueSeverity.warning => 'WARNING',
      OverdueSeverity.none => 'OK',
    };
  }

  void _navigateToJob(BuildContext context, WidgetRef ref) {
    // Collapse the panel before navigating
    ref.read(showOverduePanelProvider.notifier).state = false;
    // Navigate to job detail using GoRouter push — see RouteNames.jobDetailPath
    context.push(RouteNames.jobDetailPath(info.jobId));
  }
}
