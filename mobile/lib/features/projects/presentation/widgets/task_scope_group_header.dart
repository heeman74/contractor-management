import 'package:flutter/material.dart';

/// Collapsible section header for a trade scope group in the My Tasks screen.
///
/// Shows the trade name, completed/total count, and expand/collapse icon.
/// Collapsed state is managed in the parent StatefulWidget — no Drift persistence.
class TaskScopeGroupHeader extends StatelessWidget {
  const TaskScopeGroupHeader({
    required this.tradeName,
    required this.completedCount,
    required this.totalCount,
    required this.isCollapsed,
    required this.onToggle,
    super.key,
  });

  final String tradeName;
  final int completedCount;
  final int totalCount;
  final bool isCollapsed;
  final VoidCallback onToggle;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final colorScheme = Theme.of(context).colorScheme;

    return Semantics(
      label: isCollapsed
          ? 'Expand $tradeName tasks'
          : 'Collapse $tradeName tasks',
      child: InkWell(
        onTap: onToggle,
        child: Container(
          height: 48,
          padding: const EdgeInsets.symmetric(horizontal: 16),
          color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  tradeName,
                  style: textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const SizedBox(width: 8),
              Text(
                '$completedCount/$totalCount complete',
                style: textTheme.bodySmall?.copyWith(
                  color: colorScheme.onSurface.withValues(alpha: 0.6),
                ),
              ),
              const SizedBox(width: 4),
              Icon(
                isCollapsed ? Icons.expand_more : Icons.expand_less,
                color: colorScheme.onSurface.withValues(alpha: 0.6),
                size: 20,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
