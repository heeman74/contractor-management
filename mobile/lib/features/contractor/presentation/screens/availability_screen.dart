import 'package:flutter/material.dart';

/// Availability screen — Contractor only. Placeholder for Phase 3.
///
/// Phase 3 will implement:
/// - Set recurring weekly working hours per trade type
/// - Block specific dates (vacation, sick leave, personal)
/// - Multi-day availability blocking
/// - Integration with scheduling engine for job assignment
class AvailabilityScreen extends StatelessWidget {
  const AvailabilityScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('My Availability'),
        backgroundColor: Colors.orange[50],
      ),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.event_available_outlined,
              size: 80,
              color: Colors.orange[300],
            ),
            const SizedBox(height: 24),
            const Text(
              'Availability',
              style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            Text(
              'Contractor Only — Coming in Phase 3',
              style: TextStyle(fontSize: 16, color: Colors.grey[600]),
            ),
            const SizedBox(height: 16),
            Text(
              'Set your working hours, block time off,\nand manage trade availability.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 14, color: Colors.grey[500]),
            ),
          ],
        ),
      ),
    );
  }
}
