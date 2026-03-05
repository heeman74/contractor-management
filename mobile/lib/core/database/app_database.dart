import 'package:drift/drift.dart';
import 'package:drift_flutter/drift_flutter.dart';
import 'package:path_provider/path_provider.dart';

import '../../features/company/data/company_dao.dart';
import '../../features/users/data/user_dao.dart';
import 'tables/companies.dart';
import 'tables/user_roles.dart';
import 'tables/users.dart';

export '../../features/company/data/company_dao.dart';
export '../../features/users/data/user_dao.dart';

part 'app_database.g.dart';

@DriftDatabase(
  tables: [Companies, Users, UserRoles],
  daos: [CompanyDao, UserDao],
)
class AppDatabase extends _$AppDatabase {
  AppDatabase([QueryExecutor? executor])
      : super(executor ?? _openConnection());

  @override
  int get schemaVersion => 1;

  @override
  MigrationStrategy get migration => MigrationStrategy(
        onCreate: (m) async {
          await m.createAll();
        },
        onUpgrade: stepByStep(
          // Future migrations added here
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
