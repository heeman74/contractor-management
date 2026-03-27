import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/di/service_locator.dart';
import '../../../../core/routing/route_names.dart';
import '../../../../core/sync/sync_engine.dart';
import '../../../../features/auth/domain/auth_state.dart';
import '../../../../features/auth/presentation/providers/auth_provider.dart';
import '../../../jobs/domain/job_entity.dart';
import '../../../jobs/domain/job_request_entity.dart';
import '../../../jobs/domain/job_status.dart';
import '../../../jobs/presentation/providers/crm_providers.dart';
import '../providers/client_providers.dart';

/// Client portal screen — shows the client's own jobs and pending requests.
///
/// Sections:
///   1. "Pending Requests" — visible when pending/declined requests exist
///   2. "Active Jobs" — all non-deleted jobs with ETA and delay indicators
///
/// Each job card navigates to [ClientJobDetailScreen] (not admin JobDetailScreen).
/// Completed/invoiced jobs appear dimmed with a green checkmark.
/// Delayed jobs show an orange warning icon.
class ClientPortalScreen extends ConsumerWidget {
  const ClientPortalScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final authState = ref.watch(authNotifierProvider);
    final userId =
        authState is AuthAuthenticated ? authState.userId : '';

    final jobsAsync = ref.watch(clientJobHistoryNotifierProvider(userId));
    final requestsAsync = ref.watch(clientPendingRequestsProvider(userId));

    // "Last updated" tracks last sync.
    final lastSync = DateTime.now();

    return Scaffold(
      appBar: AppBar(
        title: const Text('My Jobs'),
        backgroundColor:
            Theme.of(context).colorScheme.surfaceContainerHighest,
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(20),
          child: Padding(
            padding: const EdgeInsets.only(bottom: 4),
            child: Text(
              'Updated ${_relativeTime(lastSync)}',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
            ),
          ),
        ),
      ),
      body: RefreshIndicator(
        onRefresh: () async {
          await getIt<SyncEngine>().syncNow();
        },
        child: _PortalBody(
          jobsAsync: jobsAsync,
          requestsAsync: requestsAsync,
        ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => context.go(RouteNames.jobRequestForm),
        icon: const Icon(Icons.add_task),
        label: const Text('Request Job'),
      ),
    );
  }

  String _relativeTime(DateTime dt) {
    final now = DateTime.now();
    final diff = now.difference(dt);
    if (diff.inMinutes < 1) return 'just now';
    if (diff.inHours < 1) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    return '${dt.day}/${dt.month}/${dt.year}';
  }
}

// ─── Portal body ──────────────────────────────────────────────────────────────

class _PortalBody extends StatelessWidget {
  final AsyncValue<List<JobEntity>> jobsAsync;
  final AsyncValue<List<JobRequestEntity>> requestsAsync;

  const _PortalBody({
    required this.jobsAsync,
    required this.requestsAsync,
  });

  @override
  Widget build(BuildContext context) {
    return jobsAsync.when(
      data: (jobs) {
        final requests = requestsAsync.maybeWhen(
          data: (r) => r,
          orElse: () => <JobRequestEntity>[],
        );

        if (jobs.isEmpty && requests.isEmpty) {
          return _EmptyState();
        }

        return ListView(
          padding: const EdgeInsets.only(bottom: 80),
          children: [
            // Pending requests section (shown only when requests exist)
            if (requests.isNotEmpty) ...[
              _SectionHeader(title: 'Pending Requests', count: requests.length),
              ...requests.map((r) => _RequestCard(request: r)),
              const Divider(height: 1),
              const SizedBox(height: 8),
            ],

            // Active jobs section
            if (jobs.isNotEmpty) ...[
              _SectionHeader(title: 'My Jobs', count: jobs.length),
              ...jobs.map((job) => _JobCard(job: job)),
            ],
          ],
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
    );
  }
}

// ─── Section header ───────────────────────────────────────────────────────────

class _SectionHeader extends StatelessWidget {
  final String title;
  final int count;

  const _SectionHeader({required this.title, required this.count});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
      child: Row(
        children: [
          Text(
            title,
            style: Theme.of(context).textTheme.titleSmall?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                  fontWeight: FontWeight.w600,
                ),
          ),
          const SizedBox(width: 6),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
            decoration: BoxDecoration(
              color: Theme.of(context)
                  .colorScheme
                  .onSurfaceVariant
                  .withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Text(
              '$count',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                  ),
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Job card ─────────────────────────────────────────────────────────────────

/// Card displaying a single job for the client view.
///
/// - Completed/invoiced jobs: dimmed to 0.6 opacity, green checkmark trailing
/// - Delayed jobs: orange warning icon next to status chip
/// - ETA date shown below status chip when available
/// - Taps navigate to client-specific detail screen (not admin)
class _JobCard extends StatelessWidget {
  final JobEntity job;

  const _JobCard({required this.job});

  @override
  Widget build(BuildContext context) {
    final status = JobStatus.fromString(job.status);
    final statusColor = _statusColor(status);
    final isFinished =
        status == JobStatus.complete || status == JobStatus.invoiced;

    // Check for delay entries in statusHistory.
    final hasDelay = job.statusHistory.any((e) => e['type'] == 'delay');

    // ETA from scheduledCompletionDate.
    final eta = job.scheduledCompletionDate;
    final etaLabel = eta != null ? _formatDate(eta) : null;

    return Opacity(
      opacity: isFinished ? 0.6 : 1.0,
      child: Card(
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
                  // Status chip
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 8, vertical: 2),
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
                  // Delay warning icon
                  if (hasDelay && !isFinished) ...[
                    const SizedBox(width: 4),
                    const Icon(
                      Icons.warning_amber_rounded,
                      size: 14,
                      color: Colors.orange,
                    ),
                  ],
                  const SizedBox(width: 8),
                  Text(
                    job.tradeType,
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ],
              ),
              // ETA date
              if (etaLabel != null)
                Padding(
                  padding: const EdgeInsets.only(top: 2),
                  child: Text(
                    'ETA: $etaLabel',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: hasDelay && !isFinished
                              ? Colors.orange.shade700
                              : Theme.of(context).colorScheme.onSurfaceVariant,
                          fontWeight: hasDelay && !isFinished
                              ? FontWeight.w500
                              : FontWeight.normal,
                        ),
                  ),
                ),
            ],
          ),
          trailing: isFinished
              ? const Icon(Icons.check_circle, color: Colors.green, size: 22)
              : const Icon(Icons.chevron_right),
          onTap: () =>
              context.push(RouteNames.clientJobDetailPath(job.id)),
        ),
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

  String _formatDate(DateTime dt) {
    final months = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'
    ];
    return '${months[dt.month - 1]} ${dt.day}, ${dt.year}';
  }
}

// ─── Request card ─────────────────────────────────────────────────────────────

/// Card for a pending/declined job request in the client portal.
///
/// Pending: amber status badge
/// Declined: red badge + decline reason shown
/// Request_more_info: blue badge + admin message shown
class _RequestCard extends StatelessWidget {
  final JobRequestEntity request;

  const _RequestCard({required this.request});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final status = request.requestStatus;

    Color statusColor;
    String statusLabel;

    switch (status) {
      case 'pending':
        statusColor = Colors.amber.shade700;
        statusLabel = 'Pending Review';
      case 'declined':
        statusColor = Colors.red;
        statusLabel = 'Declined';
      case 'request_more_info':
        statusColor = Colors.blue;
        statusLabel = 'More Info Needed';
      default:
        statusColor = Colors.grey;
        statusLabel = status;
    }

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      color: theme.colorScheme.surfaceContainerLowest,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(
                    color: statusColor.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                        color: statusColor.withValues(alpha: 0.4)),
                  ),
                  child: Text(
                    statusLabel,
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: statusColor,
                    ),
                  ),
                ),
                const Spacer(),
                if (request.urgency == 'urgent' ||
                    request.urgency == 'emergency')
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: Colors.deepOrange.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Text(
                      request.urgency.toUpperCase(),
                      style: const TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.bold,
                        color: Colors.deepOrange,
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              request.description,
              style: theme.textTheme.bodyMedium,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
            // Decline reason
            if (status == 'declined' && request.declineMessage != null) ...[
              const SizedBox(height: 6),
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.red.shade50,
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  request.declineMessage!,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: Colors.red.shade700,
                  ),
                ),
              ),
            ],
            // More info message
            if (status == 'request_more_info' &&
                request.declineMessage != null) ...[
              const SizedBox(height: 6),
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.blue.shade50,
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  request.declineMessage!,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: Colors.blue.shade700,
                  ),
                ),
              ),
            ],
            const SizedBox(height: 4),
            Text(
              'Submitted ${_relativeTime(request.createdAt)}',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _relativeTime(DateTime dt) {
    final now = DateTime.now();
    final diff = now.difference(dt);
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    final months = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'
    ];
    return '${months[dt.month - 1]} ${dt.day}';
  }
}

// ─── Empty state ──────────────────────────────────────────────────────────────

/// Empty state when the client has no jobs or pending requests.
class _EmptyState extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        return ListView(
          children: [
            SizedBox(
              height: constraints.maxHeight,
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
      },
    );
  }
}
