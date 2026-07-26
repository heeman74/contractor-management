import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/database/app_database.dart' show CostEntry;
import '../providers/cost_providers.dart';
import 'add_cost_sheet.dart';
import 'cost_entry_card.dart';

/// Costs section for a job or trade-scope detail screen: header, cost-entry
/// list, empty state, and an "Add cost" action (finance.manage only).
///
/// Callers watch the appropriate stream ([costEntriesForJobProvider] or
/// [costEntriesForTradeScopeProvider]) and pass the resolved [entries] +
/// anchor down — mirrors the existing `ScopeBillingSection` data-down
/// pattern. Overall section visibility (finance.view) is the caller's
/// responsibility (job/trade-scope detail screens gate on
/// [financePermissionProvider] before mounting this widget).
class CostListSection extends ConsumerWidget {
  const CostListSection({
    required this.entries,
    this.jobId,
    this.tradeScopeId,
    super.key,
  }) : assert(
          (jobId == null) != (tradeScopeId == null),
          'CostListSection requires exactly one of jobId/tradeScopeId',
        );

  final List<CostEntry> entries;
  final String? jobId;
  final String? tradeScopeId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final canManage = ref.watch(financePermissionProvider).canManage;

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 8),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  'Costs',
                  style: Theme.of(context)
                      .textTheme
                      .titleMedium
                      ?.copyWith(fontWeight: FontWeight.w600),
                ),
              ),
              if (canManage)
                TextButton.icon(
                  onPressed: () => AddCostSheet.show(
                    context,
                    jobId: jobId,
                    tradeScopeId: tradeScopeId,
                  ),
                  icon: const Icon(Icons.add, size: 18),
                  label: const Text('Add cost'),
                ),
            ],
          ),
        ),
        const Divider(indent: 16, endIndent: 16),
        if (entries.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
            child: Text(
              'No costs recorded yet.',
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
            ),
          )
        else
          ...entries.map((entry) => CostEntryCard(entry: entry)),
        const SizedBox(height: 16),
      ],
    );
  }
}
