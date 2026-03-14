import 'line_item_entity.dart';

/// Domain entity for a Quote with populated line items and computed totals.
///
/// This is a plain immutable class (no @freezed annotation since build_runner
/// is unavailable). Computed properties (subtotal, discountAmount, taxAmount,
/// total) are calculated on-the-fly from [lineItems], [taxRate], [discountType],
/// and [discountValue] — not stored in the database.
///
/// The entity is constructed by [QuoteDao.watchQuotesForJob] and
/// [QuoteDao.watchQuote] after joining the parent quote with its line items.
class QuoteEntity {
  final String id;
  final String companyId;
  final String jobId;
  final String status;
  final int revisionNumber;
  final double taxRate;
  final String? discountType;
  final double discountValue;
  final DateTime? expiryDate;
  final DateTime? sentAt;
  final DateTime? viewedAt;
  final DateTime? approvedAt;
  final DateTime? declinedAt;
  final String? declineReason;
  final String? declineDetail;
  final String? adminNotes;
  final List<LineItemEntity> lineItems;
  final DateTime createdAt;
  final DateTime updatedAt;

  const QuoteEntity({
    required this.id,
    required this.companyId,
    required this.jobId,
    required this.status,
    required this.revisionNumber,
    required this.taxRate,
    required this.discountValue,
    required this.lineItems,
    required this.createdAt,
    required this.updatedAt,
    this.discountType,
    this.expiryDate,
    this.sentAt,
    this.viewedAt,
    this.approvedAt,
    this.declinedAt,
    this.declineReason,
    this.declineDetail,
    this.adminNotes,
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
  // Lifecycle helpers
  // ────────────────────────────────────────────────────────────────────────

  bool get isDraft => status == 'draft';
  bool get isSent => status == 'sent';
  bool get isApproved => status == 'approved';
  bool get isDeclined => status == 'declined';
  bool get isExpired => status == 'expired';

  /// Whether the quote is still awaiting a client decision.
  bool get isPending => status == 'sent' || status == 'viewed';

  // ────────────────────────────────────────────────────────────────────────
  // copyWith
  // ────────────────────────────────────────────────────────────────────────

  QuoteEntity copyWith({
    String? id,
    String? companyId,
    String? jobId,
    String? status,
    int? revisionNumber,
    double? taxRate,
    String? discountType,
    double? discountValue,
    DateTime? expiryDate,
    DateTime? sentAt,
    DateTime? viewedAt,
    DateTime? approvedAt,
    DateTime? declinedAt,
    String? declineReason,
    String? declineDetail,
    String? adminNotes,
    List<LineItemEntity>? lineItems,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return QuoteEntity(
      id: id ?? this.id,
      companyId: companyId ?? this.companyId,
      jobId: jobId ?? this.jobId,
      status: status ?? this.status,
      revisionNumber: revisionNumber ?? this.revisionNumber,
      taxRate: taxRate ?? this.taxRate,
      discountType: discountType ?? this.discountType,
      discountValue: discountValue ?? this.discountValue,
      expiryDate: expiryDate ?? this.expiryDate,
      sentAt: sentAt ?? this.sentAt,
      viewedAt: viewedAt ?? this.viewedAt,
      approvedAt: approvedAt ?? this.approvedAt,
      declinedAt: declinedAt ?? this.declinedAt,
      declineReason: declineReason ?? this.declineReason,
      declineDetail: declineDetail ?? this.declineDetail,
      adminNotes: adminNotes ?? this.adminNotes,
      lineItems: lineItems ?? this.lineItems,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is QuoteEntity && runtimeType == other.runtimeType && id == other.id;

  @override
  int get hashCode => id.hashCode;

  @override
  String toString() =>
      'QuoteEntity(id: $id, jobId: $jobId, status: $status, revisionNumber: $revisionNumber, total: $total)';
}
