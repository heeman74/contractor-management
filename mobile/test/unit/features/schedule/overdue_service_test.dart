/// Unit tests for OverdueService — pure Dart, no Flutter or mocking needed.
///
/// Tests verify the two public static methods:
///   - OverdueService.computeSeverity(DateTime?) -> OverdueSeverity
///   - OverdueService.isOverdue(String status, DateTime?) -> bool
///
/// Severity tiers:
///   none     — null date, future date, or today exactly
///   warning  — 1–3 days overdue
///   critical — 4+ days overdue
///
/// isOverdue rules:
///   - Only 'scheduled' and 'in_progress' are active statuses
///   - Complete, invoiced, cancelled are terminal — never overdue
///   - Null scheduledCompletionDate — never overdue
///   - Past scheduled date + active status = overdue
library;

import 'package:contractorhub/features/schedule/domain/overdue_service.dart';
import 'package:flutter_test/flutter_test.dart';

/// Returns a DateTime that is [days] days in the future from today (time stripped).
DateTime futureDate(int days) {
  final now = DateTime.now();
  final today = DateTime(now.year, now.month, now.day);
  return today.add(Duration(days: days));
}

/// Returns a DateTime that is [days] days in the past from today (time stripped).
DateTime pastDate(int days) {
  final now = DateTime.now();
  final today = DateTime(now.year, now.month, now.day);
  return today.subtract(Duration(days: days));
}

void main() {
  group('OverdueService.computeSeverity', () {
    // ────────────────────────────────────────────────────────────────────────
    // None cases
    // ────────────────────────────────────────────────────────────────────────

    test('returns none when date is in the future', () {
      final result = OverdueService.computeSeverity(futureDate(1));
      expect(result, equals(OverdueSeverity.none));
    });

    test('returns none when date is today (same calendar day)', () {
      // A job due today is NOT overdue yet — becomes overdue tomorrow.
      final result = OverdueService.computeSeverity(DateTime.now());
      expect(result, equals(OverdueSeverity.none));
    });

    test('returns none when date is null', () {
      final result = OverdueService.computeSeverity(null);
      expect(result, equals(OverdueSeverity.none));
    });

    test('returns none when 7 days in the future', () {
      final result = OverdueService.computeSeverity(futureDate(7));
      expect(result, equals(OverdueSeverity.none));
    });

    // ────────────────────────────────────────────────────────────────────────
    // Warning cases (1–3 days overdue)
    // ────────────────────────────────────────────────────────────────────────

    test('returns warning when 1 day overdue', () {
      final result = OverdueService.computeSeverity(pastDate(1));
      expect(result, equals(OverdueSeverity.warning));
    });

    test('returns warning when 2 days overdue', () {
      final result = OverdueService.computeSeverity(pastDate(2));
      expect(result, equals(OverdueSeverity.warning));
    });

    test('returns warning when 3 days overdue (boundary: last warning day)', () {
      final result = OverdueService.computeSeverity(pastDate(3));
      expect(result, equals(OverdueSeverity.warning));
    });

    // ────────────────────────────────────────────────────────────────────────
    // Critical cases (4+ days overdue)
    // ────────────────────────────────────────────────────────────────────────

    test('returns critical when 4 days overdue (boundary: first critical day)', () {
      final result = OverdueService.computeSeverity(pastDate(4));
      expect(result, equals(OverdueSeverity.critical));
    });

    test('returns critical when 10 days overdue', () {
      final result = OverdueService.computeSeverity(pastDate(10));
      expect(result, equals(OverdueSeverity.critical));
    });

    test('returns critical when 30 days overdue', () {
      final result = OverdueService.computeSeverity(pastDate(30));
      expect(result, equals(OverdueSeverity.critical));
    });
  });

  group('OverdueService.isOverdue', () {
    // ────────────────────────────────────────────────────────────────────────
    // Returns true cases (active status + past date)
    // ────────────────────────────────────────────────────────────────────────

    test('returns true for scheduled status with past date', () {
      final result = OverdueService.isOverdue('scheduled', pastDate(1));
      expect(result, isTrue);
    });

    test('returns true for in_progress status with past date', () {
      final result = OverdueService.isOverdue('in_progress', pastDate(5));
      expect(result, isTrue);
    });

    test('returns true for scheduled status many days overdue', () {
      final result = OverdueService.isOverdue('scheduled', pastDate(30));
      expect(result, isTrue);
    });

    // ────────────────────────────────────────────────────────────────────────
    // Returns false — terminal status
    // ────────────────────────────────────────────────────────────────────────

    test('returns false for complete status even with past date', () {
      final result = OverdueService.isOverdue('complete', pastDate(7));
      expect(result, isFalse);
    });

    test('returns false for invoiced status even with past date', () {
      final result = OverdueService.isOverdue('invoiced', pastDate(7));
      expect(result, isFalse);
    });

    test('returns false for cancelled status even with past date', () {
      final result = OverdueService.isOverdue('cancelled', pastDate(7));
      expect(result, isFalse);
    });

    test('returns false for quote status even with past date', () {
      // Quote is not an active scheduled status — cannot be overdue.
      final result = OverdueService.isOverdue('quote', pastDate(7));
      expect(result, isFalse);
    });

    // ────────────────────────────────────────────────────────────────────────
    // Returns false — future or null date
    // ────────────────────────────────────────────────────────────────────────

    test('returns false for scheduled status with future date', () {
      final result = OverdueService.isOverdue('scheduled', futureDate(3));
      expect(result, isFalse);
    });

    test('returns false for scheduled status with today (same calendar day)', () {
      // A job due today is NOT overdue — only past today's date is overdue.
      final result = OverdueService.isOverdue('scheduled', DateTime.now());
      expect(result, isFalse);
    });

    test('returns false for scheduled status with null date', () {
      final result = OverdueService.isOverdue('scheduled', null);
      expect(result, isFalse);
    });

    test('returns false for in_progress status with null date', () {
      final result = OverdueService.isOverdue('in_progress', null);
      expect(result, isFalse);
    });
  });
}
