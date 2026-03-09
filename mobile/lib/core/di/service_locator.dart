import 'package:get_it/get_it.dart';

import '../auth/auth_repository.dart';
import '../auth/token_storage.dart';
import '../database/app_database.dart';
import '../network/dio_client.dart';
import '../sync/connectivity_service.dart';
import '../sync/handlers/company_sync_handler.dart';
import '../sync/handlers/user_role_sync_handler.dart';
import '../sync/handlers/user_sync_handler.dart';
import '../sync/sync_engine.dart';
import '../sync/sync_registry.dart';
import '../../features/jobs/data/client_profile_sync_handler.dart';
import '../../features/jobs/data/job_request_sync_handler.dart';
import '../../features/jobs/data/job_sync_handler.dart';
import '../../features/schedule/data/booking_sync_handler.dart';
import '../../features/schedule/data/job_site_sync_handler.dart';

final getIt = GetIt.instance;

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
}
