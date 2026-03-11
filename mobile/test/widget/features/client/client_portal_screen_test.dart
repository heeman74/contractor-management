/// E2E widget tests for ClientPortalScreen.
///
/// Tests cover:
/// 1. Empty state when no jobs
/// 2. Job cards render with description, status badge, trade type
/// 3. FAB "Request Job" is present
/// 4. Multiple jobs render in list
library;

import 'package:contractorhub/features/auth/domain/auth_state.dart';
import 'package:contractorhub/features/auth/presentation/providers/auth_provider.dart';
import 'package:contractorhub/features/client/presentation/screens/client_portal_screen.dart';
import 'package:contractorhub/features/jobs/domain/job_entity.dart';
import 'package:contractorhub/features/jobs/presentation/providers/crm_providers.dart';
import 'package:contractorhub/shared/models/user_role.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

class _StubAuthNotifier extends AuthNotifier {
  _StubAuthNotifier(this._fixedState);
  final AuthState _fixedState;
  @override
  AuthState build() => _fixedState;
}

const _clientState = AuthState.authenticated(
  userId: 'client-1',
  companyId: 'co-1',
  roles: {UserRole.client},
);

JobEntity _makeJob({
  String id = 'job-1',
  String description = 'Fix sink',
  String status = 'quote',
  String tradeType = 'Plumbing',
  String? clientId = 'client-1',
}) {
  final now = DateTime.now();
  return JobEntity(
    id: id,
    companyId: 'co-1',
    description: description,
    tradeType: tradeType,
    status: status,
    statusHistory: const [],
    priority: 'medium',
    tags: const [],
    version: 1,
    createdAt: now,
    updatedAt: now,
    clientId: clientId,
  );
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

void main() {
  Widget buildWidget({List<JobEntity> jobs = const []}) {
    return ProviderScope(
      overrides: [
        authNotifierProvider
            .overrideWith(() => _StubAuthNotifier(_clientState)),
        clientJobHistoryNotifierProvider('client-1')
            .overrideWith((ref) => Stream.value(jobs)),
      ],
      child: MaterialApp(
        home: const ClientPortalScreen(),
      ),
    );
  }

  group('ClientPortalScreen — empty state', () {
    testWidgets('shows empty state when no jobs', (tester) async {
      await tester.pumpWidget(buildWidget());
      await tester.pumpAndSettle();

      expect(find.text('No jobs yet'), findsOneWidget);
      expect(find.textContaining('Submit a job request'), findsOneWidget);
    });

    testWidgets('shows FAB with Request Job', (tester) async {
      await tester.pumpWidget(buildWidget());
      await tester.pumpAndSettle();

      expect(find.text('Request Job'), findsOneWidget);
      expect(find.byType(FloatingActionButton), findsOneWidget);
    });
  });

  group('ClientPortalScreen — job list', () {
    testWidgets('renders job card with description and status',
        (tester) async {
      await tester.pumpWidget(buildWidget(jobs: [
        _makeJob(description: 'Replace water heater', status: 'scheduled'),
      ]));
      await tester.pumpAndSettle();

      expect(find.text('Replace water heater'), findsOneWidget);
      expect(find.text('Scheduled'), findsOneWidget);
      expect(find.text('Plumbing'), findsOneWidget);
    });

    testWidgets('renders multiple jobs', (tester) async {
      await tester.pumpWidget(buildWidget(jobs: [
        _makeJob(
            id: 'j-1',
            description: 'Fix sink',
            status: 'quote',
            tradeType: 'Plumbing'),
        _makeJob(
            id: 'j-2',
            description: 'Paint walls',
            status: 'in_progress',
            tradeType: 'Painting'),
        _makeJob(
            id: 'j-3',
            description: 'Rewire outlet',
            status: 'complete',
            tradeType: 'Electrical'),
      ]));
      await tester.pumpAndSettle();

      expect(find.text('Fix sink'), findsOneWidget);
      expect(find.text('Paint walls'), findsOneWidget);
      expect(find.text('Rewire outlet'), findsOneWidget);
      expect(find.text('Quote'), findsOneWidget);
      expect(find.text('In Progress'), findsOneWidget);
      expect(find.text('Complete'), findsOneWidget);
    });

    testWidgets('app bar shows Client Portal title', (tester) async {
      await tester.pumpWidget(buildWidget());
      await tester.pumpAndSettle();

      expect(find.text('Client Portal'), findsOneWidget);
    });
  });
}
