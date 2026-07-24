import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/routing/route_names.dart';

/// Empty state shown when a trade scope has no tasks and no punch items.
///
/// Offers a "Start AI Interview" action to generate a task plan.
class EmptyTasksState extends StatelessWidget {
  const EmptyTasksState({
    required this.scopeId,
    required this.tradeName,
    super.key,
  });

  final String scopeId;
  final String tradeName;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final colorScheme = Theme.of(context).colorScheme;

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.check_circle_outline,
              size: 64,
              color: colorScheme.onSurface.withValues(alpha: 0.3),
            ),
            const SizedBox(height: 16),
            Text(
              'No tasks yet',
              style: textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w600,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              'Use AI Interview to generate a detailed task plan for this trade scope.',
              style: textTheme.bodyMedium?.copyWith(
                color: colorScheme.onSurface.withValues(alpha: 0.6),
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),
            // Start Interview button — visible when no tasks exist
            ElevatedButton.icon(
              onPressed: () {
                context.push(
                  '${RouteNames.aiInterviewPath(scopeId)}?tradeName=${Uri.encodeComponent(tradeName)}',
                );
              },
              icon: const Icon(Icons.smart_toy),
              label: const Text('Start AI Interview'),
            ),
          ],
        ),
      ),
    );
  }
}
