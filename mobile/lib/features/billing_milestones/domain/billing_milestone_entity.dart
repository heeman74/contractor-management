import 'package:drift/drift.dart';

import '../../../core/database/app_database.dart';

/// Domain entity for a BillingMilestone.
///
/// A BillingMilestone represents a payment trigger point for a trade scope
/// (e.g., "25% on mobilisation", "50% on framing complete"). Each milestone
/// tracks a percentage of the total contract value and whether it has been
/// invoiced.
///
/// Constructed by [BillingMilestoneDao.watchByScope] from Drift [BillingMilestone]
/// rows via [fromDrift].
class BillingMilestoneEntity {
  final String id;
  final String companyId;

  /// ID of the TradeScope this milestone belongs to (soft FK).
  final String tradeScopeId;

  /// Human-readable milestone name (e.g., 'Mobilisation', 'Completion').
  final String name;

  /// Percentage of total contract value (0.0–100.0).
  final double percentage;

  /// Optional description providing more detail about the milestone.
  final String? description;

  /// Whether an invoice has been raised against this milestone.
  final bool isInvoiced;

  /// Display order within the trade scope's milestone list (0-indexed).
  final int sortOrder;

  final int version;
  final DateTime createdAt;
  final DateTime updatedAt;

  /// Soft-delete timestamp. Non-null means the milestone is logically deleted.
  final DateTime? deletedAt;

  const BillingMilestoneEntity({
    required this.id,
    required this.companyId,
    required this.tradeScopeId,
    required this.name,
    required this.percentage,
    required this.isInvoiced,
    required this.sortOrder,
    required this.version,
    required this.createdAt,
    required this.updatedAt,
    this.description,
    this.deletedAt,
  });

  /// Construct a [BillingMilestoneEntity] from a Drift [BillingMilestone] data class.
  factory BillingMilestoneEntity.fromDrift(BillingMilestone row) {
    return BillingMilestoneEntity(
      id: row.id,
      companyId: row.companyId,
      tradeScopeId: row.tradeScopeId,
      name: row.name,
      percentage: row.percentage,
      description: row.description,
      isInvoiced: row.isInvoiced,
      sortOrder: row.sortOrder,
      version: row.version,
      createdAt: row.createdAt,
      updatedAt: row.updatedAt,
      deletedAt: row.deletedAt,
    );
  }

  /// Convert this entity to a [BillingMilestonesCompanion] for Drift insert/update.
  BillingMilestonesCompanion toCompanion() {
    return BillingMilestonesCompanion(
      id: Value(id),
      companyId: Value(companyId),
      tradeScopeId: Value(tradeScopeId),
      name: Value(name),
      percentage: Value(percentage),
      description: Value(description),
      isInvoiced: Value(isInvoiced),
      sortOrder: Value(sortOrder),
      version: Value(version),
      createdAt: Value(createdAt),
      updatedAt: Value(updatedAt),
      deletedAt: Value(deletedAt),
    );
  }

  // ────────────────────────────────────────────────────────────────────────
  // copyWith
  // ────────────────────────────────────────────────────────────────────────

  BillingMilestoneEntity copyWith({
    String? id,
    String? companyId,
    String? tradeScopeId,
    String? name,
    double? percentage,
    String? description,
    bool? isInvoiced,
    int? sortOrder,
    int? version,
    DateTime? createdAt,
    DateTime? updatedAt,
    DateTime? deletedAt,
  }) {
    return BillingMilestoneEntity(
      id: id ?? this.id,
      companyId: companyId ?? this.companyId,
      tradeScopeId: tradeScopeId ?? this.tradeScopeId,
      name: name ?? this.name,
      percentage: percentage ?? this.percentage,
      description: description ?? this.description,
      isInvoiced: isInvoiced ?? this.isInvoiced,
      sortOrder: sortOrder ?? this.sortOrder,
      version: version ?? this.version,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      deletedAt: deletedAt ?? this.deletedAt,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is BillingMilestoneEntity &&
          runtimeType == other.runtimeType &&
          id == other.id;

  @override
  int get hashCode => id.hashCode;

  @override
  String toString() =>
      'BillingMilestoneEntity(id: $id, name: $name, percentage: $percentage%, isInvoiced: $isInvoiced)';
}
