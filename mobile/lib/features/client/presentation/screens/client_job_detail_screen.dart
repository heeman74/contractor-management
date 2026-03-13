import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/di/service_locator.dart';
import '../../../../core/sync/sync_engine.dart';
import '../../../jobs/domain/job_entity.dart';
import '../../../jobs/domain/job_status.dart';
import '../providers/client_providers.dart';
import '../widgets/client_notes_tab.dart';
import '../widgets/delay_banner.dart';
import '../widgets/job_progress_stepper.dart';
import '../widgets/photo_timeline.dart';

/// Client-specific job detail screen.
///
/// Shows:
///   - Job lifecycle progress stepper (or "Cancelled" banner)
///   - Delay banner when active delays exist
///   - Three tabs: Photos (with count badge), Notes, Details
///   - "Last updated" relative time indicator
///
/// Navigated to via [RouteNames.clientJobDetailPath(jobId)].
/// Streams job data from [clientJobProvider] — offline-first, reactive.
class ClientJobDetailScreen extends ConsumerWidget {
  final String jobId;

  const ClientJobDetailScreen({super.key, required this.jobId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final jobAsync = ref.watch(clientJobProvider(jobId));

    return jobAsync.when(
      data: (job) {
        if (job == null) {
          return Scaffold(
            appBar: AppBar(title: const Text('Job Detail')),
            body: const Center(child: Text('Job not found.')),
          );
        }
        return _JobDetailContent(job: job, jobId: jobId);
      },
      loading: () => Scaffold(
        appBar: AppBar(title: const Text('Job Detail')),
        body: const Center(child: CircularProgressIndicator()),
      ),
      error: (e, _) => Scaffold(
        appBar: AppBar(title: const Text('Job Detail')),
        body: Center(child: Text('Error loading job: $e')),
      ),
    );
  }
}

// ─── Main content widget ──────────────────────────────────────────────────────

class _JobDetailContent extends ConsumerStatefulWidget {
  final JobEntity job;
  final String jobId;

  const _JobDetailContent({required this.job, required this.jobId});

  @override
  ConsumerState<_JobDetailContent> createState() => _JobDetailContentState();
}

class _JobDetailContentState extends ConsumerState<_JobDetailContent>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final job = widget.job;
    final status = JobStatus.fromString(job.status);
    final isCancelled = status == JobStatus.cancelled;

    // Extract delay entries from statusHistory.
    final delayEntries = job.statusHistory
        .where((e) => e['type'] == 'delay')
        .map((e) => Map<String, dynamic>.from(e))
        .toList();

    // Show delay banner only when job is not completed/invoiced.
    final showDelayBanner = delayEntries.isNotEmpty &&
        status != JobStatus.complete &&
        status != JobStatus.invoiced;

    // Photo count badge from photosForJobProvider.
    final photosAsync = ref.watch(photosForJobProvider(widget.jobId));
    final photoCount =
        photosAsync.maybeWhen(data: (p) => p.length, orElse: () => 0);

    return Scaffold(
      appBar: AppBar(
        title: Text(
          job.description,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
      ),
      body: RefreshIndicator(
        onRefresh: () async {
          await getIt<SyncEngine>().syncNow();
        },
        child: Column(
          children: [
            // Cancelled banner OR progress stepper
            if (isCancelled)
              _CancelledBanner()
            else
              JobProgressStepper(currentStatus: status),

            // Delay banner (only for active delayed jobs)
            if (showDelayBanner) DelayBanner(delayEntries: delayEntries),

            // "Last updated" indicator
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
              child: Align(
                alignment: Alignment.centerRight,
                child: Text(
                  'Last updated: ${_relativeTime(job.updatedAt)}',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                ),
              ),
            ),

            // Tab bar
            TabBar(
              controller: _tabController,
              tabs: [
                Tab(
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Text('Photos'),
                      if (photoCount > 0) ...[
                        const SizedBox(width: 4),
                        _Badge(count: photoCount),
                      ],
                    ],
                  ),
                ),
                const Tab(text: 'Notes'),
                const Tab(text: 'Details'),
              ],
            ),

            // Tab views
            Expanded(
              child: TabBarView(
                controller: _tabController,
                children: [
                  PhotoTimeline(jobId: widget.jobId),
                  ClientNotesTab(jobId: widget.jobId, job: job),
                  _DetailsTab(job: job),
                ],
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
    if (diff.inMinutes < 1) return 'just now';
    if (diff.inHours < 1) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    final local = dt.toLocal();
    final months = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'
    ];
    return '${months[local.month - 1]} ${local.day}';
  }
}

// ─── Cancelled banner ─────────────────────────────────────────────────────────

class _CancelledBanner extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.red.shade50,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.red.shade300),
      ),
      child: Row(
        children: [
          Icon(Icons.cancel_outlined, color: Colors.red.shade700),
          const SizedBox(width: 8),
          Text(
            'This job has been cancelled',
            style: TextStyle(
              color: Colors.red.shade700,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Photo count badge ────────────────────────────────────────────────────────

class _Badge extends StatelessWidget {
  final int count;

  const _Badge({required this.count});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.primary,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Text(
        '$count',
        style: const TextStyle(
          color: Colors.white,
          fontSize: 10,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }
}

// ─── Details tab ─────────────────────────────────────────────────────────────

class _DetailsTab extends StatelessWidget {
  final JobEntity job;

  const _DetailsTab({required this.job});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _DetailRow(
                  label: 'Description',
                  value: job.description,
                ),
                const Divider(),
                _DetailRow(
                  label: 'Trade Type',
                  value: job.tradeType,
                ),
                const Divider(),
                _DetailRow(
                  label: 'Status',
                  value: JobStatus.fromString(job.status).displayLabel,
                ),
                if (job.gpsAddress != null) ...[
                  const Divider(),
                  _DetailRow(
                    label: 'Location',
                    value: job.gpsAddress!,
                  ),
                ],
                if (job.scheduledCompletionDate != null) ...[
                  const Divider(),
                  _DetailRow(
                    label: 'Expected Completion',
                    value: _formatDate(job.scheduledCompletionDate!),
                  ),
                ],
              ],
            ),
          ),
        ),
        const SizedBox(height: 8),
        Text(
          'Note: Pricing information is not shown in the client portal.',
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
            fontStyle: FontStyle.italic,
          ),
          textAlign: TextAlign.center,
        ),
      ],
    );
  }

  String _formatDate(DateTime dt) {
    final months = [
      'January', 'February', 'March', 'April', 'May', 'June',
      'July', 'August', 'September', 'October', 'November', 'December'
    ];
    return '${months[dt.month - 1]} ${dt.day}, ${dt.year}';
  }
}

class _DetailRow extends StatelessWidget {
  final String label;
  final String value;

  const _DetailRow({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 140,
            child: Text(
              label,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: theme.textTheme.bodyMedium,
            ),
          ),
        ],
      ),
    );
  }
}
