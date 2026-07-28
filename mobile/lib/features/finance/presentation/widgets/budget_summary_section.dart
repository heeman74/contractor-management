import 'package:flutter/material.dart';

import '../../data/cost_breakdown.dart';
import 'breakdown_row_widgets.dart';
import 'finance_formatters.dart';

const _budgetLabel = 'Budget';
const _spentLabel = 'Spent';
const _remainingLabel = 'Remaining';
const _nearingBudgetChipLabel = 'Nearing budget';
const _nearingBudgetPercent = 80;

/// Budget / Spent / Remaining rows for a project or trade-scope Costs section.
/// Receives parsed data, never fetches (D-13: view-only on mobile, no Drift).
/// Band classification reads the backend strings only — the client never
/// divides to get a percent. Amber chip (80–100%) and red over-budget
/// numerals are mutually exclusive: one state, one signal.
class BudgetSummarySection extends StatelessWidget {
  const BudgetSummarySection({required this.budget, super.key});

  final BudgetVsActual? budget;

  @override
  Widget build(BuildContext context) {
    final budget = this.budget;
    if (budget == null) return const SizedBox.shrink();

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Divider(
          indent: financeRowHorizontalPadding,
          endIndent: financeRowHorizontalPadding,
        ),
        BreakdownRow(
          label: _budgetLabel,
          trailing: _amountText(context, '\$${budget.total}'),
        ),
        BreakdownRow(
          label: _spentLabel,
          trailing: _amountText(context, _spentFigure(budget)),
        ),
        BreakdownRow(
          label: _remainingLabel,
          trailing: _remainingTrailing(context, budget),
        ),
      ],
    );
  }

  String _spentFigure(BudgetVsActual budget) {
    final percent = formatPercentUsed(budget.percentUsed);
    return '\$${budget.spent}$financeFigureSeparator$percent%';
  }

  Widget _amountText(BuildContext context, String figure) {
    return Text(
      figure,
      style: Theme.of(context)
          .textTheme
          .titleSmall
          ?.copyWith(fontWeight: FontWeight.w600),
    );
  }

  Widget _remainingTrailing(BuildContext context, BudgetVsActual budget) {
    final remainingAmount = double.tryParse(budget.remaining) ?? 0;
    final isOverBudget = remainingAmount < 0;
    // Warning band is 80 ≤ used < 100 (UI-SPEC state 4): at exactly 100% the
    // chip disappears and the $0.00 figure is the signal (state 5).
    final isNearingBudget = remainingAmount > 0 &&
        (double.tryParse(budget.percentUsed) ?? 0) >= _nearingBudgetPercent;

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (isNearingBudget) ...[
          const FinanceFlagChip(_nearingBudgetChipLabel),
          const SizedBox(width: 8),
        ],
        Text(
          formatMarginDollars(budget.remaining),
          style: Theme.of(context).textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w700,
                color: isOverBudget
                    ? Theme.of(context).colorScheme.error
                    : null,
              ),
        ),
      ],
    );
  }
}
