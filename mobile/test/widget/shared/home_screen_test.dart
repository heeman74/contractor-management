/// E2E widget tests for HomeScreen.
///
/// Tests cover:
/// 1. Admin sees admin quick links (Team, Clients, Jobs Pipeline, Schedule)
/// 2. Contractor sees contractor quick links (My Jobs, My Schedule, Availability)
/// 3. Client sees client quick links (Client Portal)
/// 4. Multi-role user sees combined sections
library;

import 'package:contractorhub/core/di/service_locator.dart';
import 'package:contractorhub/core/sync/sync_engine.dart';
import 'package:contractorhub/features/auth/domain/auth_state.dart';
import 'package:contractorhub/features/auth/presentation/providers/auth_provider.dart';
import 'package:contractorhub/shared/models/user_role.dart';
import 'package:contractorhub/shared/screens/home_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

class _StubAuthNotifier extends AuthNotifier {
  _StubAuthNotifier(this._fixedState);
  final AuthState _fixedState;
  @override
  AuthState build() => _fixedState;
}

class _MockSyncEngine extends Mock implements SyncEngine {}

Widget _buildWidget(AuthState authState) {
  return ProviderScope(
    overrides: [
      authNotifierProvider
          .overrideWith(() => _StubAuthNotifier(authState)),
    ],
    child: const MaterialApp(home: HomeScreen()),
  );
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

void main() {
  late _MockSyncEngine mockSync;

  setUp(() {
    mockSync = _MockSyncEngine();
    when(() => mockSync.syncNow()).thenAnswer((_) async {});

    if (getIt.isRegistered<SyncEngine>()) getIt.unregister<SyncEngine>();
    getIt.registerSingleton<SyncEngine>(mockSync);
  });

  tearDown(() {
    if (getIt.isRegistered<SyncEngine>()) getIt.unregister<SyncEngine>();
  });

  group('HomeScreen — Admin role', () {
    const adminState = AuthState.authenticated(
      userId: 'admin-1',
      companyId: 'co-1',
      roles: {UserRole.admin},
    );

    testWidgets('shows admin quick links', (tester) async {
      await tester.pumpWidget(_buildWidget(adminState));
      await tester.pumpAndSettle();

      expect(find.text('Admin Features'), findsOneWidget);
      expect(find.text('Team Management'), findsOneWidget);
      expect(find.text('Client Management'), findsOneWidget);
      expect(find.text('Jobs Pipeline'), findsOneWidget);
      expect(find.text('Schedule'), findsOneWidget);
    });
  });

  group('HomeScreen — Contractor role', () {
    const contractorState = AuthState.authenticated(
      userId: 'con-1',
      companyId: 'co-1',
      roles: {UserRole.contractor},
    );

    testWidgets('shows contractor quick links', (tester) async {
      await tester.pumpWidget(_buildWidget(contractorState));
      await tester.pumpAndSettle();

      expect(find.text('Contractor Features'), findsOneWidget);
      expect(find.text('My Jobs'), findsOneWidget);
      expect(find.text('My Schedule'), findsOneWidget);
      expect(find.text('Availability'), findsOneWidget);
    });

    testWidgets('does not show admin or client sections', (tester) async {
      await tester.pumpWidget(_buildWidget(contractorState));
      await tester.pumpAndSettle();

      expect(find.text('Admin Features'), findsNothing);
      expect(find.text('Client Features'), findsNothing);
    });
  });

  group('HomeScreen — Client role', () {
    const clientState = AuthState.authenticated(
      userId: 'client-1',
      companyId: 'co-1',
      roles: {UserRole.client},
    );

    testWidgets('shows client quick links', (tester) async {
      await tester.pumpWidget(_buildWidget(clientState));
      await tester.pumpAndSettle();

      expect(find.text('Client Features'), findsOneWidget);
      expect(find.text('Client Portal'), findsOneWidget);
      expect(find.text('Track your jobs and submit requests'), findsOneWidget);
    });

    testWidgets('does not show admin or contractor sections', (tester) async {
      await tester.pumpWidget(_buildWidget(clientState));
      await tester.pumpAndSettle();

      expect(find.text('Admin Features'), findsNothing);
      expect(find.text('Contractor Features'), findsNothing);
    });
  });

  group('HomeScreen — Multi-role', () {
    const multiState = AuthState.authenticated(
      userId: 'multi-1',
      companyId: 'co-1',
      roles: {UserRole.admin, UserRole.contractor},
    );

    testWidgets('shows both admin and contractor sections', (tester) async {
      await tester.pumpWidget(_buildWidget(multiState));
      await tester.pumpAndSettle();

      expect(find.text('Admin Features'), findsOneWidget);
      expect(find.text('Contractor Features'), findsOneWidget);
      expect(find.text('Client Features'), findsNothing);
    });
  });
}
