import 'package:drift/drift.dart';
import 'package:uuid/uuid.dart';

import 'companies.dart';
import 'tasks.dart';

/// Drift table definition for the TaskNote entity.
///
/// A TaskNote is a field-created note on a project task, written by a
/// contractor during on-site work. Notes capture progress observations,
/// issues, or instructions for a specific [ProjectTask].
///
/// [version] is used for optimistic locking on the backend — incremented
/// on every update to detect concurrent edit conflicts.
///
/// Offline-first: notes are created locally via TaskNoteDao (with outbox
/// dual-write) and synced to the backend when connectivity is restored.
class TaskNotes extends Table {
  TextColumn get id => text().clientDefault(() => const Uuid().v4())();

  /// FK to Companies.id — tenant scope.
  TextColumn get companyId => text().references(Companies, #id)();

  /// FK to ProjectTasks.id — the task this note belongs to.
  TextColumn get taskId => text().references(ProjectTasks, #id)();

  /// FK to Users.id — the user who authored the note.
  /// Soft FK (no hard reference) to avoid cross-feature coupling.
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
