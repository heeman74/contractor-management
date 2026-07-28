import 'package:flutter/material.dart';

import '../../data/cost_breakdown.dart';
import 'breakdown_row_widgets.dart';
import 'margin_summary_section.dart';

/// Which Costs surface a [CostBreakdownSummary] renders on. Trade scopes
/// show "Tracked at job level" instead of a labor amount (D-08).
enum CostBreakdownVariant { job, tradeScope, project }

const _secondsPerHour = 3600;
const _unburdenedCaption =
    'Wage cost only — excludes payroll tax, insurance, overhead.';
const _jobLevelLaborNote = 'Tracked at job level';
const _offlineNote = 'Breakdown unavailable offline';
const _laborCategoryName = 'labor';
const _orderedCategoryNames = ['materials', 'subcontractor', 'other'];
const _loadingAmountPlaceholder = '—';

/// "12.5 hrs unrated" / "1 hr unrated" / "2 hrs unrated" — hours always
/// visible (D-05), rounded to one decimal with a trailing .0 dropped.
/// Returns an empty string for zero (or negative) seconds: callers never
/// render a chip when every hour is rated.
String formatUnratedHours(int unratedSeconds) {
  if (unratedSeconds <= 0) return '';
  final tenthsOfHours = (unratedSeconds * 10 / _secondsPerHour).round();
  final wholeHours = tenthsOfHours ~/ 10;
  final display = tenthsOfHours % 10 == 0
      ? '$wholeHours'
      : '$wholeHours.${tenthsOfHours % 10}';
  final unit = display == '1' ? 'hr' : 'hrs';
  return '$display $unit unrated';
}

/// Materials, Subcontractor, Other, then custom names alphabetically. The
/// reserved labor category is dropped — labor renders from
/// [CostBreakdown.labor], and the backend already folded any legacy
/// labor-categorized entries into that figure.
List<CategoryTotal> orderedCategories(List<CategoryTotal> categories) {
  final nonLabor = categories
      .where((category) =>
          category.categoryName.toLowerCase() != _laborCategoryName)
      .toList();
  final fixed = [
    for (final name in _orderedCategoryNames)
      ...nonLabor.where(
        (category) => category.categoryName.toLowerCase() == name,
      ),
  ];
  final custom = nonLabor
      .where((category) =>
          !_orderedCategoryNames.contains(category.categoryName.toLowerCase()))
      .toList()
    ..sort((a, b) => a.categoryName
        .toLowerCase()
        .compareTo(b.categoryName.toLowerCase()));
  return [...fixed, ...custom];
}

/// "materials" -> "Materials"
String displayCategoryName(String name) {
  if (name.isEmpty) return name;
  return name[0].toUpperCase() + name.substring(1);
}

/// Itemized cost breakdown rows for a job, trade-scope, or project Costs
/// surface: labor (with unrated chip and unburdened caption), category
/// totals in fixed order, the grand total, then the margin section (Phase
/// 33 — renders nothing when the backend sends no margin block).
///
/// Receives data, never fetches — callers watch the matching breakdown
/// provider and pass its [AsyncValue] fields down. Amounts are backend
/// Decimal-as-Strings displayed verbatim, never re-summed locally (D-11).
class CostBreakdownSummary extends StatelessWidget {
  const CostBreakdownSummary({
    required this.breakdown,
    required this.variant,
    this.isLoading = false,
    this.isUnavailable = false,
    super.key,
  });

  final CostBreakdown? breakdown;
  final CostBreakdownVariant variant;
  final bool isLoading;
  final bool isUnavailable;

  @override
  Widget build(BuildContext context) {
    if (isUnavailable) return const BreakdownCaption(_offlineNote);
    final breakdown = this.breakdown;
    if (breakdown == null && !isLoading) return const SizedBox.shrink();

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _laborRow(context, breakdown?.labor),
        if (variant != CostBreakdownVariant.tradeScope)
          const BreakdownCaption(_unburdenedCaption),
        for (final category
            in orderedCategories(breakdown?.categories ?? const []))
          BreakdownRow(
            label: displayCategoryName(category.categoryName),
            trailing: _amount(context, category.total),
          ),
        const Divider(
          indent: financeRowHorizontalPadding,
          endIndent: financeRowHorizontalPadding,
        ),
        BreakdownRow(
          label: 'Total',
          trailing: _totalAmount(context, breakdown?.grandTotal),
        ),
        MarginSummarySection(margin: breakdown?.margin),
      ],
    );
  }

  Widget _laborRow(BuildContext context, LaborCostSummary? labor) {
    if (variant == CostBreakdownVariant.tradeScope) {
      return BreakdownRow(
        label: 'Labor',
        trailing:
            Text(_jobLevelLaborNote, style: financeSecondaryStyle(context)),
      );
    }

    final chipLabel = labor == null ? '' : formatUnratedHours(labor.unratedSeconds);
    return BreakdownRow(
      label: 'Labor',
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (chipLabel.isNotEmpty) ...[
            FinanceFlagChip(chipLabel),
            const SizedBox(width: 8),
          ],
          _amount(context, labor?.total),
        ],
      ),
    );
  }

  Widget _amount(BuildContext context, String? amount) {
    return Text(
      amount == null ? _loadingAmountPlaceholder : '\$$amount',
      style: Theme.of(context)
          .textTheme
          .titleSmall
          ?.copyWith(fontWeight: FontWeight.w600),
    );
  }

  Widget _totalAmount(BuildContext context, String? grandTotal) {
    return Text(
      grandTotal == null ? _loadingAmountPlaceholder : '\$$grandTotal',
      style: Theme.of(context)
          .textTheme
          .titleMedium
          ?.copyWith(fontWeight: FontWeight.w700),
    );
  }
}
