import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'core/di/service_locator.dart';
import 'core/routing/app_router.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await setupServiceLocator();
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
