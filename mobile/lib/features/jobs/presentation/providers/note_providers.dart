import 'package:flutter_riverpod/flutter_riverpod.dart';

// app_database.dart re-exports NoteDao and AttachmentDao (and their generated
// Drift row types: JobNote, Attachment).
import '../../../../core/database/app_database.dart';
import '../../../../core/di/service_locator.dart';
import '../../domain/attachment_entity.dart';
import '../../domain/note_entity.dart';

// ─── DAO providers ────────────────────────────────────────────────────────────

/// Provider exposing the [NoteDao] singleton from GetIt.
///
/// NOTE: GetIt is used here because [NoteDao] is a database accessor registered
/// at startup in service_locator.dart. (CLAUDE.md: document GetIt<->Riverpod tradeoffs)
final noteDaoProvider = Provider<NoteDao>((ref) {
  return getIt<NoteDao>();
});

/// Provider exposing the [AttachmentDao] singleton from GetIt.
///
/// NOTE: GetIt is used here because [AttachmentDao] is a database accessor
/// registered at startup in service_locator.dart.
final attachmentDaoProvider = Provider<AttachmentDao>((ref) {
  return getIt<AttachmentDao>();
});

// ─── Notes stream providers ───────────────────────────────────────────────────

/// Streams all active notes for a job, newest-first, with their attachments.
///
/// For each note returned by [NoteDao.watchNotesForJob], a separate
/// stream merges in the attachments via [AttachmentDao.watchAttachmentsForNote].
/// The final list is a complete [NoteEntity] graph ready for UI display.
///
/// Uses StreamProvider.autoDispose.family — one instance per jobId.
/// Automatically disposed when the caller widget is removed.
final notesForJobProvider = StreamProvider.autoDispose
    .family<List<NoteEntity>, String>((ref, jobId) async* {
  final noteDao = ref.watch(noteDaoProvider);
  final attachmentDao = ref.watch(attachmentDaoProvider);

  // Listen to the notes stream and emit merged NoteEntity lists.
  await for (final notes in noteDao.watchNotesForJob(jobId)) {
    final entities = <NoteEntity>[];

    for (final note in notes) {
      // Fetch current attachments snapshot for this note (not streamed per-note
      // to avoid N+1 subscriptions; re-emits on any note list change).
      final attachments = await attachmentDao
          .watchAttachmentsForNote(note.id)
          .first;

      final attachmentEntities = attachments
          .map(
            (a) => AttachmentEntity(
              id: a.id,
              companyId: a.companyId,
              noteId: a.noteId,
              attachmentType: a.attachmentType,
              localPath: a.localPath,
              thumbnailPath: a.thumbnailPath,
              caption: a.caption,
              uploadStatus: a.uploadStatus,
              remoteUrl: a.remoteUrl,
              sortOrder: a.sortOrder,
              createdAt: a.createdAt,
              updatedAt: a.updatedAt,
              deletedAt: a.deletedAt,
            ),
          )
          .toList();

      entities.add(
        NoteEntity(
          id: note.id,
          companyId: note.companyId,
          jobId: note.jobId,
          authorId: note.authorId,
          body: note.body,
          version: note.version,
          createdAt: note.createdAt,
          updatedAt: note.updatedAt,
          deletedAt: note.deletedAt,
          attachments: attachmentEntities,
        ),
      );
    }

    yield entities;
  }
});

/// Derives the count of notes for a job for badge display.
///
/// Derives from [notesForJobProvider] — no separate DB query needed.
final noteCountProvider = Provider.autoDispose
    .family<int, String>((ref, jobId) {
  final notesAsync = ref.watch(notesForJobProvider(jobId));
  return notesAsync.maybeWhen(
    data: (notes) => notes.length,
    orElse: () => 0,
  );
});
