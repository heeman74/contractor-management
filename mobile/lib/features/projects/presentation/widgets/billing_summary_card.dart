import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers/billing_summary_providers.dart';

/// Type of billing summary to display.
enum BillingSummaryType { quote, invoice }

/// Project-level billing aggregation card.
///
/// For [BillingSummaryType.quote]: watches [projectQuoteSummaryProvider] and
/// renders a per-trade breakdown table with quote counts and subtotals, plus
/// a grand total row.
///
/// For [BillingSummaryType.invoice]: watches [projectInvoiceSummaryProvider]
/// and renders a per-trade breakdown with billed / paid / outstanding columns.
/// Outstanding amounts > 0 are shown in red.
///
/// Loading state: progress indicator.
/// Error state: error message with a retry button.
class BillingSummaryCard extends ConsumerWidget {
  const BillingSummaryCard({
    required this.projectId,
    required this.type,
    super.key,
  });

  final String projectId;
  final BillingSummaryType type;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (type == BillingSummaryType.quote) {
      return _QuoteSummaryCard(projectId: projectId, ref: ref);
    } else {
      return _InvoiceSummaryCard(projectId: projectId, ref: ref);
    }
  }
}

// ─── Quote summary ─────────────────────────────────────────────────────────────

class _QuoteSummaryCard extends ConsumerWidget {
  const _QuoteSummaryCard({required this.projectId, required this.ref});

  final String projectId;
  // ignore: unused_field
  final WidgetRef ref;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final summaryAsync = ref.watch(projectQuoteSummaryProvider(projectId));

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      elevation: 1,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
            child: Text(
              'Quote Summary',
              style: Theme.of(context).textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
            ),
          ),
          const Divider(height: 1, indent: 16, endIndent: 16),
          summaryAsync.when(
            loading: () => const Padding(
              padding: EdgeInsets.all(16),
              child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
            ),
            error: (error, _) => _ErrorRetry(
              onRetry: () =>
                  ref.invalidate(projectQuoteSummaryProvider(projectId)),
            ),
            data: (data) => _QuoteSummaryBody(data: data),
          ),
        ],
      ),
    );
  }
}

class _QuoteSummaryBody extends StatelessWidget {
  const _QuoteSummaryBody({required this.data});

  final Map<String, dynamic> data;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final colorScheme = Theme.of(context).colorScheme;

    final scopes = data['scopes'];
    final grandTotal = (data['grand_total'] as num?)?.toDouble() ?? 0.0;

    if (scopes is! List || scopes.isEmpty) {
      return Padding(
        padding: const EdgeInsets.all(16),
        child: Text(
          'No quotes yet for this project.',
          style: textTheme.bodySmall?.copyWith(
            color: colorScheme.onSurface.withValues(alpha: 0.5),
          ),
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        children: [
          // Header row
          Row(
            children: [
              Expanded(
                flex: 3,
                child: Text('Trade',
                    style: textTheme.labelSmall
                        ?.copyWith(fontWeight: FontWeight.w600)),
              ),
              Expanded(
                child: Text('Quotes',
                    textAlign: TextAlign.center,
                    style: textTheme.labelSmall
                        ?.copyWith(fontWeight: FontWeight.w600)),
              ),
              Expanded(
                flex: 2,
                child: Text('Subtotal',
                    textAlign: TextAlign.end,
                    style: textTheme.labelSmall
                        ?.copyWith(fontWeight: FontWeight.w600)),
              ),
            ],
          ),
          const Divider(height: 12),

          // Scope rows
          ...scopes.map((scope) {
            if (scope is! Map) return const SizedBox.shrink();
            final tradeName = scope['trade_name'] as String? ?? 'Unknown';
            final quoteCount = (scope['quote_count'] as num?)?.toInt() ?? 0;
            final subtotal = (scope['subtotal'] as num?)?.toDouble() ?? 0.0;

            return Padding(
              padding: const EdgeInsets.symmetric(vertical: 3),
              child: Row(
                children: [
                  Expanded(
                      flex: 3,
                      child: Text(tradeName,
                          style: textTheme.bodySmall)),
                  Expanded(
                    child: Text(
                      '$quoteCount',
                      textAlign: TextAlign.center,
                      style: textTheme.bodySmall,
                    ),
                  ),
                  Expanded(
                    flex: 2,
                    child: Text(
                      _formatCurrency(subtotal),
                      textAlign: TextAlign.end,
                      style: textTheme.bodySmall,
                    ),
                  ),
                ],
              ),
            );
          }),

          const Divider(height: 12),

          // Grand total row
          Row(
            children: [
              const Expanded(
                  flex: 3, child: Text('Grand Total')),
              const Expanded(child: SizedBox()),
              Expanded(
                flex: 2,
                child: Text(
                  _formatCurrency(grandTotal),
                  textAlign: TextAlign.end,
                  style: textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                    color: colorScheme.primary,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  static String _formatCurrency(double amount) {
    return '\$${amount.toStringAsFixed(2)}';
  }
}

// ─── Invoice summary ───────────────────────────────────────────────────────────

class _InvoiceSummaryCard extends ConsumerWidget {
  const _InvoiceSummaryCard({required this.projectId, required this.ref});

  final String projectId;
  // ignore: unused_field
  final WidgetRef ref;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final summaryAsync = ref.watch(projectInvoiceSummaryProvider(projectId));

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      elevation: 1,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
            child: Text(
              'Invoice Summary',
              style: Theme.of(context).textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
            ),
          ),
          const Divider(height: 1, indent: 16, endIndent: 16),
          summaryAsync.when(
            loading: () => const Padding(
              padding: EdgeInsets.all(16),
              child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
            ),
            error: (error, _) => _ErrorRetry(
              onRetry: () =>
                  ref.invalidate(projectInvoiceSummaryProvider(projectId)),
            ),
            data: (data) => _InvoiceSummaryBody(data: data),
          ),
        ],
      ),
    );
  }
}

class _InvoiceSummaryBody extends StatelessWidget {
  const _InvoiceSummaryBody({required this.data});

  final Map<String, dynamic> data;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final colorScheme = Theme.of(context).colorScheme;

    final scopes = data['scopes'];
    final grandTotal = data['grand_total'];
    final gtBilled =
        (grandTotal is Map ? (grandTotal['billed'] as num?)?.toDouble() : null) ??
            0.0;
    final gtPaid =
        (grandTotal is Map ? (grandTotal['paid'] as num?)?.toDouble() : null) ??
            0.0;
    final gtOutstanding =
        (grandTotal is Map
            ? (grandTotal['outstanding'] as num?)?.toDouble()
            : null) ??
            0.0;

    if (scopes is! List || scopes.isEmpty) {
      return Padding(
        padding: const EdgeInsets.all(16),
        child: Text(
          'No invoices yet for this project.',
          style: textTheme.bodySmall?.copyWith(
            color: colorScheme.onSurface.withValues(alpha: 0.5),
          ),
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        children: [
          // Header row
          Row(
            children: [
              Expanded(
                flex: 3,
                child: Text('Trade',
                    style: textTheme.labelSmall
                        ?.copyWith(fontWeight: FontWeight.w600)),
              ),
              Expanded(
                flex: 2,
                child: Text('Billed',
                    textAlign: TextAlign.end,
                    style: textTheme.labelSmall
                        ?.copyWith(fontWeight: FontWeight.w600)),
              ),
              Expanded(
                flex: 2,
                child: Text('Paid',
                    textAlign: TextAlign.end,
                    style: textTheme.labelSmall
                        ?.copyWith(fontWeight: FontWeight.w600)),
              ),
              Expanded(
                flex: 2,
                child: Text('Owed',
                    textAlign: TextAlign.end,
                    style: textTheme.labelSmall
                        ?.copyWith(fontWeight: FontWeight.w600)),
              ),
            ],
          ),
          const Divider(height: 12),

          // Scope rows
          ...scopes.map((scope) {
            if (scope is! Map) return const SizedBox.shrink();
            final tradeName = scope['trade_name'] as String? ?? 'Unknown';
            final billed = (scope['billed'] as num?)?.toDouble() ?? 0.0;
            final paid = (scope['paid'] as num?)?.toDouble() ?? 0.0;
            final outstanding =
                (scope['outstanding'] as num?)?.toDouble() ?? 0.0;

            return Padding(
              padding: const EdgeInsets.symmetric(vertical: 3),
              child: Row(
                children: [
                  Expanded(
                      flex: 3,
                      child: Text(tradeName,
                          style: textTheme.bodySmall)),
                  Expanded(
                    flex: 2,
                    child: Text(_formatCurrency(billed),
                        textAlign: TextAlign.end,
                        style: textTheme.bodySmall),
                  ),
                  Expanded(
                    flex: 2,
                    child: Text(_formatCurrency(paid),
                        textAlign: TextAlign.end,
                        style: textTheme.bodySmall),
                  ),
                  Expanded(
                    flex: 2,
                    child: Text(
                      _formatCurrency(outstanding),
                      textAlign: TextAlign.end,
                      style: textTheme.bodySmall?.copyWith(
                        color: outstanding > 0
                            ? colorScheme.error
                            : colorScheme.onSurface,
                        fontWeight: outstanding > 0
                            ? FontWeight.w600
                            : FontWeight.normal,
                      ),
                    ),
                  ),
                ],
              ),
            );
          }),

          const Divider(height: 12),

          // Grand total row
          Row(
            children: [
              const Expanded(flex: 3, child: Text('Total')),
              Expanded(
                flex: 2,
                child: Text(
                  _formatCurrency(gtBilled),
                  textAlign: TextAlign.end,
                  style: textTheme.bodyMedium
                      ?.copyWith(fontWeight: FontWeight.w700),
                ),
              ),
              Expanded(
                flex: 2,
                child: Text(
                  _formatCurrency(gtPaid),
                  textAlign: TextAlign.end,
                  style: textTheme.bodyMedium
                      ?.copyWith(fontWeight: FontWeight.w700),
                ),
              ),
              Expanded(
                flex: 2,
                child: Text(
                  _formatCurrency(gtOutstanding),
                  textAlign: TextAlign.end,
                  style: textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                    color: gtOutstanding > 0
                        ? colorScheme.error
                        : colorScheme.onSurface,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  static String _formatCurrency(double amount) {
    return '\$${amount.toStringAsFixed(2)}';
  }
}

// ─── Shared error/retry widget ─────────────────────────────────────────────────

class _ErrorRetry extends StatelessWidget {
  const _ErrorRetry({required this.onRetry});

  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            'Could not load billing summary.',
            style: TextStyle(color: Theme.of(context).colorScheme.error),
          ),
          const SizedBox(height: 8),
          TextButton.icon(
            onPressed: onRetry,
            icon: const Icon(Icons.refresh),
            label: const Text('Retry'),
          ),
        ],
      ),
    );
  }
}
