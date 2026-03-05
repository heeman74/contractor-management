/// Unit tests for AuthNotifier state management.
///
/// Tests verify:
/// - Initial state is AuthLoading
/// - setMockUser transitions to AuthAuthenticated with correct roles
/// - logout transitions to AuthUnauthenticated
/// - Authenticated state with single role contains that role
/// - Authenticated state with multiple roles contains all specified roles
///
/// Uses ProviderContainer for testing Riverpod providers outside of widget context.
/// No mocktail mocking needed — AuthNotifier has no external dependencies in Phase 1.
///
/// NOTE: Requires Flutter SDK + build_runner to generate:
/// - auth_state.freezed.dart (Freezed sealed class)
/// - auth_provider.g.dart (Riverpod generator output)
///
/// Run setup: cd mobile && dart run build_runner build --delete-conflicting-outputs
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:contractorhub/features/auth/domain/auth_state.dart';
import 'package:contractorhub/features/auth/presentation/providers/auth_provider.dart';
import 'package:contractorhub/shared/models/user_role.dart';

void main() {
  group('AuthNotifier', () {
    late ProviderContainer container;

    setUp(() {
      container = ProviderContainer();
    });

    tearDown(() {
      container.dispose();
    });

    test('starts in loading state', () {
      final state = container.read(authNotifierProvider);
      expect(state, isA<AuthLoading>());
    });

    test('setMockUser transitions to authenticated state', () {
      final notifier = container.read(authNotifierProvider.notifier);

      notifier.setMockUser(
        userId: 'user-123',
        companyId: 'company-456',
        roles: {UserRole.admin},
      );

      final state = container.read(authNotifierProvider);
      expect(state, isA<AuthAuthenticated>());

      final authenticated = state as AuthAuthenticated;
      expect(authenticated.userId, equals('user-123'));
      expect(authenticated.companyId, equals('company-456'));
      expect(authenticated.roles, contains(UserRole.admin));
    });

    test('logout transitions to unauthenticated state', () {
      final notifier = container.read(authNotifierProvider.notifier);

      // First authenticate
      notifier.setMockUser(
        userId: 'user-123',
        companyId: 'company-456',
        roles: {UserRole.contractor},
      );
      expect(container.read(authNotifierProvider), isA<AuthAuthenticated>());

      // Then logout
      notifier.logout();
      expect(container.read(authNotifierProvider), isA<AuthUnauthenticated>());
    });

    test('authenticated state with admin role contains UserRole.admin', () {
      final notifier = container.read(authNotifierProvider.notifier);

      notifier.setMockUser(
        userId: 'admin-user',
        companyId: 'company-1',
        roles: {UserRole.admin},
      );

      final state = container.read(authNotifierProvider) as AuthAuthenticated;
      expect(state.roles, contains(UserRole.admin));
      expect(state.roles, hasLength(1));
    });

    test('authenticated state with multiple roles contains all specified roles', () {
      final notifier = container.read(authNotifierProvider.notifier);

      notifier.setMockUser(
        userId: 'multi-role-user',
        companyId: 'company-1',
        roles: {UserRole.admin, UserRole.contractor},
      );

      final state = container.read(authNotifierProvider) as AuthAuthenticated;
      expect(state.roles, contains(UserRole.admin));
      expect(state.roles, contains(UserRole.contractor));
      expect(state.roles, hasLength(2));
    });

    test('setMockUser overwrites previous auth state', () {
      final notifier = container.read(authNotifierProvider.notifier);

      notifier.setMockUser(
        userId: 'user-1',
        companyId: 'company-1',
        roles: {UserRole.contractor},
      );

      notifier.setMockUser(
        userId: 'user-2',
        companyId: 'company-2',
        roles: {UserRole.admin},
      );

      final state = container.read(authNotifierProvider) as AuthAuthenticated;
      expect(state.userId, equals('user-2'));
      expect(state.companyId, equals('company-2'));
      expect(state.roles, containsAll([UserRole.admin]));
      expect(state.roles, isNot(contains(UserRole.contractor)));
    });

    test('all three role types can be set', () {
      final notifier = container.read(authNotifierProvider.notifier);

      notifier.setMockUser(
        userId: 'all-roles-user',
        companyId: 'company-1',
        roles: {UserRole.admin, UserRole.contractor, UserRole.client},
      );

      final state = container.read(authNotifierProvider) as AuthAuthenticated;
      expect(state.roles, containsAll([
        UserRole.admin,
        UserRole.contractor,
        UserRole.client,
      ]));
      expect(state.roles, hasLength(3));
    });
  });
}
