import 'package:drift/drift.dart';
import 'package:uuid/uuid.dart';

import 'companies.dart';
import 'tasks.dart';

/// Drift table definition for the TaskAttachment entity.
///
/// A TaskAttachment is a photo, document, or other file linked to a [ProjectTask].
/// Supports both remote URLs (already uploaded) and local file paths (pending upload).
///
/// Unlike [Attachments] (for job notes), TaskAttachments track remote URLs
/// directly without a separate upload status — the sync handler propagates
/// them as part of the task attachment sync flow.
class TaskAttachments extends Table {
  TextColumn get id => text().clientDefault(() => const Uuid().v4())();
  TextColumn get companyId => text().references(Companies, #id)();

  /// FK to ProjectTasks.id — the task this attachment belongs to.
  TextColumn get taskId => text().references(ProjectTasks, #id)();

  /// Media type: 'photo' | 'document' | 'drawing'
  TextColumn get attachmentType => text()();

  /// Public URL of the uploaded file. Null until uploaded.
  TextColumn get remoteUrl => text().nullable()();

  /// Local file system path for offline-captured media.
  TextColumn get localPath => text().nullable()();

  /// Optional display caption for the attachment.
  TextColumn get caption => text().nullable()();

  /// JSON-encoded annotation overlay data for photo markup.
  ///
  /// Non-destructive: the base photo (localPath/remoteUrl) is never modified.
  /// Annotation strokes, arrows, circles, text, and measurements are stored
  /// here as a JSON string and rendered as an overlay layer on the client.
  /// Null until the user annotates the photo.
  TextColumn get annotationData => text().nullable()();

  /// Display order within the task's attachment list.
  IntColumn get sortOrder => integer().withDefault(const Constant(0))();

  IntColumn get version => integer().withDefault(const Constant(1))();
  DateTimeColumn get createdAt => dateTime()();
  DateTimeColumn get updatedAt => dateTime()();

  /// Soft-delete for sync tombstone propagation across devices.
  DateTimeColumn get deletedAt => dateTime().nullable()();

  @override
  Set<Column> get primaryKey => {id};
}
