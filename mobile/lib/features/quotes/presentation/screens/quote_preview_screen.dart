import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/network/dio_client.dart';
import '../../../../core/di/service_locator.dart';
import '../../domain/quote_entity.dart';
import '../providers/quote_providers.dart';
import '../widgets/quote_summary_card.dart';

/// Admin preview screen — shows the quote as the client will see it.
///
/// Read-only layout matching [QuoteDetailScreen] format.
/// Primary action: "Send to Client" — calls POST /quotes/{id}/send via API.
///
/// Navigated to via [RouteNames.quotePreviewPath(jobId)] from [QuoteBuilderScreen].
class QuotePreviewScreen extends ConsumerWidget {
  final String jobId;

  const QuotePreviewScreen({super.key, required this.jobId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final quotesAsync = ref.watch(quoteForJobProvider(jobId));

    return quotesAsync.when(
      data: (quotes) {
        if (quotes.isEmpty) {
          return Scaffold(
            appBar: AppBar(title: const Text('Quote Preview')),
            body: const Center(child: Text('No draft quote found. Save a draft first.')),
          );
        }
        final quote = quotes.first; // Latest revision
        return _PreviewContent(quote: quote, jobId: jobId);
      },
      loading: () => Scaffold(
        appBar: AppBar(title: const Text('Quote Preview')),
        body: const Center(child: CircularProgressIndicator()),
      ),
      error: (e, _) => Scaffold(
        appBar: AppBar(title: const Text('Quote Preview')),
        body: Center(child: Text('Error: $e')),
      ),
    );
  }
}

class _PreviewContent extends ConsumerStatefulWidget {
  final QuoteEntity quote;
  final String jobId;

  const _PreviewContent({required this.quote, required this.jobId});

  @override
  ConsumerState<_PreviewContent> createState() => _PreviewContentState();
}

class _PreviewContentState extends ConsumerState<_PreviewContent> {
  bool _isSending = false;

  @override
  Widget build(BuildContext context) {
    final quote = widget.quote;
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: Text('Preview — Quote v${quote.revisionNumber}'),
        backgroundColor: theme.colorScheme.surfaceContainerHighest,
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: FilledButton.icon(
              onPressed: _isSending ? null : _sendToClient,
              icon: _isSending
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.send_outlined),
              label: const Text('Send to Client'),
            ),
          ),
        ],
      ),
      body: _QuoteReadOnlyBody(quote: quote, isPreview: true),
    );
  }

  Future<void> _sendToClient() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Send Quote'),
        content: Text(
          'Send Quote v${widget.quote.revisionNumber} to the client?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Send'),
          ),
        ],
      ),
    );

    if (confirmed != true || !mounted) return;

    setState(() => _isSending = true);

    try {
      final dioClient = getIt<DioClient>();
      await dioClient.instance.post('/quotes/${widget.quote.id}/send', data: {});

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Quote sent to client'),
            behavior: SnackBarBehavior.floating,
          ),
        );
        Navigator.pop(context); // Go back to job detail
        Navigator.pop(context); // Pop builder screen too
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to send quote: $e'),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isSending = false);
    }
  }
}

class _QuoteReadOnlyBody extends StatelessWidget {
  final QuoteEntity quote;
  final bool isPreview;

  const _QuoteReadOnlyBody({required this.quote, required this.isPreview});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        // Preview mode banner
        if (isPreview)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            margin: const EdgeInsets.only(bottom: 12),
            decoration: BoxDecoration(
              color: Colors.amber.shade50,
              border: Border.all(color: Colors.amber.shade300),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(
              children: [
                Icon(Icons.info_outline, color: Colors.amber.shade800, size: 18),
                const SizedBox(width: 8),
                Text(
                  'Preview mode — this is how the client will see the quote',
                  style: TextStyle(
                    color: Colors.amber.shade900,
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ),

        // Quote title
        Text(
          'Quote v${quote.revisionNumber}',
          style: theme.textTheme.headlineSmall,
        ),
        const SizedBox(height: 4),
        _StatusBadge(status: quote.status),

        // Expiry date
        if (quote.expiryDate != null) ...[
          const SizedBox(height: 8),
          Row(
            children: [
              Icon(
                Icons.schedule,
                size: 16,
                color: quote.isExpired
                    ? Colors.red
                    : theme.colorScheme.onSurfaceVariant,
              ),
              const SizedBox(width: 4),
              Text(
                quote.isExpired
                    ? 'Expired on ${_formatDate(quote.expiryDate!)}'
                    : 'Valid until ${_formatDate(quote.expiryDate!)}',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: quote.isExpired ? Colors.red : null,
                  fontWeight:
                      quote.isExpired ? FontWeight.bold : null,
                ),
              ),
            ],
          ),
        ],

        // Expired banner
        if (quote.isExpired) ...[
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              color: Colors.orange.shade50,
              border: Border.all(color: Colors.orange.shade300),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(
              children: [
                Icon(Icons.warning_amber, color: Colors.orange.shade700),
                const SizedBox(width: 8),
                Text(
                  'This quote has expired',
                  style: TextStyle(
                    color: Colors.orange.shade800,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        ],

        const SizedBox(height: 16),

        // Line items table
        Text('Line Items', style: theme.textTheme.titleMedium),
        const SizedBox(height: 8),
        Card(
          child: _LineItemsTable(quote: quote),
        ),

        const SizedBox(height: 8),

        // Summary card
        QuoteSummaryCard(
          subtotal: quote.subtotal,
          discountAmount: quote.discountAmount,
          discountType: quote.discountType ?? 'none',
          discountValue: quote.discountValue,
          taxRate: quote.taxRate,
          taxAmount: quote.taxAmount,
          total: quote.total,
        ),

        // Admin notes
        if (quote.adminNotes != null && quote.adminNotes!.isNotEmpty) ...[
          const SizedBox(height: 8),
          Text('Notes', style: theme.textTheme.titleMedium),
          const SizedBox(height: 4),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Text(quote.adminNotes!),
            ),
          ),
        ],
      ],
    );
  }

  String _formatDate(DateTime dt) {
    final months = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'
    ];
    return '${months[dt.month - 1]} ${dt.day}, ${dt.year}';
  }
}

// ─── Line items table ─────────────────────────────────────────────────────────

class _LineItemsTable extends StatelessWidget {
  final QuoteEntity quote;

  const _LineItemsTable({required this.quote});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Table(
      columnWidths: const {
        0: FlexColumnWidth(3),
        1: IntrinsicColumnWidth(),
        2: IntrinsicColumnWidth(),
        3: IntrinsicColumnWidth(),
      },
      border: TableBorder(
        horizontalInside: BorderSide(
          color: theme.colorScheme.outlineVariant,
          width: 0.5,
        ),
      ),
      children: [
        // Header row
        TableRow(
          decoration: BoxDecoration(
            color: theme.colorScheme.surfaceContainerHighest,
          ),
          children: [
            _HeaderCell('Description'),
            _HeaderCell('Type'),
            _HeaderCell('Qty × Unit'),
            _HeaderCell('Subtotal'),
          ],
        ),
        // Data rows
        for (final item in quote.lineItems)
          TableRow(
            children: [
              _DataCell(item.description),
              _DataCell(
                item.itemType == 'labor' ? 'Labor' : 'Material',
                color: item.itemType == 'labor'
                    ? Colors.blue.shade700
                    : Colors.green.shade700,
              ),
              _DataCell(
                  '${_fmtNum(item.quantity)} ${item.unit} @ \$${_fmtMoney(item.unitPrice)}'),
              _DataCell('\$${_fmtMoney(item.lineTotal)}'),
            ],
          ),
      ],
    );
  }

  String _fmtNum(double v) =>
      v == v.truncate() ? v.truncate().toString() : v.toStringAsFixed(2);

  String _fmtMoney(double v) => v.toStringAsFixed(2);
}

class _HeaderCell extends StatelessWidget {
  final String text;

  const _HeaderCell(this.text);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      child: Text(
        text,
        style: Theme.of(context).textTheme.bodySmall?.copyWith(
              fontWeight: FontWeight.bold,
            ),
      ),
    );
  }
}

class _DataCell extends StatelessWidget {
  final String text;
  final Color? color;

  const _DataCell(this.text, {this.color});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      child: Text(
        text,
        style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: color),
      ),
    );
  }
}

// ─── Status badge ─────────────────────────────────────────────────────────────

class _StatusBadge extends StatelessWidget {
  final String status;

  const _StatusBadge({required this.status});

  @override
  Widget build(BuildContext context) {
    final (label, color) = _statusStyle(status);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.4)),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: color,
          fontWeight: FontWeight.w600,
          fontSize: 12,
        ),
      ),
    );
  }

  (String, Color) _statusStyle(String status) => switch (status) {
        'draft' => ('Draft', Colors.grey),
        'sent' => ('Sent', Colors.blue),
        'viewed' => ('Viewed', Colors.blue),
        'approved' => ('Approved', Colors.green),
        'declined' => ('Declined', Colors.red),
        'expired' => ('Expired', Colors.orange),
        'revised' => ('Revised', Colors.purple),
        _ => (status, Colors.grey),
      };
}
