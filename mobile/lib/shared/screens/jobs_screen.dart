import 'package:flutter/material.dart';

import '../../core/di/service_locator.dart';
import '../../core/sync/sync_engine.dart';

/// Jobs screen — placeholder for Phase 4 implementation.
///
/// Phase 4 will implement:
/// - Job creation with customer details, trade type, and location
/// - Assignment to contractors based on availability and skills
/// - Job status tracking (pending, assigned, in-progress, complete)
/// - Real-time status updates visible to clients
///
/// Pull-to-refresh: swipe down to trigger [SyncEngine.syncNow] — pushes pending
/// local mutations then pulls remote changes.
class JobsScreen extends StatelessWidget {
  const JobsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    // AppBar is provided by AppShell — no Scaffold/AppBar here.
    // The shell shows "Jobs" as the title and SyncStatusSubtitle.

    // RefreshIndicator requires a scrollable child.
    // The placeholder Column is not scrollable, so we wrap it in
    // SingleChildScrollView with AlwaysScrollableScrollPhysics to ensure
    // pull-to-refresh works even when content doesn't fill the screen.
    return RefreshIndicator(
      onRefresh: () async {
        final syncEngine = getIt<SyncEngine>();
        await syncEngine.syncNow();
      },
      child: SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        child: SizedBox(
          height: 500, // Minimum height so content is visible and pull works
          child: Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  Icons.work_outline,
                  size: 80,
                  color: Colors.grey[400],
                ),
                const SizedBox(height: 24),
                const Text(
                  'Jobs',
                  style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 8),
                Text(
                  'Coming in Phase 4',
                  style: TextStyle(fontSize: 16, color: Colors.grey[600]),
                ),
                const SizedBox(height: 16),
                Text(
                  'Create and track jobs, assign contractors,\nand keep clients informed in real time.',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 14, color: Colors.grey[500]),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
