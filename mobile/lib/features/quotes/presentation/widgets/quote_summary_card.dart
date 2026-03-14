import 'package:flutter/material.dart';

/// Reusable summary card displaying quote financial totals.
///
/// Shows: Subtotal → Discount (with type label) → Tax → Total.
/// Used in both the admin quote builder screen and the client-facing
/// quote detail / preview screens.
///
/// All values are passed directly — the widget does no computation.
class QuoteSummaryCard extends StatelessWidget {
  final double subtotal;
  final double discountAmount;

  /// 'none', 'percentage', or 'fixed' — drives the label shown next to discount.
  final String discountType;
  final double discountValue;
  final double taxRate;
  final double taxAmount;
  final double total;

  const QuoteSummaryCard({
    super.key,
    required this.subtotal,
    required this.discountAmount,
    required this.discountType,
    required this.discountValue,
    required this.taxRate,
    required this.taxAmount,
    required this.total,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final hasDiscount = discountType != 'none' && discountAmount > 0;
    final hasTax = taxRate > 0;

    return Card(
      elevation: 2,
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            _SummaryRow(
              label: 'Subtotal',
              value: subtotal,
              theme: theme,
            ),
            if (hasDiscount) ...[
              const Divider(height: 12),
              _SummaryRow(
                label: _discountLabel(),
                value: -discountAmount,
                theme: theme,
                isDiscount: true,
              ),
            ],
            if (hasTax) ...[
              const Divider(height: 12),
              _SummaryRow(
                label: 'Tax (${taxRate.toStringAsFixed(1)}%)',
                value: taxAmount,
                theme: theme,
              ),
            ],
            const Divider(height: 16, thickness: 1.5),
            _SummaryRow(
              label: 'Total',
              value: total,
              theme: theme,
              isTotal: true,
            ),
          ],
        ),
      ),
    );
  }

  String _discountLabel() {
    if (discountType == 'percentage') {
      return 'Discount (${discountValue.toStringAsFixed(1)}%)';
    }
    return 'Discount (Fixed)';
  }
}

class _SummaryRow extends StatelessWidget {
  final String label;
  final double value;
  final ThemeData theme;
  final bool isTotal;
  final bool isDiscount;

  const _SummaryRow({
    required this.label,
    required this.value,
    required this.theme,
    this.isTotal = false,
    this.isDiscount = false,
  });

  @override
  Widget build(BuildContext context) {
    final labelStyle = isTotal
        ? theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold)
        : theme.textTheme.bodyMedium?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          );

    final valueStyle = isTotal
        ? theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold)
        : isDiscount
            ? theme.textTheme.bodyMedium?.copyWith(color: Colors.green.shade700)
            : theme.textTheme.bodyMedium;

    final displayValue = isDiscount
        ? '-\$${value.abs().toStringAsFixed(2)}'
        : '\$${value.toStringAsFixed(2)}';

    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(label, style: labelStyle),
        Text(displayValue, style: valueStyle),
      ],
    );
  }
}
