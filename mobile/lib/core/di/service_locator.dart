import 'package:get_it/get_it.dart';

import '../database/app_database.dart';
import '../network/dio_client.dart';
import '../sync/connectivity_service.dart';
import '../sync/handlers/company_sync_handler.dart';
import '../sync/handlers/user_role_sync_handler.dart';
import '../sync/handlers/user_sync_handler.dart';
import '../sync/sync_engine.dart';
import '../sync/sync_registry.dart';

final getIt = GetIt.instance;

Future<void> setupServiceLocator() async {
  // Database — single SQLite instance for the entire app lifetime
  getIt.registerSingleton<AppDatabase>(AppDatabase());

  // HTTP client — configured Dio instance with RetryInterceptor
  getIt.registerSingleton<DioClient>(DioClient());

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
}
