import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

// app_database.dart re-exports NoteDao and AttachmentDao.
import '../../../../core/database/app_database.dart';
import '../../../../core/di/service_locator.dart';
import '../../domain/note_entity.dart';
import '../providers/note_providers.dart';
import 'add_note_bottom_sheet.dart';
import 'attachment_thumbnail.dart';

/// Notes tab content for the job detail screen.
///
/// Displays timestamped field notes newest-first with inline attachment thumbnails.
/// Notes are immutable — no edit or delete actions (per user decision).
///
/// FAB opens [AddNoteBottomSheet] for adding text notes with optional attachments.
/// Empty state shows a centered prompt to add the first note.
class NotesTab extends ConsumerWidget {
  final String jobId;
  final String companyId;
  final String authorId;

  const NotesTab({
    required this.jobId,
    required this.companyId,
    required this.authorId,
    super.key,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final notesAsync = ref.watch(notesForJobProvider(jobId));

    return Stack(
      children: [
        notesAsync.when(
          data: (notes) {
            if (notes.isEmpty) {
              return _EmptyNotesState(
                onAddNote: () => _openAddNote(context),
              );
            }
            return _NotesList(notes: notes);
          },
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (e, _) => Center(child: Text('Error loading notes: $e')),
        ),
        // FAB positioned in lower-right
        Positioned(
          bottom: 16,
          right: 16,
          child: FloatingActionButton.extended(
            onPressed: () => _openAddNote(context),
            icon: const Icon(Icons.add_comment_outlined),
            label: const Text('Add Note'),
          ),
        ),
      ],
    );
  }

  void _openAddNote(BuildContext context) {
    AddNoteBottomSheet.show(
      context: context,
      jobId: jobId,
      companyId: companyId,
      authorId: authorId,
      noteDao: getIt<NoteDao>(),
      attachmentDao: getIt<AttachmentDao>(),
    );
  }
}

// ─── Notes list ────────────────────────────────────────────────────────────────

class _NotesList extends StatelessWidget {
  final List<NoteEntity> notes;

  const _NotesList({required this.notes});

  @override
  Widget build(BuildContext context) {
    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 96), // leave room for FAB
      itemCount: notes.length,
      separatorBuilder: (_, __) => const SizedBox(height: 8),
      itemBuilder: (context, index) => _NoteCard(note: notes[index]),
    );
  }
}

// ─── Note card ─────────────────────────────────────────────────────────────────

class _NoteCard extends StatelessWidget {
  final NoteEntity note;

  const _NoteCard({required this.note});

  @override
  Widget build(BuildContext context) {
    final accentColor = _accentColorForAuthor(context);
    final relativeTime = _formatRelativeTime(note.createdAt);

    return Card(
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8),
        side: BorderSide(
          color: Theme.of(context).colorScheme.outlineVariant,
        ),
      ),
      child: IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Left accent bar
            Container(
              width: 4,
              decoration: BoxDecoration(
                color: accentColor,
                borderRadius: const BorderRadius.only(
                  topLeft: Radius.circular(8),
                  bottomLeft: Radius.circular(8),
                ),
              ),
            ),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Header row: author ID + timestamp
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            // Display authorId for now — Phase 07 will resolve names
                            _truncateAuthorId(note.authorId),
                            style: Theme.of(context)
                                .textTheme
                                .labelMedium
                                ?.copyWith(fontWeight: FontWeight.w600),
                          ),
                        ),
                        Text(
                          relativeTime,
                          style:
                              Theme.of(context).textTheme.labelSmall?.copyWith(
                                    color: Theme.of(context)
                                        .colorScheme
                                        .onSurfaceVariant,
                                  ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    // Body text
                    Text(
                      note.body,
                      style: Theme.of(context).textTheme.bodyMedium,
                    ),
                    // Attachments row (if any)
                    if (note.attachments.isNotEmpty) ...[
                      const SizedBox(height: 8),
                      SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        child: Row(
                          children: note.attachments
                              .map(
                                (a) => Padding(
                                  padding: const EdgeInsets.only(right: 6),
                                  child: AttachmentThumbnail(attachment: a),
                                ),
                              )
                              .toList(),
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
    );
  }

  Color _accentColorForAuthor(BuildContext context) {
    // Role-based accent: we don't have role info here in v1
    // Use a stable color derived from the authorId hash
    final hash = note.authorId.codeUnits.fold(0, (a, b) => a + b);
    final colors = [
      Colors.blue.shade400,
      Colors.green.shade400,
      Colors.orange.shade400,
      Colors.purple.shade400,
    ];
    return colors[hash % colors.length];
  }

  String _truncateAuthorId(String authorId) {
    // Show last 8 chars of UUID as compact identifier
    if (authorId.length > 8) {
      return '...${authorId.substring(authorId.length - 8)}';
    }
    return authorId;
  }

  String _formatRelativeTime(DateTime timestamp) {
    final now = DateTime.now();
    final diff = now.difference(timestamp);

    if (diff.inSeconds < 60) return 'Just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes} min ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    if (diff.inDays == 1) return 'Yesterday';
    if (diff.inDays < 7) return '${diff.inDays} days ago';

    // Fallback: date string
    return '${timestamp.day}/${timestamp.month}/${timestamp.year}';
  }
}

// ─── Empty state ───────────────────────────────────────────────────────────────

class _EmptyNotesState extends StatelessWidget {
  final VoidCallback onAddNote;

  const _EmptyNotesState({required this.onAddNote});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.sticky_note_2_outlined,
              size: 64,
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
            const SizedBox(height: 16),
            const Text(
              'No notes yet',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            Text(
              'Add field notes, photos, and documents to keep a record of this job.',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 24),
            FilledButton.icon(
              onPressed: onAddNote,
              icon: const Icon(Icons.add_comment_outlined),
              label: const Text('Add the first note'),
            ),
          ],
        ),
      ),
    );
  }
}
