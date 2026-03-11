import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:uuid/uuid.dart';

import '../../../core/database/app_database.dart';
import '../../../core/database/tables/attachments.dart';

part 'attachment_dao.g.dart';

/// Drift DAO for Attachment CRUD.
///
/// Attachments are NOT dual-written to the sync_queue text outbox —
/// they use a dedicated binary upload service (AttachmentUploadService,
/// Plan 06-03) for multipart file upload.
///
/// Text-field sync (remoteUrl, uploadStatus) flows via the pull path in
/// [upsertFromSync] only, driven by the server after successful upload.
///
/// All read methods return [Stream] — offline-first, reactive to local DB changes.
@DriftAccessor(
  tables: [Attachments],
)
class AttachmentDao extends DatabaseAccessor<AppDatabase>
    with _$AttachmentDaoMixin {
  AttachmentDao(super.db);

  // ────────────────────────────────────────────────────────────────────────
  // Attachment streams
  // ────────────────────────────────────────────────────────────────────────

  /// Reactive stream of active (non-deleted) attachments for a note.
  ///
  /// Ordered by [sortOrder] for consistent display in the attachment viewer.
  Stream<List<Attachment>> watchAttachmentsForNote(String noteId) {
    return (select(attachments)
          ..where(
            (tbl) =>
                tbl.noteId.equals(noteId) & tbl.deletedAt.isNull(),
          )
          ..orderBy([(tbl) => OrderingTerm.asc(tbl.sortOrder)]))
        .watch();
  }

  // ────────────────────────────────────────────────────────────────────────
  // Attachment mutations
  // ────────────────────────────────────────────────────────────────────────

  /// Insert a new attachment with [uploadStatus] = 'pending_upload'.
  ///
  /// Does NOT write to sync_queue — attachments use the binary upload service.
  /// Returns the generated attachment UUID.
  Future<String> insertAttachment({
    required String companyId,
    required String noteId,
    required String attachmentType,
    required String localPath,
    String? thumbnailPath,
    String? caption,
    int sortOrder = 0,
  }) async {
    final now = DateTime.now();
    final attachmentId = const Uuid().v4();

    await into(attachments).insert(
      AttachmentsCompanion.insert(
        id: Value(attachmentId),
        companyId: companyId,
        noteId: noteId,
        attachmentType: attachmentType,
        localPath: localPath,
        thumbnailPath: Value(thumbnailPath),
        caption: Value(caption),
        sortOrder: Value(sortOrder),
        createdAt: now,
        updatedAt: now,
      ),
    );

    return attachmentId;
  }

  /// Get all attachments that need uploading.
  ///
  /// Returns attachments with [uploadStatus] = 'pending_upload' or 'failed',
  /// excluding soft-deleted rows. Used by AttachmentUploadService.
  Future<List<Attachment>> getPendingUploads() {
    return (select(attachments)
          ..where(
            (tbl) =>
                (tbl.uploadStatus.equals('pending_upload') |
                    tbl.uploadStatus.equals('failed')) &
                tbl.deletedAt.isNull(),
          )
          ..orderBy([(tbl) => OrderingTerm.asc(tbl.createdAt)]))
        .get();
  }

  /// Update the upload status for an attachment.
  Future<void> setUploadStatus(String id, String status) async {
    await (update(attachments)..where((tbl) => tbl.id.equals(id))).write(
      AttachmentsCompanion(
        uploadStatus: Value(status),
        updatedAt: Value(DateTime.now()),
      ),
    );
  }

  /// Mark an attachment as successfully uploaded with its remote URL.
  ///
  /// Sets [uploadStatus] = 'uploaded' and [remoteUrl] = url.
  Future<void> markUploaded(String id, String remoteUrl) async {
    await (update(attachments)..where((tbl) => tbl.id.equals(id))).write(
      AttachmentsCompanion(
        uploadStatus: const Value('uploaded'),
        remoteUrl: Value(remoteUrl),
        updatedAt: Value(DateTime.now()),
      ),
    );
  }

  /// Mark an attachment upload as failed.
  ///
  /// Sets [uploadStatus] = 'failed'. AttachmentUploadService tracks retry
  /// count externally and calls this to record the failure.
  Future<void> incrementRetry(String id) async {
    await (update(attachments)..where((tbl) => tbl.id.equals(id))).write(
      AttachmentsCompanion(
        uploadStatus: const Value('failed'),
        updatedAt: Value(DateTime.now()),
      ),
    );
  }

  // ────────────────────────────────────────────────────────────────────────
  // Sync pull upsert
  // ────────────────────────────────────────────────────────────────────────

  /// Upsert an attachment from a sync pull response (server-wins on conflict).
  ///
  /// Populates [remoteUrl] from the server response after successful upload.
  /// No sync_queue entry — this IS the sync.
  Future<void> upsertFromSync(Map<String, dynamic> data) async {
    final deletedAt = data['deleted_at'] != null
        ? DateTime.parse(data['deleted_at'] as String)
        : null;

    final companion = AttachmentsCompanion(
      id: Value(data['id'] as String),
      companyId: Value(data['company_id'] as String),
      noteId: Value(data['note_id'] as String),
      attachmentType: Value(data['attachment_type'] as String),
      localPath: Value(data['local_path'] is String ? data['local_path'] as String : ''),
      thumbnailPath: Value(data['thumbnail_path'] as String?),
      caption: Value(data['caption'] as String?),
      uploadStatus: Value(data['upload_status'] is String ? data['upload_status'] as String : 'uploaded'),
      remoteUrl: Value(data['remote_url'] as String?),
      sortOrder: data['sort_order'] != null
          ? Value(data['sort_order'] as int)
          : const Value.absent(),
      createdAt: data['created_at'] != null
          ? Value(DateTime.parse(data['created_at'] as String))
          : const Value.absent(),
      updatedAt: data['updated_at'] != null
          ? Value(DateTime.parse(data['updated_at'] as String))
          : const Value.absent(),
      deletedAt: Value(deletedAt),
    );

    await into(attachments).insertOnConflictUpdate(companion);
  }
}
