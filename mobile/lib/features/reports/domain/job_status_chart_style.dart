import 'package:flutter/material.dart';

/// Color + label mapping for job statuses shown in report charts.
///
/// Centralizes the status color/label maps that were previously inlined in the
/// admin reports chart widgets.
class JobStatusChartStyle {
  JobStatusChartStyle._();

  static const _colors = <String, Color>{
    'quote': Colors.grey,
    'scheduled': Colors.blue,
    'in_progress': Colors.amber,
    'complete': Colors.green,
    'invoiced': Colors.purple,
    'cancelled': Colors.red,
  };
  static const _labels = <String, String>{
    'quote': 'Quote',
    'scheduled': 'Scheduled',
    'in_progress': 'In Progress',
    'complete': 'Complete',
    'invoiced': 'Invoiced',
    'cancelled': 'Cancelled',
  };

  static Color color(String status) => _colors[status] ?? Colors.grey;

  static String label(String status) => _labels[status] ?? status;
}
