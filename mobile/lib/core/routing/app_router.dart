import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../features/admin/presentation/screens/client_management_screen.dart';
import '../../features/admin/presentation/screens/team_management_screen.dart';
import '../../features/auth/domain/auth_state.dart';
import '../../features/auth/presentation/providers/auth_provider.dart';
import '../../features/auth/presentation/screens/login_screen.dart';
import '../../features/auth/presentation/screens/onboarding_screen.dart';
import '../../features/auth/presentation/screens/register_screen.dart';
import '../../features/auth/presentation/screens/splash_screen.dart';
import '../../features/auth/presentation/screens/unauthorized_screen.dart';
import '../../features/client/presentation/screens/client_portal_screen.dart';
import '../../features/contractor/presentation/screens/availability_screen.dart';
import '../../shared/models/user_role.dart';
import '../../shared/screens/home_screen.dart';
import '../../shared/screens/jobs_screen.dart';
import '../../shared/screens/profile_screen.dart';
import '../../shared/screens/schedule_screen.dart';
import '../../shared/widgets/app_shell.dart';
import 'route_names.dart';

part 'app_router.g.dart';

/// GoRouter provider using the ValueNotifier bridge pattern.
///
/// CRITICAL PATTERN — prevents Router Rebuild Bug (RESEARCH.md Pitfall 4):
/// GoRouter's `refreshListenable` must NOT be the Riverpod provider itself,
/// because `ref.watch(authNotifierProvider)` inside the Provider would cause the
/// entire GoRouter to be recreated on every auth state change. This destroys
/// navigation history and causes visual glitches.
///
/// Solution: Use `ref.listen` to synchronize auth state changes into a
/// `ValueNotifier<AuthState>`. The ValueNotifier is passed as `refreshListenable`.
/// GoRouter listens to the ValueNotifier and re-runs its redirect function
/// WITHOUT rebuilding the router instance. This is the correct pattern.
///
/// Reference: go_router docs — "Listening to changes outside the router"
@riverpod
GoRouter router(Ref ref) {
  // Create the bridge ValueNotifier with the current auth state as initial value.
  // This notifier lives for the lifetime of the routerProvider.
  final authNotifier = ValueNotifier<AuthState>(
    ref.read(authNotifierProvider),
  );

  // Keep the ValueNotifier in sync with future auth state changes.
  // ref.listen does NOT rebuild the router Provider — it's a side-effect listener.
  ref.listen<AuthState>(authNotifierProvider, (_, next) {
    authNotifier.value = next;
  });

  // Dispose the ValueNotifier when the provider is disposed.
  ref.onDispose(authNotifier.dispose);

  final router = GoRouter(
    initialLocation: RouteNames.splash,
    refreshListenable: authNotifier, // <-- bridge, NOT the Riverpod provider
    debugLogDiagnostics: kDebugMode,
    redirect: (context, state) {
      final authState = authNotifier.value;
      final location = state.uri.path;

      return switch (authState) {
        // While loading: show splash
        AuthLoading() => location == RouteNames.splash
            ? null
            : RouteNames.splash,

        // Not logged in: allow onboarding, login, register screens
        AuthUnauthenticated() => (location == RouteNames.onboarding ||
                location == RouteNames.login ||
                location == RouteNames.register)
            ? null
            : RouteNames.onboarding,

        // Authenticated: redirect away from auth-only screens, then apply role guards
        AuthAuthenticated(:final roles) => (location == RouteNames.splash ||
                location == RouteNames.onboarding ||
                location == RouteNames.login ||
                location == RouteNames.register)
            ? RouteNames.home
            : _checkRoleAccess(location, roles),
      };
    },
    routes: [
      // --- Non-shell routes (no bottom nav) ---
      GoRoute(
        path: RouteNames.splash,
        builder: (context, state) => const SplashScreen(),
      ),
      GoRoute(
        path: RouteNames.onboarding,
        builder: (context, state) => const OnboardingScreen(),
      ),
      GoRoute(
        path: RouteNames.login,
        builder: (context, state) => const LoginScreen(),
      ),
      GoRoute(
        path: RouteNames.register,
        builder: (context, state) => const RegisterScreen(),
      ),
      GoRoute(
        path: RouteNames.unauthorized,
        builder: (context, state) => const UnauthorizedScreen(),
      ),

      // --- Shell routes (with bottom nav) ---
      // StatefulShellRoute preserves each tab's navigation stack independently.
      StatefulShellRoute.indexedStack(
        builder: (context, state, navigationShell) => AppShell(
          navigationShell: navigationShell,
        ),
        branches: [
          // Branch 0: Home
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: RouteNames.home,
                builder: (context, state) => const HomeScreen(),
              ),
            ],
          ),
          // Branch 1: Jobs
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: RouteNames.jobs,
                builder: (context, state) => const JobsScreen(),
              ),
            ],
          ),
          // Branch 2: Schedule
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: RouteNames.schedule,
                builder: (context, state) => const ScheduleScreen(),
              ),
            ],
          ),
          // Branch 3: Profile
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: RouteNames.profile,
                builder: (context, state) => const ProfileScreen(),
              ),
            ],
          ),
          // Branch 4: Admin - Team (includes client management as a sub-route)
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: RouteNames.adminTeam,
                builder: (context, state) => const TeamManagementScreen(),
              ),
              GoRoute(
                path: RouteNames.adminClients,
                builder: (context, state) => const ClientManagementScreen(),
              ),
            ],
          ),
          // Branch 5: Contractor - Availability
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: RouteNames.contractorAvailability,
                builder: (context, state) => const AvailabilityScreen(),
              ),
            ],
          ),
          // Branch 6: Client - Portal
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: RouteNames.clientPortal,
                builder: (context, state) => const ClientPortalScreen(),
              ),
            ],
          ),
        ],
      ),
    ],
  );

  // Dispose the GoRouter when the provider is disposed.
  ref.onDispose(router.dispose);

  return router;
}

/// Role-based access control for authenticated users.
///
/// Returns null (allow) if the user has the required role for this route,
/// or redirects to /unauthorized if they lack permission.
///
/// Routes not in any role-gated prefix are freely accessible to all
/// authenticated users (home, jobs, schedule, profile).
String? _checkRoleAccess(String location, Set<UserRole> roles) {
  // Admin-gated routes
  if (location.startsWith('/admin')) {
    if (!roles.contains(UserRole.admin)) return RouteNames.unauthorized;
  }
  // Contractor-gated routes
  else if (location.startsWith('/contractor')) {
    if (!roles.contains(UserRole.contractor)) return RouteNames.unauthorized;
  }
  // Client-gated routes
  else if (location.startsWith('/client')) {
    if (!roles.contains(UserRole.client)) return RouteNames.unauthorized;
  }

  // Allow: authenticated user accessing a non-role-gated route,
  // or accessing a role-gated route with the correct role.
  return null;
}
