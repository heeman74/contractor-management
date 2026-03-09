import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/routing/route_names.dart';
import '../../features/auth/domain/auth_state.dart';
import '../../features/auth/presentation/providers/auth_provider.dart';
import '../../features/schedule/presentation/providers/overdue_providers.dart';
import '../../shared/models/user_role.dart';
import 'sync_status_subtitle.dart';

/// Shared app shell — wraps all authenticated routes with a bottom navigation bar
/// and a unified app bar showing the current tab title and sync status subtitle.
///
/// This is the core of the "one unified app with different views" user requirement:
/// all roles see the same shell and the same core tabs (Home, Jobs, Schedule, Profile).
/// The only difference is the admin role gets an additional "Team" tab.
///
/// The app bar always shows:
/// - Primary title: current tab name (e.g. "Home", "Jobs", "Schedule")
/// - Subtitle: [SyncStatusSubtitle] — always visible sync state indicator
///   (user decision: subtitle stays on screen at all times, no toast/banner)
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
  const AppShell({required this.navigationShell, super.key});

  /// The navigation shell provided by go_router's StatefulShellRoute.
  /// Used to get the current branch index and navigate between branches.
  final StatefulNavigationShell navigationShell;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final authState = ref.watch(authNotifierProvider);
    final isAdmin = authState is AuthAuthenticated &&
        authState.roles.contains(UserRole.admin);

    // Watch overdue count for the bottom nav Schedule tab badge.
    // Badge remains visible on ALL tabs (it's on the bottom nav, not the calendar).
    final overdueCount = ref.watch(overdueJobCountProvider);

    final tabs = _buildTabs(isAdmin);
    final currentIndex = _getCurrentIndex(tabs);
    final currentTab = tabs[currentIndex];

    return Scaffold(
      appBar: AppBar(
        // The title is a Column showing the tab name above and sync status below.
        // AppBar automatically handles centering based on centerTitle theme setting.
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(currentTab.label),
            const SyncStatusSubtitle(),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.logout),
            onPressed: () =>
                ref.read(authNotifierProvider.notifier).logout(),
            tooltip: 'Sign out',
          ),
        ],
      ),
      body: navigationShell,
      bottomNavigationBar: NavigationBar(
        selectedIndex: currentIndex,
        onDestinationSelected: (index) => _onTabSelected(tabs, index),
        destinations: tabs
            .map(
              (tab) => NavigationDestination(
                icon: _buildTabIcon(
                  tab: tab,
                  isSelected: false,
                  overdueCount: overdueCount,
                ),
                selectedIcon: _buildTabIcon(
                  tab: tab,
                  isSelected: true,
                  overdueCount: overdueCount,
                ),
                label: tab.label,
              ),
            )
            .toList(),
      ),
    );
  }

  /// Wraps a tab icon in a Material 3 [Badge] if the tab is the Schedule tab
  /// and there are overdue jobs.
  ///
  /// The Badge is always visible on the bottom nav (regardless of active tab)
  /// so admins see the overdue count without switching to the Schedule screen.
  Widget _buildTabIcon({
    required _TabItem tab,
    required bool isSelected,
    required int overdueCount,
  }) {
    final icon = Icon(isSelected ? tab.selectedIcon : tab.icon);

    if (tab.route == RouteNames.schedule) {
      // Material 3 Badge — built into package:flutter/material.dart (Flutter 3.22+).
      // Red background by default in M3 theme. Label hidden when count == 0.
      return Badge(
        isLabelVisible: overdueCount > 0,
        label: Text('$overdueCount'),
        child: icon,
      );
    }

    return icon;
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
