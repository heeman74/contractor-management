import 'package:drift/drift.dart';
import 'package:drift_flutter/drift_flutter.dart';
import 'package:path_provider/path_provider.dart';

import '../../features/company/data/company_dao.dart';
import '../../features/users/data/user_dao.dart';
import '../sync/sync_cursor_dao.dart';
import '../sync/sync_queue_dao.dart';
import 'tables/companies.dart';
import 'tables/sync_cursor.dart';
import 'tables/sync_queue.dart';
import 'tables/user_roles.dart';
import 'tables/users.dart';

export '../../features/company/data/company_dao.dart';
export '../../features/users/data/user_dao.dart';

part 'app_database.g.dart';

@DriftDatabase(
  tables: [Companies, Users, UserRoles, SyncQueue, SyncCursor],
  daos: [CompanyDao, UserDao, SyncQueueDao, SyncCursorDao],
)
class AppDatabase extends _$AppDatabase {
  AppDatabase([QueryExecutor? executor])
      : super(executor ?? _openConnection());

  @override
  int get schemaVersion => 2;

  @override
  MigrationStrategy get migration => MigrationStrategy(
        onCreate: (m) async {
          await m.createAll();
        },
        onUpgrade: stepByStep(
          from1To2: (m, schema) async {
            // Create new outbox and cursor tables
            await m.createTable(schema.syncQueue);
            await m.createTable(schema.syncCursor);
            // Add soft-delete column to all entity tables
            await m.addColumn(schema.companies, schema.companies.deletedAt);
            await m.addColumn(schema.users, schema.users.deletedAt);
            await m.addColumn(schema.userRoles, schema.userRoles.deletedAt);
          },
        ),
      );

  static QueryExecutor _openConnection() {
    return driftDatabase(
      name: 'contractorhub',
      native: DriftNativeOptions(
        databaseDirectory: getApplicationSupportDirectory,
      ),
    );
  }
}
