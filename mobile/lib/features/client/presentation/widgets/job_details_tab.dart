import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/routing/route_names.dart';
import '../../../../shared/utils/date_format_utils.dart';
import '../../../invoices/domain/invoice_entity.dart';
import '../../../invoices/domain/invoice_status_presentation.dart';
import '../../../invoices/presentation/providers/invoice_providers.dart';
import '../../../jobs/domain/job_entity.dart';
import '../../../jobs/domain/job_status.dart';

/// Read-only "Details" tab for the client job detail screen.
///
/// Shows core job fields and, when an invoice exists, a read-only invoice
/// summary. Pricing information is intentionally hidden from the client portal.
class JobDetailsTab extends ConsumerWidget {
  const JobDetailsTab({required this.job, required this.jobId, super.key});

  final JobEntity job;
  final String jobId;

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
                    value: DateFormatUtils.formatLongDate(
                        job.scheduledCompletionDate!),
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
          data: (invoices) => invoices.isEmpty
              ? const SizedBox.shrink()
              : _InvoiceSummaryCard(invoice: invoices.first),
          loading: () => const SizedBox.shrink(),
          error: (_, __) => const SizedBox.shrink(),
        ),
      ],
    );
  }
}

/// Read-only invoice summary shown in the client's Details tab.
class _InvoiceSummaryCard extends StatelessWidget {
  const _InvoiceSummaryCard({required this.invoice});

  final InvoiceEntity invoice;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final statusColor = InvoiceStatusPresentation.color(invoice.status);
    final statusLabel = InvoiceStatusPresentation.label(invoice.status);

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
                    Icon(Icons.receipt_outlined,
                        size: 18, color: theme.colorScheme.primary),
                    const SizedBox(width: 8),
                    Text(
                      'Invoice',
                      style: theme.textTheme.titleMedium
                          ?.copyWith(fontWeight: FontWeight.w600),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      invoice.invoiceNumber,
                      style: theme.textTheme.bodyLarge
                          ?.copyWith(fontWeight: FontWeight.w600),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                        color: statusColor.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                            color: statusColor.withValues(alpha: 0.4)),
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
  }
}

class _DetailRow extends StatelessWidget {
  const _DetailRow({required this.label, required this.value});

  final String label;
  final String value;

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
