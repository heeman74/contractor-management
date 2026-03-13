import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../features/jobs/domain/job_entity.dart';
import '../../../../features/jobs/presentation/providers/note_providers.dart';

/// Read-only activity log tab for the client job detail screen.
///
/// Merges three event types into a single chronological list (newest first):
///   a. Contractor notes — body text, attachment count badge, timestamp.
///   b. Delay events — parsed from [JobEntity.statusHistory] where type=='delay'.
///   c. Status transitions — parsed from statusHistory where type=='transition'.
///
/// Events are sorted by their timestamps, newest first.
/// No user interaction beyond scrolling — read-only view.
class ClientNotesTab extends ConsumerWidget {
  final String jobId;
  final JobEntity job;

  const ClientNotesTab({super.key, required this.jobId, required this.job});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final notesAsync = ref.watch(notesForJobProvider(jobId));

    return notesAsync.when(
      data: (notes) {
        // Build the unified activity list.
        final entries = <_ActivityEntry>[];

        // Add contractor notes.
        for (final note in notes) {
          entries.add(
            _ActivityEntry(
              type: _EntryType.note,
              timestamp: note.createdAt,
              content: note.body,
              attachmentCount: note.attachments.length,
              authorId: note.authorId,
            ),
          );
        }

        // Parse status history entries.
        for (final entry in job.statusHistory) {
          final type = entry['type'] as String? ?? '';
          final rawTs = entry['timestamp'] as String?;
          DateTime? ts;
          if (rawTs != null) {
            try {
              ts = DateTime.parse(rawTs);
            } catch (_) {}
          }
          ts ??= job.updatedAt;

          if (type == 'delay') {
            entries.add(
              _ActivityEntry(
                type: _EntryType.delay,
                timestamp: ts,
                content: entry['reason'] as String? ?? 'Delay reported',
                newEta: entry['new_eta'] as String?,
              ),
            );
          } else if (type == 'transition') {
            final toStatus = entry['to'] as String? ?? entry['status'] as String?;
            entries.add(
              _ActivityEntry(
                type: _EntryType.transition,
                timestamp: ts,
                content: toStatus != null
                    ? 'Status changed to ${_formatStatus(toStatus)}'
                    : 'Status updated',
              ),
            );
          }
        }

        // Sort newest first.
        entries.sort((a, b) => b.timestamp.compareTo(a.timestamp));

        if (entries.isEmpty) {
          return Center(
            child: Padding(
              padding: const EdgeInsets.all(32),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    Icons.notes_outlined,
                    size: 64,
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'No activity yet',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ],
              ),
            ),
          );
        }

        return ListView.builder(
          padding: const EdgeInsets.all(8),
          itemCount: entries.length,
          itemBuilder: (context, index) {
            return _ActivityCard(entry: entries[index]);
          },
        );
      },
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) =>
          Center(child: Text('Error loading activity: $e')),
    );
  }

  String _formatStatus(String raw) {
    return raw.replaceAll('_', ' ').replaceFirstMapped(
      RegExp(r'^[a-z]'),
      (m) => m.group(0)!.toUpperCase(),
    );
  }
}

// ─── Internal data model ──────────────────────────────────────────────────────

enum _EntryType { note, delay, transition }

class _ActivityEntry {
  final _EntryType type;
  final DateTime timestamp;
  final String content;
  final int attachmentCount;
  final String? authorId;
  final String? newEta;

  const _ActivityEntry({
    required this.type,
    required this.timestamp,
    required this.content,
    this.attachmentCount = 0,
    this.authorId,
    this.newEta,
  });
}

// ─── Activity card widget ─────────────────────────────────────────────────────

class _ActivityCard extends StatelessWidget {
  final _ActivityEntry entry;

  const _ActivityCard({required this.entry});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    IconData icon;
    Color iconColor;
    String title;

    switch (entry.type) {
      case _EntryType.note:
        icon = Icons.sticky_note_2_outlined;
        iconColor = theme.colorScheme.primary;
        title = 'Contractor Note';
      case _EntryType.delay:
        icon = Icons.warning_amber_rounded;
        iconColor = Colors.orange;
        title = 'Delay Reported';
      case _EntryType.transition:
        icon = Icons.info_outline;
        iconColor = Colors.blue;
        title = entry.content;
    }

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
      elevation: 1,
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: iconColor.withValues(alpha: 0.12),
          child: Icon(icon, color: iconColor, size: 20),
        ),
        title: Text(
          title,
          style: theme.textTheme.bodyMedium
              ?.copyWith(fontWeight: FontWeight.w600),
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (entry.type == _EntryType.note && entry.content.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(
                  entry.content,
                  style: theme.textTheme.bodySmall,
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            if (entry.type == _EntryType.delay && entry.content.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(
                  entry.content,
                  style: theme.textTheme.bodySmall,
                ),
              ),
            if (entry.newEta != null)
              Padding(
                padding: const EdgeInsets.only(top: 2),
                child: Text(
                  'New ETA: ${entry.newEta}',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: Colors.orange.shade800,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
            if (entry.attachmentCount > 0)
              Padding(
                padding: const EdgeInsets.only(top: 2),
                child: Row(
                  children: [
                    Icon(Icons.attach_file, size: 12,
                        color: theme.colorScheme.onSurfaceVariant),
                    const SizedBox(width: 2),
                    Text(
                      '${entry.attachmentCount} attachment${entry.attachmentCount == 1 ? '' : 's'}',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                _formatTimestamp(entry.timestamp),
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                  fontSize: 11,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _formatTimestamp(DateTime dt) {
    final local = dt.toLocal();
    final now = DateTime.now();
    final diff = now.difference(local);

    if (diff.inMinutes < 1) return 'Just now';
    if (diff.inHours < 1) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    return '${local.day}/${local.month}/${local.year}';
  }
}
