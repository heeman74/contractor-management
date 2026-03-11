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

  /// In-app job request form -- client submits a request for admin review.
  static const jobRequestForm = '/client/request';

  // --- Schedule routes ---

  /// Contractor personal schedule — shown on the Schedule tab for contractor role.
  static const contractorSchedule = '/contractor/schedule';

  /// Schedule settings — weekly working-hour template management.
  ///
  /// Accessible from:
  ///   - Contractor's schedule screen (gear icon)
  ///   - Admin calendar via long-press on contractor lane header
  ///     (with optional contractorId query param)
  static const scheduleSettings = '/schedule/settings';

  /// Drawing pad — full-screen landscape canvas accessible from Add Note sheet.
  ///
  /// Push via: context.pushNamed(RouteNames.drawingPad)
  /// Returns: String? file path of saved PNG, or null if dismissed.
  static const drawingPad = '/drawing-pad';

  /// Timer screen — dedicated clock-in/out view for a contractor on a job.
  ///
  /// Push via: context.push(RouteNames.timerPath(jobId))
  /// Shows large HH:MM:SS display, session history, and Clock In/Out button.
  static const timer = '/timer/:jobId';

  // ─── Helpers ─────────────────────────────────────────────────────────────

  /// Build the job detail path for a specific job ID.
  static String jobDetailPath(String jobId) => '/jobs/$jobId';

  /// Build the client detail path for a specific client ID.
  static String clientDetailPath(String clientId) =>
      '/admin/clients/$clientId';

  /// Build the schedule settings path for a specific contractor (admin access).
  static String scheduleSettingsPath(String contractorId) =>
      '/schedule/settings?contractorId=$contractorId';

  /// Build the timer screen path for a specific job.
  static String timerPath(String jobId) => '/timer/$jobId';
}
