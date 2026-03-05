import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../features/auth/domain/auth_state.dart';
import '../../features/auth/presentation/providers/auth_provider.dart';
import '../../shared/models/user_role.dart';
import '../../core/routing/route_names.dart';

/// Shared app shell — wraps all authenticated routes with a bottom navigation bar.
///
/// This is the core of the "one unified app with different views" user requirement:
/// all roles see the same shell and the same core tabs (Home, Jobs, Schedule, Profile).
/// The only difference is the admin role gets an additional "Team" tab.
///
/// Used as the [builder] for the ShellRoute in app_router.dart. The [child] parameter
/// is the currently active route widget, rendered in the body.
///
/// Tab visibility by role:
/// - Home:     all roles
/// - Jobs:     all roles
/// - Schedule: all roles
/// - Profile:  all roles
/// - Team:     admin only (5th tab, shown only when user has UserRole.admin)
class AppShell extends ConsumerWidget {
  const AppShell({super.key, required this.navigationShell});

  /// The navigation shell provided by go_router's StatefulShellRoute.
  /// Used to get the current branch index and navigate between branches.
  final StatefulNavigationShell navigationShell;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final authState = ref.watch(authNotifierProvider);
    final isAdmin = authState is AuthAuthenticated &&
        authState.roles.contains(UserRole.admin);

    final tabs = _buildTabs(isAdmin);
    final currentIndex = _getCurrentIndex(tabs);

    return Scaffold(
      body: navigationShell,
      bottomNavigationBar: NavigationBar(
        selectedIndex: currentIndex,
        onDestinationSelected: (index) => _onTabSelected(tabs, index),
        destinations: tabs
            .map(
              (tab) => NavigationDestination(
                icon: Icon(tab.icon),
                selectedIcon: Icon(tab.selectedIcon),
                label: tab.label,
              ),
            )
            .toList(),
      ),
    );
  }

  List<_TabItem> _buildTabs(bool isAdmin) {
    return [
      const _TabItem(
        label: 'Home',
        icon: Icons.home_outlined,
        selectedIcon: Icons.home,
        route: RouteNames.home,
      ),
      const _TabItem(
        label: 'Jobs',
        icon: Icons.work_outline,
        selectedIcon: Icons.work,
        route: RouteNames.jobs,
      ),
      const _TabItem(
        label: 'Schedule',
        icon: Icons.calendar_month_outlined,
        selectedIcon: Icons.calendar_month,
        route: RouteNames.schedule,
      ),
      const _TabItem(
        label: 'Profile',
        icon: Icons.person_outline,
        selectedIcon: Icons.person,
        route: RouteNames.profile,
      ),
      if (isAdmin)
        const _TabItem(
          label: 'Team',
          icon: Icons.groups_outlined,
          selectedIcon: Icons.groups,
          route: RouteNames.adminTeam,
        ),
    ];
  }

  int _getCurrentIndex(List<_TabItem> tabs) {
    // StatefulNavigationShell.currentIndex reflects the active branch index.
    // For the Team tab (admin-only, branch index 4), we clamp to the visible
    // tab count in case the user is non-admin and tabs has fewer entries.
    final branchIndex = navigationShell.currentIndex;
    return branchIndex < tabs.length ? branchIndex : 0;
  }

  void _onTabSelected(List<_TabItem> tabs, int index) {
    // Use goBranch to properly switch between StatefulShellRoute branches.
    // initialLocation: true restores the branch's saved navigation state.
    navigationShell.goBranch(
      index,
      initialLocation: index == navigationShell.currentIndex,
    );
  }
}

class _TabItem {
  const _TabItem({
    required this.label,
    required this.icon,
    required this.selectedIcon,
    required this.route,
  });

  final String label;
  final IconData icon;
  final IconData selectedIcon;
  final String route;
}
