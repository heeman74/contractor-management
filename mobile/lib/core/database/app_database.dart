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
import '../../features/projects/data/task_attachment_dao.dart';
import '../../features/projects/data/task_dao.dart';
import '../../features/projects/data/task_dependency_dao.dart';
import '../../features/projects/data/task_inspection_dao.dart';
import '../../features/projects/data/task_note_dao.dart';
import '../../features/projects/data/site_walk_flag_dao.dart';
import '../../features/projects/data/punch_list_item_dao.dart';
import '../../features/projects/data/trade_catalog_dao.dart';
import '../../features/projects/data/trade_scope_dao.dart';
import '../../features/quotes/data/quote_dao.dart';
import '../../features/ai/data/ai_conversation_dao.dart';
import '../../features/chat/data/chat_dao.dart';
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
import 'tables/task_notes.dart';
import 'tables/tasks.dart';
import 'tables/time_entries.dart';
import 'tables/trade_catalog.dart';
import 'tables/trade_scopes.dart';
import 'tables/user_roles.dart';
import 'tables/user_trade_specialties.dart';
import 'tables/users.dart';
import 'tables/ai_conversations.dart';
import 'tables/ai_messages.dart';
import 'tables/chat_threads.dart';
import 'tables/chat_messages.dart';
import 'tables/chat_read_receipts.dart';
import 'tables/task_inspections.dart';
import 'tables/site_walk_flags.dart';
import 'tables/punch_list_items.dart';

export '../../features/company/data/company_dao.dart';
export '../../features/invoices/data/invoice_dao.dart';
export '../../features/jobs/data/attachment_dao.dart';
export '../../features/jobs/data/job_dao.dart';
export '../../features/jobs/data/note_dao.dart';
export '../../features/jobs/data/time_entry_dao.dart';
export '../../features/projects/data/project_dao.dart';
export '../../features/projects/data/project_zone_dao.dart';
export '../../features/projects/data/task_attachment_dao.dart';
export '../../features/projects/data/task_dao.dart';
export '../../features/projects/data/task_dependency_dao.dart';
export '../../features/projects/data/task_inspection_dao.dart';
export '../../features/projects/data/task_note_dao.dart';
export '../../features/projects/data/site_walk_flag_dao.dart';
export '../../features/projects/data/punch_list_item_dao.dart';
export '../../features/projects/data/trade_catalog_dao.dart';
export '../../features/projects/data/trade_scope_dao.dart';
export '../../features/quotes/data/quote_dao.dart';
export '../../features/ai/data/ai_conversation_dao.dart';
export '../../features/chat/data/chat_dao.dart';
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
    TaskNotes,
    UserTradeSpecialties,
    TaskDependencies,
    ProjectZones,
    AiConversations,
    AiMessages,
    ChatThreads,
    ChatMessages,
    ChatReadReceipts,
    TaskInspections,
    SiteWalkFlags,
    PunchListItems,
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
    TaskNoteDao,
    TaskAttachmentDao,
    TaskDependencyDao,
    ProjectZoneDao,
    AiConversationDao,
    ChatDao,
    TaskInspectionDao,
    SiteWalkFlagDao,
    PunchListItemDao,
  ],
)
class AppDatabase extends _$AppDatabase {
  AppDatabase([QueryExecutor? executor])
      : super(executor ?? _openConnection());

  @override
  int get schemaVersion => 12;

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
            // Add zoneId and startDate columns if not already present
            // (they exist if projectTasks was created fresh at schema >= 7)
            await _addColumnIfMissing(m, 'project_tasks', 'zone_id',
                projectTasks, projectTasks.zoneId);
            await _addColumnIfMissing(m, 'project_tasks', 'start_date',
                projectTasks, projectTasks.startDate);
            // Remove dependsOn column — dependencies now live in task_dependencies table.
            // alterTable rewrites the table with current column definitions (dependsOn excluded).
            await m.alterTable(TableMigration(projectTasks));
          }
          if (from < 9) {
            // Phase 21: AI conversation transcript cache tables (D-31)
            await m.createTable(aiConversations);
            await m.createTable(aiMessages);
          }
          if (from < 10) {
            // Phase 22: Task execution data layer
            // Create TaskNotes table for per-task field notes
            await m.createTable(taskNotes);
            // Add annotationData column to TaskAttachments for photo markup
            await _addColumnIfMissing(m, 'task_attachments', 'annotation_data',
                taskAttachments, taskAttachments.annotationData);
          }
          if (from < 11) {
            // Phase 23: Real-time chat data layer
            // Create ChatThreads table for project conversation channels
            await m.createTable(chatThreads);
            // Create ChatMessages table for individual messages
            await m.createTable(chatMessages);
            // Create ChatReadReceipts table for read position tracking
            await m.createTable(chatReadReceipts);
          }
          if (from < 12) {
            // Phase 24: GC inspection workflow data layer
            // Create TaskInspections table for GC approve/reject audit trail
            await m.createTable(taskInspections);
            // Create SiteWalkFlags table for GC site walk issue capture
            await m.createTable(siteWalkFlags);
            // Create PunchListItems table for formal corrective action tracking
            await m.createTable(punchListItems);
            // Add inspectionChecklist column to TradeScopes for per-scope checklists
            await _addColumnIfMissing(m, 'trade_scopes', 'inspection_checklist',
                tradeScopes, tradeScopes.inspectionChecklist);
          }
        },
      );

  /// Adds a column only if it doesn't already exist in the table.
  /// Prevents "duplicate column" errors when a table was created fresh
  /// at a schema version that already included the column.
  Future<void> _addColumnIfMissing(
    Migrator m,
    String tableName,
    String columnName,
    TableInfo table,
    GeneratedColumn column,
  ) async {
    final cols = await customSelect(
      "PRAGMA table_info('$tableName')",
    ).get();
    final exists = cols.any((row) => row.read<String>('name') == columnName);
    if (!exists) {
      await m.addColumn(table, column);
    }
  }

  static QueryExecutor _openConnection() {
    return driftDatabase(
      name: 'contractorhub',
      native: DriftNativeOptions(
        databaseDirectory: getApplicationSupportDirectory,
      ),
    );
  }
}
