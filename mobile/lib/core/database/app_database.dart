import 'package:drift/drift.dart';
import 'package:drift_flutter/drift_flutter.dart';
import 'package:path_provider/path_provider.dart';
import 'package:uuid/uuid.dart';

import '../../features/company/data/company_dao.dart';
import '../../features/jobs/data/job_dao.dart';
import '../../features/schedule/data/booking_dao.dart';
import '../../features/users/data/user_dao.dart';
import '../sync/sync_cursor_dao.dart';
import '../sync/sync_queue_dao.dart';
import 'tables/bookings.dart';
import 'tables/client_profiles.dart';
import 'tables/client_properties.dart';
import 'tables/companies.dart';
import 'tables/job_requests.dart';
import 'tables/job_sites.dart';
import 'tables/jobs.dart';
import 'tables/sync_cursor.dart';
import 'tables/sync_queue.dart';
import 'tables/user_roles.dart';
import 'tables/users.dart';

export '../../features/company/data/company_dao.dart';
export '../../features/jobs/data/job_dao.dart';
export '../../features/schedule/data/booking_dao.dart';
export '../../features/users/data/user_dao.dart';

part 'app_database.g.dart';

@DriftDatabase(
  tables: [
    Companies,
    Users,
    UserRoles,
    SyncQueue,
    SyncCursor,
    Jobs,
    ClientProfiles,
    ClientProperties,
    JobRequests,
    Bookings,
    JobSites,
  ],
  daos: [CompanyDao, UserDao, SyncQueueDao, SyncCursorDao, JobDao, BookingDao],
)
class AppDatabase extends _$AppDatabase {
  AppDatabase([QueryExecutor? executor])
      : super(executor ?? _openConnection());

  @override
  int get schemaVersion => 4;

  @override
  MigrationStrategy get migration => MigrationStrategy(
        onCreate: (m) async {
          await m.createAll();
        },
        onUpgrade: (m, from, to) async {
          if (from < 2) {
            await m.createTable(syncQueue);
            await m.createTable(syncCursor);
            await m.addColumn(companies, companies.deletedAt);
            await m.addColumn(users, users.deletedAt);
            await m.addColumn(userRoles, userRoles.deletedAt);
          }
          if (from < 3) {
            await m.createTable(jobs);
            await m.createTable(clientProfiles);
            await m.createTable(clientProperties);
            await m.createTable(jobRequests);
          }
          if (from < 4) {
            await m.createTable(bookings);
            await m.createTable(jobSites);
          }
        },
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
