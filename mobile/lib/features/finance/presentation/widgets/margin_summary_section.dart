import 'package:flutter/material.dart';

import '../../data/cost_breakdown.dart';
import 'breakdown_row_widgets.dart';
import 'finance_formatters.dart';

export 'finance_formatters.dart' show formatMarginDollars, formatMarginPercent;

const _revenueLabel = 'Revenue';
const _marginLabel = 'Margin';
const _quotedBasisCaption = 'Based on approved quote — not yet invoiced.';
const _mixedBasisCaption = 'Includes approved quote amounts not yet invoiced.';
const _incompleteChipLabel = 'Incomplete cost data';
const _incompleteCaption =
    'Margin may overstate profit — some costs are missing or unrated.';
const _noRevenueNote =
    'No revenue recorded — margin will appear once an invoice or approved quote exists.';
const _revenueBasisQuoted = 'quoted';
const _revenueBasisMixed = 'mixed';
const _revenueBasisNone = 'none';
const _absentFigurePlaceholder = '—';

/// "$4200.00 · 21%", or dollars alone when [percent] is null (D-06: the
/// number is never suppressed, the percent is honestly absent at zero
/// revenue).
String formatMarginFigure(String margin, String? percent) {
  final dollars = formatMarginDollars(margin);
  if (percent == null) return dollars;
  return '$dollars$financeFigureSeparator${formatMarginPercent(percent)}%';
}

/// Revenue and Margin rows beneath the Total of a Costs surface, exactly as
/// locked by 33-UI-SPEC: basis caption when quote-backed, amber incomplete
/// chip and caption when flagged, error-colored numerals when negative, and
/// a neutral note when no revenue exists. Pure display — receives parsed
/// data, never fetches, never persists (D-10).
class MarginSummarySection extends StatelessWidget {
  const MarginSummarySection({required this.margin, super.key});

  final MarginSummary? margin;

  @override
  Widget build(BuildContext context) {
    final margin = this.margin;
    if (margin == null) return const SizedBox.shrink();

    final children = margin.revenueBasis == _revenueBasisNone
        ? const <Widget>[BreakdownCaption(_noRevenueNote)]
        : <Widget>[
            _revenueRow(context, margin),
            ..._basisCaption(margin),
            _marginRow(context, margin),
            if (margin.incomplete) const BreakdownCaption(_incompleteCaption),
          ];

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Divider(
          indent: financeRowHorizontalPadding,
          endIndent: financeRowHorizontalPadding,
        ),
        ...children,
      ],
    );
  }

  Widget _revenueRow(BuildContext context, MarginSummary margin) {
    final revenue = margin.revenue;
    return BreakdownRow(
      label: _revenueLabel,
      trailing: Text(
        revenue == null ? _absentFigurePlaceholder : '\$$revenue',
        style: Theme.of(context)
            .textTheme
            .titleSmall
            ?.copyWith(fontWeight: FontWeight.w600),
      ),
    );
  }

  List<Widget> _basisCaption(MarginSummary margin) {
    switch (margin.revenueBasis) {
      case _revenueBasisQuoted:
        return const [BreakdownCaption(_quotedBasisCaption)];
      case _revenueBasisMixed:
        return const [BreakdownCaption(_mixedBasisCaption)];
      default:
        return const [];
    }
  }

  Widget _marginRow(BuildContext context, MarginSummary margin) {
    return BreakdownRow(
      label: _marginLabel,
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (margin.incomplete) ...[
            const FinanceFlagChip(_incompleteChipLabel),
            const SizedBox(width: 8),
          ],
          _marginFigure(context, margin),
        ],
      ),
    );
  }

  Widget _marginFigure(BuildContext context, MarginSummary margin) {
    final marginDollars = margin.margin;
    final isNegative = marginDollars != null && marginDollars.startsWith('-');
    return Text(
      marginDollars == null
          ? _absentFigurePlaceholder
          : formatMarginFigure(marginDollars, margin.marginPercent),
      style: Theme.of(context).textTheme.titleMedium?.copyWith(
            fontWeight: FontWeight.w700,
            color: isNegative ? Theme.of(context).colorScheme.error : null,
          ),
    );
  }
}
