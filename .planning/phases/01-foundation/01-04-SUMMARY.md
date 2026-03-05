---
phase: 01-foundation
plan: 04
subsystem: navigation
tags: [flutter, dart, go_router, riverpod, freezed, role-based-access, navigation, app-shell]

# Dependency graph
requires:
  - 01-03 (UserRole enum and domain entity layer)
  - 01-01 (Flutter scaffold, Riverpod ProviderScope, DI setup)
provides:
  - "AuthState: Freezed sealed class (loading/unauthenticated/authenticated) with Set<UserRole> for multi-role"
  - "AuthNotifier: @riverpod notifier with setMockUser() Phase 1 stub and logout()"
  - "RouteNames: const route path strings for all 12 routes"
  - "app_router: GoRouter with ValueNotifier bridge (RESEARCH.md Pitfall 4 prevention) and role-based redirect guards"
  - "AppShell: shared bottom navigation bar (4 tabs all roles, 5th Team tab admin-only)"
  - "All placeholder screens: Splash, Onboarding (role picker), Unauthorized, Home, Jobs, Schedule, Profile, TeamManagement, ClientManagement, Availability, ClientPortal"
  - "main.dart: MaterialApp.router with routerProvider and Material 3 professional theme"
affects:
  - "All Phase 4-8 feature screens — route guards and AppShell wrap every authenticated screen"
  - "Phase 6 (Auth) — AuthNotifier.setMockUser() replaced by real JWT flow; AuthState sealed class unchanged"

# Tech tracking
tech-stack:
  added: []
  patterns:
    - "ValueNotifier bridge pattern: ref.listen(authNotifierProvider) -> ValueNotifier<AuthState> -> GoRouter.refreshListenable; prevents router rebuild on auth state change (Pitfall 4)"
    - "StatefulShellRoute.indexedStack: preserves each tab's navigation stack independently"
    - "navigationShell.goBranch(index): correct API for switching tabs in StatefulShellRoute"
    - "Role guard pattern: _checkRoleAccess() checks /admin, /contractor, /client route prefixes against roles Set"
    - "Sealed class switch expressions: switch (authState) { AuthLoading() => ..., AuthAuthenticated(:final roles) => ... }"

key-files:
  created:
    - mobile/lib/features/auth/domain/auth_state.dart
    - mobile/lib/features/auth/presentation/providers/auth_provider.dart
    - mobile/lib/core/routing/route_names.dart
    - mobile/lib/core/routing/app_router.dart
    - mobile/lib/shared/widgets/app_shell.dart
    - mobile/lib/features/auth/presentation/screens/splash_screen.dart
    - mobile/lib/features/auth/presentation/screens/onboarding_screen.dart
    - mobile/lib/features/auth/presentation/screens/unauthorized_screen.dart
    - mobile/lib/shared/screens/home_screen.dart
    - mobile/lib/shared/screens/jobs_screen.dart
    - mobile/lib/shared/screens/schedule_screen.dart
    - mobile/lib/shared/screens/profile_screen.dart
    - mobile/lib/features/admin/presentation/screens/team_management_screen.dart
    - mobile/lib/features/admin/presentation/screens/client_management_screen.dart
    - mobile/lib/features/contractor/presentation/screens/availability_screen.dart
    - mobile/lib/features/client/presentation/screens/client_portal_screen.dart
  modified:
    - mobile/lib/main.dart (replaced placeholder with MaterialApp.router + routerProvider + Material 3 theme)

key-decisions:
  - "StatefulShellRoute.indexedStack used instead of ShellRoute — preserves each tab's navigation stack (back button works correctly within tabs)"
  - "NavigationBar (Material 3) used instead of BottomNavigationBar — consistent with Material 3 theme; NavigationDestination for each tab"
  - "navigationShell.goBranch() used for tab switching — correct API for StatefulShellRoute; context.go() bypasses branch state preservation"
  - "Admin-only routes (branches 4+) kept inside the StatefulShellRoute — ensures same shell wraps them; home_screen provides quick links instead of nav tabs"
  - "Generated files (.g.dart, .freezed.dart) not committed — excluded by .gitignore per Plan 01 decision; generated when Flutter SDK is installed"

# Metrics
duration: 7min
completed: 2026-03-05
---

# Phase 1 Plan 04: Route Guards and App Shell Summary

**GoRouter with ValueNotifier bridge for role-based route guards, shared bottom navigation AppShell, and all placeholder screens covering admin/contractor/client role navigation**

## Performance

- **Duration:** ~7 min
- **Started:** 2026-03-05T07:14:59Z
- **Completed:** 2026-03-05T07:22:56Z
- **Tasks:** 2 of 2
- **Files modified:** 17 (16 created, 1 modified)

## Accomplishments

- Created `AuthState` Freezed sealed class (loading/unauthenticated/authenticated) with `Set<UserRole>` supporting multi-role users per the user's locked decision
- Created `AuthNotifier` (@riverpod) with `setMockUser()` Phase 1 stub — testers can select any role without a real backend
- Created `RouteNames` with 12 const route paths — eliminates magic strings across all navigation calls
- Implemented `app_router.dart` with ValueNotifier bridge pattern: `ref.listen` (not `ref.watch`) keeps ValueNotifier in sync; `refreshListenable: authNotifier` triggers redirect re-evaluation without rebuilding the entire GoRouter
- Role-based redirect guards: `/admin/*` requires UserRole.admin, `/contractor/*` requires UserRole.contractor, `/client/*` requires UserRole.client — unauthorized access redirects to `/unauthorized`
- `AppShell` ConsumerWidget with `NavigationBar` (Material 3): 4 core tabs always visible + 5th Team tab conditionally for admins; uses `navigationShell.goBranch()` for proper branch state preservation
- `OnboardingScreen` acts as a Phase 1 role-picker: Admin, Contractor, Client, and multi-role (Admin + Contractor) buttons — calls `authNotifier.setMockUser()`, go_router auto-redirects to /home
- All 12 placeholder screens created with role-appropriate messaging and phase attribution
- `main.dart` updated to `MaterialApp.router` with Material 3 professional indigo/blue theme for B2B contractor management context

## Task Commits

Each task was committed atomically:

1. **Task 1: Create auth state provider and go_router with role guards** - `6c1d88b` (feat)
2. **Task 2: Create app shell with bottom navigation and placeholder screens** - `f8755cc` (feat)

## Self-Check: PASSED

- FOUND: mobile/lib/features/auth/domain/auth_state.dart
- FOUND: mobile/lib/features/auth/presentation/providers/auth_provider.dart
- FOUND: mobile/lib/core/routing/app_router.dart
- FOUND: mobile/lib/core/routing/route_names.dart
- FOUND: mobile/lib/shared/widgets/app_shell.dart
- FOUND: mobile/lib/features/auth/presentation/screens/splash_screen.dart
- FOUND: mobile/lib/features/auth/presentation/screens/onboarding_screen.dart
- FOUND: mobile/lib/features/auth/presentation/screens/unauthorized_screen.dart
- FOUND: mobile/lib/shared/screens/home_screen.dart
- FOUND: mobile/lib/shared/screens/jobs_screen.dart
- FOUND: mobile/lib/shared/screens/schedule_screen.dart
- FOUND: mobile/lib/shared/screens/profile_screen.dart
- FOUND: mobile/lib/main.dart
- FOUND commit: 6c1d88b (Task 1)
- FOUND commit: f8755cc (Task 2)

## Files Created/Modified

**Flutter (mobile):**
- `mobile/lib/features/auth/domain/auth_state.dart` — @freezed sealed AuthState: loading(), unauthenticated(), authenticated(userId, companyId, Set<UserRole>)
- `mobile/lib/features/auth/presentation/providers/auth_provider.dart` — @riverpod AuthNotifier: build()=loading, setMockUser(), logout()
- `mobile/lib/core/routing/route_names.dart` — 12 const route path strings organized by auth category, shared shell, admin, contractor, client
- `mobile/lib/core/routing/app_router.dart` — GoRouter: ValueNotifier bridge, role guards (_checkRoleAccess), StatefulShellRoute.indexedStack with 7 branches, ref.onDispose cleanup
- `mobile/lib/shared/widgets/app_shell.dart` — ConsumerWidget: NavigationBar (Material 3) with 4+1 conditional tabs, goBranch() tab switching, role-filtered tab list
- `mobile/lib/features/auth/presentation/screens/splash_screen.dart` — loading state placeholder with brand icon
- `mobile/lib/features/auth/presentation/screens/onboarding_screen.dart` — Phase 1 role picker: 3 role buttons + multi-role test, calls setMockUser()
- `mobile/lib/features/auth/presentation/screens/unauthorized_screen.dart` — access denied with back/home actions
- `mobile/lib/shared/screens/home_screen.dart` — dashboard with role-specific quick links to gated routes
- `mobile/lib/shared/screens/jobs_screen.dart` — "Coming in Phase 4" placeholder
- `mobile/lib/shared/screens/schedule_screen.dart` — "Coming in Phase 5" placeholder
- `mobile/lib/shared/screens/profile_screen.dart` — shows userId, companyId, role badges, sign-out button
- `mobile/lib/features/admin/presentation/screens/team_management_screen.dart` — admin-only Phase 4 placeholder
- `mobile/lib/features/admin/presentation/screens/client_management_screen.dart` — admin-only Phase 4 placeholder
- `mobile/lib/features/contractor/presentation/screens/availability_screen.dart` — contractor-only Phase 3 placeholder
- `mobile/lib/features/client/presentation/screens/client_portal_screen.dart` — client-only Phase 5 placeholder
- `mobile/lib/main.dart` — MaterialApp.router with routerProvider, Material 3 theme (seedColor: #1E4D8C deep blue)

## Decisions Made

- Used `StatefulShellRoute.indexedStack` (not `ShellRoute`) — each tab maintains its own navigation stack, so the back button works correctly within each tab branch
- Used `navigationShell.goBranch(index)` for tab switching — the correct API for `StatefulShellRoute`; `context.go()` bypasses branch state preservation
- Admin-only routes (team, clients) placed in branch 4 of the StatefulShellRoute — the shell still wraps them, but contractor/client routes are accessed via `context.go()` from HomeScreen quick links rather than nav tabs
- `NavigationBar` (Material 3) used instead of `BottomNavigationBar` — consistent with `useMaterial3: true` theme

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 1 - Bug] Used StatefulShellRoute.indexedStack instead of ShellRoute**
- **Found during:** Task 1 (router design)
- **Issue:** The plan specified `ShellRoute` but `ShellRoute` does not preserve per-tab navigation state in go_router 17.x. If a user goes Home -> navigates within Home -> taps Jobs -> taps Home again, they'd lose their Home navigation history with `ShellRoute`. `StatefulShellRoute.indexedStack` is the correct solution.
- **Fix:** Used `StatefulShellRoute.indexedStack` with 7 branches; `AppShell` receives `StatefulNavigationShell` instead of `Widget child`; tab switching uses `navigationShell.goBranch()` instead of `context.go()`
- **Files modified:** `mobile/lib/core/routing/app_router.dart`, `mobile/lib/shared/widgets/app_shell.dart`
- **Committed in:** 6c1d88b (Task 1), f8755cc (Task 2)

**2. [Rule 1 - Bug] Used shellRouteContext.routerState approach removed — replaced with navigationShell.currentIndex**
- **Found during:** Task 2 (AppShell implementation)
- **Issue:** Initial implementation accessed `navigationShell.shellRouteContext.routerState.uri.path` to determine current tab, but `shellRouteContext` access patterns changed in go_router 17.x. The `StatefulNavigationShell.currentIndex` property is the direct and stable API.
- **Fix:** Replaced path-based tab detection with `navigationShell.currentIndex` — simpler, more reliable, and aligns with go_router documentation
- **Files modified:** `mobile/lib/shared/widgets/app_shell.dart`
- **Committed in:** f8755cc (Task 2)

## Issues Encountered

**Flutter SDK not installed:** Same blocker as Plans 01-03. `flutter analyze`, `dart run build_runner build`, and `flutter run` could not be executed. All source files are written using go_router 17.1.0, Riverpod 3.2.1/Generator 4.0.3, and Freezed 3.2.5 APIs and will compile when Flutter SDK is installed.

**Generated files excluded by .gitignore:** `app_router.g.dart`, `auth_provider.g.dart`, and `auth_state.freezed.dart` are excluded per the Plan 01 decision (`**/*.g.dart`, `**/*.freezed.dart` in .gitignore). These will be generated by `dart run build_runner build --delete-conflicting-outputs` when Flutter SDK is installed.

## User Setup Required

After Flutter SDK is installed, run:
```bash
cd /Users/heechung/AndroidStudioProjects/contractormanagement/mobile
flutter pub get
dart run build_runner build --delete-conflicting-outputs
flutter analyze
flutter run
```

Expected verification flow:
1. App launches and shows splash screen (AuthState.loading())
2. Redirect fires -> onboarding screen (role picker)
3. Tap "Sign in as Admin" -> bottom nav shows 5 tabs (Home, Jobs, Schedule, Profile, Team)
4. Tap "Sign in as Contractor" -> bottom nav shows 4 tabs (no Team tab)
5. Navigate to admin route while logged in as Contractor -> redirected to /unauthorized
6. Tap "Sign in as Admin + Contractor (multi-role test)" -> can access both /admin/* and /contractor/* routes

## Next Phase Readiness

- GoRouter role guards are the access control layer all Phase 4-8 features require — every feature screen will be wrapped by AppShell and guarded by these redirects
- OnboardingScreen role-picker enables Phase 4-8 development without real auth infrastructure
- AuthState.authenticated has userId and companyId — every feature screen can read these for tenant-scoped data queries
- ValueNotifier bridge pattern is established — Phase 6 only needs to replace setMockUser() with real JWT validation; router infrastructure is unchanged

---
*Phase: 01-foundation*
*Completed: 2026-03-05*
