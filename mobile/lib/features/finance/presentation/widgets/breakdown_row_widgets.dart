import 'package:flutter/material.dart';

const financeRowHorizontalPadding = 16.0;
const financeRowVerticalPadding = 4.0;
const _flagChipBackground = Color(0x26F5A623);
const _flagChipForeground = Color(0xFF78350F);
const _flagChipBorderRadius = 999.0;

/// bodySmall in onSurfaceVariant — the caption voice of every finance summary.
TextStyle? financeSecondaryStyle(BuildContext context) {
  return Theme.of(context).textTheme.bodySmall?.copyWith(
        color: Theme.of(context).colorScheme.onSurfaceVariant,
      );
}

/// [label] left, [trailing] right, 16/4 padding — the row rhythm of the
/// Costs surfaces.
class BreakdownRow extends StatelessWidget {
  const BreakdownRow({required this.label, required this.trailing, super.key});

  final String label;
  final Widget trailing;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: financeRowHorizontalPadding,
        vertical: financeRowVerticalPadding,
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
}

/// A full-width caption beneath a row (unburdened note, basis caption,
/// flag caption).
class BreakdownCaption extends StatelessWidget {
  const BreakdownCaption(this.text, {super.key});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: financeRowHorizontalPadding,
        vertical: financeRowVerticalPadding,
      ),
      child: Text(text, style: financeSecondaryStyle(context)),
    );
  }
}

/// The one amber data-quality pill: unrated hours (Phase 32) and incomplete
/// cost data (Phase 33). Informational, never destructive — a data gap is
/// not an error.
class FinanceFlagChip extends StatelessWidget {
  const FinanceFlagChip(this.label, {super.key});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: _flagChipBackground,
        borderRadius: BorderRadius.circular(_flagChipBorderRadius),
      ),
      child: Text(
        label,
        style: Theme.of(context)
            .textTheme
            .bodySmall
            ?.copyWith(color: _flagChipForeground),
      ),
    );
  }
}
