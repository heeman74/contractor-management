import 'package:drift/drift.dart';
import 'package:uuid/uuid.dart';

import 'companies.dart';
import 'projects.dart';
import 'users.dart';

/// Drift table definition for project-to-user assignments.
///
/// Tracks which users (typically foremen) are assigned to which projects.
/// The [role] column indicates the assignment capacity (e.g., 'foreman').
/// Soft-deleted via [deletedAt] for sync tombstone propagation.
class ProjectAssignments extends Table {
  TextColumn get id => text().clientDefault(() => const Uuid().v4())();
  TextColumn get companyId => text().references(Companies, #id)();
  TextColumn get projectId => text().references(Projects, #id)();
  TextColumn get userId => text().references(Users, #id)();

  /// Assignment role: 'foreman' | future roles like 'inspector', 'safety_officer'
  TextColumn get role => text().withDefault(const Constant('foreman'))();

  DateTimeColumn get assignedAt => dateTime()();
  DateTimeColumn get createdAt => dateTime()();

  /// Soft-delete for sync tombstone propagation across devices.
  TextColumn get deletedAt => text().nullable()();

  @override
  Set<Column> get primaryKey => {id};
}
