import 'package:drift/drift.dart';
import 'package:uuid/uuid.dart';

import 'companies.dart';
import 'projects.dart';

/// Drift table definition for the SiteWalkFlag entity.
///
/// A SiteWalkFlag is an issue or defect captured by a GC during a site walk.
/// Flags can be converted to [PunchListItems] when they require formal
/// remediation tracking (see [SiteWalkFlagDao.convertFlag]).
///
/// [severity] levels: 'low' | 'medium' | 'high' | 'critical'
/// [status] lifecycle: 'open' → 'resolved' | 'converted' | 'dismissed'
///
/// Offline-first: flags are created locally via SiteWalkFlagDao (with
/// outbox dual-write) and synced to the backend when connectivity is
/// restored.
class SiteWalkFlags extends Table {
  TextColumn get id => text().clientDefault(() => const Uuid().v4())();

  /// FK to Companies.id — tenant scope.
  TextColumn get companyId => text().references(Companies, #id)();

  /// FK to Projects.id — the project this flag belongs to.
  TextColumn get projectId => text().references(Projects, #id)();

  /// FK to Users.id — the GC who flagged the issue.
  /// Soft FK (no hard reference) to avoid cross-feature coupling.
  TextColumn get flaggedBy => text()();

  /// Description of the issue observed during the site walk.
  TextColumn get description => text()();

  /// Issue severity: 'low' | 'medium' | 'high' | 'critical'
  TextColumn get severity =>
      text().withDefault(const Constant('medium'))();

  /// Human-readable location label (e.g., "Unit 3B, kitchen wall").
  TextColumn get locationLabel => text().nullable()();

  /// URL or local path of a photo documenting the flag.
  TextColumn get photoUrl => text().nullable()();

  /// JSON annotation overlay for [photoUrl].
  /// Stored as normalized 0-1 coordinate array — non-destructive overlay.
  TextColumn get annotationData => text().nullable()();

  /// Flag status: 'open' | 'resolved' | 'converted' | 'dismissed'
  TextColumn get status =>
      text().withDefault(const Constant('open'))();

  IntColumn get version => integer().withDefault(const Constant(1))();
  DateTimeColumn get createdAt => dateTime()();
  DateTimeColumn get updatedAt => dateTime()();

  /// Soft-delete for sync tombstone propagation across devices.
  DateTimeColumn get deletedAt => dateTime().nullable()();

  @override
  Set<Column> get primaryKey => {id};
}
