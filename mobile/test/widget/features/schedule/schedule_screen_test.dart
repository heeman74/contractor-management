/// Widget tests for ScheduleScreen — admin dispatch calendar.
///
/// Tests cover:
/// 1. Screen shows day view by default (CalendarDayView present)
/// 2. View mode toggle switches to week view (CalendarWeekView)
/// 3. View mode toggle switches to month view (CalendarMonthView)
/// 4. Today button is present in header
/// 5. Overdue badge shows count 0 when no overdue jobs
/// 6. Overdue badge shows count from overdueJobCountProvider override
/// 7. Header contains view mode segmented button (Day/Week/Month)
/// 8. Header contains trade filter dropdown
/// 9. Switching between view modes works bidirectionally
///
/// Strategy: Use ProviderScope overrides with stub notifiers to isolate
/// ScheduleScreen from Drift, network, and GetIt dependencies.
///
/// The ScheduleScreen requires Scaffold (it doesn't create one itself —
/// it is mounted inside AppShell). We wrap it in MaterialApp + Scaffold.
library;

import 'package:contractorhub/features/auth/domain/auth_state.dart';
import 'package:contractorhub/features/auth/presentation/providers/auth_provider.dart';
import 'package:contractorhub/features/jobs/domain/job_entity.dart';
import 'package:contractorhub/features/jobs/presentation/providers/job_providers.dart'
    as job_providers;
import 'package:contractorhub/features/schedule/domain/booking_entity.dart';
import 'package:contractorhub/features/schedule/presentation/providers/calendar_providers.dart';
import 'package:contractorhub/features/schedule/presentation/providers/overdue_providers.dart';
import 'package:contractorhub/features/schedule/presentation/screens/schedule_screen.dart';
import 'package:contractorhub/features/schedule/presentation/widgets/calendar_day_view.dart';
import 'package:contractorhub/features/schedule/presentation/widgets/calendar_month_view.dart';
import 'package:contractorhub/features/schedule/presentation/widgets/calendar_week_view.dart';
import 'package:contractorhub/features/users/domain/user_entity.dart';
import 'package:contractorhub/shared/models/user_role.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

// ---------------------------------------------------------------------------
// Test helpers
// ---------------------------------------------------------------------------

class _StubAuthNotifier extends AuthNotifier {
  _StubAuthNotifier(this._fixedState);
  final AuthState _fixedState;

  @override
  AuthState build() => _fixedState;
}

const _adminAuthState = AuthState.authenticated(
  userId: 'admin-user-1',
  companyId: 'co-1',
  roles: {UserRole.admin},
);

/// Stub notifier for bookings — subclasses BookingsForDateNotifier to be type-compatible.
class _StubBookingsNotifier extends BookingsForDateNotifier {
  @override
  Future<List<BookingEntity>> build() async => [];
}

/// Stub notifier for contractors — subclasses ContractorsNotifier to be type-compatible.
class _StubContractorsNotifier extends ContractorsNotifier {
  @override
  Future<List<UserEntity>> build() async => [];
}

/// Stub notifier for job list — subclasses JobListNotifier to be type-compatible.
class _StubJobListNotifier extends job_providers.JobListNotifier {
  @override
  Future<List<JobEntity>> build() async => [];
}

/// Build a ScheduleScreen with all providers overridden for isolation.
Widget buildScheduleScreen({
  int overdueCount = 0,
}) {
  return ProviderScope(
    overrides: [
      authNotifierProvider
          .overrideWith(() => _StubAuthNotifier(_adminAuthState)),
      bookingsForDateProvider
          .overrideWith(() => _StubBookingsNotifier()),
      contractorsProvider
          .overrideWith(() => _StubContractorsNotifier()),
      job_providers.jobListNotifierProvider
          .overrideWith(() => _StubJobListNotifier()),
      overdueJobCountProvider.overrideWithValue(overdueCount),
    ],
    child: const MaterialApp(
      home: Scaffold(
        body: ScheduleScreen(),
      ),
    ),
  );
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

void main() {
  setUp(() {
    // Register SyncEngine in GetIt to prevent ScheduleScreen's pull-to-refresh
    // from throwing a GetIt lookup error during test. We do not actually trigger
    // pull-to-refresh in these tests, but GetIt.instance lookup happens during
    // build if the widget tree contains RefreshIndicator with onRefresh callback.
    // No-op: ScheduleScreen's onRefresh uses getIt<SyncEngine>().syncNow() which
    // is only called when user pulls down — not triggered in these static tests.
  });

  group('ScheduleScreen', () {
    testWidgets('shows day view by default (CalendarDayView present)',
        (tester) async {
      await tester.pumpWidget(buildScheduleScreen());
      await tester.pumpAndSettle();

      // Day view is the default — CalendarDayView should be in the tree
      expect(find.byType(CalendarDayView), findsOneWidget);
    });

    testWidgets('view mode toggle switches to week view', (tester) async {
      await tester.pumpWidget(buildScheduleScreen());
      await tester.pumpAndSettle();

      // Tap 'Week' segment in SegmentedButton
      await tester.tap(find.text('Week'));
      await tester.pumpAndSettle();

      // CalendarWeekView should now be present
      expect(find.byType(CalendarWeekView), findsOneWidget);
      expect(find.byType(CalendarDayView), findsNothing);
    });

    testWidgets('view mode toggle switches to month view', (tester) async {
      await tester.pumpWidget(buildScheduleScreen());
      await tester.pumpAndSettle();

      // Tap 'Month' segment
      await tester.tap(find.text('Month'));
      await tester.pumpAndSettle();

      // CalendarMonthView should now be present
      expect(find.byType(CalendarMonthView), findsOneWidget);
      expect(find.byType(CalendarDayView), findsNothing);
    });

    testWidgets('Today button is present in header', (tester) async {
      await tester.pumpWidget(buildScheduleScreen());
      await tester.pumpAndSettle();

      // Today button should be visible in header
      expect(find.text('Today'), findsOneWidget);
    });

    testWidgets('overdue badge shows count of 0 when no overdue jobs',
        (tester) async {
      await tester.pumpWidget(buildScheduleScreen());
      await tester.pumpAndSettle();

      // Badge with 0 count displayed (overdue count "0" is rendered as text)
      expect(find.text('0'), findsOneWidget);
    });

    testWidgets('overdue badge shows count from overdueJobCountProvider',
        (tester) async {
      await tester.pumpWidget(buildScheduleScreen(overdueCount: 3));
      await tester.pumpAndSettle();

      // Badge displays the overdue count "3"
      expect(find.text('3'), findsOneWidget);
    });

    testWidgets('header contains view mode segmented button', (tester) async {
      await tester.pumpWidget(buildScheduleScreen());
      await tester.pumpAndSettle();

      // All three view mode labels should appear in SegmentedButton
      expect(find.text('Day'), findsOneWidget);
      expect(find.text('Week'), findsOneWidget);
      expect(find.text('Month'), findsOneWidget);
    });

    testWidgets('header contains trade filter dropdown', (tester) async {
      await tester.pumpWidget(buildScheduleScreen());
      await tester.pumpAndSettle();

      // Trade filter hint text visible when no filter selected
      expect(find.text('Trade'), findsOneWidget);
    });

    testWidgets('day view to week view and back to day view toggles correctly',
        (tester) async {
      await tester.pumpWidget(buildScheduleScreen());
      await tester.pumpAndSettle();

      // Start: day view
      expect(find.byType(CalendarDayView), findsOneWidget);

      // Switch to week
      await tester.tap(find.text('Week'));
      await tester.pumpAndSettle();
      expect(find.byType(CalendarWeekView), findsOneWidget);

      // Switch back to day
      await tester.tap(find.text('Day'));
      await tester.pumpAndSettle();
      expect(find.byType(CalendarDayView), findsOneWidget);
    });
  });
}
