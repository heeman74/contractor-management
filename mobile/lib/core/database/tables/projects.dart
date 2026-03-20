import 'package:drift/drift.dart';
import 'package:uuid/uuid.dart';

import 'companies.dart';

/// Drift table definition for the Project entity.
///
/// A Project is the top-level container for construction work in ContractorHub v3.
/// It contains Trade Scopes (one per trade) which contain Tasks.
///
/// [statusHistory] is a JSON-encoded list of status transition audit entries.
/// [status] tracks the project lifecycle: draft | active | on_hold | complete | cancelled
class Projects extends Table {
  TextColumn get id => text().clientDefault(() => const Uuid().v4())();
  TextColumn get companyId => text().references(Companies, #id)();
  TextColumn get name => text()();
  TextColumn get description => text().nullable()();
  TextColumn get address => text().nullable()();

  /// FK to Users.id with client role. Nullable — no FK reference since
  /// Users table may be in a different feature boundary.
  TextColumn get clientId => text().nullable()();

  /// Project lifecycle state: draft | active | on_hold | complete | cancelled
  TextColumn get status =>
      text().withDefault(const Constant('draft'))();

  /// JSON-encoded audit trail: [{status, timestamp, userId, reason}]
  TextColumn get statusHistory =>
      text().withDefault(const Constant('[]'))();

  DateTimeColumn get targetStartDate => dateTime().nullable()();
  DateTimeColumn get targetEndDate => dateTime().nullable()();

  IntColumn get version => integer().withDefault(const Constant(1))();
  DateTimeColumn get createdAt => dateTime()();
  DateTimeColumn get updatedAt => dateTime()();

  /// Soft-delete for sync tombstone propagation across devices.
  DateTimeColumn get deletedAt => dateTime().nullable()();

  @override
  Set<Column> get primaryKey => {id};
}
