import 'package:flutter/material.dart';

import '../../../../core/database/app_database.dart'
    hide UserRole, BookingDao, NoteDao, AttachmentDao, TimeEntryDao,
        QuoteDao, InvoiceDao;

/// Card for a single punch list item.
///
/// Visual design:
/// - [Card] with elevation 0 + grey border (matches existing task card style)
/// - 4px deep-orange left edge (`0xFFE65100`) — visual differentiator from tasks
/// - Content column: description, then [Wrap] of Punch badge + priority + status chips
/// - Optional due date line below badges
///
/// Usage in [TradeScopeDetailScreen]:
/// ```dart
/// PunchListCard(item: item, onTap: () => _showPunchItemDetail(item))
/// ```
class PunchListCard extends StatelessWidget {
  const PunchListCard({
    required this.item,
    this.onTap,
    super.key,
  });

  final PunchListItem item;
  final VoidCallback? onTap;

  static String _fmtDate(DateTime dt) {
    final months = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'
    ];
    return '${months[dt.month - 1]} ${dt.day}, ${dt.year}';
  }

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;

    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: Colors.grey.shade200),
      ),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(12),
          child: IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Deep orange left edge — punch item differentiator
                Container(
                  width: 4,
                  color: const Color(0xFFE65100),
                ),
                // Content
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          item.description,
                          style: textTheme.bodyMedium,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 8),
                        Wrap(
                          spacing: 8,
                          runSpacing: 4,
                          children: [
                            // Punch badge
                            const Chip(
                              label: Text('Punch'),
                              backgroundColor: Color(0xFFE65100),
                              labelStyle: TextStyle(color: Colors.white),
                              visualDensity: VisualDensity.compact,
                              padding: EdgeInsets.zero,
                            ),
                            // Priority badge
                            _PriorityChip(priority: item.priority),
                            // Status badge
                            _StatusChip(status: item.status),
                          ],
                        ),
                        if (item.dueDate != null) ...[
                          const SizedBox(height: 4),
                          Text(
                            'Due: ${_fmtDate(item.dueDate!)}',
                            style: textTheme.bodySmall?.copyWith(
                              color: Theme.of(context)
                                  .colorScheme
                                  .onSurface
                                  .withValues(alpha: 0.6),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _PriorityChip extends StatelessWidget {
  const _PriorityChip({required this.priority});
  final String priority;

  Color _color() {
    return switch (priority) {
      'urgent' => const Color(0xFFD32F2F),
      'high' => const Color(0xFFF57C00),
      'medium' => const Color(0xFF1565C0),
      _ => const Color(0xFF9E9E9E),
    };
  }

  @override
  Widget build(BuildContext context) {
    return Chip(
      label: Text(priority),
      backgroundColor: _color(),
      labelStyle: const TextStyle(color: Colors.white),
      visualDensity: VisualDensity.compact,
      padding: EdgeInsets.zero,
    );
  }
}

class _StatusChip extends StatelessWidget {
  const _StatusChip({required this.status});
  final String status;

  Color _color() {
    return switch (status) {
      'in_progress' => const Color(0xFF1565C0),
      'resolved' => const Color(0xFF388E3C),
      'verified' => const Color(0xFF1B5E20),
      _ => const Color(0xFF9E9E9E), // open
    };
  }

  @override
  Widget build(BuildContext context) {
    return Chip(
      label: Text(status.replaceAll('_', ' ')),
      backgroundColor: _color(),
      labelStyle: const TextStyle(color: Colors.white),
      visualDensity: VisualDensity.compact,
      padding: EdgeInsets.zero,
    );
  }
}
