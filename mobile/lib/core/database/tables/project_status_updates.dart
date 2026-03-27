import 'package:drift/drift.dart';
import 'package:uuid/uuid.dart';

import 'companies.dart';
import 'projects.dart';
import 'users.dart';

/// Drift table definition for daily project status updates.
///
/// Foremen submit daily reports capturing site conditions, worker counts,
/// safety incidents, blockers, and photos. Each update is tied to a project
/// and an author (the foreman).
///
/// [photos] is a JSON-encoded list of photo attachment URLs/paths.
/// [reportDate] is stored as ISO 8601 date string (YYYY-MM-DD) for easy querying.
class ProjectStatusUpdates extends Table {
  TextColumn get id => text().clientDefault(() => const Uuid().v4())();
  TextColumn get companyId => text().references(Companies, #id)();
  TextColumn get projectId => text().references(Projects, #id)();
  TextColumn get authorId => text().references(Users, #id)();
  TextColumn get statusText => text()();
  TextColumn get weatherConditions => text().nullable()();
  IntColumn get workersOnSite => integer().nullable()();
  IntColumn get safetyIncidents => integer().withDefault(const Constant(0))();
  TextColumn get blockers => text().nullable()();

  /// JSON-encoded list of photo attachment URLs/paths: ["url1", "url2"]
  TextColumn get photos => text().withDefault(const Constant('[]'))();

  /// ISO 8601 date string (YYYY-MM-DD) for the report date.
  TextColumn get reportDate => text()();

  DateTimeColumn get createdAt => dateTime()();

  /// Soft-delete for sync tombstone propagation across devices.
  TextColumn get deletedAt => text().nullable()();

  @override
  Set<Column> get primaryKey => {id};
}
