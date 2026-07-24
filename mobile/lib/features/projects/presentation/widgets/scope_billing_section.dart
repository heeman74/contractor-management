import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/database/app_database.dart' show ProjectTask;
import '../../../../core/di/service_locator.dart';
import '../../../../core/network/dio_client.dart';
import '../../../../core/routing/route_names.dart';
import '../../../billing_milestones/presentation/widgets/milestone_list_card.dart';
import '../providers/billing_summary_providers.dart';

/// GC/admin-only billing block for a trade scope.
///
/// Bundles the billing action buttons, milestone list, and the scope's
/// quotes and invoices lists into a single section.
class ScopeBillingSection extends StatelessWidget {
  const ScopeBillingSection({
    required this.scopeId,
    required this.tradeName,
    required this.tasks,
    super.key,
  });

  final String scopeId;
  final String tradeName;
  final List<ProjectTask> tasks;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const SizedBox(height: 8),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  'Billing',
                  style: Theme.of(context)
                      .textTheme
                      .titleMedium
                      ?.copyWith(fontWeight: FontWeight.w600),
                ),
              ),
            ],
          ),
        ),
        const Divider(indent: 16, endIndent: 16),

        // Billing action buttons — Create Quote and Generate Invoice
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
          child: _BillingActionButtons(
            scopeId: scopeId,
            tradeName: tradeName,
            tasks: tasks,
          ),
        ),

        // Milestone list card
        MilestoneListCard(scopeId: scopeId),

        // Scope quotes list
        _ScopeQuotesList(scopeId: scopeId),

        // Scope invoices list
        _ScopeInvoicesList(scopeId: scopeId),

        const SizedBox(height: 24),
      ],
    );
  }
}

/// Row of billing action buttons for the trade scope.
///
/// - "Create Quote": navigates to the quote builder with this scope's ID.
/// - "Generate Invoice": POSTs to generate an invoice for this scope
///   (only visible when the scope has completed tasks per D-05).
class _BillingActionButtons extends StatelessWidget {
  const _BillingActionButtons({
    required this.scopeId,
    required this.tradeName,
    required this.tasks,
  });

  final String scopeId;
  final String tradeName;
  final List<ProjectTask> tasks;

  bool get _hasCompletedTasks =>
      tasks.any((t) => t.status == 'completed' || t.status == 'approved');

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 8,
      runSpacing: 4,
      children: [
        // Create Quote — navigates to the quote builder for this trade scope
        OutlinedButton.icon(
          onPressed: () => context.push(
            RouteNames.quoteBuilderPath(scopeId),
            extra: {'tradeScopeId': scopeId, 'tradeName': tradeName},
          ),
          icon: const Icon(Icons.request_quote, size: 18),
          label: const Text('Create Quote'),
        ),

        // Generate Invoice — only visible when scope has completed tasks (D-05)
        if (_hasCompletedTasks)
          FilledButton.icon(
            onPressed: () => _generateInvoice(context),
            icon: const Icon(Icons.receipt, size: 18),
            label: const Text('Generate Invoice'),
          ),
      ],
    );
  }

  Future<void> _generateInvoice(BuildContext context) async {
    try {
      final dio = getIt<DioClient>();
      final response = await dio.instance.post<Map<String, dynamic>>(
        '/trade-scopes/$scopeId/invoices/generate',
      );

      final data = response.data;
      if (data == null || data['id'] is! String) {
        throw const FormatException(
            'Invalid response — expected invoice id field');
      }

      final invoiceId = data['id'] as String;
      if (context.mounted) {
        context.push(RouteNames.invoiceDetailPath(invoiceId));
      }
    } on DioException catch (e) {
      debugPrint('[BillingActionButtons] Generate invoice error: $e');
      final statusCode = e.response?.statusCode;
      final message = statusCode == 409
          ? 'Invoice already exists for this scope.'
          : 'Failed to generate invoice.';
      if (context.mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(message)));
      }
    } catch (e) {
      debugPrint('[BillingActionButtons] Unexpected error: $e');
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Failed to generate invoice.')),
        );
      }
    }
  }
}

/// List of existing quotes for this trade scope.
///
/// Each row is tappable and navigates to the quote detail screen.
class _ScopeQuotesList extends ConsumerWidget {
  const _ScopeQuotesList({required this.scopeId});

  final String scopeId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final quotesAsync = ref.watch(scopeQuotesProvider(scopeId));

    return quotesAsync.when(
      loading: () => const SizedBox.shrink(),
      error: (_, __) => const SizedBox.shrink(),
      data: (quotes) {
        if (quotes.isEmpty) return const SizedBox.shrink();

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
              child: Text(
                'Quotes (${quotes.length})',
                style: Theme.of(context).textTheme.labelMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
              ),
            ),
            ...quotes.map(
              (quote) => ListTile(
                dense: true,
                leading: const Icon(Icons.request_quote, size: 20),
                title: Text(
                  'Quote — Rev ${quote.revisionNumber}',
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
                subtitle: Text(
                  _statusLabel(quote.status),
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                trailing: const Icon(Icons.chevron_right, size: 18),
                onTap: () =>
                    context.push(RouteNames.quoteDetailPath(quote.id)),
              ),
            ),
          ],
        );
      },
    );
  }

  static String _statusLabel(String status) {
    return switch (status) {
      'draft' => 'Draft',
      'sent' => 'Sent',
      'approved' => 'Approved',
      'declined' => 'Declined',
      _ => status,
    };
  }
}

/// List of existing invoices for this trade scope.
///
/// Each row is tappable and navigates to the invoice detail screen.
class _ScopeInvoicesList extends ConsumerWidget {
  const _ScopeInvoicesList({required this.scopeId});

  final String scopeId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final invoicesAsync = ref.watch(scopeInvoicesProvider(scopeId));

    return invoicesAsync.when(
      loading: () => const SizedBox.shrink(),
      error: (_, __) => const SizedBox.shrink(),
      data: (invoices) {
        if (invoices.isEmpty) return const SizedBox.shrink();

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
              child: Text(
                'Invoices (${invoices.length})',
                style: Theme.of(context).textTheme.labelMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
              ),
            ),
            ...invoices.map(
              (invoice) => ListTile(
                dense: true,
                leading: const Icon(Icons.receipt, size: 20),
                title: Text(
                  invoice.invoiceNumber,
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
                subtitle: Text(
                  _statusLabel(invoice.status),
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                trailing: const Icon(Icons.chevron_right, size: 18),
                onTap: () =>
                    context.push(RouteNames.invoiceDetailPath(invoice.id)),
              ),
            ),
          ],
        );
      },
    );
  }

  static String _statusLabel(String status) {
    return switch (status) {
      'unpaid' => 'Unpaid',
      'partial' => 'Partially paid',
      'paid' => 'Paid',
      'overdue' => 'Overdue',
      'cancelled' => 'Cancelled',
      _ => status,
    };
  }
}
