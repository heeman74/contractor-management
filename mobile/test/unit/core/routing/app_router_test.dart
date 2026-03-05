/// Unit tests for go_router role guard behavior.
///
/// Tests verify:
/// - Unauthenticated user is redirected to /onboarding
/// - Loading state redirects to /splash
/// - Admin role can access /admin/team (no redirect)
/// - Contractor role accessing /admin/team is redirected to /unauthorized
/// - Client role accessing /contractor/availability is redirected to /unauthorized
/// - User with both admin and contractor roles can access both /admin/team
///   and /contractor/availability
///
/// Pattern:
///   Each test creates a ProviderContainer with an override for authNotifierProvider
///   to control the auth state. The GoRouter is created from routerProvider,
///   and navigation is tested by reading the current route location.
///
/// NOTE: Requires Flutter SDK + build_runner to generate:
/// - auth_state.freezed.dart
/// - auth_provider.g.dart
/// - app_router.g.dart
///
/// Also requires: go_router, flutter_riverpod, riverpod_annotation packages.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import 'package:contractorhub/core/routing/app_router.dart';
import 'package:contractorhub/core/routing/route_names.dart';
import 'package:contractorhub/features/auth/domain/auth_state.dart';
import 'package:contractorhub/features/auth/presentation/providers/auth_provider.dart';
import 'package:contractorhub/shared/models/user_role.dart';

// ---------------------------------------------------------------------------
// Test helpers
// ---------------------------------------------------------------------------

/// Build a minimal test app that uses the real routerProvider from the container.
///
/// The [overrides] control the auth state seen by the router.
Widget _buildTestApp(List<Override> overrides) {
  return ProviderScope(
    overrides: overrides,
    child: const _TestApp(),
  );
}

class _TestApp extends ConsumerWidget {
  const _TestApp();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final router = ref.watch(routerProvider);
    return MaterialApp.router(routerConfig: router);
  }
}

/// Override authNotifierProvider to return a fixed AuthState.
///
/// Replaces the real AuthNotifier with a stub that immediately returns [state].
Override _authOverride(AuthState state) {
  return authNotifierProvider.overrideWith(() => _StubAuthNotifier(state));
}

/// Stub AuthNotifier — returns fixed state, no external dependencies.
class _StubAuthNotifier extends AuthNotifier {
  _StubAuthNotifier(this._fixedState);

  final AuthState _fixedState;

  @override
  AuthState build() => _fixedState;
}

/// Extract the current location from GoRouter after widget pump.
String _routerLocation(WidgetTester tester) {
  final element = tester.element(find.byType(Router<Object>).first);
  final router = Router.of(element);
  final routeInformationProvider = router.routeInformationProvider;
  return routeInformationProvider?.value.uri.path ?? '';
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

void main() {
  group('AppRouter role guard redirect behavior', () {
    testWidgets('loading state redirects to /splash', (tester) async {
      await tester.pumpWidget(
        _buildTestApp([_authOverride(const AuthState.loading())]),
      );
      await tester.pumpAndSettle();

      expect(_routerLocation(tester), equals(RouteNames.splash));
    });

    testWidgets('unauthenticated user is redirected to /onboarding', (tester) async {
      await tester.pumpWidget(
        _buildTestApp([_authOverride(const AuthState.unauthenticated())]),
      );
      await tester.pumpAndSettle();

      expect(_routerLocation(tester), equals(RouteNames.onboarding));
    });

    testWidgets('admin role can access /admin/team (no redirect)', (tester) async {
      await tester.pumpWidget(
        _buildTestApp([
          _authOverride(const AuthState.authenticated(
            userId: 'admin-user',
            companyId: 'company-1',
            roles: {UserRole.admin},
          )),
        ]),
      );
      await tester.pumpAndSettle();

      // Navigate to admin/team
      final context = tester.element(find.byType(MaterialApp));
      GoRouter.of(context).go(RouteNames.adminTeam);
      await tester.pumpAndSettle();

      expect(_routerLocation(tester), equals(RouteNames.adminTeam));
    });

    testWidgets('contractor role accessing /admin/team is redirected to /unauthorized',
        (tester) async {
      await tester.pumpWidget(
        _buildTestApp([
          _authOverride(const AuthState.authenticated(
            userId: 'contractor-user',
            companyId: 'company-1',
            roles: {UserRole.contractor},
          )),
        ]),
      );
      await tester.pumpAndSettle();

      // Navigate to admin/team as contractor
      final context = tester.element(find.byType(MaterialApp));
      GoRouter.of(context).go(RouteNames.adminTeam);
      await tester.pumpAndSettle();

      expect(_routerLocation(tester), equals(RouteNames.unauthorized));
    });

    testWidgets(
        'client role accessing /contractor/availability is redirected to /unauthorized',
        (tester) async {
      await tester.pumpWidget(
        _buildTestApp([
          _authOverride(const AuthState.authenticated(
            userId: 'client-user',
            companyId: 'company-1',
            roles: {UserRole.client},
          )),
        ]),
      );
      await tester.pumpAndSettle();

      // Navigate to contractor/availability as client
      final context = tester.element(find.byType(MaterialApp));
      GoRouter.of(context).go(RouteNames.contractorAvailability);
      await tester.pumpAndSettle();

      expect(_routerLocation(tester), equals(RouteNames.unauthorized));
    });

    testWidgets(
        'user with admin and contractor roles can access /admin/team', (tester) async {
      await tester.pumpWidget(
        _buildTestApp([
          _authOverride(const AuthState.authenticated(
            userId: 'multi-role-user',
            companyId: 'company-1',
            roles: {UserRole.admin, UserRole.contractor},
          )),
        ]),
      );
      await tester.pumpAndSettle();

      // Navigate to admin/team — should succeed
      final context = tester.element(find.byType(MaterialApp));
      GoRouter.of(context).go(RouteNames.adminTeam);
      await tester.pumpAndSettle();

      expect(_routerLocation(tester), equals(RouteNames.adminTeam));
    });

    testWidgets(
        'user with admin and contractor roles can access /contractor/availability',
        (tester) async {
      await tester.pumpWidget(
        _buildTestApp([
          _authOverride(const AuthState.authenticated(
            userId: 'multi-role-user',
            companyId: 'company-1',
            roles: {UserRole.admin, UserRole.contractor},
          )),
        ]),
      );
      await tester.pumpAndSettle();

      // Navigate to contractor/availability — should succeed
      final context = tester.element(find.byType(MaterialApp));
      GoRouter.of(context).go(RouteNames.contractorAvailability);
      await tester.pumpAndSettle();

      expect(_routerLocation(tester), equals(RouteNames.contractorAvailability));
    });

    testWidgets('admin can navigate to home (shared route)', (tester) async {
      await tester.pumpWidget(
        _buildTestApp([
          _authOverride(const AuthState.authenticated(
            userId: 'admin-user',
            companyId: 'company-1',
            roles: {UserRole.admin},
          )),
        ]),
      );
      await tester.pumpAndSettle();

      final context = tester.element(find.byType(MaterialApp));
      GoRouter.of(context).go(RouteNames.home);
      await tester.pumpAndSettle();

      expect(_routerLocation(tester), equals(RouteNames.home));
    });
  });
}
