import 'package:drift/drift.dart';
import 'package:uuid/uuid.dart';

/// Drift table definition for the CostReceipt entity.
///
/// A CostReceipt is a photo/document receipt attached to a cost entry
/// (zero-to-many, D-04). Receipts are captured offline and queued for
/// upload via `CostReceiptUploadService` — this table mirrors [Attachments]
/// exactly, NOT the broken `TaskAttachments` pattern (31-RESEARCH.md
/// Pitfall 1: `TaskAttachment`'s sync flow has no registered push handler).
///
/// [uploadStatus] tracks the local upload lifecycle:
///   - 'pending_upload': captured locally, not yet uploaded
///   - 'uploading': upload in progress
///   - 'uploaded': successfully uploaded, [remoteUrl] is set
///   - 'failed': upload attempt failed, will be retried
///
/// Receipts are NOT in the sync_queue text outbox and are NOT part of the
/// company-wide /sync delta — they use a dedicated binary upload service and
/// are fetched on-demand per cost entry (31-RESEARCH.md Pitfall 2).
class CostReceipts extends Table {
  TextColumn get id => text().clientDefault(() => const Uuid().v4())();

  /// FK to Companies.id — tenant scope.
  TextColumn get companyId => text()();

  /// Soft FK to CostEntries.id — the cost entry this receipt belongs to.
  TextColumn get costEntryId => text()();

  /// Absolute path to the local file on device storage.
  TextColumn get localPath => text()();

  /// Absolute path to the compressed thumbnail, if generated.
  TextColumn get thumbnailPath => text().nullable()();

  /// Optional caption for display.
  TextColumn get caption => text().nullable()();

  /// Upload lifecycle state. See class-level documentation.
  TextColumn get uploadStatus =>
      text().withDefault(const Constant('pending_upload'))();

  /// Public URL of the uploaded file (set after successful upload).
  TextColumn get remoteUrl => text().nullable()();

  /// Number of upload retry attempts made so far.
  IntColumn get retryCount => integer().withDefault(const Constant(0))();

  DateTimeColumn get createdAt => dateTime()();
  DateTimeColumn get updatedAt => dateTime()();

  /// Soft-delete for sync tombstone propagation across devices.
  DateTimeColumn get deletedAt => dateTime().nullable()();

  @override
  Set<Column> get primaryKey => {id};
}
