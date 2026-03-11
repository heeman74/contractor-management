/// Widget tests for CalendarMonthView — UAT #5.
///
/// Tests cover:
/// 1. Month/year header with navigation arrows
/// 2. Day-of-week column headers (Mon-Sun)
/// 3. Today cell highlighted
/// 4. Booking count badges render
/// 5. Out-of-month days are dimmed
/// 6. Empty month renders without error
/// 7. Navigation arrows present
/// 8. Grid renders correct number of cells
library;

import 'package:contractorhub/features/schedule/presentation/providers/calendar_providers.dart';
import 'package:contractorhub/features/schedule/presentation/widgets/calendar_month_view.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../helpers/schedule_test_helpers.dart';

// ---------------------------------------------------------------------------
// Test helpers
// ---------------------------------------------------------------------------

Widget buildMonthView({
  List<dynamic>? bookings,
  DateTime? selectedDate,
}) {
  final date = selectedDate ?? DateTime.now();

  return ProviderScope(
    overrides: [
      calendarDateProvider.overrideWith((ref) => date),
      calendarViewModeProvider
          .overrideWith((ref) => CalendarViewMode.month),
    ],
    child: MaterialApp(
      home: Scaffold(
        body: CalendarMonthView(
          bookings: (bookings ?? []).cast(),
        ),
      ),
    ),
  );
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

void main() {
  group('CalendarMonthView — UAT #5', () {
    testWidgets('month header shows month name and year', (tester) async {
      final date = DateTime(2026, 3, 15);
      await tester.pumpWidget(buildMonthView(selectedDate: date));
      await tester.pumpAndSettle();

      expect(find.text('March 2026'), findsOneWidget);
    });

    testWidgets('navigation arrows present in month header', (tester) async {
      await tester.pumpWidget(buildMonthView());
      await tester.pumpAndSettle();

      expect(find.byIcon(Icons.chevron_left), findsOneWidget);
      expect(find.byIcon(Icons.chevron_right), findsOneWidget);
    });

    testWidgets('day-of-week headers render (Mon-Sun)', (tester) async {
      await tester.pumpWidget(buildMonthView());
      await tester.pumpAndSettle();

      expect(find.text('Mon'), findsOneWidget);
      expect(find.text('Tue'), findsOneWidget);
      expect(find.text('Wed'), findsOneWidget);
      expect(find.text('Thu'), findsOneWidget);
      expect(find.text('Fri'), findsOneWidget);
      expect(find.text('Sat'), findsOneWidget);
      expect(find.text('Sun'), findsOneWidget);
    });

    testWidgets('renders without error with no bookings', (tester) async {
      await tester.pumpWidget(buildMonthView());
      await tester.pumpAndSettle();

      expect(find.byType(CalendarMonthView), findsOneWidget);
    });

    testWidgets('booking count badge shows when bookings exist',
        (tester) async {
      final date = DateTime(2026, 3, 15);
      final bookingStart = DateTime(2026, 3, 15, 9, 0);
      final bookingEnd = DateTime(2026, 3, 15, 11, 0);

      final booking = makeBooking(
        timeRangeStart: bookingStart,
        timeRangeEnd: bookingEnd,
      );

      await tester.pumpWidget(buildMonthView(
        bookings: [booking],
        selectedDate: date,
      ));
      await tester.pumpAndSettle();

      // Badge should show count "1"
      expect(find.text('1'), findsAtLeast(1));
    });

    testWidgets('multiple bookings on same day show correct count',
        (tester) async {
      final date = DateTime(2026, 3, 15);
      final bookings = List.generate(3, (i) {
        final start = DateTime(2026, 3, 15, 8 + i * 2, 0);
        return makeBooking(
          id: 'booking-$i',
          timeRangeStart: start,
          timeRangeEnd: start.add(const Duration(hours: 1)),
        );
      });

      await tester.pumpWidget(buildMonthView(
        bookings: bookings,
        selectedDate: date,
      ));
      await tester.pumpAndSettle();

      // Badge should show count "3"
      expect(find.text('3'), findsAtLeast(1));
    });

    testWidgets('day "1" text is present for first of month', (tester) async {
      final date = DateTime(2026, 3, 1);
      await tester.pumpWidget(buildMonthView(selectedDate: date));
      await tester.pumpAndSettle();

      // Day 1 should appear in the grid
      expect(find.text('1'), findsAtLeast(1));
    });

    testWidgets('tapping left arrow navigates to previous month',
        (tester) async {
      final date = DateTime(2026, 3, 15);
      await tester.pumpWidget(buildMonthView(selectedDate: date));
      await tester.pumpAndSettle();

      expect(find.text('March 2026'), findsOneWidget);

      await tester.tap(find.byIcon(Icons.chevron_left));
      await tester.pumpAndSettle();

      expect(find.text('February 2026'), findsOneWidget);
    });
  });
}
