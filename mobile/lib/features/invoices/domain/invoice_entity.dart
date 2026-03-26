import '../../quotes/domain/line_item_entity.dart';

/// Domain entity for an Invoice with populated line items and computed totals.
///
/// This is a plain immutable class (no @freezed annotation since build_runner
/// is unavailable). Computed properties (subtotal, discountAmount, taxAmount,
/// total) are calculated on-the-fly from [lineItems], [taxRate], [discountType],
/// and [discountValue] — not stored in the database.
///
/// The entity is constructed by [InvoiceDao.watchInvoicesForJob] and
/// [InvoiceDao.watchInvoice] after joining the parent invoice with its line items.
class InvoiceEntity {
  final String id;
  final String companyId;

  /// FK to Jobs.id — the job this invoice belongs to.
  /// Nullable for trade-scoped invoices not tied to a specific job.
  final String? jobId;

  /// FK to the quote that generated this invoice, if any.
  final String? quoteId;

  /// Soft FK to TradeScopes.id — the trade scope this invoice belongs to.
  /// Populated for per-trade invoices; null for legacy job-based invoices.
  final String? tradeScopeId;

  /// Soft FK to BillingMilestones.id — the milestone this invoice was raised against.
  /// Null for invoices not tied to a billing milestone.
  final String? milestoneId;
  final String invoiceNumber;
  final String status;
  final double taxRate;
  final String? discountType;
  final double discountValue;
  final DateTime? dueDate;
  final DateTime issuedAt;
  final DateTime? finalizedAt;
  final List<LineItemEntity> lineItems;
  final DateTime createdAt;
  final DateTime updatedAt;

  const InvoiceEntity({
    required this.id,
    required this.companyId,
    required this.invoiceNumber,
    required this.status,
    required this.taxRate,
    required this.discountValue,
    required this.issuedAt,
    required this.lineItems,
    required this.createdAt,
    required this.updatedAt,
    this.jobId,
    this.quoteId,
    this.tradeScopeId,
    this.milestoneId,
    this.discountType,
    this.dueDate,
    this.finalizedAt,
  });

  // ────────────────────────────────────────────────────────────────────────
  // Computed financial properties
  // ────────────────────────────────────────────────────────────────────────

  /// Sum of all line item totals (qty * unitPrice) before discount and tax.
  double get subtotal {
    return lineItems.fold(0.0, (sum, item) => sum + item.lineTotal);
  }

  /// Dollar amount of the discount applied to the subtotal.
  ///
  /// - If [discountType] is 'percentage': subtotal * discountValue / 100
  /// - If [discountType] is 'fixed': discountValue directly
  /// - Otherwise: 0.0
  double get discountAmount {
    if (discountType == 'percentage') {
      return subtotal * discountValue / 100;
    } else if (discountType == 'fixed') {
      return discountValue;
    }
    return 0.0;
  }

  /// Subtotal after discount is applied.
  double get discountedSubtotal => subtotal - discountAmount;

  /// Tax amount applied to the discounted subtotal.
  double get taxAmount => discountedSubtotal * taxRate / 100;

  /// Grand total: subtotal - discount + tax.
  double get total => discountedSubtotal + taxAmount;

  // ────────────────────────────────────────────────────────────────────────
  // Status helpers
  // ────────────────────────────────────────────────────────────────────────

  bool get isUnpaid => status == 'unpaid';
  bool get isPaid => status == 'paid';
  bool get isPartial => status == 'partial';
  bool get isOverdue => status == 'overdue';
  bool get isCancelled => status == 'cancelled';

  /// Whether the invoice still requires payment action.
  bool get requiresPayment => status == 'unpaid' || status == 'partial' || status == 'overdue';

  // ────────────────────────────────────────────────────────────────────────
  // copyWith
  // ────────────────────────────────────────────────────────────────────────

  InvoiceEntity copyWith({
    String? id,
    String? companyId,
    String? jobId,
    String? quoteId,
    String? tradeScopeId,
    String? milestoneId,
    String? invoiceNumber,
    String? status,
    double? taxRate,
    String? discountType,
    double? discountValue,
    DateTime? dueDate,
    DateTime? issuedAt,
    DateTime? finalizedAt,
    List<LineItemEntity>? lineItems,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return InvoiceEntity(
      id: id ?? this.id,
      companyId: companyId ?? this.companyId,
      jobId: jobId ?? this.jobId,
      quoteId: quoteId ?? this.quoteId,
      tradeScopeId: tradeScopeId ?? this.tradeScopeId,
      milestoneId: milestoneId ?? this.milestoneId,
      invoiceNumber: invoiceNumber ?? this.invoiceNumber,
      status: status ?? this.status,
      taxRate: taxRate ?? this.taxRate,
      discountType: discountType ?? this.discountType,
      discountValue: discountValue ?? this.discountValue,
      dueDate: dueDate ?? this.dueDate,
      issuedAt: issuedAt ?? this.issuedAt,
      finalizedAt: finalizedAt ?? this.finalizedAt,
      lineItems: lineItems ?? this.lineItems,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is InvoiceEntity && runtimeType == other.runtimeType && id == other.id;

  @override
  int get hashCode => id.hashCode;

  @override
  String toString() =>
      'InvoiceEntity(id: $id, invoiceNumber: $invoiceNumber, status: $status, total: $total)';
}
