import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/database/app_database.dart';
import '../../../../core/di/service_locator.dart';
import '../../../jobs/domain/attachment_entity.dart';
import '../../../jobs/domain/job_entity.dart';
import '../../../jobs/domain/job_request_entity.dart';

// ─── Client job stream ────────────────────────────────────────────────────────

/// Streams a single job by ID for the client detail screen.
///
/// Uses [JobDao.watchJobById] — reactive, offline-first.
/// Emits null when the job is not found locally (e.g., before first sync).
///
/// NOTE: GetIt used here because JobDao is a database accessor registered
/// at startup in service_locator.dart. (CLAUDE.md: document GetIt<->Riverpod tradeoffs)
final clientJobProvider =
    StreamProvider.autoDispose.family<JobEntity?, String>((ref, jobId) {
  final jobDao = getIt<JobDao>();
  return jobDao.watchJobById(jobId);
});

// ─── Photos provider ──────────────────────────────────────────────────────────

/// Derives the list of uploaded photos/drawings for a job from the notes stream.
///
/// - Filters by uploadStatus == 'uploaded' AND remoteUrl != null.
/// - Filters by attachmentType == 'photo' OR attachmentType == 'drawing'.
/// - Sorts chronologically by createdAt (oldest first — timeline order).
///
/// Derived from [notesForJobProvider] — no extra DB query needed.
/// Uses StreamProvider.autoDispose.family — one instance per jobId.
final photosForJobProvider =
    StreamProvider.autoDispose.family<List<AttachmentEntity>, String>(
  (ref, jobId) async* {
    // Watch notesForJobProvider — when notes change, re-derive photos.
    // Riverpod 3: use ref.watch inside async* and listen to changes via
    // the underlying stream from notesForJobProvider.
    final noteDao = getIt<NoteDao>();
    final attachmentDao = getIt<AttachmentDao>();

    await for (final notes in noteDao.watchNotesForJob(jobId)) {
      final allAttachments = <AttachmentEntity>[];

      for (final note in notes) {
        final attachments =
            await attachmentDao.watchAttachmentsForNote(note.id).first;

        for (final a in attachments) {
          if (a.uploadStatus == 'uploaded' &&
              a.remoteUrl != null &&
              (a.attachmentType == 'photo' || a.attachmentType == 'drawing')) {
            allAttachments.add(
              AttachmentEntity(
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
            );
          }
        }
      }

      allAttachments.sort((a, b) => a.createdAt.compareTo(b.createdAt));
      yield allAttachments;
    }
  },
);

// ─── Pending requests provider (client-scoped) ────────────────────────────────

/// Streams job requests for a specific client, including pending, declined,
/// and request_more_info statuses.
///
/// Distinct from [pendingRequestsNotifierProvider] which is scoped to a company
/// and admin review — this provider is scoped to a client user for their portal.
///
/// NOTE: GetIt used here because JobDao is a database accessor registered
/// at startup in service_locator.dart. (CLAUDE.md: document GetIt<->Riverpod tradeoffs)
final clientPendingRequestsProvider =
    StreamProvider.autoDispose.family<List<JobRequestEntity>, String>(
  (ref, clientId) {
    final jobDao = getIt<JobDao>();
    return jobDao.watchRequestsForClient(clientId);
  },
);
