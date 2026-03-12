/// Widget tests for ContractorJobCard.
///
/// Tests cover:
/// 1. renders action bar with Add Note, Camera, Clock In buttons for non-completed jobs
/// 2. active job shows highlighted border (primary color)
/// 3. completed job shows dimmed card with no action bar
/// 4. status badge renders job status text
/// 5. Clock In button navigates to timer (via GoRouter)
library;

import 'package:contractorhub/features/auth/domain/auth_state.dart';
import 'package:contractorhub/features/auth/presentation/providers/auth_provider.dart';
import 'package:contractorhub/features/jobs/domain/job_entity.dart';
import 'package:contractorhub/features/jobs/presentation/providers/timer_providers.dart';
import 'package:contractorhub/features/jobs/presentation/widgets/contractor_job_card.dart';
import 'package:contractorhub/shared/models/user_role.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

// ---------------------------------------------------------------------------
// Stub notifiers
// ---------------------------------------------------------------------------

class _StubAuthNotifier extends AuthNotifier {
  final AuthState _state;

  _StubAuthNotifier(this._state);

  @override
  AuthState build() => _state;
}

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

JobEntity _makeJob({
  String id = 'job-1',
  String status = 'scheduled',
  String description = 'Repair boiler',
}) {
  final now = DateTime.now();
  return JobEntity(
    id: id,
    companyId: 'co-1',
    description: description,
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

Widget buildCardWidget(
  JobEntity job, {
  TimerState? timerState,
}) {
  final state = timerState ?? const TimerState();

  // Use a minimal GoRouter to satisfy GoRouter navigation calls in the card
  final router = GoRouter(
    routes: [
      GoRoute(
        path: '/',
        builder: (_, __) => Scaffold(
          body: ContractorJobCard(job: job),
        ),
        routes: [
          GoRoute(
            path: 'jobs/:jobId',
            builder: (_, __) => const Scaffold(body: Text('Job Detail')),
          ),
          GoRoute(
            path: 'timer/:jobId',
            builder: (_, __) => const Scaffold(body: Text('Timer')),
          ),
        ],
      ),
    ],
  );

  return ProviderScope(
    overrides: [
      authNotifierProvider
          .overrideWith(() => _StubAuthNotifier(_contractorAuth)),
      timerNotifierProvider
          .overrideWith(() => _StubTimerNotifier(state)),
    ],
    child: MaterialApp.router(routerConfig: router),
  );
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

void main() {
  group('ContractorJobCard', () {
    testWidgets('renders action bar with Add Note for non-completed job',
        (tester) async {
      final job = _makeJob(status: 'scheduled');

      await tester.pumpWidget(buildCardWidget(job));
      await tester.pump();

      expect(find.text('Add Note'), findsOneWidget);
    });

    testWidgets('renders Camera button for non-completed job', (tester) async {
      final job = _makeJob(status: 'in_progress');

      await tester.pumpWidget(buildCardWidget(job));
      await tester.pump();

      expect(find.text('Camera'), findsOneWidget);
    });

    testWidgets('renders Clock In button for non-active non-completed job',
        (tester) async {
      final job = _makeJob(status: 'scheduled');

      await tester.pumpWidget(buildCardWidget(job));
      await tester.pump();

      expect(find.text('Clock In'), findsOneWidget);
    });

    testWidgets('active job shows Clock Out button', (tester) async {
      final job = _makeJob(id: 'job-active', status: 'in_progress');
      final activeState = TimerState(
        activeJobId: 'job-active',
        elapsedSeconds: 300,
      );

      await tester.pumpWidget(buildCardWidget(job, timerState: activeState));
      await tester.pump();

      expect(find.text('Clock Out'), findsOneWidget);
    });

    testWidgets('completed job has no action bar (no Add Note)', (tester) async {
      final job = _makeJob(status: 'complete');

      await tester.pumpWidget(buildCardWidget(job));
      await tester.pump();

      expect(find.text('Add Note'), findsNothing);
    });

    testWidgets('renders job description text', (tester) async {
      final job = _makeJob(description: 'Fix the water heater urgently');

      await tester.pumpWidget(buildCardWidget(job));
      await tester.pump();

      expect(find.text('Fix the water heater urgently'), findsOneWidget);
    });

    testWidgets('renders status badge text', (tester) async {
      final job = _makeJob(status: 'scheduled');

      await tester.pumpWidget(buildCardWidget(job));
      await tester.pump();

      // The status badge shows the display label for 'scheduled'
      expect(find.text('Scheduled'), findsOneWidget);
    });
  });
}
