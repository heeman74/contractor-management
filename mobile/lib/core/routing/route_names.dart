/// Route path constants — avoid magic strings across navigation calls.
///
/// All navigation should use these constants rather than raw strings.
/// This ensures refactoring route paths doesn't miss any call sites.
abstract final class RouteNames {
  // --- Auth routes (no shell) ---

  /// Initial app load — shows spinner while auth state is determined.
  static const splash = '/splash';

  /// Onboarding / role selection (Phase 1 mock) — shows when unauthenticated.
  static const onboarding = '/onboarding';

  /// Shown when a user navigates to a route they don't have permission to access.
  static const unauthorized = '/unauthorized';

  // --- Shared shell routes (all authenticated roles) ---

  /// Home dashboard — visible to all roles, content filtered by role.
  static const home = '/home';

  /// Job list — coming in Phase 4.
  static const jobs = '/jobs';

  /// Schedule calendar — coming in Phase 5.
  static const schedule = '/schedule';

  /// User profile — shows current user info and roles.
  static const profile = '/profile';

  // --- Admin-only routes ---

  /// Team management — list/invite contractors and clients.
  static const adminTeam = '/admin/team';

  /// Client management — view and manage client accounts.
  static const adminClients = '/admin/clients';

  // --- Contractor-only routes ---

  /// Contractor availability settings — coming in Phase 3.
  static const contractorAvailability = '/contractor/availability';

  // --- Client-only routes ---

  /// Client self-service portal — view job status, invoices.
  static const clientPortal = '/client/portal';
}
