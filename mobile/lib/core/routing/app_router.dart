import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/database/app_database.dart'
    show TaskAttachment;
import '../../features/admin/presentation/screens/client_crm_screen.dart';
import '../../features/admin/presentation/screens/request_review_screen.dart';
import '../../features/admin/presentation/screens/team_management_screen.dart';
import '../../features/ai/presentation/screens/intake_chat_screen.dart';
import '../../features/ai/presentation/screens/interview_chat_screen.dart';
import '../../features/auth/domain/auth_state.dart';
import '../../features/auth/presentation/providers/auth_provider.dart';
import '../../features/auth/presentation/screens/login_screen.dart';
import '../../features/auth/presentation/screens/onboarding_screen.dart';
import '../../features/auth/presentation/screens/register_screen.dart';
import '../../features/auth/presentation/screens/splash_screen.dart';
import '../../features/auth/presentation/screens/unauthorized_screen.dart';
import '../../features/chat/presentation/screens/chat_screen.dart';
import '../../features/chat/presentation/screens/chat_thread_screen.dart';
import '../../features/checklists/presentation/screens/daily_checklist_screen.dart';
import '../../features/client/presentation/screens/client_job_detail_screen.dart';
import '../../features/client/presentation/screens/client_portal_screen.dart';
import '../../features/client/presentation/screens/job_request_form_screen.dart';
import '../../features/client/presentation/screens/photo_viewer_screen.dart';
import '../../features/contractor/presentation/screens/availability_screen.dart';
import '../../features/foreman/presentation/screens/daily_status_screen.dart';
import '../../features/foreman/presentation/screens/status_history_screen.dart';
import '../../features/invoices/presentation/screens/invoice_detail_screen.dart';
import '../../features/jobs/domain/attachment_entity.dart';
import '../../features/jobs/presentation/screens/client_detail_screen.dart';
import '../../features/jobs/presentation/screens/contractor_jobs_screen.dart';
import '../../features/jobs/presentation/screens/drawing_pad_screen.dart';
import '../../features/jobs/presentation/screens/job_detail_screen.dart';
import '../../features/jobs/presentation/screens/job_wizard_screen.dart';
import '../../features/jobs/presentation/screens/jobs_pipeline_screen.dart';
import '../../features/jobs/presentation/screens/timer_screen.dart';
import '../../features/projects/presentation/screens/gantt_screen.dart';
import '../../features/projects/presentation/screens/my_tasks_screen.dart';
import '../../features/projects/presentation/screens/photo_annotation_screen.dart';
import '../../features/projects/presentation/screens/project_detail_screen.dart';
import '../../features/projects/presentation/screens/project_list_screen.dart';
import '../../features/projects/presentation/screens/task_detail_screen.dart';
import '../../features/projects/presentation/screens/task_photo_viewer_screen.dart';
import '../../features/projects/presentation/screens/trade_scope_detail_screen.dart';
import '../../features/quotes/presentation/screens/quote_builder_screen.dart';
import '../../features/quotes/presentation/screens/quote_detail_screen.dart';
import '../../features/quotes/presentation/screens/quote_preview_screen.dart';
import '../../features/reports/presentation/screens/admin_reports_screen.dart';
import '../../features/reports/presentation/screens/contractor_reports_screen.dart';
import '../../features/schedule/presentation/screens/contractor_schedule_screen.dart';
import '../../features/schedule/presentation/screens/schedule_settings_screen.dart';
import '../../shared/models/user_role.dart';
import '../../shared/screens/home_screen.dart';
import '../../shared/screens/profile_screen.dart';
import '../../shared/screens/schedule_screen.dart';
import '../../shared/widgets/app_shell.dart';
import '../di/service_locator.dart';
import '../notifications/fcm_service.dart';
import 'route_names.dart';

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
final routerProvider = Provider.autoDispose<GoRouter>((ref) {
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
      // Schedule settings — accessible via push() from both contractor and admin
      // flows (long-press on contractor lane header in admin calendar, or gear
      // icon in contractor schedule screen).
      //
      // Accepts optional `contractorId` extra param (String) from GoRouter push:
      //   context.push(RouteNames.scheduleSettings, extra: contractorId)
      // When extra is null, defaults to the current user's own schedule.
      GoRoute(
        path: RouteNames.scheduleSettings,
        builder: (context, state) {
          // Admin accessing another contractor's settings: extra contains contractorId
          final contractorId = state.extra is String
              ? state.extra as String
              : null;
          return ScheduleSettingsScreen(contractorId: contractorId);
        },
      ),
      // Drawing pad — push route accessible from Add Note bottom sheet.
      // Returns the saved PNG file path via Navigator.pop(context, filePath).
      GoRoute(
        path: RouteNames.drawingPad,
        builder: (context, state) => const DrawingPadScreen(),
      ),
      // Timer screen — dedicated clock-in/out screen for a contractor job.
      // Push via: context.push(RouteNames.timerPath(jobId))
      GoRoute(
        path: RouteNames.timer,
        builder: (context, state) {
          final jobId = state.pathParameters['jobId']!;
          return TimerScreen(jobId: jobId);
        },
      ),
      // Photo viewer — full-screen push route for viewing job progress photos.
      // Navigated to from PhotoTimeline in client job detail.
      // Accepts extra: Map<String, dynamic> with keys 'photos' and 'initialIndex'.
      GoRoute(
        path: RouteNames.photoViewer,
        builder: (context, state) {
          final extra = state.extra is Map<String, dynamic>
              ? state.extra! as Map<String, dynamic>
              : <String, dynamic>{};
          return PhotoViewerScreen(
            photos: (extra['photos'] as List?)?.cast<AttachmentEntity>() ?? [],
            initialIndex: (extra['initialIndex'] as int?) ?? 0,
          );
        },
      ),
      // Job wizard — full-screen dialog (no bottom nav, own AppBar)
      GoRoute(
        path: '${RouteNames.jobs}/new',
        pageBuilder: (context, state) => const MaterialPage(
          fullscreenDialog: true,
          child: JobWizardScreen(),
        ),
      ),
      // Invoice detail — accessible by admin (edit/finalize) and client (read-only + PDF).
      // Top-level push route (no bottom nav) — navigated to from job detail and client portal.
      GoRoute(
        path: RouteNames.invoiceDetail,
        builder: (context, state) {
          final invoiceId = state.pathParameters['invoiceId']!;
          return InvoiceDetailScreen(invoiceId: invoiceId);
        },
      ),
      // Quote builder — admin creates/edits a quote for a specific job.
      // Push via: context.push(RouteNames.quoteBuilderPath(jobId))
      // For trade-scoped quotes (Phase 25): pass extra: {'tradeScopeId': scopeId}
      GoRoute(
        path: RouteNames.quoteBuilder,
        builder: (context, state) {
          final jobId = state.pathParameters['jobId']!;
          final extra = state.extra;
          final tradeScopeId = extra is Map<String, dynamic>
              ? extra['tradeScopeId'] as String?
              : null;
          return QuoteBuilderScreen(
            jobId: jobId,
            tradeScopeId: tradeScopeId,
            existingQuote: extra is Map<String, dynamic>
                ? extra['existingQuote'] as dynamic
                : null,
          );
        },
      ),
      // Quote preview — admin sees quote as client will see it, then sends.
      // Push via: context.push(RouteNames.quotePreviewPath(jobId))
      GoRoute(
        path: RouteNames.quotePreview,
        builder: (context, state) {
          final jobId = state.pathParameters['jobId']!;
          return QuotePreviewScreen(jobId: jobId);
        },
      ),
      // Quote detail — client-facing view with approve/decline actions.
      // Push via: context.push(RouteNames.quoteDetailPath(quoteId))
      GoRoute(
        path: RouteNames.quoteDetail,
        builder: (context, state) {
          final quoteId = state.pathParameters['quoteId']!;
          return QuoteDetailScreen(quoteId: quoteId);
        },
      ),
      // Phase 21: AI intake chat — GC describes project, AI generates trade breakdown.
      // Push via: context.push(RouteNames.aiIntake)
      // Optional query param: projectId (to resume existing project intake)
      GoRoute(
        path: RouteNames.aiIntake,
        builder: (context, state) {
          final projectId = state.uri.queryParameters['projectId'];
          return IntakeChatScreen(projectId: projectId);
        },
      ),
      // Phase 21: AI interview chat — contractor answers questions, AI generates task plan.
      // Push via: context.push(RouteNames.aiInterviewPath(scopeId))
      // Optional query param: tradeName (display name in AppBar)
      GoRoute(
        path: RouteNames.aiInterview,
        builder: (context, state) {
          final scopeId = state.pathParameters['scopeId']!;
          final tradeName = state.uri.queryParameters['tradeName'];
          return InterviewChatScreen(scopeId: scopeId, tradeName: tradeName);
        },
      ),
      // Phase 22: Contractor cross-scope task checklist.
      // Push via: context.push(RouteNames.myTasks)
      GoRoute(
        path: RouteNames.myTasks,
        builder: (context, state) => const MyTasksScreen(),
      ),
      // Phase 26: AI daily checklist screen — contractor morning task list.
      // Push via: context.push(RouteNames.dailyChecklist)
      GoRoute(
        path: RouteNames.dailyChecklist,
        builder: (context, state) => const DailyChecklistScreen(),
      ),
      // Phase 22: Task detail — notes, photos, annotation, status controls.
      // Push via: context.push(RouteNames.taskDetailPath(taskId))
      GoRoute(
        path: RouteNames.taskDetail,
        builder: (context, state) {
          final taskId = state.pathParameters['taskId']!;
          return TaskDetailScreen(taskId: taskId);
        },
      ),
      // Phase 22: Task photo viewer — full-screen with annotate action.
      // Push via: context.push(RouteNames.taskPhotoViewerPath(taskId, attachmentId), extra: {...})
      GoRoute(
        path: RouteNames.taskPhotoViewer,
        builder: (context, state) {
          final taskId = state.pathParameters['taskId'] ?? '';
          final extra = state.extra is Map<String, dynamic>
              ? state.extra! as Map<String, dynamic>
              : <String, dynamic>{};
          return TaskPhotoViewerScreen(
            taskId: taskId,
            attachment: extra['attachment'] as TaskAttachment,
            allPhotos: (extra['allPhotos'] as List?)?.cast<TaskAttachment>() ?? [],
            initialIndex: (extra['initialIndex'] as int?) ?? 0,
          );
        },
      ),
      // Phase 22: Photo annotation — full-screen photo overlay with 4 tools.
      // Push via: context.push(RouteNames.photoAnnotationPath(taskId, attachmentId),
      //           extra: {'localPath': ..., 'annotationData': ...})
      // Returns: String? annotation JSON string, or null on discard.
      GoRoute(
        path: RouteNames.photoAnnotation,
        builder: (context, state) {
          final extra = state.extra as Map<String, dynamic>? ?? {};
          return PhotoAnnotationScreen(
            localPath: extra['localPath'] as String? ?? '',
            annotationData: extra['annotationData'] as String?,
          );
        },
      ),
      // Foreman daily status update — full-screen form (no bottom nav).
      // Push via: context.push(RouteNames.foremanDailyStatus)
      GoRoute(
        path: RouteNames.foremanDailyStatus,
        builder: (context, state) => const DailyStatusScreen(),
      ),
      // Foreman status history — list of past updates for a project.
      // Push via: context.push(RouteNames.foremanStatusHistoryPath(projectId))
      GoRoute(
        path: RouteNames.foremanStatusHistory,
        builder: (context, state) {
          final projectId = state.pathParameters['projectId']!;
          final projectName =
              state.extra is String ? state.extra as String : null;
          return StatusHistoryScreen(
            projectId: projectId,
            projectName: projectName,
          );
        },
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
          // Branch 1: Jobs (admin/all-role pipeline)
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: RouteNames.jobs,
                builder: (context, state) => const JobsPipelineScreen(),
                routes: [
                  // Job wizard moved to top-level route (no bottom nav)
                  GoRoute(
                    path: ':id',
                    builder: (context, state) {
                      final jobId = state.pathParameters['id']!;
                      return JobDetailScreen(jobId: jobId);
                    },
                  ),
                ],
              ),
            ],
          ),
          // Branch 2: Schedule
          // Admin → ScheduleScreen (dispatch calendar)
          // Contractor → ContractorScheduleScreen (personal schedule)
          // Role selection is done via router redirect in _checkRoleAccess.
          // The Schedule tab always navigates to RouteNames.schedule;
          // the actual screen is determined by the builder reading the auth state.
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: RouteNames.schedule,
                builder: (context, state) {
                  // Role-based screen selection.
                  // Cannot use Consumer here (GoRouter builder is not a Widget).
                  // Instead, read auth state from the container via ProviderScope.
                  // This pattern reads the provider synchronously — auth state is
                  // always available at this point (redirect ran first).
                  final container = ProviderScope.containerOf(context);
                  final authState =
                      container.read(authNotifierProvider);
                  final isContractor = authState is AuthAuthenticated &&
                      authState.roles.contains(UserRole.contractor) &&
                      !authState.roles.any((r) => r.isAdminLevel);

                  return isContractor
                      ? const ContractorScheduleScreen()
                      : const ScheduleScreen();
                },
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
          // Branch 4: Admin - Team + CRM + Requests
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: RouteNames.adminTeam,
                builder: (context, state) => const TeamManagementScreen(),
              ),
              // /admin/clients — full CRM (Plan 07 will replace ClientCrmScreen)
              GoRoute(
                path: '/admin/clients',
                builder: (context, state) => const ClientCrmScreen(),
                routes: [
                  GoRoute(
                    path: ':id',
                    builder: (context, state) {
                      final clientId = state.pathParameters['id']!;
                      return ClientDetailScreen(clientId: clientId);
                    },
                  ),
                ],
              ),
              // /admin/requests — incoming job request triage queue (Plan 07)
              GoRoute(
                path: RouteNames.requestReview,
                builder: (context, state) => const RequestReviewScreen(),
              ),
            ],
          ),
          // Branch 5: Contractor - Availability + Contractor Jobs + Schedule
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: RouteNames.contractorAvailability,
                builder: (context, state) => const AvailabilityScreen(),
              ),
              GoRoute(
                path: RouteNames.contractorJobs,
                builder: (context, state) => const ContractorJobsScreen(),
              ),
              // Contractor personal schedule (also accessible as the Schedule
              // tab for contractor role — see Branch 2 role-based selection)
              GoRoute(
                path: RouteNames.contractorSchedule,
                builder: (context, state) => const ContractorScheduleScreen(),
              ),
            ],
          ),
          // Branch 6: Client - Portal + Job Detail
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: RouteNames.clientPortal,
                builder: (context, state) => const ClientPortalScreen(),
              ),
              GoRoute(
                path: RouteNames.jobRequestForm,
                builder: (context, state) => const JobRequestFormScreen(),
              ),
              // Client-specific job detail — separate from admin /jobs/:id.
              // Navigated to from the client portal list when client taps a job card.
              GoRoute(
                path: '/client/jobs/:id',
                builder: (context, state) {
                  final jobId = state.pathParameters['id']!;
                  return ClientJobDetailScreen(jobId: jobId);
                },
              ),
            ],
          ),
          // Branch 7: Reports — admin sees full dashboard; contractor sees own stats.
          // Client role is excluded from this tab (per locked design decision).
          // Role-based screen selection mirrors the Schedule branch pattern.
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: RouteNames.reports,
                builder: (context, state) {
                  // Role-based screen selection.
                  // Redirect guarantees auth resolved before builder runs.
                  final container = ProviderScope.containerOf(context);
                  final authState = container.read(authNotifierProvider);
                  final isAdmin = authState is AuthAuthenticated &&
                      authState.roles.any((r) => r.isAdminLevel);

                  return isAdmin
                      ? const AdminReportsScreen()
                      : const ContractorReportsScreen();
                },
              ),
            ],
          ),
          // Branch 8: Projects — GC sees all projects; contractor sees assigned.
          // Client role is excluded (projects tab is for GC and contractors only).
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: RouteNames.projects,
                builder: (context, state) => const ProjectListScreen(),
                routes: [
                  GoRoute(
                    path: ':projectId',
                    builder: (context, state) {
                      final projectId = state.pathParameters['projectId']!;
                      return ProjectDetailScreen(projectId: projectId);
                    },
                    routes: [
                      GoRoute(
                        path: 'scopes/:scopeId',
                        builder: (context, state) {
                          final projectId =
                              state.pathParameters['projectId']!;
                          final scopeId = state.pathParameters['scopeId']!;
                          return TradeScopeDetailScreen(
                            projectId: projectId,
                            scopeId: scopeId,
                          );
                        },
                      ),
                      // Phase 23: Real-time chat thread list for project
                      GoRoute(
                        path: 'chat',
                        builder: (context, state) {
                          final projectId =
                              state.pathParameters['projectId']!;
                          return ChatScreen(projectId: projectId);
                        },
                        routes: [
                          // Phase 23: Individual chat thread screen
                          GoRoute(
                            path: ':threadId',
                            builder: (context, state) {
                              final projectId =
                                  state.pathParameters['projectId']!;
                              final threadId =
                                  state.pathParameters['threadId']!;
                              return ChatThreadScreen(
                                threadId: threadId,
                                projectId: projectId,
                              );
                            },
                          ),
                        ],
                      ),
                      GoRoute(
                        path: 'gantt',
                        builder: (context, state) {
                          final projectId =
                              state.pathParameters['projectId']!;
                          final projectName =
                              state.extra is String
                                  ? state.extra as String
                                  : 'Timeline';
                          return GanttScreen(
                            projectId: projectId,
                            projectName: projectName,
                          );
                        },
                      ),
                    ],
                  ),
                ],
              ),
            ],
          ),
        ],
      ),
    ],
  );

  // Wire FCM message handlers — enables deep-link navigation on notification tap.
  // Wrapped in try/catch: FcmService may not be registered in test environments.
  try {
    getIt<FcmService>().setupMessageHandlers(router);
  } catch (e) {
    // FcmService not registered (e.g., test environment without Firebase).
    // Intentional: FCM setup is non-critical for routing to function.
    debugPrint('[routerProvider] FcmService not available (non-fatal): $e');
  }

  // Dispose the GoRouter when the provider is disposed.
  ref.onDispose(router.dispose);

  return router;
});

/// Role-based access control for authenticated users.
///
/// Returns null (allow) if the user has the required role for this route,
/// or redirects to /unauthorized if they lack permission.
///
/// Routes not in any role-gated prefix are freely accessible to all
/// authenticated users (home, jobs, schedule, profile).
String? _checkRoleAccess(String location, Set<UserRole> roles) {
  // Admin-gated routes — owner satisfies admin
  if (location.startsWith('/admin')) {
    if (!roles.any((r) => r.isAdminLevel)) return RouteNames.unauthorized;
  }
  // Contractor-gated routes — open to the field roles
  else if (location.startsWith('/contractor')) {
    if (!roles.any((r) =>
        r == UserRole.contractor ||
        r == UserRole.foreman ||
        r == UserRole.worker)) {
      return RouteNames.unauthorized;
    }
  }
  // Client-gated routes
  else if (location.startsWith('/client')) {
    if (!roles.contains(UserRole.client)) return RouteNames.unauthorized;
  }
  // Foreman-gated routes — managers/GC oversee; foremen access their own
  else if (location.startsWith('/foreman')) {
    if (!roles.any((r) =>
        r.isManagerLevel || r.isGcLevel || r == UserRole.foreman)) {
      return RouteNames.unauthorized;
    }
  }

  // Allow: authenticated user accessing a non-role-gated route,
  // or accessing a role-gated route with the correct role.
  return null;
}
