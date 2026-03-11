/// E2E widget tests for ProfileScreen.
///
/// Tests cover:
/// 1. Shows user ID, company ID, and roles from auth state
/// 2. Renders role chips with correct labels
/// 3. Sign Out button triggers logout
/// 4. Shows loading when auth state is loading
/// 5. Multi-role display
///
/// No Drift streams — reads authNotifierProvider only.
library;

import 'package:contractorhub/features/auth/domain/auth_state.dart';
import 'package:contractorhub/features/auth/presentation/providers/auth_provider.dart';
import 'package:contractorhub/shared/models/user_role.dart';
import 'package:contractorhub/shared/screens/profile_screen.dart';
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

  bool logoutCalled = false;

  @override
  Future<void> logout() async {
    logoutCalled = true;
  }
}

const _adminState = AuthState.authenticated(
  userId: 'user-123',
  companyId: 'company-456',
  roles: {UserRole.admin},
);

const _multiRoleState = AuthState.authenticated(
  userId: 'user-789',
  companyId: 'company-abc',
  roles: {UserRole.admin, UserRole.contractor},
);

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

void main() {
  group('ProfileScreen — authenticated', () {
    testWidgets('shows user ID, company ID, and role', (tester) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            authNotifierProvider
                .overrideWith(() => _StubAuthNotifier(_adminState)),
          ],
          child: const MaterialApp(home: ProfileScreen()),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('user-123'), findsOneWidget);
      expect(find.text('company-456'), findsOneWidget);
      expect(find.text('admin'), findsWidgets); // in info row + chip
    });

    testWidgets('shows role chips with uppercase label', (tester) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            authNotifierProvider
                .overrideWith(() => _StubAuthNotifier(_adminState)),
          ],
          child: const MaterialApp(home: ProfileScreen()),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('ADMIN'), findsOneWidget);
      expect(find.byType(Chip), findsOneWidget);
    });

    testWidgets('shows multiple role chips when multi-role', (tester) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            authNotifierProvider
                .overrideWith(() => _StubAuthNotifier(_multiRoleState)),
          ],
          child: const MaterialApp(home: ProfileScreen()),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('ADMIN'), findsOneWidget);
      expect(find.text('CONTRACTOR'), findsOneWidget);
      expect(find.byType(Chip), findsNWidgets(2));
    });

    testWidgets('Sign Out button triggers logout', (tester) async {
      final notifier = _StubAuthNotifier(_adminState);

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            authNotifierProvider.overrideWith(() => notifier),
          ],
          child: const MaterialApp(home: ProfileScreen()),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Sign Out'), findsOneWidget);
      await tester.tap(find.text('Sign Out'));
      await tester.pump();

      expect(notifier.logoutCalled, isTrue);
    });

    testWidgets('shows Phase 1 info note', (tester) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            authNotifierProvider
                .overrideWith(() => _StubAuthNotifier(_adminState)),
          ],
          child: const MaterialApp(home: ProfileScreen()),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.textContaining('Phase 1'), findsOneWidget);
    });

    testWidgets('shows avatar with person icon', (tester) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            authNotifierProvider
                .overrideWith(() => _StubAuthNotifier(_adminState)),
          ],
          child: const MaterialApp(home: ProfileScreen()),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byType(CircleAvatar), findsOneWidget);
      expect(find.byIcon(Icons.person), findsOneWidget);
    });
  });

  group('ProfileScreen — loading', () {
    testWidgets('shows spinner when auth is loading', (tester) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            authNotifierProvider.overrideWith(
                () => _StubAuthNotifier(const AuthState.loading())),
          ],
          child: const MaterialApp(home: ProfileScreen()),
        ),
      );
      await tester.pump();

      expect(find.byType(CircularProgressIndicator), findsOneWidget);
    });
  });
}
