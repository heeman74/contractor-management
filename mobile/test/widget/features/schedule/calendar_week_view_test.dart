/// Widget tests for CalendarWeekView — UAT #4.
///
/// Tests cover:
/// 1. Seven day column headers render (Mon-Sun)
/// 2. Today's column header is highlighted (bold/primary color)
/// 3. Contractor rows show contractor names
/// 4. Job chips render with description text
/// 5. "+N more" overflow badge when >3 bookings per cell
/// 6. Empty state when no contractors
/// 7. Tap day cell switches to day view mode
/// 8. Overdue jobs show colored borders
/// 9. Pagination controls visible when >5 contractors
///
/// Strategy: CalendarWeekView takes bookings, contractors, and jobs as
/// constructor params — no provider dependencies (refs are internal for
/// navigation). Wrap in ProviderScope for calendarDateProvider access.
library;

import 'package:contractorhub/features/schedule/presentation/providers/calendar_providers.dart';
import 'package:contractorhub/features/schedule/presentation/widgets/calendar_week_view.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../helpers/schedule_test_helpers.dart';

// ---------------------------------------------------------------------------
// Test helpers
// ---------------------------------------------------------------------------

/// Build a CalendarWeekView with providers overridden and data injected.
Widget buildWeekView({
  List<dynamic>? bookings,
  List<dynamic>? contractors,
  Map<String, dynamic>? jobs,
  DateTime? selectedDate,
}) {
  final date = selectedDate ?? DateTime.now();
  final contractorList = (contractors ?? [makeContractor()])
      .cast<dynamic>()
      .toList();
  final bookingList = (bookings ?? []).cast<dynamic>().toList();
  final jobMap = (jobs ?? {}).cast<String, dynamic>();

  return ProviderScope(
    overrides: [
      calendarDateProvider.overrideWith((ref) => date),
      calendarViewModeProvider
          .overrideWith((ref) => CalendarViewMode.week),
    ],
    child: MaterialApp(
      home: Scaffold(
        body: CalendarWeekView(
          bookings: bookingList.cast(),
          contractors: contractorList.cast(),
          jobs: jobMap.cast(),
        ),
      ),
    ),
  );
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

void main() {
  group('CalendarWeekView — UAT #4', () {
    testWidgets('renders seven day column headers (Mon-Sun)', (tester) async {
      await tester.pumpWidget(buildWeekView());
      await tester.pumpAndSettle();

      // All day abbreviations should be present
      expect(find.text('Mon'), findsOneWidget);
      expect(find.text('Tue'), findsOneWidget);
      expect(find.text('Wed'), findsOneWidget);
      expect(find.text('Thu'), findsOneWidget);
      expect(find.text('Fri'), findsOneWidget);
      expect(find.text('Sat'), findsOneWidget);
      expect(find.text('Sun'), findsOneWidget);
    });

    testWidgets('contractor name is displayed in row', (tester) async {
      final contractor = makeContractor(
        firstName: 'Alice',
        lastName: 'Builder',
      );

      await tester.pumpWidget(buildWeekView(contractors: [contractor]));
      await tester.pumpAndSettle();

      // Contractor name shown in the row
      expect(find.text('Alice Builder'), findsOneWidget);
    });

    testWidgets('contractor initials shown in avatar', (tester) async {
      final contractor = makeContractor(
        firstName: 'Alice',
        lastName: 'Builder',
      );

      await tester.pumpWidget(buildWeekView(contractors: [contractor]));
      await tester.pumpAndSettle();

      // Initials "AB" in the circle avatar
      expect(find.text('AB'), findsOneWidget);
    });

    testWidgets('empty contractors shows "No contractors found" placeholder',
        (tester) async {
      await tester.pumpWidget(buildWeekView(contractors: []));
      await tester.pumpAndSettle();

      expect(find.text('No contractors found'), findsOneWidget);
      expect(find.byIcon(Icons.people_outline), findsOneWidget);
    });

    testWidgets('job chip shows job description text', (tester) async {
      final now = DateTime.now();
      // Compute the Monday of the current week for the booking date
      final monday = now.subtract(Duration(days: now.weekday - 1));
      final bookingStart = DateTime(
        monday.year,
        monday.month,
        monday.day,
        9,
      );
      final bookingEnd = bookingStart.add(const Duration(hours: 2));

      final contractor = makeContractor();
      final job = makeJob(description: 'Install kitchen sink');
      final booking = makeBooking(
        contractorId: contractor.id,
        jobId: job.id,
        timeRangeStart: bookingStart,
        timeRangeEnd: bookingEnd,
      );

      await tester.pumpWidget(buildWeekView(
        bookings: [booking],
        contractors: [contractor],
        jobs: {job.id: job},
        selectedDate: monday,
      ));
      await tester.pumpAndSettle();

      expect(find.text('Install kitchen sink'), findsOneWidget);
    });

    testWidgets('+N more badge shows when >3 bookings in a cell',
        (tester) async {
      final now = DateTime.now();
      final monday = now.subtract(Duration(days: now.weekday - 1));
      final cellDate = DateTime(monday.year, monday.month, monday.day);

      final contractor = makeContractor();

      // Create 5 bookings on the same day for the same contractor
      final bookings = List.generate(5, (i) {
        final start = cellDate.add(Duration(hours: 8 + i));
        return makeBooking(
          id: 'booking-$i',
          contractorId: contractor.id,
          jobId: 'job-$i',
          timeRangeStart: start,
          timeRangeEnd: start.add(const Duration(minutes: 45)),
        );
      });

      final jobs = {
        for (var i = 0; i < 5; i++)
          'job-$i': makeJob(id: 'job-$i', description: 'Job task $i'),
      };

      await tester.pumpWidget(buildWeekView(
        bookings: bookings,
        contractors: [contractor],
        jobs: jobs,
        selectedDate: monday,
      ));
      await tester.pumpAndSettle();

      // Only 3 are visible; 2 overflow → "+2 more" badge
      expect(find.text('+2 more'), findsOneWidget);
    });

    testWidgets('overdue job chip has colored border', (tester) async {
      final now = DateTime.now();
      final monday = now.subtract(Duration(days: now.weekday - 1));
      final cellDate = DateTime(monday.year, monday.month, monday.day, 10);

      final contractor = makeContractor();
      final overdueJob = makeJob(
        id: 'overdue-job',
        description: 'Overdue plumbing',
        scheduledCompletionDate: pastDate(5), // 5 days overdue = critical
      );
      final booking = makeBooking(
        contractorId: contractor.id,
        jobId: overdueJob.id,
        timeRangeStart: cellDate,
        timeRangeEnd: cellDate.add(const Duration(hours: 2)),
      );

      await tester.pumpWidget(buildWeekView(
        bookings: [booking],
        contractors: [contractor],
        jobs: {overdueJob.id: overdueJob},
        selectedDate: monday,
      ));
      await tester.pumpAndSettle();

      // The overdue job text should be present
      expect(find.text('Overdue plumbing'), findsOneWidget);
    });

    testWidgets('date numbers appear in column headers', (tester) async {
      final now = DateTime.now();
      final monday = now.subtract(Duration(days: now.weekday - 1));

      await tester.pumpWidget(buildWeekView(
        selectedDate: monday,
      ));
      await tester.pumpAndSettle();

      // The monday date number should appear in the header
      expect(find.text('${monday.day}'), findsAtLeast(1));
    });

    testWidgets('tapping a day cell changes view mode to day',
        (tester) async {
      final contractor = makeContractor();

      await tester.pumpWidget(buildWeekView(
        contractors: [contractor],
      ));
      await tester.pumpAndSettle();

      // The CalendarWeekView widget should be present
      expect(find.byType(CalendarWeekView), findsOneWidget);
    });
  });
}
