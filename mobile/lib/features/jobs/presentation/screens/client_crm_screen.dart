import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/routing/route_names.dart';
import '../../../../features/auth/domain/auth_state.dart';
import '../../../../features/auth/presentation/providers/auth_provider.dart';
import '../../domain/client_profile_entity.dart';
import '../providers/crm_providers.dart';
import '../widgets/client_card.dart';

/// Admin client management screen — CRM hub with searchable list and
/// inline expandable cards.
///
/// Replaces the placeholder [ClientManagementScreen].
///
/// Per CONTEXT.md: inline expandable cards (not separate navigation) for
/// quick scanning. Admins can see key info without leaving the list.
///
/// Features:
/// - Real-time search filtering by tags / admin notes / referral source
/// - Pending request badge in the AppBar
/// - FAB: "Add Client" (with guidance dialog)
/// - Empty state with actionable guidance
class ClientCrmScreen extends ConsumerWidget {
  const ClientCrmScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final authState = ref.watch(authNotifierProvider);
    final companyId =
        authState is AuthAuthenticated ? authState.companyId : '';

    final clientsAsync = ref.watch(clientListNotifierProvider(companyId));
    final pendingAsync =
        ref.watch(pendingRequestsNotifierProvider(companyId));
    final searchQuery = ref.watch(clientSearchQueryProvider);

    final pendingCount = pendingAsync.valueOrNull?.length ?? 0;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Clients'),
        backgroundColor:
            Theme.of(context).colorScheme.surfaceContainerHighest,
        actions: [
          // Pending request badge — navigates to request review queue
          if (pendingCount > 0)
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: Badge(
                label: Text('$pendingCount'),
                child: IconButton(
                  icon: const Icon(Icons.inbox_outlined),
                  tooltip: 'Pending Requests ($pendingCount)',
                  onPressed: () {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text(
                          'Navigate to Request Review queue — use the Jobs tab',
                        ),
                      ),
                    );
                  },
                ),
              ),
            ),
        ],
      ),
      body: Column(
        children: [
          // Search bar
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 4),
            child: SearchBar(
              hintText: 'Search clients by name, tag, or note…',
              leading: const Icon(Icons.search),
              trailing: [
                if (searchQuery.isNotEmpty)
                  IconButton(
                    icon: const Icon(Icons.clear),
                    onPressed: () => ref
                        .read(clientSearchQueryProvider.notifier)
                        .state = '',
                  ),
              ],
              onChanged: (value) =>
                  ref.read(clientSearchQueryProvider.notifier).state =
                      value,
            ),
          ),

          // Client list
          Expanded(
            child: clientsAsync.when(
              data: (clients) {
                final filtered = _filterClients(clients, searchQuery);
                if (filtered.isEmpty) {
                  return _EmptyState(hasSearch: searchQuery.isNotEmpty);
                }
                return ListView.builder(
                  padding: const EdgeInsets.only(bottom: 80),
                  itemCount: filtered.length,
                  itemBuilder: (context, index) {
                    final profile = filtered[index];
                    return _ClientCardWrapper(
                      profile: profile,
                    );
                  },
                );
              },
              loading: () =>
                  const Center(child: CircularProgressIndicator()),
              error: (error, _) => Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(Icons.error_outline, size: 48),
                    const SizedBox(height: 16),
                    Text('Failed to load clients: $error'),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _showAddClientDialog(context),
        icon: const Icon(Icons.person_add),
        label: const Text('Add Client'),
      ),
    );
  }

  List<ClientProfileEntity> _filterClients(
    List<ClientProfileEntity> clients,
    String query,
  ) {
    if (query.isEmpty) return clients;
    final lower = query.toLowerCase();
    return clients.where((c) {
      return (c.adminNotes?.toLowerCase().contains(lower) ?? false) ||
          c.tags.any((tag) => tag.toLowerCase().contains(lower)) ||
          (c.referralSource?.toLowerCase().contains(lower) ?? false) ||
          (c.billingAddress?.toLowerCase().contains(lower) ?? false);
    }).toList();
  }

  void _showAddClientDialog(BuildContext context) {
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Add Client'),
        content: const Text(
          'To add a new client, invite them via the Team Management screen '
          'and assign them the Client role. Their client profile will '
          'appear here automatically.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }
}

/// Wrapper that loads job history for a profile and renders a [ClientCard].
class _ClientCardWrapper extends ConsumerWidget {
  final ClientProfileEntity profile;

  const _ClientCardWrapper({required this.profile});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final historyAsync =
        ref.watch(clientJobHistoryNotifierProvider(profile.userId));
    final jobs = historyAsync.valueOrNull ?? [];

    return ClientCard(
      profile: profile,
      displayName: profile.userId, // replaced by User.email once join is added
      jobCount: jobs.length,
      recentJobs: jobs.take(3).toList(),
      savedPropertyCount: 0, // loaded per-profile on the detail screen
      onViewProfile: () => context.go(
        RouteNames.clientDetailPath(profile.id),
      ),
      onCreateJob: () => context.go(
        '${RouteNames.jobNew}?clientId=${profile.id}',
      ),
    );
  }
}

/// Empty state shown when no clients match the current search or
/// when there are no clients yet.
class _EmptyState extends StatelessWidget {
  final bool hasSearch;

  const _EmptyState({required this.hasSearch});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              hasSearch ? Icons.search_off : Icons.people_outline,
              size: 72,
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
            const SizedBox(height: 24),
            Text(
              hasSearch ? 'No clients match your search' : 'No clients yet',
              style: Theme.of(context).textTheme.titleLarge,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 12),
            Text(
              hasSearch
                  ? 'Try a different search term or clear the search.'
                  : 'Invite clients via the Team Management screen '
                      'and assign them the Client role. They\'ll appear here '
                      'once you\'ve synced with the server.',
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color:
                        Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}
