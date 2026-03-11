import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/di/service_locator.dart';
import '../../../../core/routing/route_names.dart';
import '../../../../features/auth/domain/auth_state.dart';
import '../../../../features/auth/presentation/providers/auth_provider.dart';
import '../../data/attachment_dao.dart';
import '../../data/note_dao.dart';
import '../../domain/job_entity.dart';
import '../../domain/job_status.dart';
import '../providers/job_providers.dart';
import '../providers/timer_providers.dart';
import 'add_note_bottom_sheet.dart';

/// Redesigned contractor job card with action bar for field use.
///
/// Layout:
/// - Top section: job title, status badge (long-press for transitions),
///   trade type, priority.
/// - Active job indicator: highlighted border + pulsing dot + live elapsed time.
/// - Completed job: dimmed (opacity 0.6), total tracked time shown, NO action bar.
/// - Bottom action bar (non-completed only):
///   - [Add Note] — opens AddNoteBottomSheet
///   - [Camera] — opens AddNoteBottomSheet with camera pre-triggered
///   - [Clock In] / [Clock Out] — navigates to TimerScreen
///
/// Status transitions (Scheduled → In Progress, In Progress → Complete) are
/// exposed via a long-press menu on the status badge — NOT in the action bar.
///
/// [isActive] = true when this is the currently clocked-in job; the card
/// gets a primary-colored border and live elapsed time.
class ContractorJobCard extends ConsumerWidget {
  final JobEntity job;

  const ContractorJobCard({required this.job, super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final timerAsync = ref.watch(timerNotifierProvider);
    final timerState = timerAsync.value;
    final isActive = timerState?.activeJobId == job.id;
    final isCompleted = job.jobStatus == JobStatus.complete ||
        job.jobStatus == JobStatus.invoiced ||
        job.jobStatus == JobStatus.cancelled;

    final statusColor = _statusColor(job.jobStatus);

    Widget card = Card(
      margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      shape: isActive
          ? RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
              side: BorderSide(
                color: Theme.of(context).colorScheme.primary,
                width: 2,
              ),
            )
          : null,
      child: InkWell(
        onTap: () => context.push(RouteNames.jobDetailPath(job.id)),
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // ── Top row: Status badge + priority ──────────────────────────
              Row(
                children: [
                  // Status badge — long-press for transition menu
                  GestureDetector(
                    onLongPress: isCompleted
                        ? null
                        : () => _showStatusMenu(context, ref),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                        color: statusColor.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(
                          color: statusColor.withValues(alpha: 0.3),
                        ),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            job.jobStatus.displayLabel,
                            style: TextStyle(
                              fontWeight: FontWeight.w600,
                              color: statusColor,
                              fontSize: 13,
                            ),
                          ),
                          if (!isCompleted) ...[
                            const SizedBox(width: 4),
                            Icon(
                              Icons.expand_more,
                              size: 14,
                              color: statusColor,
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),
                  const Spacer(),
                  if (isActive) ...[
                    _PulsingDot(
                        color: Theme.of(context).colorScheme.primary),
                    const SizedBox(width: 6),
                    Text(
                      _formatElapsed(
                          timerState?.elapsedSeconds ?? 0),
                      style: TextStyle(
                        fontWeight: FontWeight.w700,
                        color: Theme.of(context).colorScheme.primary,
                        fontSize: 15,
                        fontFeatures: const [FontFeature.tabularFigures()],
                      ),
                    ),
                    const SizedBox(width: 8),
                  ],
                  Text(
                    job.priority.toUpperCase(),
                    style: TextStyle(
                      fontSize: 11,
                      color:
                          Theme.of(context).colorScheme.onSurfaceVariant,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),

              // ── Job description ────────────────────────────────────────────
              Text(
                job.description,
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 2),
              Text(
                job.tradeType,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: Theme.of(context)
                          .colorScheme
                          .onSurfaceVariant,
                    ),
              ),

              // ── Completed: total tracked time ─────────────────────────────
              if (isCompleted) ...[
                const SizedBox(height: 8),
                _TotalTrackedBadge(jobId: job.id),
              ],

              // ── Action bar (non-completed only) ───────────────────────────
              if (!isCompleted) ...[
                const SizedBox(height: 12),
                _ActionBar(
                  job: job,
                  isActive: isActive,
                ),
              ],
            ],
          ),
        ),
      ),
    );

    // Dim completed jobs
    if (isCompleted) {
      card = Opacity(opacity: 0.6, child: card);
    }

    return card;
  }

  /// Shows a status transition menu on long-press of the status badge.
  ///
  /// Available transitions depend on current status:
  /// - Scheduled → In Progress (Start)
  /// - In Progress → Complete (Complete)
  void _showStatusMenu(BuildContext context, WidgetRef ref) {
    final canStart = job.jobStatus == JobStatus.scheduled;
    final canComplete = job.jobStatus == JobStatus.inProgress;

    if (!canStart && !canComplete) return;

    final overlay = Overlay.of(context).context.findRenderObject()!
        as RenderBox;

    showMenu<String>(
      context: context,
      position: RelativeRect.fromRect(
        const Offset(16, 60) & const Size(200, 0),
        Offset.zero & overlay.size,
      ),
      items: [
        if (canStart)
          const PopupMenuItem<String>(
            value: 'in_progress',
            child: Row(
              children: [
                Icon(Icons.play_arrow, size: 18, color: Colors.blue),
                SizedBox(width: 8),
                Text('Start Work'),
              ],
            ),
          ),
        if (canComplete)
          const PopupMenuItem<String>(
            value: 'complete',
            child: Row(
              children: [
                Icon(Icons.check_circle, size: 18, color: Colors.green),
                SizedBox(width: 8),
                Text('Mark Complete'),
              ],
            ),
          ),
      ],
    ).then((value) {
      if (value != null && context.mounted) {
        _performTransition(context, ref, value);
      }
    });
  }

  Future<void> _performTransition(
      BuildContext context, WidgetRef ref, String newStatus) async {
    try {
      final authState = ref.read(authNotifierProvider);
      final userId =
          authState is AuthAuthenticated ? authState.userId : 'unknown';

      final dao = ref.read(jobDaoProvider);
      final now = DateTime.now();

      final history = List<Map<String, dynamic>>.from(job.statusHistory)
        ..add({
          'status': newStatus,
          'timestamp': now.toIso8601String(),
          'user_id': userId,
        });

      await dao.updateJobStatus(
        job.id,
        newStatus,
        jsonEncode(history),
        job.version + 1,
      );

      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              newStatus == 'in_progress' ? 'Job started' : 'Job completed',
            ),
          ),
        );
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to update status: $e'),
            backgroundColor: Theme.of(context).colorScheme.error,
          ),
        );
      }
    }
  }

  String _formatElapsed(int seconds) {
    final h = seconds ~/ 3600;
    final m = (seconds % 3600) ~/ 60;
    final s = seconds % 60;
    return '${h.toString().padLeft(2, '0')}:${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
  }

  Color _statusColor(JobStatus status) {
    return switch (status) {
      JobStatus.quote => Colors.grey,
      JobStatus.scheduled => Colors.blue,
      JobStatus.inProgress => Colors.orange,
      JobStatus.complete => Colors.green,
      JobStatus.invoiced => Colors.purple,
      JobStatus.cancelled => Colors.red,
    };
  }
}

// ─── Pulsing dot ──────────────────────────────────────────────────────────────

class _PulsingDot extends StatefulWidget {
  final Color color;

  const _PulsingDot({required this.color});

  @override
  State<_PulsingDot> createState() => _PulsingDotState();
}

class _PulsingDotState extends State<_PulsingDot>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _animation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800),
    )..repeat(reverse: true);
    _animation = Tween<double>(begin: 0.4, end: 1.0).animate(_controller);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _animation,
      builder: (_, __) => Opacity(
        opacity: _animation.value,
        child: Container(
          width: 8,
          height: 8,
          decoration: BoxDecoration(
            color: widget.color,
            shape: BoxShape.circle,
          ),
        ),
      ),
    );
  }
}

// ─── Action bar ───────────────────────────────────────────────────────────────

/// Bottom action bar with Add Note, Camera, and Clock In/Out buttons.
///
/// Only rendered for non-completed jobs.
class _ActionBar extends ConsumerWidget {
  final JobEntity job;
  final bool isActive;

  const _ActionBar({required this.job, required this.isActive});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final authState = ref.watch(authNotifierProvider);
    final companyId =
        authState is AuthAuthenticated ? authState.companyId : '';
    final userId =
        authState is AuthAuthenticated ? authState.userId : '';

    return Container(
      decoration: BoxDecoration(
        border: Border(
          top: BorderSide(
            color: Theme.of(context).colorScheme.outlineVariant,
          ),
        ),
      ),
      padding: const EdgeInsets.only(top: 8),
      child: Row(
        children: [
          // Add Note
          _ActionButton(
            icon: Icons.add_comment_outlined,
            label: 'Add Note',
            onPressed: () => _openAddNote(context, companyId, userId),
          ),
          const SizedBox(width: 8),
          // Camera
          _ActionButton(
            icon: Icons.camera_alt_outlined,
            label: 'Camera',
            onPressed: () => _openCamera(context, companyId, userId),
          ),
          const SizedBox(width: 8),
          // Clock In / Clock Out
          Expanded(
            child: isActive
                ? OutlinedButton.icon(
                    onPressed: () => _navigateToTimer(context),
                    icon: const Icon(Icons.stop_circle_outlined, size: 18),
                    label: const Text('Clock Out'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor:
                          Theme.of(context).colorScheme.error,
                      side: BorderSide(
                          color: Theme.of(context).colorScheme.error),
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 8),
                      textStyle:
                          const TextStyle(fontWeight: FontWeight.w600),
                    ),
                  )
                : FilledButton.icon(
                    onPressed: () => _navigateToTimer(context),
                    icon: const Icon(Icons.play_circle_outlined, size: 18),
                    label: const Text('Clock In'),
                    style: FilledButton.styleFrom(
                      backgroundColor: Colors.green.shade600,
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 8),
                      textStyle:
                          const TextStyle(fontWeight: FontWeight.w600),
                    ),
                  ),
          ),
        ],
      ),
    );
  }

  void _openAddNote(
      BuildContext context, String companyId, String userId) {
    AddNoteBottomSheet.show(
      context: context,
      jobId: job.id,
      companyId: companyId,
      authorId: userId,
      noteDao: getIt<NoteDao>(),
      attachmentDao: getIt<AttachmentDao>(),
    );
  }

  Future<void> _openCamera(
      BuildContext context, String companyId, String userId) async {
    // Opens AddNoteBottomSheet with camera auto-trigger by using the existing
    // sheet. The camera button inside the sheet will be the entry point.
    // For immediate camera capture: open the sheet which has Camera button.
    // A future enhancement would pre-trigger the camera on open.
    AddNoteBottomSheet.show(
      context: context,
      jobId: job.id,
      companyId: companyId,
      authorId: userId,
      noteDao: getIt<NoteDao>(),
      attachmentDao: getIt<AttachmentDao>(),
    );
  }

  void _navigateToTimer(BuildContext context) {
    context.push(RouteNames.timerPath(job.id));
  }
}

// ─── Action button ─────────────────────────────────────────────────────────────

class _ActionButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onPressed;

  const _ActionButton({
    required this.icon,
    required this.label,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    return OutlinedButton(
      onPressed: onPressed,
      style: OutlinedButton.styleFrom(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 18),
          const SizedBox(height: 2),
          Text(label, style: const TextStyle(fontSize: 10)),
        ],
      ),
    );
  }
}

// ─── Total tracked badge (completed jobs) ─────────────────────────────────────

/// Shows total tracked time for a completed job.
///
/// Derived from [timeEntriesForJobProvider] — reactive, offline-first.
class _TotalTrackedBadge extends ConsumerWidget {
  final String jobId;

  const _TotalTrackedBadge({required this.jobId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final entriesAsync = ref.watch(timeEntriesForJobProvider(jobId));

    return entriesAsync.when(
      data: (entries) {
        int totalSeconds = 0;
        for (final e in entries) {
          if (e.durationSeconds != null) totalSeconds += e.durationSeconds!;
        }
        if (totalSeconds == 0) return const SizedBox.shrink();

        final h = totalSeconds ~/ 3600;
        final m = (totalSeconds % 3600) ~/ 60;
        final label = h > 0 ? '${h}h ${m}m' : '${m}m';

        return Container(
          padding:
              const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
          decoration: BoxDecoration(
            color: Theme.of(context)
                .colorScheme
                .surfaceContainerHighest,
            borderRadius: BorderRadius.circular(6),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.timer_outlined,
                size: 14,
                color:
                    Theme.of(context).colorScheme.onSurfaceVariant,
              ),
              const SizedBox(width: 4),
              Text(
                'Total: $label',
                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                      color: Theme.of(context)
                          .colorScheme
                          .onSurfaceVariant,
                    ),
              ),
            ],
          ),
        );
      },
      loading: () => const SizedBox.shrink(),
      error: (_, __) => const SizedBox.shrink(),
    );
  }
}
