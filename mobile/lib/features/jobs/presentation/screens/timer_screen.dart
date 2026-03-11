import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/database/app_database.dart';
import '../../../../features/auth/domain/auth_state.dart';
import '../../../../features/auth/presentation/providers/auth_provider.dart';
import '../providers/job_providers.dart';
import '../providers/timer_providers.dart';

/// Dedicated timer screen for a contractor on a specific job.
///
/// Displays:
/// - Large HH:MM:SS elapsed counter (live-updating via [TimerNotifier]).
/// - Clock In (green) / Clock Out (red) full-width button with pulsing indicator.
/// - If active on a DIFFERENT job: warning text + "Clock In (will clock out of other job)".
/// - Session history list (date, start – end, duration).
/// - Total time summary across all completed + current sessions.
///
/// Timer state is backed by [TimerNotifier] which restores active sessions from
/// Drift on app restart — the timer survives app kill.
///
/// Route: /timer/:jobId (push route, no bottom nav).
class TimerScreen extends ConsumerWidget {
  final String jobId;

  const TimerScreen({required this.jobId, super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final jobAsync = ref.watch(jobDetailNotifierProvider(jobId));

    return jobAsync.when(
      data: (job) {
        if (job == null) {
          return Scaffold(
            appBar: AppBar(title: const Text('Timer')),
            body: const Center(child: Text('Job not found')),
          );
        }
        return _TimerView(jobId: jobId, jobDescription: job.description);
      },
      loading: () => Scaffold(
        appBar: AppBar(title: const Text('Timer')),
        body: const Center(child: CircularProgressIndicator()),
      ),
      error: (e, _) => Scaffold(
        appBar: AppBar(title: const Text('Timer')),
        body: Center(child: Text('Error: $e')),
      ),
    );
  }
}

// ─── Main view ─────────────────────────────────────────────────────────────────

class _TimerView extends ConsumerWidget {
  final String jobId;
  final String jobDescription;

  const _TimerView({required this.jobId, required this.jobDescription});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final timerAsync = ref.watch(timerNotifierProvider);
    final entriesAsync = ref.watch(timeEntriesForJobProvider(jobId));
    final authState = ref.watch(authNotifierProvider);

    final companyId =
        authState is AuthAuthenticated ? authState.companyId : '';

    return Scaffold(
      appBar: AppBar(
        title: Text(
          jobDescription,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        backgroundColor:
            Theme.of(context).colorScheme.surfaceContainerHighest,
      ),
      body: timerAsync.when(
        data: (timer) => _TimerBody(
          jobId: jobId,
          companyId: companyId,
          timer: timer,
          entriesAsync: entriesAsync,
        ),
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Error loading timer: $e')),
      ),
    );
  }
}

// ─── Timer body ─────────────────────────────────────────────────────────────────

class _TimerBody extends ConsumerWidget {
  final String jobId;
  final String companyId;
  final TimerState timer;
  final AsyncValue<List<TimeEntry>> entriesAsync;

  const _TimerBody({
    required this.jobId,
    required this.companyId,
    required this.timer,
    required this.entriesAsync,
  });

  bool get _isActiveOnThisJob => timer.activeJobId == jobId;
  bool get _isActiveOnOtherJob =>
      timer.activeEntry != null && timer.activeJobId != jobId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return ListView(
      padding: const EdgeInsets.all(24),
      children: [
        // ── Elapsed display ──────────────────────────────────────────────────
        Center(
          child: _ElapsedDisplay(
            seconds: _isActiveOnThisJob ? timer.elapsedSeconds : 0,
            isActive: _isActiveOnThisJob,
          ),
        ),
        const SizedBox(height: 8),

        // ── Pulsing dot + "In progress" label ───────────────────────────────
        if (_isActiveOnThisJob)
          Center(
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                _PulsingDot(color: Theme.of(context).colorScheme.error),
                const SizedBox(width: 8),
                Text(
                  'Recording time',
                  style: Theme.of(context).textTheme.labelLarge?.copyWith(
                        color: Theme.of(context).colorScheme.error,
                        fontWeight: FontWeight.w600,
                      ),
                ),
              ],
            ),
          ),

        // ── Warning for clocked-in-elsewhere ────────────────────────────────
        if (_isActiveOnOtherJob)
          Container(
            margin: const EdgeInsets.only(top: 8),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: Colors.orange.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: Colors.orange.shade300),
            ),
            child: Row(
              children: [
                const Icon(Icons.warning_amber_rounded,
                    color: Colors.orange, size: 18),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'You are currently clocked in to another job. Clocking in here will auto-clock you out.',
                    style: TextStyle(
                        color: Colors.orange.shade800, fontSize: 12),
                  ),
                ),
              ],
            ),
          ),

        const SizedBox(height: 24),

        // ── Clock In / Clock Out button ──────────────────────────────────────
        _ClockButton(
          jobId: jobId,
          companyId: companyId,
          timer: timer,
          isActiveOnThisJob: _isActiveOnThisJob,
          isActiveOnOtherJob: _isActiveOnOtherJob,
        ),

        const SizedBox(height: 32),

        // ── Session history ──────────────────────────────────────────────────
        entriesAsync.when(
          data: (entries) {
            if (entries.isEmpty) {
              return const Center(
                child: Padding(
                  padding: EdgeInsets.all(24),
                  child: Text(
                    'No time sessions yet.\nTap Clock In to start.',
                    textAlign: TextAlign.center,
                  ),
                ),
              );
            }
            return _SessionHistoryList(
              entries: entries,
              activeJobId: timer.activeJobId,
              elapsedSeconds:
                  _isActiveOnThisJob ? timer.elapsedSeconds : 0,
            );
          },
          loading: () =>
              const Center(child: CircularProgressIndicator()),
          error: (e, _) => Center(child: Text('Error: $e')),
        ),
      ],
    );
  }
}

// ─── Elapsed display ──────────────────────────────────────────────────────────

class _ElapsedDisplay extends StatelessWidget {
  final int seconds;
  final bool isActive;

  const _ElapsedDisplay({required this.seconds, required this.isActive});

  @override
  Widget build(BuildContext context) {
    final h = seconds ~/ 3600;
    final m = (seconds % 3600) ~/ 60;
    final s = seconds % 60;
    final formatted =
        '${h.toString().padLeft(2, '0')}:${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';

    return Text(
      formatted,
      style: TextStyle(
        fontSize: 64,
        fontWeight: FontWeight.w300,
        fontFeatures: const [FontFeature.tabularFigures()],
        color: isActive
            ? Theme.of(context).colorScheme.primary
            : Theme.of(context).colorScheme.onSurfaceVariant,
        letterSpacing: 2,
      ),
    );
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
      builder: (context, child) => Opacity(
        opacity: _animation.value,
        child: Container(
          width: 10,
          height: 10,
          decoration: BoxDecoration(
            color: widget.color,
            shape: BoxShape.circle,
          ),
        ),
      ),
    );
  }
}

// ─── Clock button ─────────────────────────────────────────────────────────────

class _ClockButton extends ConsumerWidget {
  final String jobId;
  final String companyId;
  final TimerState timer;
  final bool isActiveOnThisJob;
  final bool isActiveOnOtherJob;

  const _ClockButton({
    required this.jobId,
    required this.companyId,
    required this.timer,
    required this.isActiveOnThisJob,
    required this.isActiveOnOtherJob,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (isActiveOnThisJob) {
      // Clock out button
      return SizedBox(
        width: double.infinity,
        child: FilledButton.icon(
          onPressed: () => _clockOut(context, ref),
          icon: const Icon(Icons.stop_circle_outlined),
          label: const Text('Clock Out'),
          style: FilledButton.styleFrom(
            backgroundColor: Theme.of(context).colorScheme.error,
            minimumSize: const Size.fromHeight(56),
          ),
        ),
      );
    }

    // Clock in button (with warning text if active elsewhere)
    final label = isActiveOnOtherJob
        ? 'Clock In (will clock out of current job)'
        : 'Clock In';

    return SizedBox(
      width: double.infinity,
      child: FilledButton.icon(
        onPressed: () => _clockIn(context, ref),
        icon: const Icon(Icons.play_circle_outlined),
        label: Text(label),
        style: FilledButton.styleFrom(
          backgroundColor: Colors.green.shade600,
          minimumSize: const Size.fromHeight(56),
        ),
      ),
    );
  }

  Future<void> _clockIn(BuildContext context, WidgetRef ref) async {
    try {
      await ref
          .read(timerNotifierProvider.notifier)
          .clockIn(jobId, companyId);
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to clock in: $e'),
            backgroundColor: Theme.of(context).colorScheme.error,
          ),
        );
      }
    }
  }

  Future<void> _clockOut(BuildContext context, WidgetRef ref) async {
    try {
      await ref.read(timerNotifierProvider.notifier).clockOut();
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to clock out: $e'),
            backgroundColor: Theme.of(context).colorScheme.error,
          ),
        );
      }
    }
  }
}

// ─── Session history list ─────────────────────────────────────────────────────

class _SessionHistoryList extends StatelessWidget {
  final List<TimeEntry> entries;
  final String? activeJobId;
  final int elapsedSeconds;

  const _SessionHistoryList({
    required this.entries,
    required this.activeJobId,
    required this.elapsedSeconds,
  });

  @override
  Widget build(BuildContext context) {
    // Compute total seconds (completed sessions + current active if any).
    int totalSeconds = 0;
    for (final e in entries) {
      if (e.clockedOutAt != null && e.durationSeconds != null) {
        totalSeconds += e.durationSeconds!;
      }
    }
    // Add live elapsed for active session if it's for this job.
    totalSeconds += elapsedSeconds;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Sessions',
          style: Theme.of(context).textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w700,
              ),
        ),
        const SizedBox(height: 8),
        ...entries.map(
          (entry) => _SessionCard(
            entry: entry,
            isActive: entry.clockedOutAt == null,
            liveElapsedSeconds:
                entry.clockedOutAt == null ? elapsedSeconds : 0,
          ),
        ),
        const Divider(height: 24),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              'Total Time',
              style: Theme.of(context).textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
            ),
            Text(
              _formatDuration(totalSeconds),
              style: Theme.of(context).textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w700,
                    color: Theme.of(context).colorScheme.primary,
                  ),
            ),
          ],
        ),
      ],
    );
  }

  String _formatDuration(int seconds) {
    if (seconds <= 0) return '0m';
    final h = seconds ~/ 3600;
    final m = (seconds % 3600) ~/ 60;
    if (h > 0) return '${h}h ${m}m';
    return '${m}m';
  }
}

class _SessionCard extends StatelessWidget {
  final TimeEntry entry;
  final bool isActive;
  final int liveElapsedSeconds;

  const _SessionCard({
    required this.entry,
    required this.isActive,
    required this.liveElapsedSeconds,
  });

  @override
  Widget build(BuildContext context) {
    final date = _formatDate(entry.clockedInAt);
    final startTime = _formatTime(entry.clockedInAt);
    final endLabel = isActive
        ? 'In progress'
        : (entry.clockedOutAt != null ? _formatTime(entry.clockedOutAt!) : '—');
    final duration = isActive
        ? _formatDuration(liveElapsedSeconds)
        : (entry.durationSeconds != null
            ? _formatDuration(entry.durationSeconds!)
            : '—');

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: isActive
            ? Theme.of(context).colorScheme.primaryContainer.withValues(alpha: 0.4)
            : Theme.of(context).colorScheme.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(8),
        border: isActive
            ? Border.all(
                color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.5))
            : null,
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  date,
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                        color:
                            Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                ),
                Text(
                  '$startTime — $endLabel',
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
              ],
            ),
          ),
          Text(
            duration,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  fontWeight: FontWeight.w600,
                  color: isActive
                      ? Theme.of(context).colorScheme.primary
                      : null,
                ),
          ),
        ],
      ),
    );
  }

  String _formatDate(DateTime dt) {
    const months = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
    ];
    return '${months[dt.month - 1]} ${dt.day}, ${dt.year}';
  }

  String _formatTime(DateTime dt) {
    final h = dt.hour % 12 == 0 ? 12 : dt.hour % 12;
    final m = dt.minute.toString().padLeft(2, '0');
    final period = dt.hour < 12 ? 'AM' : 'PM';
    return '$h:$m $period';
  }

  String _formatDuration(int seconds) {
    if (seconds <= 0) return '0m';
    final h = seconds ~/ 3600;
    final m = (seconds % 3600) ~/ 60;
    if (h > 0) return '${h}h ${m}m';
    return '${m}m';
  }
}
