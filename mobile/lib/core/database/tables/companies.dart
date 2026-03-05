import 'package:drift/drift.dart';
import 'package:uuid/uuid.dart';

class Companies extends Table {
  TextColumn get id => text().clientDefault(() => const Uuid().v4())();
  TextColumn get name => text()();
  TextColumn get address => text().nullable()();
  TextColumn get phone => text().nullable()();
  TextColumn get businessNumber => text().nullable()();
  TextColumn get logoUrl => text().nullable()();
  // Comma-separated TradeType names (e.g., "plumber,electrician")
  TextColumn get tradeTypes => text().nullable()();
  IntColumn get version => integer().withDefault(const Constant(1))();
  DateTimeColumn get createdAt => dateTime()();
  DateTimeColumn get updatedAt => dateTime()();
  // Soft-delete for sync tombstone propagation across devices.
  // Null means the record is active. Non-null means logically deleted.
  DateTimeColumn get deletedAt => dateTime().nullable()();

  @override
  Set<Column> get primaryKey => {id};
}
