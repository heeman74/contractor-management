import 'package:flutter/material.dart';

import '../../data/cost_breakdown.dart';

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
const _unratedChipBackground = Color(0x26F5A623);
const _unratedChipForeground = Color(0xFF78350F);
const _loadingAmountPlaceholder = '—';
const _horizontalPadding = 16.0;
const _chipBorderRadius = 999.0;

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
/// totals in fixed order, then the grand total.
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
    if (isUnavailable) return _secondaryText(context, _offlineNote);
    final breakdown = this.breakdown;
    if (breakdown == null && !isLoading) return const SizedBox.shrink();

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _laborRow(context, breakdown?.labor),
        if (variant != CostBreakdownVariant.tradeScope)
          _secondaryText(context, _unburdenedCaption),
        for (final category
            in orderedCategories(breakdown?.categories ?? const []))
          _breakdownRow(
            context,
            label: displayCategoryName(category.categoryName),
            trailing: _amount(context, category.total),
          ),
        const Divider(indent: 16, endIndent: 16),
        _breakdownRow(
          context,
          label: 'Total',
          trailing: _totalAmount(context, breakdown?.grandTotal),
        ),
      ],
    );
  }

  Widget _laborRow(BuildContext context, LaborCostSummary? labor) {
    if (variant == CostBreakdownVariant.tradeScope) {
      return _breakdownRow(
        context,
        label: 'Labor',
        trailing: Text(_jobLevelLaborNote, style: _secondaryStyle(context)),
      );
    }

    final chipLabel = labor == null ? '' : formatUnratedHours(labor.unratedSeconds);
    return _breakdownRow(
      context,
      label: 'Labor',
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (chipLabel.isNotEmpty) ...[
            _unratedChip(context, chipLabel),
            const SizedBox(width: 8),
          ],
          _amount(context, labor?.total),
        ],
      ),
    );
  }

  /// Single home for the label/amount layout and 16px padding of every row.
  Widget _breakdownRow(
    BuildContext context, {
    required String label,
    required Widget trailing,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: _horizontalPadding,
        vertical: 4,
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(label, style: Theme.of(context).textTheme.bodyMedium),
          ),
          trailing,
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

  Widget _unratedChip(BuildContext context, String label) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: _unratedChipBackground,
        borderRadius: BorderRadius.circular(_chipBorderRadius),
      ),
      child: Text(
        label,
        style: Theme.of(context)
            .textTheme
            .bodySmall
            ?.copyWith(color: _unratedChipForeground),
      ),
    );
  }

  Widget _secondaryText(BuildContext context, String text) {
    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: _horizontalPadding,
        vertical: 4,
      ),
      child: Text(text, style: _secondaryStyle(context)),
    );
  }

  TextStyle? _secondaryStyle(BuildContext context) {
    return Theme.of(context).textTheme.bodySmall?.copyWith(
          color: Theme.of(context).colorScheme.onSurfaceVariant,
        );
  }
}
