import 'package:flutter/material.dart';

/// Client management screen — Admin only. Placeholder for Phase 4.
///
/// Phase 4 will implement:
/// - View all clients and their associated jobs
/// - Invite new clients via email/SMS
/// - Client portal access management
/// - Client communication history
class ClientManagementScreen extends StatelessWidget {
  const ClientManagementScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Client Management'),
        backgroundColor: Colors.blue[50],
      ),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.business_outlined, size: 80, color: Colors.blue[300]),
            const SizedBox(height: 24),
            const Text(
              'Client Management',
              style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            Text(
              'Admin Only — Coming in Phase 4',
              style: TextStyle(fontSize: 16, color: Colors.grey[600]),
            ),
            const SizedBox(height: 16),
            Text(
              'Manage client accounts, job history,\nand portal access.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 14, color: Colors.grey[500]),
            ),
          ],
        ),
      ),
    );
  }
}
