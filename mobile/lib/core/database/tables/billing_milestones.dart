import 'package:drift/drift.dart';
import 'package:uuid/uuid.dart';

import 'companies.dart';

/// Drift table definition for the BillingMilestone entity.
///
/// A BillingMilestone defines a payment trigger point for a trade scope —
/// e.g., "25% on mobilisation", "50% on framing complete". Each milestone
/// tracks a percentage of the total contract value and whether it has been
/// invoiced.
///
/// [tradeScopeId] is a soft FK — no hard reference to TradeScopes to keep
/// table definitions decoupled across features.
///
/// Offline-first: milestones are created locally via BillingMilestoneDao
/// (with outbox dual-write) and synced to the backend when connectivity is
/// restored.
class BillingMilestones extends Table {
  TextColumn get id => text().clientDefault(() => const Uuid().v4())();

  /// FK to Companies.id — tenant scope.
  TextColumn get companyId => text().references(Companies, #id)();

  /// Soft FK to TradeScopes.id — the trade scope these milestones belong to.
  /// No hard reference to avoid cross-feature coupling.
  TextColumn get tradeScopeId => text()();

  /// Human-readable milestone name (e.g., 'Mobilisation', 'Completion').
  TextColumn get name => text()();

  /// Percentage of total contract value this milestone represents (0.0-100.0).
  RealColumn get percentage => real()();

  /// Optional description providing more detail about the milestone.
  TextColumn get description => text().nullable()();

  /// Whether an invoice has been raised against this milestone.
  BoolColumn get isInvoiced => boolean().withDefault(const Constant(false))();

  /// Display order within the trade scope's milestone list (0-indexed).
  IntColumn get sortOrder => integer().withDefault(const Constant(0))();

  IntColumn get version => integer().withDefault(const Constant(1))();
  DateTimeColumn get createdAt => dateTime()();
  DateTimeColumn get updatedAt => dateTime()();

  /// Soft-delete for sync tombstone propagation across devices.
  DateTimeColumn get deletedAt => dateTime().nullable()();

  @override
  Set<Column> get primaryKey => {id};
}
