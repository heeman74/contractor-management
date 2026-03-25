import 'package:drift/drift.dart';
import 'package:uuid/uuid.dart';

import 'companies.dart';
import 'projects.dart';
import 'trade_scopes.dart';

/// Drift table definition for the PunchListItem entity.
///
/// A PunchListItem is a formal deficiency or corrective action item
/// scoped to a [TradeScope]. Items can be created directly by a GC or
/// converted from a [SiteWalkFlag] via [SiteWalkFlagDao.convertFlag].
///
/// [priority] levels: 'low' | 'medium' | 'high' | 'urgent'
/// [status] lifecycle: 'open' → 'in_progress' → 'resolved' | 'rejected'
///
/// [sourceFlagId] links back to the originating [SiteWalkFlag] when this
/// item was created via flag conversion — enables audit trail tracing.
///
/// Offline-first: items are created locally via PunchListItemDao (with
/// outbox dual-write) and synced to the backend when connectivity is
/// restored.
class PunchListItems extends Table {
  TextColumn get id => text().clientDefault(() => const Uuid().v4())();

  /// FK to Companies.id — tenant scope.
  TextColumn get companyId => text().references(Companies, #id)();

  /// FK to Projects.id — the project this punch list item belongs to.
  TextColumn get projectId => text().references(Projects, #id)();

  /// FK to TradeScopes.id — the trade scope responsible for remediation.
  TextColumn get tradeScopeId => text().references(TradeScopes, #id)();

  /// FK to Users.id — the GC who created this punch list item.
  /// Soft FK (no hard reference) to avoid cross-feature coupling.
  TextColumn get createdBy => text()();

  /// FK to Users.id — the contractor assigned to resolve this item.
  /// Nullable until explicitly assigned.
  TextColumn get assignedTo => text().nullable()();

  /// Description of the deficiency or corrective action required.
  TextColumn get description => text()();

  /// Item priority: 'low' | 'medium' | 'high' | 'urgent'
  TextColumn get priority =>
      text().withDefault(const Constant('medium'))();

  /// Item status: 'open' | 'in_progress' | 'resolved' | 'rejected'
  TextColumn get status =>
      text().withDefault(const Constant('open'))();

  /// URL or local path of a photo documenting the deficiency.
  TextColumn get photoUrl => text().nullable()();

  /// JSON annotation overlay for [photoUrl].
  /// Stored as normalized 0-1 coordinate array — non-destructive overlay.
  TextColumn get annotationData => text().nullable()();

  /// FK to SiteWalkFlags.id — populated when this item was created
  /// via [SiteWalkFlagDao.convertFlag]. Null for directly-created items.
  TextColumn get sourceFlagId => text().nullable()();

  /// Optional due date for resolving this punch list item.
  DateTimeColumn get dueDate => dateTime().nullable()();

  IntColumn get version => integer().withDefault(const Constant(1))();
  DateTimeColumn get createdAt => dateTime()();
  DateTimeColumn get updatedAt => dateTime()();

  /// Soft-delete for sync tombstone propagation across devices.
  DateTimeColumn get deletedAt => dateTime().nullable()();

  @override
  Set<Column> get primaryKey => {id};
}
