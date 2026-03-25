import 'package:drift/drift.dart';
import 'package:uuid/uuid.dart';

import 'companies.dart';
import 'projects.dart';

/// Drift table definition for the TradeScope entity.
///
/// A TradeScope represents one trade's scope of work within a [Project].
/// Each project has one TradeScope per trade (e.g., electrical, plumbing).
///
/// [contractorId] is the user assigned to execute this scope — nullable
/// until a contractor is assigned.
///
/// [statusOverride] allows the GC to manually set the status regardless
/// of task completion percentage.
///
/// [sortOrder] determines display order within the project's trade list.
class TradeScopes extends Table {
  TextColumn get id => text().clientDefault(() => const Uuid().v4())();
  TextColumn get companyId => text().references(Companies, #id)();

  /// FK to Projects.id — the project this scope belongs to.
  TextColumn get projectId => text().references(Projects, #id)();

  /// FK to TradeCatalogEntries.id — optional link to catalog definition.
  /// Nullable — a scope may use a custom trade name without a catalog entry.
  TextColumn get tradeCatalogId => text().nullable()();

  /// Display name for this trade scope (may differ from catalog entry).
  TextColumn get tradeName => text()();

  /// Hex color code for UI display. Defaults to grey.
  TextColumn get tradeColor =>
      text().withDefault(const Constant('#9E9E9E'))();

  /// FK to Users.id with contractor role. Nullable until assigned.
  TextColumn get contractorId => text().nullable()();

  /// Scope lifecycle state: not_started | in_progress | complete | blocked
  TextColumn get status =>
      text().withDefault(const Constant('not_started'))();

  /// When true, the GC has manually overridden the auto-calculated status.
  BoolColumn get statusOverride =>
      boolean().withDefault(const Constant(false))();

  /// Display order within the project's trade scope list.
  IntColumn get sortOrder => integer().withDefault(const Constant(0))();

  /// JSON array defining the checklist items a GC must evaluate when
  /// inspecting tasks in this trade scope. Each item:
  /// { "id": "...", "label": "...", "required": true/false }
  /// Nullable — scopes without a checklist use a free-form inspection flow.
  TextColumn get inspectionChecklist => text().nullable()();

  IntColumn get version => integer().withDefault(const Constant(1))();
  DateTimeColumn get createdAt => dateTime()();
  DateTimeColumn get updatedAt => dateTime()();

  /// Soft-delete for sync tombstone propagation across devices.
  DateTimeColumn get deletedAt => dateTime().nullable()();

  @override
  Set<Column> get primaryKey => {id};
}
