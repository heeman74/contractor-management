import 'package:drift/drift.dart';
import 'package:drift_flutter/drift_flutter.dart';
import 'package:path_provider/path_provider.dart';
import 'package:uuid/uuid.dart';

import '../../features/company/data/company_dao.dart';
import '../../features/invoices/data/invoice_dao.dart';
import '../../features/jobs/data/attachment_dao.dart';
import '../../features/jobs/data/job_dao.dart';
import '../../features/jobs/data/note_dao.dart';
import '../../features/jobs/data/time_entry_dao.dart';
import '../../features/projects/data/project_dao.dart';
import '../../features/projects/data/project_zone_dao.dart';
import '../../features/projects/data/task_dao.dart';
import '../../features/projects/data/task_dependency_dao.dart';
import '../../features/projects/data/trade_catalog_dao.dart';
import '../../features/projects/data/trade_scope_dao.dart';
import '../../features/quotes/data/quote_dao.dart';
import '../../features/schedule/data/booking_dao.dart';
import '../../features/users/data/user_dao.dart';
import '../sync/sync_cursor_dao.dart';
import '../sync/sync_queue_dao.dart';
import 'tables/attachments.dart';
import 'tables/bookings.dart';
import 'tables/client_profiles.dart';
import 'tables/client_properties.dart';
import 'tables/companies.dart';
import 'tables/invoice_line_items.dart';
import 'tables/invoices.dart';
import 'tables/job_notes.dart';
import 'tables/job_requests.dart';
import 'tables/job_sites.dart';
import 'tables/jobs.dart';
import 'tables/projects.dart';
import 'tables/quote_line_items.dart';
import 'tables/quote_templates.dart';
import 'tables/quotes.dart';
import 'tables/project_zones.dart';
import 'tables/sync_cursor.dart';
import 'tables/sync_queue.dart';
import 'tables/task_attachments.dart';
import 'tables/task_dependencies.dart';
import 'tables/tasks.dart';
import 'tables/time_entries.dart';
import 'tables/trade_catalog.dart';
import 'tables/trade_scopes.dart';
import 'tables/user_roles.dart';
import 'tables/user_trade_specialties.dart';
import 'tables/users.dart';

export '../../features/company/data/company_dao.dart';
export '../../features/invoices/data/invoice_dao.dart';
export '../../features/jobs/data/attachment_dao.dart';
export '../../features/jobs/data/job_dao.dart';
export '../../features/jobs/data/note_dao.dart';
export '../../features/jobs/data/time_entry_dao.dart';
export '../../features/projects/data/project_dao.dart';
export '../../features/projects/data/project_zone_dao.dart';
export '../../features/projects/data/task_dao.dart';
export '../../features/projects/data/task_dependency_dao.dart';
export '../../features/projects/data/trade_catalog_dao.dart';
export '../../features/projects/data/trade_scope_dao.dart';
export '../../features/quotes/data/quote_dao.dart';
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
    JobNotes,
    Attachments,
    TimeEntries,
    Quotes,
    QuoteLineItems,
    QuoteTemplates,
    Invoices,
    InvoiceLineItems,
    TradeCatalogEntries,
    Projects,
    TradeScopes,
    ProjectTasks,
    TaskAttachments,
    UserTradeSpecialties,
    TaskDependencies,
    ProjectZones,
  ],
  daos: [
    CompanyDao,
    UserDao,
    SyncQueueDao,
    SyncCursorDao,
    JobDao,
    BookingDao,
    NoteDao,
    AttachmentDao,
    TimeEntryDao,
    QuoteDao,
    InvoiceDao,
    ProjectDao,
    TradeCatalogDao,
    TradeScopeDao,
    TaskDao,
    TaskDependencyDao,
    ProjectZoneDao,
  ],
)
class AppDatabase extends _$AppDatabase {
  AppDatabase([QueryExecutor? executor])
      : super(executor ?? _openConnection());

  @override
  int get schemaVersion => 8;

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
          if (from < 5) {
            await m.createTable(jobNotes);
            await m.createTable(attachments);
            await m.createTable(timeEntries);
            await m.addColumn(jobs, jobs.gpsLatitude);
            await m.addColumn(jobs, jobs.gpsLongitude);
            await m.addColumn(jobs, jobs.gpsAddress);
          }
          if (from < 6) {
            await m.createTable(quotes);
            await m.createTable(quoteLineItems);
            await m.createTable(quoteTemplates);
            await m.createTable(invoices);
            await m.createTable(invoiceLineItems);
            await m.addColumn(jobs, jobs.quoteId);
            await m.addColumn(jobs, jobs.invoiceId);
          }
          if (from < 7) {
            await m.createTable(tradeCatalogEntries);
            await m.createTable(projects);
            await m.createTable(tradeScopes);
            await m.createTable(projectTasks);
            await m.createTable(taskAttachments);
            await m.createTable(userTradeSpecialties);
          }
          if (from < 8) {
            // Create task_dependencies edge table for FS/SS/FF/SE dependency links
            await m.createTable(taskDependencies);
            // Create project_zones table for spatial conflict detection
            await m.createTable(projectZones);
            // Add zoneId soft-FK column to projectTasks
            await m.addColumn(projectTasks, projectTasks.zoneId);
            // Add startDate column for Gantt/CPM scheduling
            await m.addColumn(projectTasks, projectTasks.startDate);
            // Remove dependsOn column — dependencies now live in task_dependencies table.
            // alterTable rewrites the table with current column definitions (dependsOn excluded).
            await m.alterTable(TableMigration(projectTasks));
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
