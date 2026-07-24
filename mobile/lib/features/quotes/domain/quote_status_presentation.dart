import 'package:flutter/material.dart';

/// Client-facing presentation mapping for quote statuses.
///
/// Centralizes the label + color logic used in the client job detail screen's
/// quote tab. Labels are phrased for the client audience.
class QuoteStatusPresentation {
  QuoteStatusPresentation._();

  static const _colors = <String, Color>{
    'approved': Colors.green,
    'declined': Colors.red,
    'expired': Colors.orange,
  };
  static const _labels = <String, String>{
    'sent': 'Awaiting your approval',
    'viewed': 'Awaiting your approval',
    'approved': 'Approved',
    'declined': 'Declined',
    'expired': 'Expired',
    'revised': 'Revised',
  };
  static const Color _defaultColor = Colors.blue;

  static Color color(String status) => _colors[status] ?? _defaultColor;

  static String label(String status) => _labels[status] ?? status;
}
