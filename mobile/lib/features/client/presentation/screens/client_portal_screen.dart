import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/routing/route_names.dart';

/// Client portal screen — Client only. Placeholder for Phase 5.
///
/// Phase 5 will implement:
/// - Real-time job status updates (Clients always know what's happening)
/// - Invoice viewing and payment history
/// - Job history and documentation
/// - Two-way communication with the contractor team
class ClientPortalScreen extends StatelessWidget {
  const ClientPortalScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Client Portal'),
        backgroundColor: Colors.green[50],
      ),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.dashboard_outlined,
              size: 80,
              color: Colors.green[300],
            ),
            const SizedBox(height: 24),
            const Text(
              'Client Portal',
              style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            Text(
              'Client Only — Coming in Phase 5',
              style: TextStyle(fontSize: 16, color: Colors.grey[600]),
            ),
            const SizedBox(height: 16),
            Text(
              'Track job status, view invoices,\nand stay in the loop on your projects.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 14, color: Colors.grey[500]),
            ),
            const SizedBox(height: 24),
            FilledButton.icon(
              icon: const Icon(Icons.add_task),
              label: const Text('Submit a Job Request'),
              onPressed: () => context.go(RouteNames.jobRequestForm),
            ),
          ],
        ),
      ),
    );
  }
}
