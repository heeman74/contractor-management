import 'package:drift/drift.dart';
import 'package:uuid/uuid.dart';

import 'companies.dart';

/// Drift table definition for the UserTradeSpecialty entity.
///
/// Maps a contractor (user) to a trade catalog entry, indicating
/// they are qualified/specialised in that trade type.
///
/// Used by the project team assignment UI to suggest suitable contractors
/// for each trade scope.
///
/// Both [userId] and [tradeCatalogId] are stored as plain text FKs without
/// Drift-level references to avoid cross-feature coupling.
class UserTradeSpecialties extends Table {
  TextColumn get id => text().clientDefault(() => const Uuid().v4())();
  TextColumn get companyId => text().references(Companies, #id)();

  /// FK to Users.id — the contractor with this specialty.
  TextColumn get userId => text()();

  /// FK to TradeCatalogEntries.id — the trade they specialise in.
  TextColumn get tradeCatalogId => text()();

  IntColumn get version => integer().withDefault(const Constant(1))();
  DateTimeColumn get createdAt => dateTime()();
  DateTimeColumn get updatedAt => dateTime()();

  /// Soft-delete for sync tombstone propagation across devices.
  DateTimeColumn get deletedAt => dateTime().nullable()();

  @override
  Set<Column> get primaryKey => {id};
}
