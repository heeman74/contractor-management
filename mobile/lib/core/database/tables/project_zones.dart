import 'package:drift/drift.dart';
import 'package:uuid/uuid.dart';

import 'companies.dart';
import 'projects.dart';

/// Named spatial zone within a project (e.g., Kitchen, Master Bath, Garage).
///
/// Zones are used for resource conflict detection — prevents scheduling two
/// trades in the same zone at the same time. Synced from backend.
///
/// [name] is the display label for the zone, unique within a project.
class ProjectZones extends Table {
  TextColumn get id => text().clientDefault(() => const Uuid().v4())();
  TextColumn get companyId => text().references(Companies, #id)();

  /// FK to Projects.id — the project this zone belongs to.
  TextColumn get projectId => text().references(Projects, #id)();

  /// Human-readable zone name (e.g., "Kitchen", "Master Bath").
  TextColumn get name => text()();

  IntColumn get version => integer().withDefault(const Constant(1))();
  DateTimeColumn get createdAt => dateTime()();
  DateTimeColumn get updatedAt => dateTime()();

  /// Soft-delete for sync tombstone propagation across devices.
  DateTimeColumn get deletedAt => dateTime().nullable()();

  @override
  Set<Column> get primaryKey => {id};
}
