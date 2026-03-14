import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';

import '../../../../features/auth/domain/auth_state.dart';
import '../../../../features/auth/presentation/providers/auth_provider.dart';
import '../../../../shared/models/user_role.dart';
import '../../domain/invoice_entity.dart';
import '../providers/invoice_providers.dart';

/// Invoice detail screen — shows line items, totals, payment status, and PDF download.
///
/// Admin capabilities:
/// - Update payment status (Unpaid → Partially Paid → Paid) via dropdown
/// - Edit invoice (only if not finalized)
/// - Finalize invoice (locks editing)
/// - Download PDF
///
/// Client capabilities:
/// - Read-only payment status display
/// - Download PDF
///
/// Navigated to via [RouteNames.invoiceDetail].
class InvoiceDetailScreen extends ConsumerWidget {
  final String invoiceId;

  const InvoiceDetailScreen({required this.invoiceId, super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final invoiceAsync = ref.watch(invoiceDetailProvider(invoiceId));

    return invoiceAsync.when(
      data: (invoice) {
        if (invoice == null) {
          return Scaffold(
            appBar: AppBar(title: const Text('Invoice')),
            body: const Center(child: Text('Invoice not found.')),
          );
        }
        return _InvoiceDetailContent(invoice: invoice);
      },
      loading: () => Scaffold(
        appBar: AppBar(title: const Text('Invoice')),
        body: const Center(child: CircularProgressIndicator()),
      ),
      error: (e, _) => Scaffold(
        appBar: AppBar(title: const Text('Invoice')),
        body: Center(child: Text('Error loading invoice: $e')),
      ),
    );
  }
}

// ─── Main content ─────────────────────────────────────────────────────────────

class _InvoiceDetailContent extends ConsumerStatefulWidget {
  final InvoiceEntity invoice;

  const _InvoiceDetailContent({required this.invoice});

  @override
  ConsumerState<_InvoiceDetailContent> createState() =>
      _InvoiceDetailContentState();
}

class _InvoiceDetailContentState extends ConsumerState<_InvoiceDetailContent> {
  bool _isDownloading = false;
  bool _isUpdatingStatus = false;
  bool _isFinalizing = false;

  @override
  Widget build(BuildContext context) {
    final authState = ref.watch(authNotifierProvider);
    final isAdmin = authState is AuthAuthenticated &&
        authState.roles.contains(UserRole.admin);

    final invoice = widget.invoice;
    final isFinalized = invoice.finalizedAt != null;

    return Scaffold(
      appBar: AppBar(
        title: Text('Invoice ${invoice.invoiceNumber}'),
        actions: [
          // PDF download button
          _isDownloading
              ? const Padding(
                  padding: EdgeInsets.all(12),
                  child: SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                )
              : IconButton(
                  icon: const Icon(Icons.picture_as_pdf_outlined),
                  tooltip: 'Download PDF',
                  onPressed: () => _downloadPdf(context, invoice.id),
                ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // Header: status badge
          _StatusBadge(status: invoice.status),
          const SizedBox(height: 16),

          // Invoice metadata
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Invoice Details',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                  ),
                  const SizedBox(height: 12),
                  _MetaRow(label: 'Invoice #', value: invoice.invoiceNumber),
                  _MetaRow(
                    label: 'Issued',
                    value: _formatDate(invoice.issuedAt),
                  ),
                  if (invoice.dueDate != null)
                    _MetaRow(
                      label: 'Due Date',
                      value: _formatDate(invoice.dueDate!),
                    ),
                  if (invoice.finalizedAt != null)
                    _MetaRow(
                      label: 'Finalized',
                      value: _formatDate(invoice.finalizedAt!),
                    ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),

          // Line items table
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Line Items',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                  ),
                  const SizedBox(height: 12),
                  if (invoice.lineItems.isEmpty)
                    Text(
                      'No line items.',
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                    )
                  else
                    ...invoice.lineItems.map(
                      (item) => Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: Row(
                          children: [
                            Expanded(
                              flex: 3,
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    item.description,
                                    style: Theme.of(context)
                                        .textTheme
                                        .bodyMedium
                                        ?.copyWith(fontWeight: FontWeight.w500),
                                  ),
                                  Text(
                                    '${item.itemType.toUpperCase()} · ${item.quantity} ${item.unit} @ \$${item.unitPrice.toStringAsFixed(2)}',
                                    style: Theme.of(context)
                                        .textTheme
                                        .bodySmall
                                        ?.copyWith(
                                          color: Theme.of(context)
                                              .colorScheme
                                              .onSurfaceVariant,
                                        ),
                                  ),
                                ],
                              ),
                            ),
                            Text(
                              '\$${item.lineTotal.toStringAsFixed(2)}',
                              style: Theme.of(context)
                                  .textTheme
                                  .bodyMedium
                                  ?.copyWith(fontWeight: FontWeight.w600),
                            ),
                          ],
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),

          // Totals summary card
          _TotalsCard(invoice: invoice),
          const SizedBox(height: 12),

          // Payment status section
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Payment Status',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                  ),
                  const SizedBox(height: 12),
                  if (isAdmin)
                    _AdminPaymentControl(
                      invoice: invoice,
                      isUpdating: _isUpdatingStatus,
                      onStatusChanged: (newStatus) =>
                          _updatePaymentStatus(context, invoice.id, newStatus),
                    )
                  else
                    _StatusBadge(status: invoice.status),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),

          // Admin actions (Edit / Finalize)
          if (isAdmin) ...[
            if (!isFinalized) ...[
              OutlinedButton.icon(
                icon: const Icon(Icons.edit_outlined),
                label: const Text('Edit Invoice'),
                onPressed: () {
                  // Navigate to invoice editor — same pattern as quote builder
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Invoice editing coming soon'),
                    ),
                  );
                },
              ),
              const SizedBox(height: 8),
              FilledButton.icon(
                icon: _isFinalizing
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : const Icon(Icons.lock_outlined),
                label: const Text('Finalize Invoice'),
                onPressed: _isFinalizing
                    ? null
                    : () => _finalizeInvoice(context, invoice.id),
              ),
            ],
            if (isFinalized)
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  color: Colors.green.shade50,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.green.shade300),
                ),
                child: Row(
                  children: [
                    Icon(Icons.check_circle_outline,
                        color: Colors.green.shade700, size: 16),
                    const SizedBox(width: 8),
                    Text(
                      'Invoice finalized — editing is locked',
                      style: TextStyle(
                        color: Colors.green.shade700,
                        fontSize: 13,
                      ),
                    ),
                  ],
                ),
              ),
            const SizedBox(height: 16),
          ],
        ],
      ),
    );
  }

  Future<void> _downloadPdf(BuildContext context, String invoiceId) async {
    setState(() => _isDownloading = true);
    try {
      final bytes = await downloadInvoicePdf(invoiceId);

      // Save to temp directory
      final dir = await getTemporaryDirectory();
      final file = File('${dir.path}/invoice_$invoiceId.pdf');
      await file.writeAsBytes(bytes);

      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('PDF saved to ${file.path}'),
            action: SnackBarAction(
              label: 'OK',
              onPressed: () {},
            ),
          ),
        );
      }
    } on DioException catch (e) {
      if (context.mounted) {
        final status = e.response?.statusCode;
        final msg = status != null
            ? 'Failed to download PDF (HTTP $status)'
            : 'Network error downloading PDF';
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(msg)));
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error downloading PDF: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _isDownloading = false);
    }
  }

  Future<void> _updatePaymentStatus(
    BuildContext context,
    String invoiceId,
    String newStatus,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Update Payment Status'),
        content: Text(
          'Mark invoice as "${_statusLabel(newStatus)}"?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Confirm'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    setState(() => _isUpdatingStatus = true);
    try {
      await updateInvoicePaymentStatus(
        invoiceId: invoiceId,
        status: newStatus,
      );
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content:
                Text('Payment status updated to "${_statusLabel(newStatus)}"'),
          ),
        );
      }
    } on DioException catch (e) {
      if (context.mounted) {
        final status = e.response?.statusCode;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(status != null
                ? 'Failed to update status (HTTP $status)'
                : 'Network error updating status'),
          ),
        );
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _isUpdatingStatus = false);
    }
  }

  Future<void> _finalizeInvoice(BuildContext context, String invoiceId) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Finalize Invoice'),
        content: const Text(
          'Are you sure? Once finalized, the invoice cannot be edited.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Finalize'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    setState(() => _isFinalizing = true);
    try {
      await finalizeInvoice(invoiceId);
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Invoice finalized successfully')),
        );
      }
    } on DioException catch (e) {
      if (context.mounted) {
        final status = e.response?.statusCode;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(status != null
                ? 'Failed to finalize (HTTP $status)'
                : 'Network error finalizing invoice'),
          ),
        );
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _isFinalizing = false);
    }
  }

  String _formatDate(DateTime dt) {
    final months = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
    ];
    return '${months[dt.month - 1]} ${dt.day}, ${dt.year}';
  }

  String _statusLabel(String status) {
    return switch (status) {
      'unpaid' => 'Unpaid',
      'partial' => 'Partially Paid',
      'paid' => 'Paid',
      'overdue' => 'Overdue',
      'cancelled' => 'Cancelled',
      _ => status,
    };
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
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withValues(alpha: 0.5)),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: color,
          fontWeight: FontWeight.w700,
          fontSize: 13,
        ),
      ),
    );
  }

  (String, Color) _statusStyle(String status) {
    return switch (status) {
      'unpaid' => ('Unpaid', Colors.red),
      'partial' => ('Partially Paid', Colors.orange),
      'paid' => ('Paid', Colors.green),
      'overdue' => ('Overdue', Colors.deepOrange),
      'cancelled' => ('Cancelled', Colors.grey),
      _ => (status, Colors.grey),
    };
  }
}

// ─── Admin payment control ────────────────────────────────────────────────────

class _AdminPaymentControl extends StatelessWidget {
  final InvoiceEntity invoice;
  final bool isUpdating;
  final void Function(String) onStatusChanged;

  const _AdminPaymentControl({
    required this.invoice,
    required this.isUpdating,
    required this.onStatusChanged,
  });

  @override
  Widget build(BuildContext context) {
    if (isUpdating) {
      return const Center(child: CircularProgressIndicator());
    }

    const statuses = ['unpaid', 'partial', 'paid', 'overdue', 'cancelled'];
    const labels = {
      'unpaid': 'Unpaid',
      'partial': 'Partially Paid',
      'paid': 'Paid',
      'overdue': 'Overdue',
      'cancelled': 'Cancelled',
    };

    return InputDecorator(
      decoration: const InputDecoration(
        labelText: 'Payment Status',
        border: OutlineInputBorder(),
        isDense: true,
        contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String>(
          value: invoice.status,
          isDense: true,
          isExpanded: true,
          items: statuses
              .map(
                (s) => DropdownMenuItem<String>(
                  value: s,
                  child: Text(labels[s] ?? s),
                ),
              )
              .toList(),
          onChanged: (newStatus) {
            if (newStatus != null && newStatus != invoice.status) {
              onStatusChanged(newStatus);
            }
          },
        ),
      ),
    );
  }
}

// ─── Totals summary card ──────────────────────────────────────────────────────

class _TotalsCard extends StatelessWidget {
  final InvoiceEntity invoice;

  const _TotalsCard({required this.invoice});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Summary',
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 12),
            _TotalRow(
              label: 'Subtotal',
              value: '\$${invoice.subtotal.toStringAsFixed(2)}',
            ),
            if (invoice.discountAmount > 0)
              _TotalRow(
                label: invoice.discountType == 'percentage'
                    ? 'Discount (${invoice.discountValue.toStringAsFixed(0)}%)'
                    : 'Discount',
                value: '-\$${invoice.discountAmount.toStringAsFixed(2)}',
                valueColor: Colors.green,
              ),
            if (invoice.taxAmount > 0)
              _TotalRow(
                label: 'Tax (${invoice.taxRate.toStringAsFixed(1)}%)',
                value: '\$${invoice.taxAmount.toStringAsFixed(2)}',
              ),
            const Divider(),
            _TotalRow(
              label: 'Total',
              value: '\$${invoice.total.toStringAsFixed(2)}',
              isBold: true,
            ),
          ],
        ),
      ),
    );
  }
}

class _TotalRow extends StatelessWidget {
  final String label;
  final String value;
  final bool isBold;
  final Color? valueColor;

  const _TotalRow({
    required this.label,
    required this.value,
    this.isBold = false,
    this.valueColor,
  });

  @override
  Widget build(BuildContext context) {
    final style = isBold
        ? Theme.of(context)
            .textTheme
            .bodyLarge
            ?.copyWith(fontWeight: FontWeight.w700)
        : Theme.of(context).textTheme.bodyMedium;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: style),
          Text(
            value,
            style: style?.copyWith(color: valueColor),
          ),
        ],
      ),
    );
  }
}

// ─── Meta row ─────────────────────────────────────────────────────────────────

class _MetaRow extends StatelessWidget {
  final String label;
  final String value;

  const _MetaRow({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          SizedBox(
            width: 100,
            child: Text(
              label,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: Theme.of(context)
                  .textTheme
                  .bodyMedium
                  ?.copyWith(fontWeight: FontWeight.w500),
            ),
          ),
        ],
      ),
    );
  }
}
