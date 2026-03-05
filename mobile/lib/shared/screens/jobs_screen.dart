import 'package:flutter/material.dart';

/// Jobs screen — placeholder for Phase 4 implementation.
///
/// Phase 4 will implement:
/// - Job creation with customer details, trade type, and location
/// - Assignment to contractors based on availability and skills
/// - Job status tracking (pending, assigned, in-progress, complete)
/// - Real-time status updates visible to clients
class JobsScreen extends StatelessWidget {
  const JobsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Jobs')),
      body: Center(
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
    );
  }
}
