import 'package:flutter/material.dart';

/// Team management screen — Admin only. Placeholder for Phase 4.
///
/// Phase 4 will implement:
/// - View all contractors and their active roles
/// - Invite new contractors via email/SMS
/// - Manage trade type tags per contractor
/// - Suspend or remove team members
class TeamManagementScreen extends StatelessWidget {
  const TeamManagementScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Team Management'),
        backgroundColor: Colors.blue[50],
      ),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.groups_outlined, size: 80, color: Colors.blue[300]),
            const SizedBox(height: 24),
            const Text(
              'Team Management',
              style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            Text(
              'Admin Only — Coming in Phase 4',
              style: TextStyle(fontSize: 16, color: Colors.grey[600]),
            ),
            const SizedBox(height: 16),
            Text(
              'Invite contractors, manage roles,\nand view team availability.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 14, color: Colors.grey[500]),
            ),
          ],
        ),
      ),
    );
  }
}
