import 'package:drift/drift.dart';
import 'package:uuid/uuid.dart';

import 'companies.dart';
import 'users.dart';

class UserRoles extends Table {
  TextColumn get id => text().clientDefault(() => const Uuid().v4())();
  TextColumn get userId => text().references(Users, #id)();
  TextColumn get companyId => text().references(Companies, #id)();
  // Role values: 'admin' | 'contractor' | 'client'
  TextColumn get role => text()();
  DateTimeColumn get createdAt => dateTime()();
  // Soft-delete for sync tombstone propagation across devices.
  DateTimeColumn get deletedAt => dateTime().nullable()();

  @override
  Set<Column> get primaryKey => {id};
}
