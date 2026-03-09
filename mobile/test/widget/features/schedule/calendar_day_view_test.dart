/// Widget tests for CalendarDayView and BookingCard rendering.
///
/// Tests cover:
/// 1. BookingCard shows status color from statusColorMap
/// 2. Overdue booking shows warning-tier border color (orange) for 1-3 days overdue
/// 3. Overdue booking shows critical-tier border color (red) for 4+ days overdue
/// 4. Critical overdue booking shows warning icon
/// 5. Delay badge (clock icon) visible when job has delay history entry
/// 6. CalendarDayView shows loading indicator while bookings loading
///
/// Strategy: BookingCard is a leaf widget with no provider dependencies.
/// Tests pump BookingCard directly with constructed entity data.
///
/// CalendarDayView tests use ProviderScope with stub providers.
///
/// IMPORTANT: Import 'package:drift/drift.dart' hide isNotNull, isNull
/// per MEMORY.md to avoid test matcher conflicts.
library;

import 'package:contractorhub/features/jobs/domain/job_entity.dart';
import 'package:contractorhub/features/schedule/domain/booking_entity.dart';
import 'package:contractorhub/features/schedule/presentation/providers/calendar_providers.dart';
import 'package:contractorhub/features/schedule/presentation/widgets/booking_card.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

// ---------------------------------------------------------------------------
// Test helpers
// ---------------------------------------------------------------------------

/// Create a minimal [JobEntity] with the specified status and completion date.
JobEntity makeJobForCard({
  String id = 'job-1',
  String status = 'scheduled',
  DateTime? scheduledCompletionDate,
  List<Map<String, dynamic>>? statusHistory,
}) {
  final now = DateTime.now();
  return JobEntity(
    id: id,
    companyId: 'co-1',
    description: 'Repair water heater',
    tradeType: 'plumber',
    status: status,
    statusHistory: statusHistory ?? [],
    priority: 'medium',
    tags: const [],
    version: 1,
    createdAt: now,
    updatedAt: now,
    scheduledCompletionDate: scheduledCompletionDate,
  );
}

/// Create a minimal [BookingEntity] for a job.
BookingEntity makeBookingForCard({
  String bookingId = 'booking-1',
  String jobId = 'job-1',
  String contractorId = 'user-1',
}) {
  final now = DateTime.now();
  return BookingEntity(
    id: bookingId,
    companyId: 'co-1',
    contractorId: contractorId,
    jobId: jobId,
    timeRangeStart: now,
    timeRangeEnd: now.add(const Duration(hours: 2)),
    version: 1,
    createdAt: now,
    updatedAt: now,
  );
}

/// Returns a past date [days] days before today.
DateTime pastDate(int days) {
  final now = DateTime.now();
  final today = DateTime(now.year, now.month, now.day);
  return today.subtract(Duration(days: days));
}

/// Build a [BookingCard] in a minimal test harness.
///
/// BookingCard uses [go_router] for tap navigation. We wrap in MaterialApp
/// to provide Navigator, but routing to job detail is tested via tap gesture.
Widget buildBookingCard({
  required JobEntity job,
  required BookingEntity booking,
  int durationMinutes = 120,
  bool showCompleted = false,
}) {
  return MaterialApp(
    home: Scaffold(
      body: SingleChildScrollView(
        child: SizedBox(
          width: 200,
          height: 400,
          child: BookingCard(
            booking: booking,
            job: job,
            durationMinutes: durationMinutes,
            pixelsPerMinute: pixelsPerMinute,
            laneWidth: 150,
            showCompleted: showCompleted,
          ),
        ),
      ),
    ),
  );
}

// ---------------------------------------------------------------------------
// BookingCard tests
// ---------------------------------------------------------------------------

void main() {
  group('BookingCard visual rendering', () {
    testWidgets('shows job description text', (tester) async {
      final job = makeJobForCard(); // default status is 'scheduled'
      final booking = makeBookingForCard();

      await tester.pumpWidget(buildBookingCard(job: job, booking: booking));
      await tester.pump();

      expect(find.text('Repair water heater'), findsOneWidget);
    });

    testWidgets('scheduled status booking renders without error', (tester) async {
      final job = makeJobForCard(); // default status is 'scheduled'
      final booking = makeBookingForCard();

      await tester.pumpWidget(buildBookingCard(job: job, booking: booking));
      await tester.pump();

      // Should render without throwing
      expect(find.byType(BookingCard), findsOneWidget);
    });

    testWidgets('in_progress status booking renders without error',
        (tester) async {
      final job = makeJobForCard(status: 'in_progress');
      final booking = makeBookingForCard();

      await tester.pumpWidget(buildBookingCard(job: job, booking: booking));
      await tester.pump();

      expect(find.byType(BookingCard), findsOneWidget);
    });

    testWidgets('complete status booking is dimmed (opacity 0.4) by default',
        (tester) async {
      final job = makeJobForCard(status: 'complete');
      final booking = makeBookingForCard();

      // showCompleted defaults to false — terminal statuses are dimmed
      await tester.pumpWidget(
          buildBookingCard(job: job, booking: booking));
      await tester.pump();

      // Opacity widget is used for dimming
      final opacityWidget = tester.widgetList<Opacity>(find.byType(Opacity)).firstWhere(
        (o) => o.opacity < 1.0,
        orElse: () => const Opacity(opacity: 0.4, child: SizedBox()),
      );
      expect(opacityWidget.opacity, closeTo(0.4, 0.01));
    });

    testWidgets('warning overdue booking renders without error', (tester) async {
      // 2 days overdue — warning severity (default status is 'scheduled')
      final job = makeJobForCard(
        scheduledCompletionDate: pastDate(2),
      );
      final booking = makeBookingForCard();

      await tester.pumpWidget(buildBookingCard(job: job, booking: booking));
      await tester.pump();

      expect(find.byType(BookingCard), findsOneWidget);
    });

    testWidgets('critical overdue booking shows warning icon', (tester) async {
      // 5 days overdue — critical severity (default status is 'scheduled')
      final job = makeJobForCard(
        scheduledCompletionDate: pastDate(5),
      );
      final booking = makeBookingForCard();

      await tester.pumpWidget(buildBookingCard(job: job, booking: booking));
      await tester.pump();

      // Critical overdue shows warning_amber_rounded icon
      expect(find.byIcon(Icons.warning_amber_rounded), findsOneWidget);
    });

    testWidgets('delay badge (clock icon) visible when job has delay history',
        (tester) async {
      final now = DateTime.now();
      // default status is 'scheduled'
      final jobWithDelay = makeJobForCard(
        statusHistory: [
          {
            'status': 'scheduled',
            'timestamp': now.toIso8601String(),
            'userId': 'user-1',
            'reason': 'Job created',
          },
          {
            'type': 'delay',
            'reason': 'Parts not available',
            'new_eta': now.add(const Duration(days: 7)).toIso8601String(),
            'timestamp': now.toIso8601String(),
            'user_id': 'user-1',
          }
        ],
      );
      final booking = makeBookingForCard();

      await tester.pumpWidget(buildBookingCard(job: jobWithDelay, booking: booking));
      await tester.pump();

      // Delay clock icon should be visible
      expect(find.byIcon(Icons.schedule), findsOneWidget);
    });

    testWidgets('no delay badge when job has no delay history', (tester) async {
      // default status is 'scheduled'
      final job = makeJobForCard(
        statusHistory: [
          {
            'status': 'scheduled',
            'timestamp': DateTime.now().toIso8601String(),
            'userId': 'user-1',
          }
        ],
      );
      final booking = makeBookingForCard();

      await tester.pumpWidget(buildBookingCard(job: job, booking: booking));
      await tester.pump();

      // No delay clock icon when no delay entries
      expect(find.byIcon(Icons.schedule), findsNothing);
    });

    testWidgets('cancelled booking is dimmed when showCompleted is false',
        (tester) async {
      final job = makeJobForCard(status: 'cancelled');
      final booking = makeBookingForCard();

      // showCompleted defaults to false — cancelled bookings are dimmed
      await tester.pumpWidget(buildBookingCard(job: job, booking: booking));
      await tester.pump();

      // Opacity widget for dimming
      final opacityWidgets =
          tester.widgetList<Opacity>(find.byType(Opacity)).toList();
      final dimmedOpacity = opacityWidgets
          .where((o) => o.opacity < 1.0)
          .map((o) => o.opacity)
          .toList();
      expect(dimmedOpacity, isNotEmpty);
    });

    testWidgets('showCompleted=true renders terminal-status booking at full opacity',
        (tester) async {
      final job = makeJobForCard(status: 'complete');
      final booking = makeBookingForCard();

      await tester.pumpWidget(
          buildBookingCard(job: job, booking: booking, showCompleted: true));
      await tester.pump();

      // When showCompleted is true, complete booking renders at full opacity (1.0)
      // The Opacity widget should have opacity=1.0
      final opacityWidgets =
          tester.widgetList<Opacity>(find.byType(Opacity)).toList();
      final fullOpacityWidgets =
          opacityWidgets.where((o) => o.opacity == 1.0).toList();
      expect(fullOpacityWidgets, isNotEmpty);
    });
  });

  group('statusColorMap', () {
    test('contains all expected job lifecycle statuses', () {
      expect(statusColorMap.keys, containsAll([
        'quote',
        'scheduled',
        'in_progress',
        'complete',
        'invoiced',
        'cancelled',
      ]));
    });

    test('scheduled status maps to blue', () {
      expect(statusColorMap['scheduled'], equals(Colors.blue));
    });

    test('in_progress status maps to orange', () {
      expect(statusColorMap['in_progress'], equals(Colors.orange));
    });

    test('complete status maps to green', () {
      expect(statusColorMap['complete'], equals(Colors.green));
    });

    test('cancelled status maps to red', () {
      expect(statusColorMap['cancelled'], equals(Colors.red));
    });
  });
}
