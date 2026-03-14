import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/di/service_locator.dart';
import '../../../../core/network/dio_client.dart';
import '../../domain/quote_entity.dart';
import '../providers/quote_providers.dart';
import '../widgets/quote_summary_card.dart';

/// Client-facing quote detail screen.
///
/// Shows quote status, line items table, totals, admin notes, and expiry.
/// When status is 'sent' or 'viewed' and quote is not expired:
///   - "Approve" button with confirmation dialog
///   - "Decline" button with reason picker bottom sheet
///
/// Read receipt: first client view triggers a GET call to the backend which
/// records the viewed_at timestamp (per backend Pattern 4 research).
class QuoteDetailScreen extends ConsumerWidget {
  final String quoteId;

  const QuoteDetailScreen({super.key, required this.quoteId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final quoteAsync = ref.watch(quoteByIdProvider(quoteId));

    return quoteAsync.when(
      data: (quote) {
        if (quote == null) {
          return Scaffold(
            appBar: AppBar(title: const Text('Quote')),
            body: const Center(child: Text('Quote not found.')),
          );
        }
        return _QuoteDetailContent(quote: quote);
      },
      loading: () => Scaffold(
        appBar: AppBar(title: const Text('Quote')),
        body: const Center(child: CircularProgressIndicator()),
      ),
      error: (e, _) => Scaffold(
        appBar: AppBar(title: const Text('Quote')),
        body: Center(child: Text('Error loading quote: $e')),
      ),
    );
  }
}

class _QuoteDetailContent extends ConsumerStatefulWidget {
  final QuoteEntity quote;

  const _QuoteDetailContent({required this.quote});

  @override
  ConsumerState<_QuoteDetailContent> createState() =>
      _QuoteDetailContentState();
}

class _QuoteDetailContentState extends ConsumerState<_QuoteDetailContent> {
  bool _isActing = false;
  bool _readReceiptSent = false;

  @override
  void initState() {
    super.initState();
    // Trigger read receipt on first view if status is 'sent'.
    // GET /quotes/{id} is called once per screen lifecycle — backend records viewed_at.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _triggerReadReceipt();
    });
  }

  @override
  Widget build(BuildContext context) {
    final quote = widget.quote;
    final canAct = quote.isPending && !quote.isExpired;

    return Scaffold(
      appBar: AppBar(
        title: Text('Quote v${quote.revisionNumber}'),
      ),
      body: Column(
        children: [
          Expanded(
            child: _QuoteClientBody(quote: quote),
          ),
          // Action buttons
          if (canAct)
            _ActionBar(
              quote: quote,
              isActing: _isActing,
              onApprove: _approve,
              onDecline: _decline,
            ),
        ],
      ),
    );
  }

  // ─── Read receipt ────────────────────────────────────────────────────────────

  Future<void> _triggerReadReceipt() async {
    if (_readReceiptSent) return;
    if (widget.quote.status != 'sent') return;
    _readReceiptSent = true;

    try {
      final dioClient = getIt<DioClient>();
      // GET call records viewed_at on backend — no response parsing needed.
      await dioClient.instance.get('/quotes/${widget.quote.id}');
    } catch (e) {
      // Non-fatal: read receipt failure doesn't block the client view.
      debugPrint('[QuoteDetailScreen] Read receipt error: $e');
    }
  }

  // ─── Approve ─────────────────────────────────────────────────────────────────

  Future<void> _approve() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Approve Quote'),
        content: const Text(
          'By approving this quote, you agree to the terms and pricing shown. '
          'The contractor will be notified to proceed.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Approve'),
          ),
        ],
      ),
    );

    if (confirmed != true || !mounted) return;

    setState(() => _isActing = true);

    try {
      final dioClient = getIt<DioClient>();
      await dioClient.instance
          .post('/quotes/${widget.quote.id}/approve', data: {});

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Quote approved — the contractor has been notified'),
            behavior: SnackBarBehavior.floating,
          ),
        );
        Navigator.pop(context);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to approve: $e'),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isActing = false);
    }
  }

  // ─── Decline ─────────────────────────────────────────────────────────────────

  Future<void> _decline() async {
    final result = await showModalBottomSheet<_DeclineResult>(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => const _DeclineBottomSheet(),
    );

    if (result == null || !mounted) return;

    setState(() => _isActing = true);

    try {
      final dioClient = getIt<DioClient>();
      await dioClient.instance.post(
        '/quotes/${widget.quote.id}/decline',
        data: {
          'reason': result.reason,
          if (result.detail.isNotEmpty) 'detail': result.detail,
        },
      );

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Quote declined'),
            behavior: SnackBarBehavior.floating,
          ),
        );
        Navigator.pop(context);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to decline: $e'),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isActing = false);
    }
  }
}

// ─── Client quote body ────────────────────────────────────────────────────────

class _QuoteClientBody extends StatelessWidget {
  final QuoteEntity quote;

  const _QuoteClientBody({required this.quote});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        // Quote title + status
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
                  fontWeight: quote.isExpired ? FontWeight.bold : null,
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
                  'This quote has expired and cannot be approved',
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

        // Declined reason (if applicable)
        if (quote.isDeclined && quote.declineReason != null) ...[
          const SizedBox(height: 8),
          Text('Decline Reason', style: theme.textTheme.titleMedium),
          const SizedBox(height: 4),
          Card(
            color: Colors.red.shade50,
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    _declineLabel(quote.declineReason!),
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                  if (quote.declineDetail != null &&
                      quote.declineDetail!.isNotEmpty)
                    Text(quote.declineDetail!),
                ],
              ),
            ),
          ),
        ],

        const SizedBox(height: 80), // Space for action bar
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

  String _declineLabel(String reason) => switch (reason) {
        'too_expensive' => 'Too expensive',
        'wrong_scope' => 'Wrong scope',
        'changed_mind' => 'Changed mind',
        'other' => 'Other',
        _ => reason,
      };
}

// ─── Action bar ───────────────────────────────────────────────────────────────

class _ActionBar extends StatelessWidget {
  final QuoteEntity quote;
  final bool isActing;
  final VoidCallback onApprove;
  final VoidCallback onDecline;

  const _ActionBar({
    required this.quote,
    required this.isActing,
    required this.onApprove,
    required this.onDecline,
  });

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Row(
          children: [
            Expanded(
              child: OutlinedButton(
                onPressed: isActing ? null : onDecline,
                style: OutlinedButton.styleFrom(
                  foregroundColor: Colors.red,
                  side: const BorderSide(color: Colors.red),
                ),
                child: const Text('Decline'),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              flex: 2,
              child: FilledButton(
                onPressed: isActing ? null : onApprove,
                child: isActing
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : const Text('Approve Quote'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─── Decline bottom sheet ─────────────────────────────────────────────────────

class _DeclineResult {
  final String reason;
  final String detail;

  const _DeclineResult({required this.reason, required this.detail});
}

const _kDeclineReasons = [
  ('too_expensive', 'Too expensive'),
  ('wrong_scope', 'Wrong scope of work'),
  ('changed_mind', 'Changed my mind'),
  ('other', 'Other'),
];

class _DeclineBottomSheet extends StatefulWidget {
  const _DeclineBottomSheet();

  @override
  State<_DeclineBottomSheet> createState() => _DeclineBottomSheetState();
}

class _DeclineBottomSheetState extends State<_DeclineBottomSheet> {
  String? _selectedReason;
  final _detailController = TextEditingController();

  @override
  void dispose() {
    _detailController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
      ),
      child: Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: theme.colorScheme.surface,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Why are you declining?', style: theme.textTheme.titleLarge),
            const SizedBox(height: 16),
            // Reason picker
            for (final (value, label) in _kDeclineReasons)
              RadioListTile<String>(
                value: value,
                groupValue: _selectedReason,
                title: Text(label),
                contentPadding: EdgeInsets.zero,
                onChanged: (v) => setState(() => _selectedReason = v),
              ),
            const SizedBox(height: 8),
            // Optional detail text
            TextField(
              controller: _detailController,
              decoration: const InputDecoration(
                labelText: 'Additional details (optional)',
                hintText: 'Tell us more...',
                border: OutlineInputBorder(),
              ),
              maxLines: 3,
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: const Text('Cancel'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: FilledButton(
                    onPressed: _selectedReason == null
                        ? null
                        : () => Navigator.pop(
                              context,
                              _DeclineResult(
                                reason: _selectedReason!,
                                detail: _detailController.text.trim(),
                              ),
                            ),
                    style: FilledButton.styleFrom(
                      backgroundColor: Colors.red,
                    ),
                    child: const Text('Decline Quote'),
                  ),
                ),
              ],
            ),
          ],
        ),
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
