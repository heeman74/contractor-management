import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../features/auth/domain/auth_state.dart';
import '../../features/auth/presentation/providers/auth_provider.dart';
import '../../shared/models/user_role.dart';
import '../../core/routing/route_names.dart';

/// Home dashboard — the landing screen after authentication.
///
/// Shows role-appropriate content hints. Content varies by role:
/// - Admin: quick links to team management and job overview
/// - Contractor: upcoming jobs and availability status
/// - Client: recent job updates and portal link
///
/// Full content implementations come in Phase 4-5.
class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final authState = ref.watch(authNotifierProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Home'),
        actions: [
          IconButton(
            icon: const Icon(Icons.logout),
            onPressed: () => ref.read(authNotifierProvider.notifier).logout(),
            tooltip: 'Sign out',
          ),
        ],
      ),
      body: switch (authState) {
        AuthAuthenticated(:final roles, :final userId) =>
          _AuthenticatedHome(roles: roles, userId: userId),
        _ => const Center(child: CircularProgressIndicator()),
      },
    );
  }
}

class _AuthenticatedHome extends StatelessWidget {
  const _AuthenticatedHome({required this.roles, required this.userId});

  final Set<UserRole> roles;
  final String userId;

  @override
  Widget build(BuildContext context) {
    final roleLabel = roles.map((r) => r.name).join(', ');

    return ListView(
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
          _SectionHeader('Admin Features'),
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
          const SizedBox(height: 16),
        ],
        if (roles.contains(UserRole.contractor)) ...[
          _SectionHeader('Contractor Features'),
          _QuickLink(
            icon: Icons.event_available_outlined,
            title: 'My Availability',
            subtitle: 'Set your working hours — coming Phase 3',
            onTap: () => context.go(RouteNames.contractorAvailability),
          ),
          const SizedBox(height: 16),
        ],
        if (roles.contains(UserRole.client)) ...[
          _SectionHeader('Client Features'),
          _QuickLink(
            icon: Icons.dashboard_outlined,
            title: 'Client Portal',
            subtitle: 'Track jobs and invoices — coming Phase 5',
            onTap: () => context.go(RouteNames.clientPortal),
          ),
          const SizedBox(height: 16),
        ],
        _SectionHeader('Coming Soon'),
        const _PlaceholderCard(
          'Phase 4: Jobs',
          'Create, assign, and track jobs with your team',
        ),
        const _PlaceholderCard(
          'Phase 5: Scheduling',
          'Smart scheduling with travel time and availability',
        ),
      ],
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

class _PlaceholderCard extends StatelessWidget {
  const _PlaceholderCard(this.title, this.subtitle);
  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      color: Colors.grey[50],
      child: ListTile(
        leading: const Icon(Icons.hourglass_empty, color: Colors.grey),
        title: Text(title, style: const TextStyle(color: Colors.grey)),
        subtitle: Text(subtitle,
            style: const TextStyle(fontSize: 12, color: Colors.grey)),
      ),
    );
  }
}
