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

  /// Login screen — email + password authentication.
  static const login = '/login';

  /// Register screen — create a new company + admin account.
  static const register = '/register';

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

  // --- Job routes ---

  /// Job detail — view a single job's details, schedule, and history.
  static const jobDetail = '/jobs/:id';

  /// Job creation wizard — 4-step form to create a new job.
  static const jobNew = '/jobs/new';

  // --- Admin-only routes ---

  /// Team management — list/invite contractors and clients.
  static const adminTeam = '/admin/team';

  /// Client management — view and manage client accounts.
  static const adminClients = '/admin/clients';

  /// Client CRM — detailed client profile and job history (Plan 07).
  static const clientCrm = '/admin/clients';

  /// Client detail — individual client profile view (Plan 07).
  static const clientDetail = '/admin/clients/:id';

  /// Request review queue — admin triage incoming job requests (Plan 07).
  static const requestReview = '/admin/requests';

  // --- Contractor-only routes ---

  /// Contractor availability settings — coming in Phase 3.
  static const contractorAvailability = '/contractor/availability';

  /// Contractor job list — assigned jobs with quick-action transitions.
  static const contractorJobs = '/contractor/jobs';

  // --- Client-only routes ---

  /// Client self-service portal — view job status, invoices.
  static const clientPortal = '/client/portal';

  // ─── Helpers ─────────────────────────────────────────────────────────────

  /// Build the job detail path for a specific job ID.
  static String jobDetailPath(String jobId) => '/jobs/$jobId';

  /// Build the client detail path for a specific client ID.
  static String clientDetailPath(String clientId) =>
      '/admin/clients/$clientId';
}
