import 'package:drift/drift.dart';
import 'package:uuid/uuid.dart';

/// Drift table definition for the JobNote entity.
///
/// A JobNote is a field-created note on a job, written by a contractor or
/// admin during on-site work. Notes support rich attachments (photos, drawings)
/// via the [Attachments] table which FKs to [id].
///
/// [version] is used for optimistic locking on the backend — incremented
/// on every update to detect concurrent edit conflicts.
///
/// Offline-first: notes are created locally via NoteDao (with outbox
/// dual-write) and synced to the backend when connectivity is restored.
class JobNotes extends Table {
  TextColumn get id => text().clientDefault(() => const Uuid().v4())();

  /// FK to Companies.id — tenant scope.
  TextColumn get companyId => text()();

  /// FK to Jobs.id — the job this note belongs to.
  TextColumn get jobId => text()();

  /// FK to Users.id — the user who authored the note.
  TextColumn get authorId => text()();

  /// The note body text content.
  TextColumn get body => text()();

  IntColumn get version => integer().withDefault(const Constant(1))();
  DateTimeColumn get createdAt => dateTime()();
  DateTimeColumn get updatedAt => dateTime()();

  /// Soft-delete for sync tombstone propagation across devices.
  DateTimeColumn get deletedAt => dateTime().nullable()();

  @override
  Set<Column> get primaryKey => {id};
}
