import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/di/service_locator.dart';
import '../../../../core/sync/sync_engine.dart';
import '../../../../shared/utils/date_format_utils.dart';
import '../../../jobs/domain/job_entity.dart';
import '../../../jobs/domain/job_status.dart';
import '../providers/client_providers.dart';
import '../widgets/cancelled_banner.dart';
import '../widgets/client_notes_tab.dart';
import '../widgets/delay_banner.dart';
import '../widgets/job_details_tab.dart';
import '../widgets/job_history_tab.dart';
import '../widgets/job_progress_stepper.dart';
import '../widgets/job_quote_tab.dart';
import '../widgets/photo_count_badge.dart';
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
///
/// [contractId] is optional and, when supplied (e.g. via a `contract_ready`
/// notification deep-link that carries `contract_id`), surfaces a Contract
/// card in the Quote tab. There is no by-job contract lookup endpoint, so the
/// contract is shown only when its id is known.
class ClientJobDetailScreen extends ConsumerWidget {
  final String jobId;
  final String? contractId;

  const ClientJobDetailScreen({
    required this.jobId,
    this.contractId,
    super.key,
  });

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
        return _JobDetailContent(
          job: job,
          jobId: jobId,
          contractId: contractId,
        );
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
  final String? contractId;

  const _JobDetailContent({
    required this.job,
    required this.jobId,
    this.contractId,
  });

  @override
  ConsumerState<_JobDetailContent> createState() => _JobDetailContentState();
}

class _JobDetailContentState extends ConsumerState<_JobDetailContent>
    with SingleTickerProviderStateMixin {
  static const _tabCount = 5; // Photos, Notes, Details, History, Quote

  late TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: _tabCount, vsync: this);
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

    final delayEntries = _delayEntries(job);
    final showDelayBanner = _shouldShowDelayBanner(status, delayEntries);
    final photoCount = _photoCount();

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
              const CancelledBanner()
            else
              JobProgressStepper(currentStatus: status),

            // Delay banner (only for active delayed jobs)
            if (showDelayBanner) DelayBanner(delayEntries: delayEntries),

            _LastUpdatedIndicator(updatedAt: job.updatedAt),

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
                        PhotoCountBadge(count: photoCount),
                      ],
                    ],
                  ),
                ),
                const Tab(text: 'Notes'),
                const Tab(text: 'Details'),
                const Tab(text: 'History'),
                const Tab(text: 'Quote'),
              ],
            ),

            // Tab views
            Expanded(
              child: TabBarView(
                controller: _tabController,
                children: [
                  PhotoTimeline(jobId: widget.jobId),
                  ClientNotesTab(jobId: widget.jobId, job: job),
                  JobDetailsTab(job: job, jobId: widget.jobId),
                  JobHistoryTab(job: job),
                  JobQuoteTab(
                    jobId: widget.jobId,
                    contractId: widget.contractId,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Delay events recorded in the job's status history.
  List<Map<String, dynamic>> _delayEntries(JobEntity job) {
    return job.statusHistory
        .where((e) => e['type'] == 'delay')
        .map((e) => Map<String, dynamic>.from(e))
        .toList();
  }

  /// Delay banner shows only when the job is delayed and still active
  /// (not completed/invoiced).
  bool _shouldShowDelayBanner(
    JobStatus status,
    List<Map<String, dynamic>> delayEntries,
  ) {
    return delayEntries.isNotEmpty &&
        status != JobStatus.complete &&
        status != JobStatus.invoiced;
  }

  /// Current photo count for the tab badge (0 while loading/errored).
  int _photoCount() {
    final photosAsync = ref.watch(photosForJobProvider(widget.jobId));
    return photosAsync.maybeWhen(data: (p) => p.length, orElse: () => 0);
  }
}

/// Right-aligned "Last updated: `<relative time>`" indicator.
class _LastUpdatedIndicator extends StatelessWidget {
  const _LastUpdatedIndicator({required this.updatedAt});

  final DateTime updatedAt;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: Align(
        alignment: Alignment.centerRight,
        child: Text(
          'Last updated: ${DateFormatUtils.relativeTime(updatedAt)}',
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
        ),
      ),
    );
  }
}
