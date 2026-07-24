/// Unit tests for the invoice/quote status presentation helpers and the
/// shared relative-time / long-date formatters extracted during the
/// client_job_detail_screen refactor.
library;

import 'package:contractorhub/features/invoices/domain/invoice_status_presentation.dart';
import 'package:contractorhub/features/quotes/domain/quote_status_presentation.dart';
import 'package:contractorhub/shared/utils/date_format_utils.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('InvoiceStatusPresentation', () {
    test('maps known statuses to labels and colors', () {
      expect(InvoiceStatusPresentation.label('partial'), 'Partially Paid');
      expect(InvoiceStatusPresentation.color('paid'), Colors.green);
      expect(InvoiceStatusPresentation.color('overdue'), Colors.deepOrange);
    });

    test('falls back to the raw status and grey for unknown values', () {
      expect(InvoiceStatusPresentation.label('mystery'), 'mystery');
      expect(InvoiceStatusPresentation.color('mystery'), Colors.grey);
    });
  });

  group('QuoteStatusPresentation', () {
    test('maps sent and viewed to the same client-facing label', () {
      expect(QuoteStatusPresentation.label('sent'), 'Awaiting your approval');
      expect(QuoteStatusPresentation.label('viewed'), 'Awaiting your approval');
    });

    test('maps known statuses to colors', () {
      expect(QuoteStatusPresentation.color('approved'), Colors.green);
      expect(QuoteStatusPresentation.color('declined'), Colors.red);
    });

    test('falls back to blue and raw status for unknown values', () {
      expect(QuoteStatusPresentation.color('mystery'), Colors.blue);
      expect(QuoteStatusPresentation.label('mystery'), 'mystery');
    });
  });

  group('DateFormatUtils.relativeTime', () {
    test('returns "just now" for sub-minute differences', () {
      final now = DateTime.now().subtract(const Duration(seconds: 10));
      expect(DateFormatUtils.relativeTime(now), 'just now');
    });

    test('returns minutes then hours then Yesterday', () {
      final now = DateTime.now();
      expect(
        DateFormatUtils.relativeTime(now.subtract(const Duration(minutes: 5))),
        '5m ago',
      );
      expect(
        DateFormatUtils.relativeTime(now.subtract(const Duration(hours: 3))),
        '3h ago',
      );
      expect(
        DateFormatUtils.relativeTime(now.subtract(const Duration(days: 1))),
        'Yesterday',
      );
    });

    test('returns a short month/day for older timestamps', () {
      expect(
        DateFormatUtils.relativeTime(DateTime(2025, 3, 26)),
        'Mar 26',
      );
    });
  });

  group('DateFormatUtils.formatLongDate', () {
    test('formats with full month name and year', () {
      expect(DateFormatUtils.formatLongDate(DateTime(2025, 3, 26)),
          'March 26, 2025');
    });
  });
}
