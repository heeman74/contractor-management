import 'package:flutter/material.dart';

import '../../../../core/database/app_database.dart' show ChatThread;

/// Chart color palette for trade scope thread type indicators.
///
/// Cycles through 5 colors (--chart-1 through --chart-5 equivalent in
/// Material 3 seed-color palette context) based on scope index.
const List<Color> _chartColors = [
  Color(0xFF2563EB), // chart-1: blue
  Color(0xFF16A34A), // chart-2: green
  Color(0xFFEA580C), // chart-3: orange
  Color(0xFF9333EA), // chart-4: purple
  Color(0xFFE11D48), // chart-5: rose
];

/// Chat thread list tile — shows thread info with unread badge.
///
/// Layout (minimum 56px height):
/// - Leading: trade color dot (scope) or group icon (project_wide)
/// - Title area: thread name + last-message preview
/// - Trailing: timestamp + unread badge
///
/// The unread badge is hidden when [ChatThread.unreadCount] == 0 and shows
/// "99+" when the count exceeds 99.
class ChatThreadTile extends StatelessWidget {
  const ChatThreadTile({
    required this.thread,
    required this.onTap,
    required this.onLongPress,
    this.tradeColorIndex = 0,
    this.isMuted = false,
    super.key,
  });

  final ChatThread thread;
  final VoidCallback onTap;
  final VoidCallback onLongPress;

  /// Index used to cycle trade scope thread dot color (0-based).
  final int tradeColorIndex;

  /// Whether this thread has been muted by the current user.
  /// When true, shows a bell-slash icon next to the thread name.
  final bool isMuted;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final textTheme = theme.textTheme;

    final isUnread = thread.unreadCount > 0;

    return Semantics(
      label:
          '${thread.name}, ${thread.unreadCount} unread messages, last message: $_lastMessagePreview',
      child: InkWell(
        onTap: onTap,
        onLongPress: onLongPress,
        child: Container(
          constraints: const BoxConstraints(minHeight: 56),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Row(
            children: [
              // Leading: thread type indicator
              _buildLeading(colorScheme),
              const SizedBox(width: 12),

              // Title area (Expanded)
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // Thread name row (bold if unread, mute icon if muted)
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            thread.name,
                            style: textTheme.titleMedium?.copyWith(
                              fontWeight: isUnread
                                  ? FontWeight.w600
                                  : FontWeight.w400,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        if (isMuted) ...[
                          const SizedBox(width: 4),
                          Icon(
                            Icons.notifications_off,
                            size: 14,
                            color: colorScheme.onSurface.withValues(alpha: 0.5),
                            semanticLabel: 'Thread muted',
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: 2),
                    // Last message preview
                    Text(
                      _lastMessagePreview,
                      style: textTheme.bodySmall?.copyWith(
                        color: colorScheme.onSurface.withValues(alpha: 0.6),
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),

              // Trailing: timestamp + unread badge
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Timestamp
                  Text(
                    _formatTimestamp(thread.lastMessageAt),
                    style: textTheme.bodySmall?.copyWith(
                      color: colorScheme.onSurface.withValues(alpha: 0.5),
                    ),
                  ),
                  if (isUnread) ...[
                    const SizedBox(height: 4),
                    _UnreadBadge(
                      count: thread.unreadCount,
                      color: colorScheme.primary,
                    ),
                  ],
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildLeading(ColorScheme colorScheme) {
    if (thread.threadType == 'scope') {
      // Trade scope: small colored dot
      final color = _chartColors[tradeColorIndex % _chartColors.length];
      return Container(
        width: 12,
        height: 12,
        decoration: BoxDecoration(
          color: color,
          shape: BoxShape.circle,
        ),
      );
    } else {
      // Project-wide: group icon
      return Icon(
        Icons.groups,
        color: colorScheme.secondary,
        size: 20,
      );
    }
  }

  String get _lastMessagePreview {
    // Placeholder — real last-message preview comes from a separate field
    // or a query join. For now we show an empty string (no last message yet).
    return '';
  }

  String _formatTimestamp(DateTime? dt) {
    if (dt == null) return '';

    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final msgDay = DateTime(dt.year, dt.month, dt.day);
    final diff = today.difference(msgDay).inDays;

    if (diff == 0) {
      // Same day — show time
      final hour = dt.hour;
      final minute = dt.minute.toString().padLeft(2, '0');
      final period = hour < 12 ? 'AM' : 'PM';
      final displayHour = hour == 0 ? 12 : (hour > 12 ? hour - 12 : hour);
      return '$displayHour:$minute $period';
    } else if (diff <= 6) {
      // This week — show day name
      const days = ['Sun', 'Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat'];
      return days[dt.weekday % 7];
    } else {
      // Older — show "Mar 18"
      const months = [
        'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
        'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
      ];
      return '${months[dt.month - 1]} ${dt.day}';
    }
  }
}

/// Circular unread count badge.
///
/// Shows the count as a number (1–99) or "99+" for counts above 99.
class _UnreadBadge extends StatelessWidget {
  const _UnreadBadge({required this.count, required this.color});

  final int count;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final label = count > 99 ? '99+' : '$count';

    return Semantics(
      label: '$count unread messages',
      child: Container(
        constraints: const BoxConstraints(minWidth: 20),
        height: 20,
        padding: const EdgeInsets.symmetric(horizontal: 6),
        decoration: BoxDecoration(
          color: color,
          borderRadius: BorderRadius.circular(10),
        ),
        alignment: Alignment.center,
        child: Text(
          label,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 11,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    );
  }
}
