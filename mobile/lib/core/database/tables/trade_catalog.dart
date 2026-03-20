import 'package:drift/drift.dart';
import 'package:uuid/uuid.dart';

import 'companies.dart';

/// Drift table definition for the TradeCatalogEntry entity.
///
/// A TradeCatalogEntry is a company-level definition of a trade type,
/// with a name and display color. Contractors can have specialties mapped
/// to catalog entries via [UserTradeSpecialties].
///
/// This catalog allows GCs to customise trade names and colors beyond
/// the built-in defaults.
class TradeCatalogEntries extends Table {
  TextColumn get id => text().clientDefault(() => const Uuid().v4())();
  TextColumn get companyId => text().references(Companies, #id)();

  /// Human-readable trade name (e.g., "Electrical", "Plumbing").
  TextColumn get name => text()();

  /// Hex color code for UI display (e.g., '#4CAF50').
  /// Defaults to grey if not specified.
  TextColumn get color =>
      text().withDefault(const Constant('#9E9E9E'))();

  IntColumn get version => integer().withDefault(const Constant(1))();
  DateTimeColumn get createdAt => dateTime()();
  DateTimeColumn get updatedAt => dateTime()();

  /// Soft-delete for sync tombstone propagation across devices.
  DateTimeColumn get deletedAt => dateTime().nullable()();

  @override
  Set<Column> get primaryKey => {id};
}
