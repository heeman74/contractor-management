import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../../core/di/service_locator.dart';
import '../../../../core/routing/route_names.dart';
import '../../../contracts/domain/contract.dart';
import '../../../contracts/presentation/providers/contract_providers.dart';
import '../../../quotes/data/quote_dao.dart';
import '../../../quotes/domain/quote_entity.dart';
import '../../../quotes/domain/quote_status_presentation.dart';

/// Client-facing quote tab inside the job detail screen.
///
/// Streams the latest sent/viewed/approved/declined quote for this job.
/// Shows a "View Quote" button that navigates to [QuoteDetailScreen].
/// When no quote exists yet, shows a placeholder message.
class JobQuoteTab extends ConsumerWidget {
  const JobQuoteTab({required this.jobId, this.contractId, super.key});

  final String jobId;
  final String? contractId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final quoteDao = getIt<QuoteDao>();

    return StreamBuilder<List<QuoteEntity>>(
      stream: quoteDao.watchQuotesForJob(jobId),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }

        final quotes = snapshot.data ?? [];
        // Show only quotes visible to client: not drafts
        final clientQuotes = quotes
            .where((q) => q.status != 'draft')
            .toList();

        // Contract card (shown when a contract id is known for this job).
        final contractCard = contractId == null
            ? const SizedBox.shrink()
            : _ContractCard(contractId: contractId!);

        if (clientQuotes.isEmpty) {
          if (contractId != null) {
            return ListView(
              padding: const EdgeInsets.all(16),
              children: [contractCard],
            );
          }
          return Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.description_outlined,
                    size: 48,
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                  const SizedBox(height: 12),
                  Text(
                    'No quote yet',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Your contractor will send a quote for your approval.',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            ),
          );
        }

        final quote = clientQuotes.first;
        final statusColor = QuoteStatusPresentation.color(quote.status);

        return ListView(
          padding: const EdgeInsets.all(16),
          children: [
            if (contractId != null) ...[
              contractCard,
              const SizedBox(height: 8),
            ],
            Card(
              child: ListTile(
                leading: Icon(Icons.description, color: statusColor),
                title: Text('Quote v${quote.revisionNumber}'),
                subtitle: Text(
                  QuoteStatusPresentation.label(quote.status),
                  style: TextStyle(color: statusColor),
                ),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => context.push(
                  RouteNames.quoteDetailPath(quote.id),
                ),
              ),
            ),
            if (quote.total > 0) ...[
              const SizedBox(height: 8),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        'Total',
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      Text(
                        '\$${quote.total.toStringAsFixed(2)}',
                        style:
                            Theme.of(context).textTheme.titleMedium?.copyWith(
                                  fontWeight: FontWeight.bold,
                                ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
            if (quote.isPending && !quote.isExpired) ...[
              const SizedBox(height: 16),
              FilledButton.icon(
                onPressed: () => context.push(
                  RouteNames.quoteDetailPath(quote.id),
                ),
                icon: const Icon(Icons.check_circle_outline),
                label: const Text('Review & Approve Quote'),
              ),
            ],
          ],
        );
      },
    );
  }
}

// ─── Contract card ────────────────────────────────────────────────────────────

/// Client-facing contract card shown in the Quote tab when a contract id is
/// known for the job.
///
/// - `sent`/`viewed`  → "Review & Sign" opens the embedded ceremony WebView.
/// - `signed`         → "View signed contract" opens the signed PDF.
/// - other statuses   → status only (no action).
///
/// Watches [contractProvider]; after the signing screen pops with success the
/// provider is invalidated so the status refreshes to `signed`.
class _ContractCard extends ConsumerWidget {
  const _ContractCard({required this.contractId});

  final String contractId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final contractAsync = ref.watch(contractProvider(contractId));

    return contractAsync.when(
      data: (contract) => _card(context, ref, contract),
      loading: () => const Card(
        child: Padding(
          padding: EdgeInsets.all(16),
          child: Center(child: CircularProgressIndicator()),
        ),
      ),
      error: (_, __) => Card(
        child: ListTile(
          leading: Icon(
            Icons.gavel_outlined,
            color: Theme.of(context).colorScheme.error,
          ),
          title: const Text('Contract'),
          subtitle: const Text('Could not load contract details.'),
          trailing: TextButton(
            onPressed: () => ref.invalidate(contractProvider(contractId)),
            child: const Text('Retry'),
          ),
        ),
      ),
    );
  }

  Widget _card(BuildContext context, WidgetRef ref, Contract contract) {
    final theme = Theme.of(context);
    final (Color statusColor, IconData icon) = _statusStyle(context, contract.status);

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, size: 18, color: statusColor),
                const SizedBox(width: 8),
                Text(
                  'Contract',
                  style: theme.textTheme.titleMedium
                      ?.copyWith(fontWeight: FontWeight.w600),
                ),
                const Spacer(),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: statusColor.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(12),
                    border:
                        Border.all(color: statusColor.withValues(alpha: 0.4)),
                  ),
                  child: Text(
                    contract.status.displayLabel,
                    style: TextStyle(
                      color: statusColor,
                      fontWeight: FontWeight.w600,
                      fontSize: 12,
                    ),
                  ),
                ),
              ],
            ),
            if (contract.status.isSignable) ...[
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  icon: const Icon(Icons.draw_outlined),
                  label: const Text('Review & Sign'),
                  onPressed: () => _openSigning(context, ref),
                ),
              ),
            ] else if (contract.status.isSigned) ...[
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  icon: const Icon(Icons.picture_as_pdf_outlined),
                  label: const Text('View signed contract'),
                  onPressed: () => _openSignedPdf(context, ref, contract),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  (Color, IconData) _statusStyle(BuildContext context, ContractStatus status) {
    switch (status) {
      case ContractStatus.signed:
        return (Colors.green, Icons.verified_outlined);
      case ContractStatus.sent:
      case ContractStatus.viewed:
        return (Colors.blue, Icons.draw_outlined);
      case ContractStatus.declined:
      case ContractStatus.voided:
        return (Theme.of(context).colorScheme.error, Icons.block_outlined);
      case ContractStatus.draft:
      case ContractStatus.unknown:
        return (Colors.grey.shade600, Icons.gavel_outlined);
    }
  }

  Future<void> _openSigning(BuildContext context, WidgetRef ref) async {
    final completed = await context.push<bool>(
      RouteNames.contractSignPath(contractId),
    );
    if (completed == true) {
      ref.invalidate(contractProvider(contractId));
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Contract signed. Thank you!')),
        );
      }
    }
  }

  Future<void> _openSignedPdf(
    BuildContext context,
    WidgetRef ref,
    Contract contract,
  ) async {
    final url = ref.read(contractRepositoryProvider).signedPdfUrl(contract);
    final messenger = ScaffoldMessenger.of(context);
    if (url == null) {
      messenger.showSnackBar(
        const SnackBar(content: Text('Signed contract is not available yet.')),
      );
      return;
    }
    final uri = Uri.parse(url);
    final opened = await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (!opened) {
      messenger.showSnackBar(
        const SnackBar(content: Text('Could not open the signed contract.')),
      );
    }
  }
}
