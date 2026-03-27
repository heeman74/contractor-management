import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../domain/line_item_entity.dart';

/// Available unit labels for quote line items.
const _kUnits = [
  'each',
  'hour',
  'day',
  'sqm',
  'sqft',
  'meter',
  'liter',
  'kg',
  'lot',
];

/// Compact form row for a single quote line item.
///
/// Renders:
///   - SegmentedButton to toggle Labor / Material type
///   - TextFormField for description
///   - Row with quantity (numeric), unit dropdown, unit price (currency)
///   - Computed subtotal: quantity * unitPrice
///   - Delete icon button
///
/// Callbacks:
///   - [onChanged] fires with the updated [LineItemEntity] on every field change.
///   - [onDelete] fires when the user taps the delete icon.
///
/// [showValidation] drives inline error text visibility.
class LineItemForm extends StatefulWidget {
  final LineItemEntity item;
  final ValueChanged<LineItemEntity> onChanged;
  final VoidCallback onDelete;
  final bool showValidation;

  const LineItemForm({
    required this.item, required this.onChanged, required this.onDelete, super.key,
    this.showValidation = false,
  });

  @override
  State<LineItemForm> createState() => _LineItemFormState();
}

class _LineItemFormState extends State<LineItemForm> {
  late final TextEditingController _descController;
  late final TextEditingController _quantityController;
  late final TextEditingController _priceController;

  @override
  void initState() {
    super.initState();
    _descController =
        TextEditingController(text: widget.item.description);
    _quantityController =
        TextEditingController(text: _formatNumber(widget.item.quantity));
    _priceController =
        TextEditingController(text: _formatNumber(widget.item.unitPrice));
  }

  @override
  void didUpdateWidget(LineItemForm oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Sync external changes (e.g., template load) without overriding mid-edit.
    if (oldWidget.item.id != widget.item.id) {
      _descController.text = widget.item.description;
      _quantityController.text = _formatNumber(widget.item.quantity);
      _priceController.text = _formatNumber(widget.item.unitPrice);
    }
  }

  @override
  void dispose() {
    _descController.dispose();
    _quantityController.dispose();
    _priceController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final item = widget.item;

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 8, 4, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ─── Header row: type toggle + delete ──────────────────────────
            Row(
              children: [
                // Labor / Material segmented button
                Expanded(
                  child: SegmentedButton<String>(
                    segments: const [
                      ButtonSegment(
                        value: 'labor',
                        label: Text('Labor'),
                        icon: Icon(Icons.engineering, size: 16),
                      ),
                      ButtonSegment(
                        value: 'material',
                        label: Text('Material'),
                        icon: Icon(Icons.inventory_2, size: 16),
                      ),
                    ],
                    selected: {item.itemType},
                    onSelectionChanged: (selected) {
                      widget.onChanged(item.copyWith(itemType: selected.first));
                    },
                    style: const ButtonStyle(
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      visualDensity: VisualDensity.compact,
                    ),
                  ),
                ),
                // Drag handle (rendered by ReorderableListView)
                ReorderableDragStartListener(
                  index: item.sortOrder,
                  child: const Icon(Icons.drag_handle, color: Colors.grey),
                ),
                // Delete
                IconButton(
                  icon: const Icon(Icons.delete_outline),
                  color: theme.colorScheme.error,
                  visualDensity: VisualDensity.compact,
                  tooltip: 'Remove line item',
                  onPressed: widget.onDelete,
                ),
              ],
            ),

            const SizedBox(height: 6),

            // ─── Description field ──────────────────────────────────────────
            TextFormField(
              controller: _descController,
              decoration: InputDecoration(
                labelText: 'Description',
                hintText: 'e.g. Install smoke detectors',
                errorText: widget.showValidation &&
                        item.description.trim().isEmpty
                    ? 'Description is required'
                    : null,
                isDense: true,
                border: const OutlineInputBorder(),
              ),
              onChanged: (value) {
                widget.onChanged(item.copyWith(description: value));
              },
            ),

            const SizedBox(height: 8),

            // ─── Qty / Unit / Price row ─────────────────────────────────────
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Quantity
                SizedBox(
                  width: 72,
                  child: TextFormField(
                    controller: _quantityController,
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    inputFormatters: [
                      FilteringTextInputFormatter.allow(
                        RegExp(r'^\d+\.?\d*'),
                      ),
                    ],
                    decoration: InputDecoration(
                      labelText: 'Qty',
                      isDense: true,
                      border: const OutlineInputBorder(),
                      errorText: widget.showValidation && item.quantity <= 0
                          ? 'Must be > 0'
                          : null,
                    ),
                    onChanged: (value) {
                      final qty = double.tryParse(value) ?? item.quantity;
                      widget.onChanged(item.copyWith(quantity: qty));
                    },
                  ),
                ),

                const SizedBox(width: 6),

                // Unit dropdown
                SizedBox(
                  width: 88,
                  child: DropdownButtonFormField<String>(
                    initialValue: _kUnits.contains(item.unit) ? item.unit : 'each',
                    isExpanded: true,
                    decoration: const InputDecoration(
                      labelText: 'Unit',
                      isDense: true,
                      border: OutlineInputBorder(),
                    ),
                    items: _kUnits
                        .map(
                          (u) => DropdownMenuItem(value: u, child: Text(u)),
                        )
                        .toList(),
                    onChanged: (value) {
                      if (value != null) {
                        widget.onChanged(item.copyWith(unit: value));
                      }
                    },
                  ),
                ),

                const SizedBox(width: 6),

                // Unit price
                Expanded(
                  child: TextFormField(
                    controller: _priceController,
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    inputFormatters: [
                      FilteringTextInputFormatter.allow(
                        RegExp(r'^\d+\.?\d*'),
                      ),
                    ],
                    decoration: InputDecoration(
                      labelText: 'Unit Price',
                      prefixText: '\$',
                      isDense: true,
                      border: const OutlineInputBorder(),
                      errorText:
                          widget.showValidation && item.unitPrice < 0
                              ? 'Cannot be negative'
                              : null,
                    ),
                    onChanged: (value) {
                      final price =
                          double.tryParse(value) ?? item.unitPrice;
                      widget.onChanged(item.copyWith(unitPrice: price));
                    },
                  ),
                ),
              ],
            ),

            const SizedBox(height: 6),

            // ─── Computed subtotal ──────────────────────────────────────────
            Align(
              alignment: Alignment.centerRight,
              child: Text(
                '${_formatNumber(item.quantity)} × \$${_formatNumber(item.unitPrice)} = \$${_formatMoney(item.lineTotal)}',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                  fontStyle: FontStyle.italic,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _formatNumber(double value) {
    if (value == value.truncate()) {
      return value.truncate().toString();
    }
    return value.toStringAsFixed(2);
  }

  String _formatMoney(double value) => value.toStringAsFixed(2);
}
