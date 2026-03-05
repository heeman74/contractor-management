import 'package:get_it/get_it.dart';

import '../database/app_database.dart';
import '../network/dio_client.dart';

final getIt = GetIt.instance;

Future<void> setupServiceLocator() async {
  // Database — single SQLite instance for the entire app lifetime
  getIt.registerSingleton<AppDatabase>(AppDatabase());

  // HTTP client — configured Dio instance
  getIt.registerSingleton<DioClient>(DioClient());
}
