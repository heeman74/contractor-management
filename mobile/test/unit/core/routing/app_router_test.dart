/// Unit tests for go_router role guard redirect behavior.
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
///   Each test creates a ProviderScope with an override for authNotifierProvider
///   to control the auth state. The GoRouter is created from routerProvider,
///   and navigation is tested by reading the current route location.
///
/// NOTE: Uses pump() instead of pumpAndSettle() because screens with
/// animations (SplashScreen spinner, etc.) never settle.
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
/// The [authState] controls the auth state seen by the router.
Widget _buildTestApp(AuthState authState) {
  return ProviderScope(
    overrides: [
      authNotifierProvider.overrideWith(() => _StubAuthNotifier(authState)),
    ],
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

/// Stub AuthNotifier — returns fixed state, no external dependencies.
class _StubAuthNotifier extends AuthNotifier {
  _StubAuthNotifier(this._fixedState);

  final AuthState _fixedState;

  @override
  AuthState build() => _fixedState;
}

/// Get the GoRouter instance from the provider container.
///
/// Uses ProviderScope.containerOf to read the router directly, avoiding
/// the "No GoRouter found in context" error that occurs when using
/// GoRouter.of() with a MaterialApp-level context.
GoRouter _getRouter(WidgetTester tester) {
  final element = tester.element(find.byType(MaterialApp));
  final container = ProviderScope.containerOf(element);
  return container.read(routerProvider);
}

/// Read the current route location from the GoRouter instance.
String _routerLocation(WidgetTester tester) {
  final router = _getRouter(tester);
  return router.routeInformationProvider.value.uri.path;
}

/// Pump enough frames for GoRouter redirect to complete.
///
/// GoRouter redirects happen asynchronously — a single pump() processes
/// the redirect, a second pump() lets the new route's widget build.
Future<void> _pumpRoute(WidgetTester tester) async {
  await tester.pump();
  await tester.pump();
  await tester.pump();
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

void main() {
  group('AppRouter role guard redirect behavior', () {
    testWidgets('loading state redirects to /splash', (tester) async {
      await tester.pumpWidget(
        _buildTestApp(const AuthState.loading()),
      );
      await _pumpRoute(tester);

      expect(_routerLocation(tester), equals(RouteNames.splash));
    });

    testWidgets('unauthenticated user is redirected to /onboarding', (tester) async {
      await tester.pumpWidget(
        _buildTestApp(const AuthState.unauthenticated()),
      );
      await _pumpRoute(tester);

      expect(_routerLocation(tester), equals(RouteNames.onboarding));
    });

    testWidgets('admin role can access /admin/team (no redirect)', (tester) async {
      await tester.pumpWidget(
        _buildTestApp(const AuthState.authenticated(
          userId: 'admin-user',
          companyId: 'company-1',
          roles: {UserRole.admin},
        )),
      );
      await _pumpRoute(tester);

      // Navigate to admin/team
      _getRouter(tester).go(RouteNames.adminTeam);
      await _pumpRoute(tester);

      expect(_routerLocation(tester), equals(RouteNames.adminTeam));
    });

    testWidgets('contractor role accessing /admin/team is redirected to /unauthorized',
        (tester) async {
      await tester.pumpWidget(
        _buildTestApp(const AuthState.authenticated(
          userId: 'contractor-user',
          companyId: 'company-1',
          roles: {UserRole.contractor},
        )),
      );
      await _pumpRoute(tester);

      // Navigate to admin/team as contractor
      _getRouter(tester).go(RouteNames.adminTeam);
      await _pumpRoute(tester);

      expect(_routerLocation(tester), equals(RouteNames.unauthorized));
    });

    testWidgets(
        'client role accessing /contractor/availability is redirected to /unauthorized',
        (tester) async {
      await tester.pumpWidget(
        _buildTestApp(const AuthState.authenticated(
          userId: 'client-user',
          companyId: 'company-1',
          roles: {UserRole.client},
        )),
      );
      await _pumpRoute(tester);

      // Navigate to contractor/availability as client
      _getRouter(tester).go(RouteNames.contractorAvailability);
      await _pumpRoute(tester);

      expect(_routerLocation(tester), equals(RouteNames.unauthorized));
    });

    testWidgets(
        'user with admin and contractor roles can access /admin/team', (tester) async {
      await tester.pumpWidget(
        _buildTestApp(const AuthState.authenticated(
          userId: 'multi-role-user',
          companyId: 'company-1',
          roles: {UserRole.admin, UserRole.contractor},
        )),
      );
      await _pumpRoute(tester);

      // Navigate to admin/team — should succeed
      _getRouter(tester).go(RouteNames.adminTeam);
      await _pumpRoute(tester);

      expect(_routerLocation(tester), equals(RouteNames.adminTeam));
    });

    testWidgets(
        'user with admin and contractor roles can access /contractor/availability',
        (tester) async {
      await tester.pumpWidget(
        _buildTestApp(const AuthState.authenticated(
          userId: 'multi-role-user',
          companyId: 'company-1',
          roles: {UserRole.admin, UserRole.contractor},
        )),
      );
      await _pumpRoute(tester);

      // Navigate to contractor/availability — should succeed
      _getRouter(tester).go(RouteNames.contractorAvailability);
      await _pumpRoute(tester);

      expect(_routerLocation(tester), equals(RouteNames.contractorAvailability));
    });

    testWidgets('admin can navigate to home (shared route)', (tester) async {
      await tester.pumpWidget(
        _buildTestApp(const AuthState.authenticated(
          userId: 'admin-user',
          companyId: 'company-1',
          roles: {UserRole.admin},
        )),
      );
      await _pumpRoute(tester);

      _getRouter(tester).go(RouteNames.home);
      await _pumpRoute(tester);

      expect(_routerLocation(tester), equals(RouteNames.home));
    });
  });
}
