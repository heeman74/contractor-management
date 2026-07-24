import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/di/service_locator.dart';
import '../../../../core/routing/route_names.dart';
import '../../../../features/auth/domain/auth_state.dart';
import '../../../../features/auth/presentation/providers/auth_provider.dart';
import '../../../../features/invoices/presentation/providers/invoice_providers.dart';
import '../../../../features/quotes/domain/quote_entity.dart';
import '../../../../features/quotes/presentation/providers/quote_providers.dart';
import '../../../../features/schedule/presentation/widgets/delay_justification_dialog.dart';
import '../../../../shared/models/user_role.dart';
import '../../../../shared/utils/date_format_utils.dart';
import '../../data/job_dao.dart';
import '../../domain/job_entity.dart';
import '../../domain/job_status.dart';
import '../../domain/job_status_colors.dart';
import '../providers/job_providers.dart';
import '../providers/note_providers.dart';
import '../widgets/gps_capture_button.dart';
import '../widgets/notes_tab.dart';
import '../widgets/time_tracked_section.dart';

/// Tabbed job detail screen — Details, Schedule, Notes, and History tabs.
///
/// Streamed from local Drift DB via [jobDetailNotifierProvider] — offline-first.
///
/// Details tab: description, client, contractor, priority, trade, notes.
/// Schedule tab: all booking dates/times, contractor, job site addresses.
/// Notes tab: timestamped field notes with inline attachment thumbnails.
/// History tab: lifecycle transition audit trail from status_history JSONB.
///
/// For Scheduled and In Progress jobs, a "Report Delay" action button allows
/// contractors and admins to log a delay reason with a new ETA date.
class JobDetailScreen extends ConsumerStatefulWidget {
  final String jobId;

  const JobDetailScreen({required this.jobId, super.key});

  @override
  ConsumerState<JobDetailScreen> createState() => _JobDetailScreenState();
}

class _JobDetailScreenState extends ConsumerState<JobDetailScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 4, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final jobAsync = ref.watch(jobDetailNotifierProvider(widget.jobId));
    final authState = ref.watch(authNotifierProvider);
    final currentUserId =
        authState is AuthAuthenticated ? authState.userId : '';

    final companyId =
        authState is AuthAuthenticated ? authState.companyId : '';

    return jobAsync.when(
      data: (job) {
        if (job == null) {
          return Scaffold(
            appBar: AppBar(title: const Text('Job Detail')),
            body: const Center(child: Text('Job not found')),
          );
        }
        return _JobDetailView(
          job: job,
          tabController: _tabController,
          currentUserId: currentUserId,
          companyId: companyId,
        );
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

class _JobDetailView extends ConsumerWidget {
  final JobEntity job;
  final TabController tabController;
  final String currentUserId;
  final String companyId;

  const _JobDetailView({
    required this.job,
    required this.tabController,
    required this.currentUserId,
    required this.companyId,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final statusColor = JobStatusColors.detail(job.jobStatus);
    // Show "Report Delay" button only for Scheduled and In Progress jobs.
    final canReportDelay = job.jobStatus == JobStatus.scheduled ||
        job.jobStatus == JobStatus.inProgress;

    // Watch note count for badge display on the Notes tab.
    final noteCount = ref.watch(noteCountProvider(job.id));

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
          tabs: [
            const Tab(icon: Icon(Icons.info_outline), text: 'Details'),
            const Tab(icon: Icon(Icons.schedule_outlined), text: 'Schedule'),
            Tab(
              icon: Badge(
                isLabelVisible: noteCount > 0,
                label: Text('$noteCount'),
                child: const Icon(Icons.comment_outlined),
              ),
              text: 'Notes',
            ),
            const Tab(icon: Icon(Icons.history_outlined), text: 'History'),
          ],
        ),
      ),
      body: TabBarView(
        controller: tabController,
        children: [
          _DetailsTab(job: job),
          _ScheduleTab(job: job),
          NotesTab(
            jobId: job.id,
            companyId: companyId,
            authorId: currentUserId,
          ),
          _HistoryTab(job: job),
        ],
      ),
      // "Report Delay" floating action button for active jobs only.
      // Rendered as a FAB so it's accessible from any of the three tabs.
      bottomNavigationBar: canReportDelay
          ? _ReportDelayBar(job: job, currentUserId: currentUserId)
          : null,
    );
  }

}

// ─── Report Delay bottom bar ───────────────────────────────────────────────────

/// Bottom action bar shown for Scheduled and In Progress jobs.
///
/// Shows "Report Delay" button with subtitle "Update your ETA" per the
/// contractor-facing UX spec in CONTEXT.md.
class _ReportDelayBar extends StatelessWidget {
  final JobEntity job;
  final String currentUserId;

  const _ReportDelayBar({required this.job, required this.currentUserId});

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: OutlinedButton.icon(
          icon: const Icon(Icons.schedule_send_outlined),
          label: const Text('Report Delay'),
          style: OutlinedButton.styleFrom(
            foregroundColor: Theme.of(context).colorScheme.error,
            side: BorderSide(color: Theme.of(context).colorScheme.error),
            minimumSize: const Size.fromHeight(48),
          ),
          onPressed: () => _reportDelay(context),
        ),
      ),
    );
  }

  Future<void> _reportDelay(BuildContext context) async {
    final jobDao = getIt<JobDao>();

    final confirmed = await DelayJustificationDialog.show(
      context: context,
      jobDao: jobDao,
      job: job,
      currentUserId: currentUserId,
    );

    if (confirmed && context.mounted) {
      final etaFormatted = job.scheduledCompletionDate != null
          ? DateFormatUtils.formatNumericDate(job.scheduledCompletionDate!)
          : 'updated';

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Delay reported — new ETA: $etaFormatted'),
          backgroundColor: Theme.of(context).colorScheme.primary,
        ),
      );
    }
  }
}

// ─── Details tab ──────────────────────────────────────────────────────────────

class _DetailsTab extends ConsumerStatefulWidget {
  final JobEntity job;

  const _DetailsTab({required this.job});

  @override
  ConsumerState<_DetailsTab> createState() => _DetailsTabState();
}

class _DetailsTabState extends ConsumerState<_DetailsTab> {
  bool _isGeneratingInvoice = false;

  @override
  Widget build(BuildContext context) {
    final job = widget.job;
    final authState = ref.watch(authNotifierProvider);
    final isAdmin = authState is AuthAuthenticated &&
        authState.roles.contains(UserRole.admin);

    // Watch quotes for this job (to show Create Quote vs View/Edit Quote)
    final quotesAsync = ref.watch(quoteForJobProvider(job.id));
    final quotes = quotesAsync.maybeWhen(
      data: (q) => q,
      orElse: () => <QuoteEntity>[],
    );
    final hasQuote = quotes.isNotEmpty;

    // Watch invoices for this job (to show View Invoice vs Generate Invoice)
    final invoicesAsync = ref.watch(invoicesForJobProvider(job.id));
    final invoices = invoicesAsync.maybeWhen(data: (i) => i, orElse: () => []);
    final hasInvoice = invoices.isNotEmpty;

    // "Generate Invoice" is shown when: admin, job is complete/invoiced, and no invoice yet
    final canGenerateInvoice = isAdmin &&
        !hasInvoice &&
        (job.jobStatus == JobStatus.complete ||
            job.jobStatus == JobStatus.invoiced);

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
                    value: DateFormatUtils.formatNumericDate(
                        job.scheduledCompletionDate!),
                  ),
                if (job.tags.isNotEmpty)
                  _DetailRow(label: 'Tags', value: job.tags.join(', ')),
              ],
            ),
          ),
        ),

        // ── Quote Section (admin only, non-terminal jobs) ─────────────────
        if (isAdmin &&
            job.jobStatus != JobStatus.cancelled &&
            job.jobStatus != JobStatus.invoiced) ...[
          const SizedBox(height: 12),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(
                        Icons.request_quote_outlined,
                        size: 18,
                        color: Theme.of(context).colorScheme.primary,
                      ),
                      const SizedBox(width: 8),
                      Text(
                        'Quote',
                        style: Theme.of(context)
                            .textTheme
                            .titleMedium
                            ?.copyWith(fontWeight: FontWeight.w600),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  SizedBox(
                    width: double.infinity,
                    child: hasQuote
                        ? OutlinedButton.icon(
                            icon: const Icon(Icons.edit_note_outlined, size: 16),
                            label: const Text('View / Edit Quote'),
                            onPressed: () => context.push(
                              RouteNames.quoteBuilderPath(job.id),
                            ),
                          )
                        : FilledButton.icon(
                            icon: const Icon(Icons.add, size: 16),
                            label: const Text('Create Quote'),
                            onPressed: () => context.push(
                              RouteNames.quoteBuilderPath(job.id),
                            ),
                          ),
                  ),
                ],
              ),
            ),
          ),
        ],

        // ── Invoice Section (admin only) ──────────────────────────────────
        if (isAdmin) ...[
          const SizedBox(height: 12),
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
                        color: Theme.of(context).colorScheme.primary,
                      ),
                      const SizedBox(width: 8),
                      Text(
                        'Invoice',
                        style:
                            Theme.of(context).textTheme.titleMedium?.copyWith(
                                  fontWeight: FontWeight.w600,
                                ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  if (hasInvoice) ...[
                    // View existing invoice
                    Text(
                      invoices.first.invoiceNumber,
                      style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                            fontWeight: FontWeight.w600,
                          ),
                    ),
                    const SizedBox(height: 8),
                    SizedBox(
                      width: double.infinity,
                      child: OutlinedButton.icon(
                        icon: const Icon(Icons.open_in_new, size: 16),
                        label: const Text('View Invoice'),
                        onPressed: () => context.push(
                          RouteNames.invoiceDetailPath(invoices.first.id),
                        ),
                      ),
                    ),
                  ] else if (canGenerateInvoice) ...[
                    Text(
                      'This job is complete. Generate an invoice from the approved quote.',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: Theme.of(context)
                                .colorScheme
                                .onSurfaceVariant,
                          ),
                    ),
                    const SizedBox(height: 12),
                    SizedBox(
                      width: double.infinity,
                      child: FilledButton.icon(
                        icon: _isGeneratingInvoice
                            ? const SizedBox(
                                width: 16,
                                height: 16,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: Colors.white,
                                ),
                              )
                            : const Icon(Icons.receipt_long_outlined),
                        label: const Text('Generate Invoice'),
                        onPressed: _isGeneratingInvoice
                            ? null
                            : () => _generateInvoice(context, job.id),
                      ),
                    ),
                  ] else ...[
                    Text(
                      'No invoice yet. Invoice can be generated once the job is complete.',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: Theme.of(context)
                                .colorScheme
                                .onSurfaceVariant,
                          ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ],

        // ── GPS Location Section ──────────────────────────────────────────
        const SizedBox(height: 12),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Job Site Location',
                  style: Theme.of(context).textTheme.labelLarge?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                ),
                const SizedBox(height: 12),
                GpsCaptureButton(job: job),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Future<void> _generateInvoice(BuildContext context, String jobId) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Generate Invoice'),
        content:
            const Text('Generate an invoice from the approved quote for this job?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Generate'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    setState(() => _isGeneratingInvoice = true);
    try {
      // Call POST /invoices/generate/{jobId}
      final invoiceId = await ref.read(
        generateInvoiceProvider(jobId).future,
      );

      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Invoice generated successfully')),
        );
        context.push(RouteNames.invoiceDetailPath(invoiceId));
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to generate invoice: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _isGeneratingInvoice = false);
    }
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
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        // Booking details placeholder — filled when scheduling data is synced.
        Center(
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 16),
            child: Column(
              children: [
                Icon(
                  Icons.calendar_month_outlined,
                  size: 48,
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
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
        ),
        const Divider(),
        // Time tracking section — shows all clock-in/out sessions for this job.
        TimeTrackedSection(jobId: job.id),
      ],
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
        // Support both status transitions (type: 'status') and delay entries.
        final entryType = entry['type'] as String?;
        final isDelay = entryType == 'delay';
        final status = entry['status'] as String? ?? (isDelay ? 'delay' : '');
        final timestamp = entry['timestamp'] as String? ?? '';
        final reason = entry['reason'] as String?;
        final newEta = entry['new_eta'] as String?;

        return ListTile(
          leading: Icon(
            isDelay ? Icons.schedule_send_outlined : Icons.circle,
            size: isDelay ? 18 : 12,
            color: isDelay
                ? Theme.of(context).colorScheme.error
                : Theme.of(context).colorScheme.onSurfaceVariant,
          ),
          title: Text(
            isDelay ? 'DELAY REPORTED' : status.replaceAll('_', ' ').toUpperCase(),
            style: TextStyle(
              fontWeight: FontWeight.w600,
              color: isDelay ? Theme.of(context).colorScheme.error : null,
            ),
          ),
          subtitle: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(timestamp),
              if (reason != null && reason.isNotEmpty)
                Text(
                  'Reason: $reason',
                  style: const TextStyle(fontStyle: FontStyle.italic),
                ),
              if (newEta != null && newEta.isNotEmpty)
                Text('New ETA: $newEta'),
            ],
          ),
        );
      },
    );
  }
}
