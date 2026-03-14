/// Domain entity for a single line item on a quote or invoice.
///
/// Shared between [QuoteEntity] and [InvoiceEntity] — the structure of
/// line items is identical for both document types.
///
/// This is a plain immutable class (no @freezed annotation since build_runner
/// is unavailable). All computed math is performed here, not in the DAO.
class LineItemEntity {
  final String id;

  /// Item type: 'labor' or 'material'.
  final String itemType;

  /// Description of the line item (e.g., 'Install smoke detectors').
  final String description;

  /// Quantity of units (e.g., 2.5 hours, 10 units).
  final double quantity;

  /// Unit label (e.g., 'hr', 'unit', 'm2').
  final String unit;

  /// Price per unit in the company's currency.
  final double unitPrice;

  /// Display sort order (ascending). Lower values appear first.
  final int sortOrder;

  const LineItemEntity({
    required this.id,
    required this.itemType,
    required this.description,
    required this.quantity,
    required this.unit,
    required this.unitPrice,
    required this.sortOrder,
  });

  /// Line total = quantity * unitPrice.
  double get lineTotal => quantity * unitPrice;

  LineItemEntity copyWith({
    String? id,
    String? itemType,
    String? description,
    double? quantity,
    String? unit,
    double? unitPrice,
    int? sortOrder,
  }) {
    return LineItemEntity(
      id: id ?? this.id,
      itemType: itemType ?? this.itemType,
      description: description ?? this.description,
      quantity: quantity ?? this.quantity,
      unit: unit ?? this.unit,
      unitPrice: unitPrice ?? this.unitPrice,
      sortOrder: sortOrder ?? this.sortOrder,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is LineItemEntity &&
          runtimeType == other.runtimeType &&
          id == other.id;

  @override
  int get hashCode => id.hashCode;

  @override
  String toString() =>
      'LineItemEntity(id: $id, itemType: $itemType, description: $description, qty: $quantity, unitPrice: $unitPrice)';
}
