import 'package:flutter/material.dart';

import '../../../../core/database/app_database.dart'
    hide UserRole, BookingDao, NoteDao, AttachmentDao, TimeEntryDao,
        QuoteDao, InvoiceDao;

/// A single immutable note entry in the task notes list.
///
/// Displays:
/// - Author ID (truncated) in bold + relative timestamp on the right
/// - Note body text below
///
/// Notes are immutable per D-11 — no edit or delete buttons shown.
class TaskNoteItem extends StatelessWidget {
  const TaskNoteItem({required this.note, super.key});

  final TaskNote note;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final colorScheme = Theme.of(context).colorScheme;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                _authorLabel(note.authorId),
                style: textTheme.bodySmall?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
              const Spacer(),
              Text(
                _relativeTime(note.createdAt),
                style: textTheme.bodySmall?.copyWith(
                  color: colorScheme.onSurface.withValues(alpha: 0.5),
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            note.body,
            style: textTheme.bodyMedium,
          ),
          const Divider(height: 16),
        ],
      ),
    );
  }

  /// Show a shortened version of the authorId as a display label.
  ///
  /// Full name lookup is deferred (per State.md decision) — falls back to
  /// the last 8 chars of the user UUID prefixed with "#".
  static String _authorLabel(String authorId) {
    if (authorId.length <= 8) return authorId;
    return '#${authorId.substring(authorId.length - 8)}';
  }

  /// Returns a human-friendly relative timestamp.
  ///
  /// Examples: "just now", "5m ago", "2h ago", "Yesterday", "12/3/2025"
  static String _relativeTime(DateTime createdAt) {
    final now = DateTime.now();
    final diff = now.difference(createdAt);

    if (diff.inMinutes < 1) return 'just now';
    if (diff.inHours < 1) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    if (diff.inDays == 1) return 'Yesterday';
    return '${createdAt.day}/${createdAt.month}/${createdAt.year}';
  }
}
