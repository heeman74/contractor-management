import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/di/service_locator.dart';
import '../../../../core/routing/route_names.dart';
import '../../../../core/sync/sync_engine.dart';
import '../../../invoices/presentation/providers/invoice_providers.dart';
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
    // 4 tabs: Photos, Notes, Details, History
    _tabController = TabController(length: 4, vsync: this);
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
                const Tab(text: 'History'),
              ],
            ),

            // Tab views
            Expanded(
              child: TabBarView(
                controller: _tabController,
                children: [
                  PhotoTimeline(jobId: widget.jobId),
                  ClientNotesTab(jobId: widget.jobId, job: job),
                  _DetailsTab(job: job, jobId: widget.jobId),
                  _HistoryTab(job: job),
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

class _DetailsTab extends ConsumerWidget {
  final JobEntity job;
  final String jobId;

  const _DetailsTab({required this.job, required this.jobId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);

    // Watch invoices for this job
    final invoicesAsync = ref.watch(invoicesForJobProvider(jobId));

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

        // Invoice section — shown when an invoice exists for this job
        invoicesAsync.when(
          data: (invoices) {
            if (invoices.isEmpty) return const SizedBox.shrink();

            final invoice = invoices.first;
            final statusColors = {
              'unpaid': Colors.red,
              'partial': Colors.orange,
              'paid': Colors.green,
              'overdue': Colors.deepOrange,
              'cancelled': Colors.grey,
            };
            final statusLabels = {
              'unpaid': 'Unpaid',
              'partial': 'Partially Paid',
              'paid': 'Paid',
              'overdue': 'Overdue',
              'cancelled': 'Cancelled',
            };
            final statusColor =
                statusColors[invoice.status] ?? Colors.grey;
            final statusLabel =
                statusLabels[invoice.status] ?? invoice.status;

            return Column(
              children: [
                const SizedBox(height: 16),
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Icon(
                              Icons.receipt_outlined,
                              size: 18,
                              color: theme.colorScheme.primary,
                            ),
                            const SizedBox(width: 8),
                            Text(
                              'Invoice',
                              style: theme.textTheme.titleMedium?.copyWith(
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(
                              invoice.invoiceNumber,
                              style: theme.textTheme.bodyLarge?.copyWith(
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 10,
                                vertical: 4,
                              ),
                              decoration: BoxDecoration(
                                color:
                                    statusColor.withValues(alpha: 0.1),
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(
                                  color: statusColor
                                      .withValues(alpha: 0.4),
                                ),
                              ),
                              child: Text(
                                statusLabel,
                                style: TextStyle(
                                  color: statusColor,
                                  fontWeight: FontWeight.w600,
                                  fontSize: 12,
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'Total: \$${invoice.total.toStringAsFixed(2)}',
                          style: theme.textTheme.bodyMedium,
                        ),
                        const SizedBox(height: 12),
                        SizedBox(
                          width: double.infinity,
                          child: OutlinedButton.icon(
                            icon: const Icon(Icons.open_in_new, size: 16),
                            label: const Text('View Invoice'),
                            onPressed: () => context.push(
                              RouteNames.invoiceDetailPath(invoice.id),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            );
          },
          loading: () => const SizedBox.shrink(),
          error: (_, __) => const SizedBox.shrink(),
        ),
      ],
    );
  }

  String _formatDate(DateTime dt) {
    final months = [
      'January', 'February', 'March', 'April', 'May', 'June',
      'July', 'August', 'September', 'October', 'November', 'December',
    ];
    return '${months[dt.month - 1]} ${dt.day}, ${dt.year}';
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
          'No history yet.',
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
        final entryType = entry['type'] as String?;

        return _HistoryEntryTile(entry: entry, entryType: entryType);
      },
    );
  }
}

/// A single history timeline entry — handles multiple event types:
/// - status transitions (type: null or 'status')
/// - delays (type: 'delay')
/// - quote events (type: quote_created / quote_sent / quote_viewed /
///   quote_approved / quote_declined / quote_revised)
/// - invoice events (type: invoice_generated)
class _HistoryEntryTile extends StatelessWidget {
  final Map<String, dynamic> entry;
  final String? entryType;

  const _HistoryEntryTile({required this.entry, required this.entryType});

  @override
  Widget build(BuildContext context) {
    final timestamp = entry['timestamp'] as String? ?? '';
    final reason = entry['reason'] as String?;
    final newEta = entry['new_eta'] as String?;

    final (IconData icon, Color color, String label) =
        _resolveEntryStyle(context);

    return ListTile(
      leading: Icon(icon, size: 18, color: color),
      title: Text(
        label,
        style: TextStyle(fontWeight: FontWeight.w600, color: color),
      ),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (timestamp.isNotEmpty) Text(timestamp),
          if (reason != null && reason.isNotEmpty)
            Text(
              'Reason: $reason',
              style: const TextStyle(fontStyle: FontStyle.italic),
            ),
          if (newEta != null && newEta.isNotEmpty) Text('New ETA: $newEta'),
        ],
      ),
    );
  }

  (IconData, Color, String) _resolveEntryStyle(BuildContext context) {
    final onSurface = Theme.of(context).colorScheme.onSurfaceVariant;
    final error = Theme.of(context).colorScheme.error;

    return switch (entryType) {
      'delay' => (Icons.schedule_send_outlined, error, 'DELAY REPORTED'),
      'quote_created' => (
          Icons.description_outlined,
          Colors.grey.shade600,
          'QUOTE CREATED',
        ),
      'quote_sent' => (
          Icons.send_outlined,
          Colors.blue,
          'QUOTE SENT FOR REVIEW',
        ),
      'quote_viewed' => (
          Icons.visibility_outlined,
          Colors.indigo,
          'QUOTE VIEWED',
        ),
      'quote_approved' => (
          Icons.check_circle_outline,
          Colors.green,
          'QUOTE APPROVED',
        ),
      'quote_declined' => (
          Icons.cancel_outlined,
          Colors.red,
          'QUOTE DECLINED',
        ),
      'quote_revised' => (
          Icons.edit_note_outlined,
          Colors.orange,
          'QUOTE REVISED',
        ),
      'invoice_generated' => (
          Icons.receipt_long_outlined,
          Colors.purple,
          'INVOICE GENERATED',
        ),
      _ => (
          Icons.circle,
          onSurface,
          (entry['status'] as String? ?? entryType ?? 'EVENT')
              .replaceAll('_', ' ')
              .toUpperCase(),
        ),
    };
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
