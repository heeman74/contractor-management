import 'package:drift/drift.dart';

import '../../database/app_database.dart';
import '../sync_handler.dart';

/// SyncHandler implementation for the Attachment entity.
///
/// Attachments are pull-only from the sync engine perspective:
/// - Pull: upserts received entities into the local Drift [attachments] table.
/// - Push: NOT supported — attachments use [AttachmentUploadService] for
///   binary multipart upload, not the text-based sync queue outbox.
///
/// The [push] method throws [StateError] if called. Binary file upload
/// goes through [AttachmentUploadService], not [SyncEngine.drainQueue].
class AttachmentSyncHandler extends SyncHandler {
  final AppDatabase _db;

  AttachmentSyncHandler(this._db);

  @override
  String get entityType => 'attachment';

  @override
  Future<void> push(SyncQueueData item) async {
    // Attachments use AttachmentUploadService for binary upload.
    // If this is ever called, it indicates a programming error.
    throw StateError(
      'AttachmentSyncHandler: push not supported. '
      'Attachments use AttachmentUploadService for binary upload.',
    );
  }

  @override
  Future<void> applyPulled(Map<String, dynamic> data) async {
    final deletedAt = data['deleted_at'] != null
        ? DateTime.parse(data['deleted_at'] as String)
        : null;

    final companion = AttachmentsCompanion(
      id: Value(data['id'] as String),
      companyId: Value(data['company_id'] as String),
      noteId: Value(data['note_id'] as String),
      attachmentType: Value(data['attachment_type'] as String),
      // Server may not have local path — default to empty string (non-nullable column).
      localPath: Value(data['local_path'] as String? ?? ''),
      thumbnailPath: Value(data['thumbnail_path'] as String?),
      caption: Value(data['caption'] as String?),
      // Pulled from server means already uploaded.
      uploadStatus: Value(data['upload_status'] as String? ?? 'uploaded'),
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

    await _db.into(_db.attachments).insertOnConflictUpdate(companion);
  }
}
