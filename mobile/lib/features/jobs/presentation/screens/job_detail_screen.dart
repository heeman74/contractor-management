import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../domain/job_entity.dart';
import '../../domain/job_status.dart';
import '../providers/job_providers.dart';

/// Tabbed job detail screen — Details, Schedule, and History tabs.
///
/// Streamed from local Drift DB via [jobDetailNotifierProvider] — offline-first.
///
/// Details tab: description, client, contractor, priority, trade, notes.
/// Schedule tab: all booking dates/times, contractor, job site addresses.
/// History tab: lifecycle transition audit trail from status_history JSONB.
class JobDetailScreen extends ConsumerStatefulWidget {
  final String jobId;

  const JobDetailScreen({super.key, required this.jobId});

  @override
  ConsumerState<JobDetailScreen> createState() => _JobDetailScreenState();
}

class _JobDetailScreenState extends ConsumerState<JobDetailScreen>
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
    final jobAsync = ref.watch(jobDetailNotifierProvider(widget.jobId));

    return jobAsync.when(
      data: (job) {
        if (job == null) {
          return Scaffold(
            appBar: AppBar(title: const Text('Job Detail')),
            body: const Center(child: Text('Job not found')),
          );
        }
        return _JobDetailView(job: job, tabController: _tabController);
      },
      loading: () => Scaffold(
        appBar: AppBar(title: const Text('Job Detail')),
        body: const Center(child: CircularProgressIndicator()),
      ),
      error: (e, _) => Scaffold(
        appBar: AppBar(title: const Text('Job Detail')),
        body: Center(child: Text('Error: $e')),
      ),
    );
  }
}

class _JobDetailView extends StatelessWidget {
  final JobEntity job;
  final TabController tabController;

  const _JobDetailView({required this.job, required this.tabController});

  @override
  Widget build(BuildContext context) {
    final statusColor = _statusColor(job.jobStatus);

    return Scaffold(
      appBar: AppBar(
        title: Text(
          job.description,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        actions: [
          // Status chip in AppBar
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: Chip(
              label: Text(job.jobStatus.displayLabel),
              backgroundColor: statusColor.withValues(alpha: 0.15),
              labelStyle: TextStyle(
                color: statusColor,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
        bottom: TabBar(
          controller: tabController,
          tabs: const [
            Tab(icon: Icon(Icons.info_outline), text: 'Details'),
            Tab(icon: Icon(Icons.schedule_outlined), text: 'Schedule'),
            Tab(icon: Icon(Icons.history_outlined), text: 'History'),
          ],
        ),
      ),
      body: TabBarView(
        controller: tabController,
        children: [
          _DetailsTab(job: job),
          _ScheduleTab(job: job),
          _HistoryTab(job: job),
        ],
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
}

// ─── Details tab ──────────────────────────────────────────────────────────────

class _DetailsTab extends StatelessWidget {
  final JobEntity job;

  const _DetailsTab({required this.job});

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _DetailRow(label: 'Description', value: job.description),
                _DetailRow(label: 'Trade', value: job.tradeType),
                _DetailRow(label: 'Priority', value: job.priority),
                if (job.clientId != null)
                  _DetailRow(label: 'Client', value: job.clientId!),
                if (job.contractorId != null)
                  _DetailRow(label: 'Contractor', value: job.contractorId!),
                if (job.notes != null)
                  _DetailRow(label: 'Notes', value: job.notes!),
                if (job.purchaseOrderNumber != null)
                  _DetailRow(label: 'PO Number', value: job.purchaseOrderNumber!),
                if (job.externalReference != null)
                  _DetailRow(label: 'External Ref', value: job.externalReference!),
                if (job.estimatedDurationMinutes != null)
                  _DetailRow(
                    label: 'Est. Duration',
                    value: '${job.estimatedDurationMinutes} min',
                  ),
                if (job.scheduledCompletionDate != null)
                  _DetailRow(
                    label: 'Completion Date',
                    value:
                        '${job.scheduledCompletionDate!.day}/${job.scheduledCompletionDate!.month}/${job.scheduledCompletionDate!.year}',
                  ),
                if (job.tags.isNotEmpty)
                  _DetailRow(label: 'Tags', value: job.tags.join(', ')),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _DetailRow extends StatelessWidget {
  final String label;
  final String value;

  const _DetailRow({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 130,
            child: Text(
              label,
              style: Theme.of(context).textTheme.labelMedium?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                    fontWeight: FontWeight.w600,
                  ),
            ),
          ),
          Expanded(
            child: Text(value, style: Theme.of(context).textTheme.bodyMedium),
          ),
        ],
      ),
    );
  }
}

// ─── Schedule tab ─────────────────────────────────────────────────────────────

class _ScheduleTab extends StatelessWidget {
  final JobEntity job;

  const _ScheduleTab({required this.job});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.calendar_month_outlined,
              size: 64,
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
            const SizedBox(height: 16),
            const Text(
              'Schedule view',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            Text(
              'Booking details will appear here once the job is scheduled.',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─── History tab ──────────────────────────────────────────────────────────────

class _HistoryTab extends StatelessWidget {
  final JobEntity job;

  const _HistoryTab({required this.job});

  @override
  Widget build(BuildContext context) {
    if (job.statusHistory.isEmpty) {
      return Center(
        child: Text(
          'No status history yet.',
          style: TextStyle(
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
        ),
      );
    }

    // Display history newest-first
    final history = List<Map<String, dynamic>>.from(job.statusHistory)
        .reversed
        .toList();

    return ListView.separated(
      padding: const EdgeInsets.all(16),
      itemCount: history.length,
      separatorBuilder: (_, __) => const Divider(),
      itemBuilder: (context, index) {
        final entry = history[index];
        final status = entry['status'] as String? ?? '';
        final timestamp = entry['timestamp'] as String? ?? '';
        final reason = entry['reason'] as String?;

        return ListTile(
          leading: const Icon(Icons.circle, size: 12),
          title: Text(
            status.replaceAll('_', ' ').toUpperCase(),
            style: const TextStyle(fontWeight: FontWeight.w600),
          ),
          subtitle: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(timestamp),
              if (reason != null && reason.isNotEmpty)
                Text('Reason: $reason', style: const TextStyle(fontStyle: FontStyle.italic)),
            ],
          ),
        );
      },
    );
  }
}
