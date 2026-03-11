import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/di/service_locator.dart';
import '../../core/routing/route_names.dart';
import '../../core/sync/sync_engine.dart';
import '../../features/auth/domain/auth_state.dart';
import '../../features/auth/presentation/providers/auth_provider.dart';
import '../../shared/models/user_role.dart';

/// Home dashboard — the landing screen after authentication.
///
/// Shows role-appropriate content hints. Content varies by role:
/// - Admin: quick links to team management and job overview
/// - Contractor: upcoming jobs and availability status
/// - Client: recent job updates and portal link
///
/// Content is fully implemented across all phases.
///
/// Pull-to-refresh: swipe down to trigger [SyncEngine.syncNow] — pushes pending
/// local mutations then pulls remote changes. Content updates automatically via
/// Drift reactive streams.
class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final authState = ref.watch(authNotifierProvider);

    // AppBar is provided by AppShell — no Scaffold/AppBar here.
    // The shell shows the tab title ("Home") and SyncStatusSubtitle.
    return switch (authState) {
      AuthAuthenticated(:final roles, :final userId) =>
        _AuthenticatedHome(roles: roles, userId: userId),
      _ => const Center(child: CircularProgressIndicator()),
    };
  }
}

class _AuthenticatedHome extends StatelessWidget {
  const _AuthenticatedHome({required this.roles, required this.userId});

  final Set<UserRole> roles;
  final String userId;

  @override
  Widget build(BuildContext context) {
    final roleLabel = roles.map((r) => r.name).join(', ');

    // RefreshIndicator requires a scrollable child to detect the pull gesture.
    // ListView is already scrollable, so no additional wrapper is needed.
    return RefreshIndicator(
      onRefresh: () async {
        final syncEngine = getIt<SyncEngine>();
        await syncEngine.syncNow();
      },
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Card(
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Welcome back!',
                    style: Theme.of(context).textTheme.headlineSmall,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Signed in as: $roleLabel',
                    style: TextStyle(color: Colors.grey[600]),
                  ),
                  Text(
                    'User ID: $userId',
                    style: TextStyle(
                      color: Colors.grey[500],
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          if (roles.contains(UserRole.admin)) ...[
            const _SectionHeader('Admin Features'),
            _QuickLink(
              icon: Icons.groups_outlined,
              title: 'Team Management',
              subtitle: 'Manage contractors and staff',
              onTap: () => context.go(RouteNames.adminTeam),
            ),
            _QuickLink(
              icon: Icons.business_outlined,
              title: 'Client Management',
              subtitle: 'View and manage clients',
              onTap: () => context.go(RouteNames.adminClients),
            ),
            _QuickLink(
              icon: Icons.work_outline,
              title: 'Jobs Pipeline',
              subtitle: 'Create, assign, and track jobs',
              onTap: () => context.go(RouteNames.jobs),
            ),
            _QuickLink(
              icon: Icons.calendar_month_outlined,
              title: 'Schedule',
              subtitle: 'Dispatch calendar and contractor lanes',
              onTap: () => context.go(RouteNames.schedule),
            ),
            const SizedBox(height: 16),
          ],
          if (roles.contains(UserRole.contractor)) ...[
            const _SectionHeader('Contractor Features'),
            _QuickLink(
              icon: Icons.work_outline,
              title: 'My Jobs',
              subtitle: 'View assigned jobs and update status',
              onTap: () => context.go(RouteNames.contractorJobs),
            ),
            _QuickLink(
              icon: Icons.calendar_today_outlined,
              title: 'My Schedule',
              subtitle: 'View your upcoming schedule',
              onTap: () => context.go(RouteNames.contractorSchedule),
            ),
            _QuickLink(
              icon: Icons.event_available_outlined,
              title: 'Availability',
              subtitle: 'Set your working hours',
              onTap: () => context.go(RouteNames.contractorAvailability),
            ),
            const SizedBox(height: 16),
          ],
          if (roles.contains(UserRole.client)) ...[
            const _SectionHeader('Client Features'),
            _QuickLink(
              icon: Icons.dashboard_outlined,
              title: 'Client Portal',
              subtitle: 'Track your jobs and submit requests',
              onTap: () => context.go(RouteNames.clientPortal),
            ),
            const SizedBox(height: 16),
          ],
        ],
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader(this.title);
  final String title;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8, left: 4),
      child: Text(
        title,
        style: Theme.of(context).textTheme.titleSmall?.copyWith(
              color: Colors.grey[600],
              letterSpacing: 0.5,
            ),
      ),
    );
  }
}

class _QuickLink extends StatelessWidget {
  const _QuickLink({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        leading: Icon(icon, color: Theme.of(context).colorScheme.primary),
        title: Text(title),
        subtitle: Text(subtitle, style: const TextStyle(fontSize: 12)),
        trailing: const Icon(Icons.chevron_right),
        onTap: onTap,
      ),
    );
  }
}

