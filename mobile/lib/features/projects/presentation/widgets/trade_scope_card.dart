import 'package:flutter/material.dart';

import 'project_status_badge.dart';

/// Card widget for displaying a trade scope within a project detail screen.
///
/// Layout per UI-SPEC:
/// - Left accent: 12px vertical bar in tradeColor
/// - Trade name in semibold
/// - Contractor name (or "Unassigned" in muted text)
/// - Right side: "X/Y tasks" count and status badge
/// - Bottom: LinearProgressIndicator in tradeColor (grey-100 track)
///
/// Props:
///   [tradeName] — display name of the trade (e.g. "Electrical")
///   [tradeColor] — brand color for this trade (hex string like "#3F51B5")
///   [contractorName] — assigned contractor's name, or null if unassigned
///   [completedTasks] — number of completed tasks in this scope
///   [totalTasks] — total active tasks in this scope
///   [status] — scope lifecycle status string
///   [onTap] — callback when card is tapped (navigate to scope detail)
class TradeScopeCard extends StatelessWidget {
  const TradeScopeCard({
    required this.tradeName,
    required this.tradeColor,
    required this.completedTasks,
    required this.totalTasks,
    required this.status,
    required this.onTap,
    this.contractorName,
    super.key,
  });

  final String tradeName;
  final Color tradeColor;
  final String? contractorName;
  final int completedTasks;
  final int totalTasks;
  final String status;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final progressValue =
        totalTasks > 0 ? completedTasks / totalTasks : 0.0;

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      elevation: 1,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              IntrinsicHeight(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // Left trade color accent bar
                    Container(
                      width: 12,
                      color: tradeColor,
                    ),
                    // Main content
                    Expanded(
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(12, 12, 12, 8),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            // Trade name + contractor
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    tradeName,
                                    style: textTheme.bodyMedium?.copyWith(
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    contractorName ?? 'Unassigned',
                                    style: textTheme.bodySmall?.copyWith(
                                      color: contractorName != null
                                          ? colorScheme.onSurface
                                              .withValues(alpha: 0.7)
                                          : colorScheme.onSurface
                                              .withValues(alpha: 0.4),
                                      fontStyle: contractorName == null
                                          ? FontStyle.italic
                                          : FontStyle.normal,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            // Task count + status badge
                            Column(
                              crossAxisAlignment: CrossAxisAlignment.end,
                              children: [
                                Text(
                                  '$completedTasks/$totalTasks tasks',
                                  style: textTheme.bodySmall?.copyWith(
                                    color: colorScheme.onSurface
                                        .withValues(alpha: 0.6),
                                  ),
                                ),
                                const SizedBox(height: 4),
                                ProjectStatusBadge(status: status),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              // Progress bar at the bottom of the card
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 0, 12, 10),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: LinearProgressIndicator(
                    value: progressValue,
                    minHeight: 4,
                    valueColor: AlwaysStoppedAnimation<Color>(tradeColor),
                    backgroundColor: const Color(0xFFF5F5F5),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Parse a hex color string (e.g. "#3F51B5" or "3F51B5") to a [Color].
/// Returns a grey fallback if the string is invalid.
Color hexToColor(String hex) {
  try {
    final cleaned = hex.replaceAll('#', '');
    final value = int.parse(cleaned, radix: 16);
    return Color(0xFF000000 | value);
  } catch (_) {
    return const Color(0xFF9E9E9E); // grey fallback
  }
}
