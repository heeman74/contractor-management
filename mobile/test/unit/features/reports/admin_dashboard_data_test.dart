/// Unit tests for [AdminDashboardData] — the typed parser that replaced the
/// bare `as` casts on the raw `/reports/dashboard` JSON in the chart widgets.
///
/// Focus: defensive parsing of malformed / partial / empty API payloads.
library;

import 'package:contractorhub/features/reports/domain/admin_dashboard_data.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('AdminDashboardData.fromJson', () {
    test('parses a well-formed payload', () {
      final data = AdminDashboardData.fromJson({
        'jobs_by_status': {'scheduled': 5, 'complete': 3},
        'revenue_by_month': [
          {'month': '2026-01', 'paid': 1500.0, 'unpaid': 500.0},
        ],
        'contractor_utilization': [
          {'name': 'John D', 'utilization': 75.0},
        ],
        'quote_conversion': {'approved': 8, 'declined': 2, 'pending': 1},
      });

      expect(data.jobsByStatus, {'scheduled': 5, 'complete': 3});
      expect(data.revenueByMonth, hasLength(1));
      expect(data.revenueByMonth.first.total, 2000.0);
      expect(data.contractorUtilization.first.name, 'John D');
      expect(data.quoteConversion.approved, 8);
      expect(data.isEmpty, isFalse);
    });

    test('returns empty collections for a fully empty payload', () {
      final data = AdminDashboardData.fromJson({});
      expect(data.jobsByStatus, isEmpty);
      expect(data.revenueByMonth, isEmpty);
      expect(data.contractorUtilization, isEmpty);
      expect(data.quoteConversion.total, 0);
      expect(data.isEmpty, isTrue);
    });

    test('ignores wrong-typed fields without throwing', () {
      final data = AdminDashboardData.fromJson({
        'jobs_by_status': 'not-a-map',
        'revenue_by_month': {'not': 'a-list'},
        'contractor_utilization': 42,
        'quote_conversion': ['not', 'a', 'map'],
      });

      expect(data.jobsByStatus, isEmpty);
      expect(data.revenueByMonth, isEmpty);
      expect(data.contractorUtilization, isEmpty);
      expect(data.quoteConversion.total, 0);
    });

    test('coerces numeric strings/ints defensively', () {
      final data = AdminDashboardData.fromJson({
        'jobs_by_status': {'scheduled': 'oops', 'complete': 4},
        'revenue_by_month': [
          {'month': 123, 'paid': null, 'unpaid': 250},
        ],
        'contractor_utilization': [
          {'utilization': 90},
        ],
      });

      // Non-numeric count falls back to 0.
      expect(data.jobsByStatus['scheduled'], 0);
      expect(data.jobsByStatus['complete'], 4);
      // Non-string month falls back to empty; null paid → 0.
      expect(data.revenueByMonth.first.month, '');
      expect(data.revenueByMonth.first.paid, 0);
      expect(data.revenueByMonth.first.unpaid, 250);
      // Missing name falls back to 'Unknown'.
      expect(data.contractorUtilization.first.name, 'Unknown');
      expect(data.contractorUtilization.first.utilization, 90);
    });
  });

  group('QuoteConversion.conversionRate', () {
    test('is the approved share of decided quotes', () {
      const conversion =
          QuoteConversion(approved: 8, declined: 2, pending: 5);
      expect(conversion.conversionRate, 80.0);
    });

    test('is zero when no quotes were decided', () {
      const conversion =
          QuoteConversion(approved: 0, declined: 0, pending: 3);
      expect(conversion.conversionRate, 0);
      expect(conversion.isEmpty, isFalse);
    });
  });
}
