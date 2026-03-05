import 'package:flutter/material.dart';

/// Schedule screen — placeholder for Phase 5 implementation.
///
/// Phase 5 will implement:
/// - Calendar view of contractor schedules and job assignments
/// - Drag-and-drop job scheduling with conflict detection
/// - Travel time estimation between jobs
/// - Multi-day availability blocking
class ScheduleScreen extends StatelessWidget {
  const ScheduleScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Schedule')),
      body: Center(
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
    );
  }
}
