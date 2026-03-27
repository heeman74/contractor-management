import 'package:flutter/material.dart';

import '../../../../features/jobs/domain/job_status.dart';

/// Horizontal step progress bar for the client job detail screen.
///
/// Displays the 5 lifecycle stages: Quote, Scheduled, In Progress, Complete, Invoiced.
/// Cancelled jobs should not use this widget — the parent should show a banner instead.
///
/// Completed stages: primary-color filled circle with check icon.
/// Current stage: primary-color filled circle with the step number.
/// Future stages: grey outlined circle with step number.
/// Connecting lines: primary color for completed transitions, grey for future.
class JobProgressStepper extends StatelessWidget {
  final JobStatus currentStatus;

  const JobProgressStepper({required this.currentStatus, super.key});

  static const _stages = [
    JobStatus.quote,
    JobStatus.scheduled,
    JobStatus.inProgress,
    JobStatus.complete,
    JobStatus.invoiced,
  ];

  static const _labels = [
    'Quote',
    'Scheduled',
    'In Progress',
    'Complete',
    'Invoiced',
  ];

  int get _currentIndex => _stages.indexOf(currentStatus);

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final primary = theme.colorScheme.primary;
    const grey = Colors.grey;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
        children: [
          for (int i = 0; i < _stages.length; i++) ...[
            // Step circle + label
            Expanded(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _StepCircle(
                    index: i,
                    currentIndex: _currentIndex,
                    primary: primary,
                    grey: grey,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    _labels[i],
                    style: theme.textTheme.bodySmall?.copyWith(
                      fontSize: 10,
                      color: i <= _currentIndex ? primary : grey,
                      fontWeight: i == _currentIndex
                          ? FontWeight.bold
                          : FontWeight.normal,
                    ),
                    textAlign: TextAlign.center,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
            // Connector line between steps (not after the last step)
            if (i < _stages.length - 1)
              Container(
                height: 2,
                width: 12,
                color: i < _currentIndex ? primary : grey.withValues(alpha: 0.3),
              ),
          ],
        ],
      ),
    );
  }
}

/// Individual step circle in the progress stepper.
class _StepCircle extends StatelessWidget {
  final int index;
  final int currentIndex;
  final Color primary;
  final Color grey;

  const _StepCircle({
    required this.index,
    required this.currentIndex,
    required this.primary,
    required this.grey,
  });

  @override
  Widget build(BuildContext context) {
    final isCompleted = index < currentIndex;
    final isCurrent = index == currentIndex;
    final isFuture = index > currentIndex;

    if (isCompleted) {
      return Container(
        width: 28,
        height: 28,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: primary,
        ),
        child: const Icon(Icons.check, color: Colors.white, size: 16),
      );
    }

    if (isCurrent) {
      return Container(
        width: 28,
        height: 28,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: primary,
        ),
        child: Center(
          child: Text(
            '${index + 1}',
            style: const TextStyle(
              color: Colors.white,
              fontSize: 12,
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
      );
    }

    // isFuture
    assert(isFuture);
    return Container(
      width: 28,
      height: 28,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(color: grey.withValues(alpha: 0.5), width: 2),
      ),
      child: Center(
        child: Text(
          '${index + 1}',
          style: TextStyle(
            color: grey,
            fontSize: 12,
            fontWeight: FontWeight.normal,
          ),
        ),
      ),
    );
  }
}
