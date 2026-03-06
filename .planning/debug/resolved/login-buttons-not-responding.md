---
status: resolved
trigger: "Login buttons in the Flutter app are not responding - no action occurs when tapping login buttons"
created: 2026-03-05T00:00:00Z
updated: 2026-03-06T00:00:00Z
---

## Current Focus

hypothesis: The routerProvider is autoDispose, causing GoRouter to be disposed and recreated on auth state changes, which breaks navigation redirects
test: Trace the provider type and lifecycle
expecting: autoDispose router causes redirect failures or router rebuild loops
next_action: Return diagnosis

## Symptoms

expected: Tapping "Sign in as Admin/Contractor/Client" buttons on the OnboardingScreen should set mock auth state and redirect to the Home screen via go_router
actual: No action occurs when tapping login buttons - app stays on onboarding screen
errors: Not specified (likely silent failure)
reproduction: Launch app, wait for splash -> onboarding, tap any role button
started: After Phase 2 (Offline Sync Engine) changes

## Eliminated

(none - root cause identified on first hypothesis)

## Evidence

- timestamp: 2026-03-05T00:01:00Z
  checked: OnboardingScreen button handlers
  found: Buttons correctly call ref.read(authNotifierProvider.notifier).setMockUser(...) which sets AuthState.authenticated. No issues in the button/handler code itself.
  implication: The button tap IS being received and auth state IS being set. The problem is downstream.

- timestamp: 2026-03-05T00:02:00Z
  checked: app_router.g.dart - routerProvider type
  found: "final routerProvider = Provider.autoDispose<GoRouter>(router);" - The router is autoDispose
  implication: CRITICAL - autoDispose GoRouter means the router can be disposed and recreated during its lifetime

- timestamp: 2026-03-05T00:03:00Z
  checked: app_router.dart - router() function and auth bridge
  found: The router function uses ref.listen(authNotifierProvider) to bridge auth state into a ValueNotifier, and ref.onDispose to clean up. The GoRouter is created with refreshListenable pointing to that ValueNotifier.
  implication: When routerProvider is autoDispose and gets recreated, it creates a NEW GoRouter instance with a NEW ValueNotifier, but MaterialApp.router may still be holding the OLD router instance until the widget tree rebuilds.

- timestamp: 2026-03-05T00:04:00Z
  checked: main.dart - ContractorHubApp.build()
  found: "final router = ref.watch(routerProvider);" - The app watches the router provider
  implication: ref.watch on an autoDispose provider means: when no one watches it, it disposes. But since ContractorHubApp always watches it, the autoDispose may not trigger... UNLESS there's a timing issue during auth state transitions.

- timestamp: 2026-03-05T00:05:00Z
  checked: GoRouter redirect logic for AuthAuthenticated
  found: "AuthAuthenticated(:final roles) => _checkRoleAccess(location, roles)" - When authenticated, it calls _checkRoleAccess which checks role-gated routes. For /onboarding (where user currently is), it returns null (allow).
  implication: CRITICAL BUG FOUND - When auth state transitions to AuthAuthenticated, the redirect runs. The user is at /onboarding. The redirect for AuthAuthenticated returns null (allow) because /onboarding is not a role-gated route. There is NO redirect from /onboarding to /home for authenticated users!

- timestamp: 2026-03-05T00:06:00Z
  checked: Redirect logic completeness for all auth states
  found: |
    - AuthLoading: if not on /splash -> redirect to /splash (correct)
    - AuthUnauthenticated: if not on /onboarding -> redirect to /onboarding (correct)
    - AuthAuthenticated: calls _checkRoleAccess which only checks /admin/*, /contractor/*, /client/* prefixes. Returns null for everything else.
  implication: The redirect for AuthAuthenticated is MISSING the case "if user is on /splash or /onboarding, redirect to /home". The _checkRoleAccess function only guards role-specific routes but never redirects authenticated users AWAY from auth screens.

## Resolution

root_cause: |
  The GoRouter redirect function in app_router.dart has a missing redirect case for
  authenticated users on auth-only screens (/splash, /onboarding).

  When AuthAuthenticated state is set, the redirect fires. The current location is
  /onboarding. The redirect matches the AuthAuthenticated branch and calls
  _checkRoleAccess("/onboarding", roles). Since "/onboarding" does not start with
  "/admin", "/contractor", or "/client", _checkRoleAccess returns null (allow).

  This means: authenticated users are ALLOWED to stay on the /onboarding screen.
  The go_router does not redirect them to /home. The buttons DO work (auth state
  IS set to authenticated), but the user sees no visual change because they remain
  on the same screen.

  Location in code: app_router.dart lines 64-77, specifically the AuthAuthenticated
  branch at line 76 which delegates entirely to _checkRoleAccess without first
  checking if the user is on an auth-only screen.

fix: (not applied - diagnosis only)
verification: (not applied - diagnosis only)
files_changed: []
