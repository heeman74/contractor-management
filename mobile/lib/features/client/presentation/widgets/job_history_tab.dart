import 'package:flutter/material.dart';

import '../../../jobs/domain/job_entity.dart';

/// "History" tab for the client job detail screen.
///
/// Renders the job's status history newest-first as a timeline of events.
class JobHistoryTab extends StatelessWidget {
  const JobHistoryTab({required this.job, super.key});

  final JobEntity job;

  @override
  Widget build(BuildContext context) {
    if (job.statusHistory.isEmpty) {
      return Center(
        child: Text(
          'No history yet.',
          style: TextStyle(
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
        ),
      );
    }

    // Display history newest-first
    final history = List<Map<String, dynamic>>.from(job.statusHistory)
        .reversed
        .toList();

    return ListView.separated(
      padding: const EdgeInsets.all(16),
      itemCount: history.length,
      separatorBuilder: (_, __) => const Divider(),
      itemBuilder: (context, index) {
        final entry = history[index];
        final entryType = entry['type'] as String?;

        return _HistoryEntryTile(entry: entry, entryType: entryType);
      },
    );
  }
}

/// A single history timeline entry — handles multiple event types:
/// - status transitions (type: null or 'status')
/// - delays (type: 'delay')
/// - quote events (type: quote_created / quote_sent / quote_viewed /
///   quote_approved / quote_declined / quote_revised)
/// - invoice events (type: invoice_generated)
class _HistoryEntryTile extends StatelessWidget {
  const _HistoryEntryTile({required this.entry, required this.entryType});

  final Map<String, dynamic> entry;
  final String? entryType;

  @override
  Widget build(BuildContext context) {
    final timestamp = entry['timestamp'] as String? ?? '';
    final reason = entry['reason'] as String?;
    final newEta = entry['new_eta'] as String?;

    final (IconData icon, Color color, String label) =
        _resolveEntryStyle(context);

    return ListTile(
      leading: Icon(icon, size: 18, color: color),
      title: Text(
        label,
        style: TextStyle(fontWeight: FontWeight.w600, color: color),
      ),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (timestamp.isNotEmpty) Text(timestamp),
          if (reason != null && reason.isNotEmpty)
            Text(
              'Reason: $reason',
              style: const TextStyle(fontStyle: FontStyle.italic),
            ),
          if (newEta != null && newEta.isNotEmpty) Text('New ETA: $newEta'),
        ],
      ),
    );
  }

  (IconData, Color, String) _resolveEntryStyle(BuildContext context) {
    final onSurface = Theme.of(context).colorScheme.onSurfaceVariant;
    final error = Theme.of(context).colorScheme.error;

    return switch (entryType) {
      'delay' => (Icons.schedule_send_outlined, error, 'DELAY REPORTED'),
      'quote_created' => (
          Icons.description_outlined,
          Colors.grey.shade600,
          'QUOTE CREATED',
        ),
      'quote_sent' => (
          Icons.send_outlined,
          Colors.blue,
          'QUOTE SENT FOR REVIEW',
        ),
      'quote_viewed' => (
          Icons.visibility_outlined,
          Colors.indigo,
          'QUOTE VIEWED',
        ),
      'quote_approved' => (
          Icons.check_circle_outline,
          Colors.green,
          'QUOTE APPROVED',
        ),
      'quote_declined' => (
          Icons.cancel_outlined,
          Colors.red,
          'QUOTE DECLINED',
        ),
      'quote_revised' => (
          Icons.edit_note_outlined,
          Colors.orange,
          'QUOTE REVISED',
        ),
      'invoice_generated' => (
          Icons.receipt_long_outlined,
          Colors.purple,
          'INVOICE GENERATED',
        ),
      _ => (
          Icons.circle,
          onSurface,
          (entry['status'] as String? ?? entryType ?? 'EVENT')
              .replaceAll('_', ' ')
              .toUpperCase(),
        ),
    };
  }
}
