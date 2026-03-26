import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/di/service_locator.dart';
import '../../../../core/network/dio_client.dart';
import '../../domain/billing_milestone_entity.dart';
import '../providers/billing_milestone_providers.dart';
import 'create_milestone_sheet.dart';

/// Card widget showing all billing milestones for a trade scope.
///
/// Displays a Card with "Billing Milestones" header and an "Add" icon button.
/// Each milestone row shows:
/// - Name and percentage badge
/// - Optional description
/// - "Invoiced" chip if [BillingMilestoneEntity.isInvoiced] is true
/// - "Generate Invoice" button if NOT yet invoiced — calls
///   POST /trade-scopes/{scopeId}/invoices/progress with milestone_id
///
/// Non-invoiced milestones support swipe-to-delete (calls [deleteMilestoneAction]).
/// "Add" button opens [CreateMilestoneSheet].
class MilestoneListCard extends ConsumerWidget {
  const MilestoneListCard({required this.scopeId, super.key});

  final String scopeId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final milestonesAsync = ref.watch(billingMilestonesByScope(scopeId));

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      elevation: 1,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header row
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 8, 0),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    'Billing Milestones',
                    style: Theme.of(context).textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.add),
                  tooltip: 'Add Milestone',
                  onPressed: () => _showCreateSheet(context, ref, milestonesAsync.value?.length ?? 0),
                ),
              ],
            ),
          ),

          const Divider(height: 1, indent: 16, endIndent: 16),

          // Milestones list
          milestonesAsync.when(
            loading: () => const Padding(
              padding: EdgeInsets.all(16),
              child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
            ),
            error: (error, _) => Padding(
              padding: const EdgeInsets.all(16),
              child: Text(
                'Error loading milestones',
                style: TextStyle(
                  color: Theme.of(context).colorScheme.error,
                ),
              ),
            ),
            data: (milestones) {
              if (milestones.isEmpty) {
                return Padding(
                  padding: const EdgeInsets.all(16),
                  child: Text(
                    'No milestones yet. Tap + to add one.',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: Theme.of(context)
                              .colorScheme
                              .onSurface
                              .withValues(alpha: 0.5),
                        ),
                  ),
                );
              }

              return ListView.separated(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: milestones.length,
                separatorBuilder: (_, __) =>
                    const Divider(height: 1, indent: 16, endIndent: 16),
                itemBuilder: (context, index) {
                  final milestone = milestones[index];
                  return _MilestoneRow(
                    milestone: milestone,
                    scopeId: scopeId,
                    ref: ref,
                  );
                },
              );
            },
          ),
        ],
      ),
    );
  }

  void _showCreateSheet(BuildContext context, WidgetRef ref, int existingCount) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => CreateMilestoneSheet(
        scopeId: scopeId,
        existingCount: existingCount,
      ),
    );
  }
}

/// Single milestone row with swipe-to-delete support for non-invoiced milestones.
class _MilestoneRow extends StatelessWidget {
  const _MilestoneRow({
    required this.milestone,
    required this.scopeId,
    required this.ref,
  });

  final BillingMilestoneEntity milestone;
  final String scopeId;
  final WidgetRef ref;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final colorScheme = Theme.of(context).colorScheme;

    final row = Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              // Name
              Expanded(
                child: Text(
                  milestone.name,
                  style:
                      textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w500),
                ),
              ),
              const SizedBox(width: 8),

              // Percentage badge
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: colorScheme.primaryContainer,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  '${milestone.percentage.toStringAsFixed(milestone.percentage % 1 == 0 ? 0 : 1)}%',
                  style: textTheme.labelSmall?.copyWith(
                    color: colorScheme.onPrimaryContainer,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),

          // Optional description
          if (milestone.description != null) ...[
            const SizedBox(height: 4),
            Text(
              milestone.description!,
              style: textTheme.bodySmall?.copyWith(
                color: colorScheme.onSurface.withValues(alpha: 0.6),
              ),
            ),
          ],

          const SizedBox(height: 6),

          // Invoice status / action
          if (milestone.isInvoiced)
            Chip(
              label: const Text('Invoiced'),
              avatar: Icon(Icons.check_circle,
                  size: 16, color: colorScheme.onSecondaryContainer),
              backgroundColor: colorScheme.secondaryContainer,
              labelStyle: textTheme.labelSmall?.copyWith(
                color: colorScheme.onSecondaryContainer,
              ),
              padding: EdgeInsets.zero,
              visualDensity: VisualDensity.compact,
            )
          else
            TextButton.icon(
              onPressed: () => _generateProgressInvoice(context),
              icon: const Icon(Icons.receipt_long, size: 16),
              label: const Text('Generate Invoice'),
              style: TextButton.styleFrom(
                visualDensity: VisualDensity.compact,
                padding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              ),
            ),
        ],
      ),
    );

    // Swipe-to-delete only for non-invoiced milestones
    if (milestone.isInvoiced) return row;

    return Dismissible(
      key: ValueKey(milestone.id),
      direction: DismissDirection.endToStart,
      background: Container(
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 16),
        color: Theme.of(context).colorScheme.errorContainer,
        child: Icon(
          Icons.delete,
          color: Theme.of(context).colorScheme.onErrorContainer,
        ),
      ),
      confirmDismiss: (direction) async {
        return await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text('Delete Milestone'),
            content: Text(
                'Delete "${milestone.name}"? This cannot be undone.'),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(ctx).pop(false),
                child: const Text('Cancel'),
              ),
              FilledButton(
                onPressed: () => Navigator.of(ctx).pop(true),
                style: FilledButton.styleFrom(
                  backgroundColor:
                      Theme.of(ctx).colorScheme.error,
                ),
                child: const Text('Delete'),
              ),
            ],
          ),
        );
      },
      onDismissed: (_) async {
        try {
          await deleteMilestoneAction(ref, milestone.id);
          if (context.mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                  content: Text('"${milestone.name}" deleted.')),
            );
          }
        } catch (e) {
          debugPrint('[MilestoneRow] Delete error: $e');
          if (context.mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                  content: Text('Failed to delete milestone.')),
            );
          }
        }
      },
      child: row,
    );
  }

  Future<void> _generateProgressInvoice(BuildContext context) async {
    try {
      final dio = getIt<DioClient>();
      await dio.instance.post<Map<String, dynamic>>(
        '/trade-scopes/$scopeId/invoices/progress',
        data: {'milestone_id': milestone.id},
      );

      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Progress invoice created.')),
        );
      }
    } on DioException catch (e) {
      debugPrint('[MilestoneRow] Generate invoice error: $e');
      final statusCode = e.response?.statusCode;
      final message = statusCode == 409
          ? 'Already invoiced.'
          : 'Failed to generate invoice.';
      if (context.mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(message)));
      }
    } catch (e) {
      debugPrint('[MilestoneRow] Generate invoice unexpected error: $e');
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Failed to generate invoice.')),
        );
      }
    }
  }
}
