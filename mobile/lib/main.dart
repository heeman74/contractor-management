import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:workmanager/workmanager.dart';

import 'core/di/service_locator.dart';
import 'core/routing/app_router.dart';
import 'core/sync/workmanager_dispatcher.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await setupServiceLocator();

  // Initialize WorkManager for periodic background sync (INFRA-04).
  //
  // The callbackDispatcher is a top-level function that re-initializes GetIt
  // in the background isolate before running sync — required because WorkManager
  // tasks run in a separate Dart isolate with fresh memory (Pitfall 1 RESEARCH.md).
  //
  // 15-minute frequency is the Android OS minimum — the OS may defer beyond this
  // to optimize battery life, but will not fire more frequently (Pitfall 5 RESEARCH.md).
  //
  // NetworkType.connected constraint ensures sync only runs when the device has
  // an active network connection.
  Workmanager().initialize(callbackDispatcher, isInDebugMode: kDebugMode);
  Workmanager().registerPeriodicTask(
    'contractorhub-sync',
    'backgroundSync',
    frequency: const Duration(minutes: 15), // Android minimum — Pitfall 5
    constraints: Constraints(networkType: NetworkType.connected),
  );

  // IMPORTANT: Do NOT add a loading spinner here or await any data fetch.
  // App opens showing cached Drift data immediately (user decision: no loading spinner).
  runApp(
    const ProviderScope(
      child: ContractorHubApp(),
    ),
  );
}

/// Root app widget — uses MaterialApp.router to hand navigation control to go_router.
///
/// The router is provided via routerProvider which uses the ValueNotifier bridge
/// pattern to avoid router rebuilds on auth state changes (RESEARCH.md Pitfall 4).
///
/// Theme uses Material 3 with a professional indigo/blue color scheme appropriate
/// for a B2B contractor management tool.
class ContractorHubApp extends ConsumerWidget {
  const ContractorHubApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final router = ref.watch(routerProvider);

    return MaterialApp.router(
      title: 'ContractorHub',
      debugShowCheckedModeBanner: false,
      theme: _buildTheme(),
      routerConfig: router,
    );
  }

  ThemeData _buildTheme() {
    const seedColor = Color(0xFF1E4D8C); // Professional deep blue

    return ThemeData(
      colorScheme: ColorScheme.fromSeed(
        seedColor: seedColor,
        brightness: Brightness.light,
      ),
      useMaterial3: true,
      appBarTheme: const AppBarTheme(
        centerTitle: false,
        elevation: 0,
        scrolledUnderElevation: 1,
      ),
      cardTheme: CardTheme(
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: BorderSide(color: Colors.grey.shade200),
        ),
      ),
      navigationBarTheme: const NavigationBarThemeData(
        labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
      ),
    );
  }
}
