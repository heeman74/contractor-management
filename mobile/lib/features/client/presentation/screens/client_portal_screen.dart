import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/di/service_locator.dart';
import '../../../../core/routing/route_names.dart';
import '../../../../core/sync/sync_engine.dart';
import '../../../../features/auth/domain/auth_state.dart';
import '../../../../features/auth/presentation/providers/auth_provider.dart';
import '../../../jobs/domain/job_entity.dart';
import '../../../jobs/domain/job_status.dart';
import '../../../jobs/presentation/providers/crm_providers.dart';

/// Client portal screen — shows the client's own jobs and a button to
/// submit new job requests.
///
/// Streams jobs from local Drift DB via [clientJobHistoryNotifierProvider]
/// parameterized by the current user's ID. Offline-first and reactive.
class ClientPortalScreen extends ConsumerWidget {
  const ClientPortalScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final authState = ref.watch(authNotifierProvider);
    final userId =
        authState is AuthAuthenticated ? authState.userId : '';

    final jobsAsync = ref.watch(clientJobHistoryNotifierProvider(userId));

    return Scaffold(
      appBar: AppBar(
        title: const Text('Client Portal'),
        backgroundColor:
            Theme.of(context).colorScheme.surfaceContainerHighest,
      ),
      body: RefreshIndicator(
        onRefresh: () async {
          await getIt<SyncEngine>().syncNow();
        },
        child: jobsAsync.when(
          data: (jobs) {
            if (jobs.isEmpty) {
              return _EmptyState();
            }
            return ListView.builder(
              padding: const EdgeInsets.only(bottom: 80),
              itemCount: jobs.length,
              itemBuilder: (context, index) {
                return _JobCard(job: jobs[index]);
              },
            );
          },
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (error, _) => Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.error_outline, size: 48),
                const SizedBox(height: 16),
                Text('Failed to load jobs: $error'),
              ],
            ),
          ),
        ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => context.go(RouteNames.jobRequestForm),
        icon: const Icon(Icons.add_task),
        label: const Text('Request Job'),
      ),
    );
  }
}

/// Card displaying a single job for the client view.
class _JobCard extends StatelessWidget {
  final JobEntity job;

  const _JobCard({required this.job});

  @override
  Widget build(BuildContext context) {
    final status = JobStatus.fromString(job.status);
    final statusColor = _statusColor(status);

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: statusColor.withValues(alpha: 0.15),
          child: Icon(_statusIcon(status), color: statusColor, size: 20),
        ),
        title: Text(
          job.description,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 4),
            Row(
              children: [
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(
                    color: statusColor.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    status.displayLabel,
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: statusColor,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  job.tradeType,
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
            ),
          ],
        ),
        trailing: const Icon(Icons.chevron_right),
        onTap: () => context.go(RouteNames.jobDetailPath(job.id)),
      ),
    );
  }

  Color _statusColor(JobStatus status) {
    return switch (status) {
      JobStatus.quote => Colors.grey,
      JobStatus.scheduled => Colors.blue,
      JobStatus.inProgress => Colors.orange,
      JobStatus.complete => Colors.green,
      JobStatus.invoiced => Colors.purple,
      JobStatus.cancelled => Colors.red,
    };
  }

  IconData _statusIcon(JobStatus status) {
    return switch (status) {
      JobStatus.quote => Icons.request_quote_outlined,
      JobStatus.scheduled => Icons.event_outlined,
      JobStatus.inProgress => Icons.build_outlined,
      JobStatus.complete => Icons.check_circle_outline,
      JobStatus.invoiced => Icons.receipt_long_outlined,
      JobStatus.cancelled => Icons.cancel_outlined,
    };
  }
}

/// Empty state when the client has no jobs yet.
class _EmptyState extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return ListView(
      children: [
        SizedBox(
          height: 400,
          child: Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  Icons.work_off_outlined,
                  size: 72,
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
                const SizedBox(height: 24),
                Text(
                  'No jobs yet',
                  style: Theme.of(context).textTheme.titleLarge,
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 12),
                Text(
                  'Submit a job request to get started.\n'
                  'Your jobs will appear here once confirmed.',
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color:
                            Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}
