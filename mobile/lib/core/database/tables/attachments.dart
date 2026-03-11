import 'package:drift/drift.dart';
import 'package:uuid/uuid.dart';

/// Drift table definition for the Attachment entity.
///
/// An Attachment is a photo, drawing, or file linked to a [JobNote].
/// Attachments are captured offline and queued for upload via the
/// [AttachmentUploadService] (Plan 06-03).
///
/// [uploadStatus] tracks the local upload lifecycle:
///   - 'pending_upload': captured locally, not yet uploaded
///   - 'uploading': upload in progress
///   - 'uploaded': successfully uploaded, [remoteUrl] is set
///   - 'failed': upload attempt failed, will be retried
///
/// [localPath] points to the device file system path for the media file.
/// [thumbnailPath] is a compressed preview for display in note cards.
///
/// Attachments are NOT in the sync_queue text outbox — they use a
/// dedicated upload service (binary multipart, not JSON).
/// Pull sync populates [remoteUrl] from the backend after upload.
class Attachments extends Table {
  TextColumn get id => text().clientDefault(() => const Uuid().v4())();

  /// FK to Companies.id — tenant scope.
  TextColumn get companyId => text()();

  /// FK to JobNotes.id — the note this attachment belongs to.
  TextColumn get noteId => text()();

  /// Media type identifier: 'photo' | 'drawing' | 'document'
  TextColumn get attachmentType => text()();

  /// Absolute path to the local file on device storage.
  TextColumn get localPath => text()();

  /// Absolute path to the compressed thumbnail, if generated.
  TextColumn get thumbnailPath => text().nullable()();

  /// Optional caption for display in the note attachment viewer.
  TextColumn get caption => text().nullable()();

  /// Upload lifecycle state. See class-level documentation.
  TextColumn get uploadStatus =>
      text().withDefault(const Constant('pending_upload'))();

  /// Public URL of the uploaded file (set after successful upload).
  TextColumn get remoteUrl => text().nullable()();

  /// Display order within the note's attachment list.
  IntColumn get sortOrder => integer().withDefault(const Constant(0))();

  DateTimeColumn get createdAt => dateTime()();
  DateTimeColumn get updatedAt => dateTime()();

  /// Soft-delete for sync tombstone propagation across devices.
  DateTimeColumn get deletedAt => dateTime().nullable()();

  @override
  Set<Column> get primaryKey => {id};
}
