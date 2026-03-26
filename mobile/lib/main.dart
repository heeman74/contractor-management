import 'dart:async';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:workmanager/workmanager.dart';

import 'core/di/service_locator.dart';
import 'core/logging/app_logger.dart';
import 'core/notifications/fcm_service.dart';
import 'core/routing/app_router.dart';
import 'core/sync/workmanager_dispatcher.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Initialize structured logger before anything else.
  AppLogger.init();

  // Capture Flutter framework errors (layout, rendering, gestures).
  FlutterError.onError = (FlutterErrorDetails details) {
    AppLogger.fatal(
      'FlutterError',
      details.exceptionAsString(),
      error: details.exception,
      stackTrace: details.stack,
    );
  };

  // Wrap the entire app in a zone to catch uncaught async errors.
  runZonedGuarded(
    () async {
      await dotenv.load();

      // Initialize Firebase — optional. If google-services.json is missing or
      // Firebase is not configured, the app runs without push notifications.
      var firebaseAvailable = false;
      try {
        await Firebase.initializeApp();
        firebaseAvailable = true;
        // Register the top-level background message handler BEFORE runApp.
        // Must be a top-level function (not a class method) — FCM requirement.
        FirebaseMessaging.onBackgroundMessage(
            firebaseMessagingBackgroundHandler);
      } catch (e) {
        AppLogger.warning('Firebase',
            'Initialization failed — running without FCM', error: e);
      }

      await setupServiceLocator();

      // Register FcmService in GetIt so it can be accessed from auth flow
      // and router setup without passing it through the widget tree.
      // When Firebase is unavailable, all FCM operations are no-ops.
      final fcmService = FcmService(enabled: firebaseAvailable);
      getIt.registerSingleton<FcmService>(fcmService);

      // Check for a cold-start deep link (app launched by tapping a notification
      // while terminated). Returns null if app was opened normally or Firebase unavailable.
      final initialRoute = await fcmService.getInitialRoute();
      if (initialRoute != null) {
        getIt.registerSingleton<String>(initialRoute,
            instanceName: 'fcmInitialRoute');
      }

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
    },
    (error, stackTrace) {
      AppLogger.fatal(
        'UncaughtAsync',
        'Uncaught async error',
        error: error,
        stackTrace: stackTrace,
      );
    },
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
      cardTheme: CardThemeData(
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
