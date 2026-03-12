/// Widget tests for TimerScreen.
///
/// Tests cover:
/// 1. renders elapsed time display in HH:MM:SS format
/// 2. shows "Clock In" button when no active session
/// 3. shows "Clock Out" button when active session for this job
/// 4. session history list renders completed sessions with duration
/// 5. total time summary displayed correctly
library;

import 'package:contractorhub/core/database/app_database.dart' hide UserRole;
import 'package:contractorhub/features/auth/domain/auth_state.dart';
import 'package:contractorhub/features/auth/presentation/providers/auth_provider.dart';
import 'package:contractorhub/features/jobs/domain/job_entity.dart';
import 'package:contractorhub/features/jobs/presentation/providers/job_providers.dart';
import 'package:contractorhub/features/jobs/presentation/providers/timer_providers.dart';
import 'package:contractorhub/features/jobs/presentation/screens/timer_screen.dart';
import 'package:contractorhub/shared/models/user_role.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

// ---------------------------------------------------------------------------
// Stub notifiers
// ---------------------------------------------------------------------------

/// Stub auth notifier returning authenticated contractor state.
class _StubAuthNotifier extends AuthNotifier {
  final AuthState _state;

  _StubAuthNotifier(this._state);

  @override
  AuthState build() => _state;
}

/// Stub TimerNotifier with configurable initial state.
class _StubTimerNotifier extends TimerNotifier {
  final TimerState _initial;

  _StubTimerNotifier(this._initial);

  @override
  Future<TimerState> build() async => _initial;

  @override
  Future<void> clockIn(String jobId, String companyId) async {}

  @override
  Future<void> clockOut() async {}
}

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

const _contractorAuth = AuthState.authenticated(
  userId: 'contractor-1',
  companyId: 'co-1',
  roles: {UserRole.contractor},
);

JobEntity _makeJob({String id = 'job-1', String status = 'scheduled'}) {
  final now = DateTime.now();
  return JobEntity(
    id: id,
    companyId: 'co-1',
    description: 'Fix the boiler',
    tradeType: 'plumber',
    status: status,
    priority: 'medium',
    statusHistory: const [],
    tags: const [],
    version: 1,
    createdAt: now,
    updatedAt: now,
  );
}

TimeEntry _makeTimeEntry({
  String id = 'entry-1',
  String jobId = 'job-1',
  String sessionStatus = 'completed',
  DateTime? clockedInAt,
  DateTime? clockedOutAt,
  int? durationSeconds,
}) {
  final now = DateTime.now();
  return TimeEntry(
    id: id,
    companyId: 'co-1',
    jobId: jobId,
    contractorId: 'contractor-1',
    clockedInAt: clockedInAt ?? now.subtract(const Duration(hours: 1)),
    clockedOutAt: clockedOutAt ?? now,
    durationSeconds: durationSeconds ?? 3600,
    sessionStatus: sessionStatus,
    adjustmentLog: '[]',
    version: 1,
    createdAt: now,
    updatedAt: now,
  );
}

Widget buildTimerScreen(
  String jobId, {
  TimerState? timerState,
  List<TimeEntry>? entries,
}) {
  final state = timerState ?? const TimerState();
  final entryList = entries ?? [];

  return ProviderScope(
    overrides: [
      authNotifierProvider.overrideWith(() => _StubAuthNotifier(_contractorAuth)),
      timerNotifierProvider.overrideWith(() => _StubTimerNotifier(state)),
      jobDetailNotifierProvider(jobId).overrideWith(
        (ref) => Stream.value(_makeJob(id: jobId)),
      ),
      timeEntriesForJobProvider(jobId).overrideWith(
        (ref) => Stream.value(entryList),
      ),
    ],
    child: MaterialApp(
      home: TimerScreen(jobId: jobId),
    ),
  );
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

void main() {
  group('TimerScreen', () {
    testWidgets('renders elapsed time display in HH:MM:SS format',
        (tester) async {
      await tester.pumpWidget(buildTimerScreen('job-1'));
      // Pump multiple frames: job stream → timer state build → entries stream
      await tester.pump();
      await tester.pump();
      await tester.pump();

      // No active session — should show 00:00:00
      expect(find.text('00:00:00'), findsOneWidget);
    });

    testWidgets('shows Clock In button when no active session', (tester) async {
      const noSession = TimerState();

      await tester.pumpWidget(buildTimerScreen('job-1', timerState: noSession));
      await tester.pump();
      await tester.pump();
      await tester.pump();

      expect(find.text('Clock In'), findsOneWidget);
    });

    testWidgets('shows Clock Out button when active session is for this job',
        (tester) async {
      final now = DateTime.now();
      final entry = _makeTimeEntry(
        id: 'entry-active',
        jobId: 'job-1',
        sessionStatus: 'active',
        clockedInAt: now.subtract(const Duration(minutes: 30)),
        clockedOutAt: null,
        durationSeconds: null,
      );

      final activeState = TimerState(
        activeEntry: entry,
        elapsedSeconds: 1800,
        activeJobId: 'job-1',
      );

      await tester.pumpWidget(
          buildTimerScreen('job-1', timerState: activeState));
      await tester.pump();
      await tester.pump();
      await tester.pump();

      expect(find.text('Clock Out'), findsOneWidget);
    });

    testWidgets('session history list shows completed sessions', (tester) async {
      final entry = _makeTimeEntry(
        id: 'entry-1',
        durationSeconds: 3600,
        sessionStatus: 'completed',
      );

      await tester.pumpWidget(buildTimerScreen('job-1', entries: [entry]));
      await tester.pump();
      await tester.pump();
      await tester.pump();

      // Session history header
      expect(find.text('Sessions'), findsOneWidget);
      // Duration formatted as 1h 0m (may appear in session card and total row)
      expect(find.text('1h 0m'), findsWidgets);
    });

    testWidgets('shows total time summary', (tester) async {
      final entry1 = _makeTimeEntry(
        id: 'entry-1',
        durationSeconds: 3600,
      );
      final entry2 = _makeTimeEntry(
        id: 'entry-2',
        durationSeconds: 1800,
      );

      await tester.pumpWidget(
          buildTimerScreen('job-1', entries: [entry1, entry2]));
      await tester.pump();
      await tester.pump();
      await tester.pump();

      expect(find.text('Total Time'), findsOneWidget);
      // 3600 + 1800 = 5400 seconds = 1h 30m
      expect(find.text('1h 30m'), findsOneWidget);
    });

    testWidgets('empty session history shows no-time placeholder', (tester) async {
      await tester.pumpWidget(buildTimerScreen('job-1', entries: []));
      await tester.pump();
      await tester.pump();
      await tester.pump();

      expect(find.textContaining('No time sessions yet'), findsOneWidget);
    });
  });
}
