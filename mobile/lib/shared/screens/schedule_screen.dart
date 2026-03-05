import 'package:flutter/material.dart';

import '../../core/di/service_locator.dart';
import '../../core/sync/sync_engine.dart';

/// Schedule screen — placeholder for Phase 5 implementation.
///
/// Phase 5 will implement:
/// - Calendar view of contractor schedules and job assignments
/// - Drag-and-drop job scheduling with conflict detection
/// - Travel time estimation between jobs
/// - Multi-day availability blocking
///
/// Pull-to-refresh: swipe down to trigger [SyncEngine.syncNow] — pushes pending
/// local mutations then pulls remote changes.
class ScheduleScreen extends StatelessWidget {
  const ScheduleScreen({super.key});

  @override
  Widget build(BuildContext context) {
    // AppBar is provided by AppShell — no Scaffold/AppBar here.
    // The shell shows "Schedule" as the title and SyncStatusSubtitle.

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
                  Icons.calendar_month_outlined,
                  size: 80,
                  color: Colors.grey[400],
                ),
                const SizedBox(height: 24),
                const Text(
                  'Schedule',
                  style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 8),
                Text(
                  'Coming in Phase 5',
                  style: TextStyle(fontSize: 16, color: Colors.grey[600]),
                ),
                const SizedBox(height: 16),
                Text(
                  'Smart scheduling with travel time estimation,\nconflict detection, and calendar views.',
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
