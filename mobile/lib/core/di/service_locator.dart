import 'package:get_it/get_it.dart';

import '../auth/auth_repository.dart';
import '../auth/token_storage.dart';
import '../database/app_database.dart';
import '../network/dio_client.dart';
import '../sync/connectivity_service.dart';
import '../sync/handlers/attachment_sync_handler.dart';
import '../sync/handlers/company_sync_handler.dart';
import '../sync/handlers/note_sync_handler.dart';
import '../sync/handlers/time_entry_sync_handler.dart';
import '../sync/handlers/user_role_sync_handler.dart';
import '../sync/handlers/user_sync_handler.dart';
import '../sync/sync_engine.dart';
import '../sync/sync_registry.dart';
import '../../features/invoices/data/invoice_line_item_sync_handler.dart';
import '../../features/invoices/data/invoice_sync_handler.dart';
import '../../features/jobs/data/client_profile_sync_handler.dart';
import '../../features/jobs/data/job_request_sync_handler.dart';
import '../../features/jobs/data/job_sync_handler.dart';
import '../../features/jobs/presentation/services/attachment_upload_service.dart';
import '../../features/projects/data/project_dao.dart';
import '../../features/projects/data/task_dao.dart';
import '../../features/projects/data/trade_catalog_dao.dart';
import '../../features/projects/data/trade_scope_dao.dart';
import '../../features/quotes/data/quote_line_item_sync_handler.dart';
import '../../features/quotes/data/quote_sync_handler.dart';
import '../../features/schedule/data/booking_sync_handler.dart';
import '../../features/schedule/data/job_site_sync_handler.dart';
import '../sync/handlers/project_sync_handler.dart';
import '../sync/handlers/project_zone_sync_handler.dart';
import '../sync/handlers/task_dependency_sync_handler.dart';
import '../sync/handlers/task_inspection_sync_handler.dart';
import '../sync/handlers/task_sync_handler.dart';
import '../sync/handlers/trade_catalog_sync_handler.dart';
import '../sync/handlers/trade_scope_sync_handler.dart';
import '../sync/handlers/site_walk_flag_sync_handler.dart';
import '../sync/handlers/punch_list_item_sync_handler.dart';
import '../sync/handlers/billing_milestone_sync_handler.dart';
import '../sync/handlers/checklist_sync_handler.dart';
import '../../features/billing_milestones/data/billing_milestone_dao.dart';
import '../../features/projects/data/project_zone_dao.dart';
import '../../features/projects/data/task_dependency_dao.dart';
import '../../features/ai/data/ai_conversation_dao.dart';
import '../../features/ai/data/ai_sse_client.dart';
import '../../features/checklists/data/checklist_dao.dart';
import '../../features/foreman/data/foreman_repository.dart';

final getIt = GetIt.instance;

/// Derive API base URL from the same BASE_URL used by DioClient.
/// Strips '/api/v1' suffix so SSE client can append its own paths.
final _apiBaseUrl = const String.fromEnvironment(
  'BASE_URL',
  defaultValue: 'http://10.0.2.2:8000/api/v1',
).replaceAll('/api/v1', '');

Future<void> setupServiceLocator() async {
  // Database — single SQLite instance for the entire app lifetime
  getIt.registerSingleton<AppDatabase>(AppDatabase());

  // Auth — secure token storage and auth repository
  final tokenStorage = TokenStorage();
  getIt.registerSingleton<TokenStorage>(tokenStorage);

  // HTTP client — configured Dio instance with RetryInterceptor
  getIt.registerSingleton<DioClient>(DioClient());

  // Auth repository — depends on DioClient and TokenStorage
  final authRepository = AuthRepository(getIt<DioClient>(), tokenStorage);
  getIt.registerSingleton<AuthRepository>(authRepository);

  // Wire auth dependencies into DioClient for AuthInterceptor
  getIt<DioClient>().setAuthDependencies(tokenStorage, authRepository);

  // Connectivity service — wraps connectivity_plus with internet verification
  getIt.registerSingleton<ConnectivityService>(ConnectivityService());

  // Sync registry — maps entity types to their SyncHandler implementations
  // Registration order: AppDatabase and DioClient must be registered first
  final db = getIt<AppDatabase>();
  final dioClient = getIt<DioClient>();

  final registry = SyncRegistry();
  registry.register(CompanySyncHandler(dioClient, db));
  registry.register(UserSyncHandler(dioClient, db));
  registry.register(UserRoleSyncHandler(dioClient, db));
  // Phase 4: Job lifecycle sync handlers
  registry.register(JobSyncHandler(dioClient, db));
  registry.register(ClientProfileSyncHandler(dioClient, db));
  registry.register(JobRequestSyncHandler(dioClient, db));
  // Phase 5: Calendar & dispatch sync handlers
  registry.register(BookingSyncHandler(dioClient, db));
  registry.register(JobSiteSyncHandler(db));
  // Phase 6: Field workflow sync handlers
  registry.register(NoteSyncHandler(dioClient, db));
  registry.register(TimeEntrySyncHandler(dioClient, db));
  // Phase 8: Business operations sync handlers
  registry.register(QuoteSyncHandler(dioClient, db));
  registry.register(InvoiceSyncHandler(dioClient, db));
  // Phase 9: Gap closure — pull-only handlers for line items and attachments
  registry.register(AttachmentSyncHandler(db));
  registry.register(QuoteLineItemSyncHandler(db));
  registry.register(InvoiceLineItemSyncHandler(db));
  // Phase 19: Project data model sync handlers
  registry.register(ProjectSyncHandler(dioClient, db));
  registry.register(TradeCatalogSyncHandler(dioClient, db));
  registry.register(TradeScopeSyncHandler(dioClient, db));
  registry.register(TaskSyncHandler(dioClient, db));
  // Phase 20: Dependency engine sync handlers
  final taskDepDao = TaskDependencyDao(db);
  final projectZoneDao = ProjectZoneDao(db);
  registry.register(TaskDependencySyncHandler(dioClient, taskDepDao));
  registry.register(ProjectZoneSyncHandler(dioClient, projectZoneDao));
  // Phase 24: GC inspection workflow sync handlers
  registry.register(TaskInspectionSyncHandler(dioClient, db));
  registry.register(SiteWalkFlagSyncHandler(dioClient, db));
  registry.register(PunchListItemSyncHandler(dioClient, db));
  // Phase 25: Per-trade billing sync handlers
  registry.register(BillingMilestoneSyncHandler(dioClient, db));
  // Phase 26: AI daily checklists sync handler (pull-only, server-generated)
  registry.register(ChecklistSyncHandler(dioClient, db));

  getIt.registerSingleton<SyncRegistry>(registry);

  // Sync engine — orchestrates queue drain, delta pull, and connectivity triggers
  // Depends on AppDatabase, DioClient, SyncRegistry, ConnectivityService
  final syncEngine = SyncEngine(
    db,
    dioClient,
    registry,
    getIt<ConnectivityService>(),
  );
  getIt.registerSingleton<SyncEngine>(syncEngine);

  // Start the connectivity listener after all singletons are registered.
  // This wires ConnectivityService -> SyncEngine._onConnectivityRestored.
  syncEngine.initialize();

  // JobDao — accessed via AppDatabase.jobDao accessor; registered for direct injection
  getIt.registerSingleton<JobDao>(db.jobDao);

  // BookingDao — accessed via AppDatabase.bookingDao accessor; registered for direct injection
  getIt.registerSingleton<BookingDao>(db.bookingDao);

  // Phase 6 DAOs — registered for direct injection in field workflow features
  getIt.registerSingleton<NoteDao>(db.noteDao);
  getIt.registerSingleton<AttachmentDao>(db.attachmentDao);
  getIt.registerSingleton<TimeEntryDao>(db.timeEntryDao);

  // Phase 8 DAOs — registered for direct injection in business operations features
  getIt.registerSingleton<QuoteDao>(db.quoteDao);
  getIt.registerSingleton<InvoiceDao>(db.invoiceDao);

  // Phase 19 DAOs — registered for direct injection in project management features
  getIt.registerSingleton<ProjectDao>(db.projectDao);
  getIt.registerSingleton<TradeCatalogDao>(db.tradeCatalogDao);
  getIt.registerSingleton<TradeScopeDao>(db.tradeScopeDao);
  getIt.registerSingleton<TaskDao>(db.taskDao);

  // Phase 22 DAOs — registered for task execution features
  getIt.registerSingleton<TaskNoteDao>(db.taskNoteDao);
  getIt.registerSingleton<TaskAttachmentDao>(db.taskAttachmentDao);

  // Phase 24 DAOs — registered for GC inspection workflow features
  getIt.registerSingleton<TaskInspectionDao>(db.taskInspectionDao);
  getIt.registerSingleton<SiteWalkFlagDao>(db.siteWalkFlagDao);
  getIt.registerSingleton<PunchListItemDao>(db.punchListItemDao);

  // Phase 25 DAOs — registered for per-trade billing features
  getIt.registerSingleton<BillingMilestoneDao>(db.billingMilestoneDao);

  // Phase 26 DAOs — registered for AI daily checklist features
  getIt.registerSingleton<DailyChecklistDao>(db.dailyChecklistDao);

  // Phase 20 DAOs — registered for dependency engine features
  getIt.registerSingleton<TaskDependencyDao>(taskDepDao);
  getIt.registerSingleton<ProjectZoneDao>(projectZoneDao);

  // AttachmentUploadService — binary file uploader for field workflow attachments.
  // Registered AFTER SyncEngine to allow post-construction wiring via
  // setAttachmentUploadService(). Text-first sync: uploads only after queue drain.
  final attachmentUploadService = AttachmentUploadService(
    dioClient: dioClient,
    attachmentDao: db.attachmentDao,
  );
  getIt.registerSingleton<AttachmentUploadService>(attachmentUploadService);

  // Wire AttachmentUploadService into SyncEngine for post-drain upload.
  syncEngine.setAttachmentUploadService(attachmentUploadService);

  // Phase 21: AI chat SSE client — bypasses Dio for text/event-stream streaming.
  // Uses dart:io HttpClient directly since Dio cannot handle SSE responses.
  getIt.registerLazySingleton<AiSseClient>(() => AiSseClient(
        baseUrl: _apiBaseUrl,
        getAccessToken: () => tokenStorage.readAccessToken(),
      ));

  // Phase 21: AI conversation DAO for local transcript cache (D-31)
  getIt.registerSingleton<AiConversationDao>(AiConversationDao(db));

  // Foreman repository — wraps DioClient for foreman-specific API calls
  // (project assignments, daily status updates).
  getIt.registerSingleton<ForemanRepository>(ForemanRepository(dioClient));
}
