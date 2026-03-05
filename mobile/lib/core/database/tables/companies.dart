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

  @override
  Set<Column> get primaryKey => {id};
}
