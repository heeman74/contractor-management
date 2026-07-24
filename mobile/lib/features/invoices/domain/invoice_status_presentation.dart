import 'package:flutter/material.dart';

/// Presentation mapping for invoice payment statuses.
///
/// Consolidates the label + color logic previously duplicated between
/// `invoice_detail_screen.dart` and the client job detail screen.
class InvoiceStatusPresentation {
  InvoiceStatusPresentation._();

  static const _entries = <String, (String label, Color color)>{
    'unpaid': ('Unpaid', Colors.red),
    'partial': ('Partially Paid', Colors.orange),
    'paid': ('Paid', Colors.green),
    'overdue': ('Overdue', Colors.deepOrange),
    'cancelled': ('Cancelled', Colors.grey),
  };

  static String label(String status) => _entries[status]?.$1 ?? status;

  static Color color(String status) => _entries[status]?.$2 ?? Colors.grey;
}
