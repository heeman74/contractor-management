import 'package:drift/drift.dart';
import 'package:uuid/uuid.dart';

import 'companies.dart';
import 'trade_scopes.dart';

/// Drift table definition for the ProjectTask entity.
///
/// Named [ProjectTasks] to avoid conflict with any existing Task class.
///
/// A ProjectTask is a discrete unit of work within a [TradeScope].
/// Tasks support offline creation, assignment, status tracking,
/// cost/time estimation, and photo documentation.
///
/// [materialsNeeded] and [dependsOn] are JSON-encoded lists stored as TEXT.
/// [dependsOn] contains task IDs this task must wait for before starting.
class ProjectTasks extends Table {
  TextColumn get id => text().clientDefault(() => const Uuid().v4())();
  TextColumn get companyId => text().references(Companies, #id)();

  /// FK to TradeScopes.id — the scope this task belongs to.
  TextColumn get tradeScopeId => text().references(TradeScopes, #id)();

  TextColumn get title => text()();
  TextColumn get description => text().nullable()();

  /// Task lifecycle state: not_started | in_progress | complete | blocked
  TextColumn get status =>
      text().withDefault(const Constant('not_started'))();

  /// Display order within the scope's task list.
  IntColumn get sortOrder => integer().withDefault(const Constant(0))();

  /// Priority level: low | medium | high | urgent
  TextColumn get priority =>
      text().withDefault(const Constant('medium'))();

  /// Estimated hours to complete this task.
  RealColumn get estimatedHours => real().nullable()();

  /// Estimated cost in base currency units.
  RealColumn get estimatedCost => real().nullable()();

  DateTimeColumn get dueDate => dateTime().nullable()();

  /// When true, task completion requires a photo attachment.
  BoolColumn get photoRequired =>
      boolean().withDefault(const Constant(false))();

  /// FK to Users.id — the user assigned to this task. Nullable.
  TextColumn get assignedTo => text().nullable()();

  /// JSON-encoded list of material names/items needed for this task.
  TextColumn get materialsNeeded =>
      text().withDefault(const Constant('[]'))();

  /// JSON-encoded list of task IDs this task depends on.
  TextColumn get dependsOn =>
      text().withDefault(const Constant('[]'))();

  IntColumn get version => integer().withDefault(const Constant(1))();
  DateTimeColumn get createdAt => dateTime()();
  DateTimeColumn get updatedAt => dateTime()();

  /// Soft-delete for sync tombstone propagation across devices.
  DateTimeColumn get deletedAt => dateTime().nullable()();

  @override
  Set<Column> get primaryKey => {id};
}
