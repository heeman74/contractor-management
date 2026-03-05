import 'package:flutter/material.dart';
import 'package:get_it/get_it.dart';
import 'package:workmanager/workmanager.dart';

import '../di/service_locator.dart';
import 'sync_engine.dart';

/// Top-level callback dispatcher for WorkManager background tasks.
///
/// CRITICAL: This runs in a separate Dart isolate with completely fresh memory.
/// All GetIt singletons registered in the main isolate are NOT available here.
/// We must call [WidgetsFlutterBinding.ensureInitialized] and [setupServiceLocator]
/// before accessing any getIt service.
///
/// The @pragma('vm:entry-point') annotation prevents the Dart compiler from
/// tree-shaking this function in release builds. Without it, the background
/// isolate will throw a missing entry point error.
///
/// Pitfall 1 from RESEARCH.md: WorkManager runs in a fresh isolate — GetIt
/// registry is empty. Always re-initialize before using any service.
@pragma('vm:entry-point')
void callbackDispatcher() {
  Workmanager().executeTask((task, inputData) async {
    try {
      // Re-initialize Flutter bindings and all GetIt services.
      // This is a fresh isolate — nothing from the main isolate is available.
      WidgetsFlutterBinding.ensureInitialized();
      await setupServiceLocator();

      final syncEngine = GetIt.instance<SyncEngine>();

      // Run drain then pull — same sequence as syncNow() in the main isolate.
      // drainQueue pushes pending local mutations before pulling remote changes
      // to prevent overwriting local writes with stale server data.
      await syncEngine.drainQueue();
      await syncEngine.pullDelta();

      // Return true to signal success to WorkManager.
      return Future.value(true);
    } catch (e) {
      // Return true even on error to avoid OS retry storm.
      // Pitfall from RESEARCH.md: returning false causes WorkManager to
      // re-schedule the task with exponential backoff, which can flood
      // the system with background work if there is a persistent error.
      //
      // The next periodic tick (15 min) will retry naturally.
      return Future.value(true);
    }
  });
}
