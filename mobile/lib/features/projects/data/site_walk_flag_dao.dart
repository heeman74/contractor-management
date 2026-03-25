import 'dart:convert';

import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:uuid/uuid.dart';

import '../../../core/database/app_database.dart';
import '../../../core/database/tables/punch_list_items.dart';
import '../../../core/database/tables/site_walk_flags.dart';
import '../../../core/database/tables/sync_queue.dart';

part 'site_walk_flag_dao.g.dart';

/// Drift DAO for SiteWalkFlag CRUD with transactional outbox dual-write.
///
/// All read methods return [Stream] — offline-first, reactive to local DB changes.
///
/// Every mutating method uses [db.transaction] to atomically write to BOTH
/// the entity table(s) AND sync_queue outbox. If either write fails, both
/// are rolled back — no orphaned queue items, no untracked mutations.
///
/// [convertFlag] is the critical method: it wraps BOTH the flag status
/// update AND punch list item creation in a single Drift transaction —
/// ensuring atomicity. If either write fails, neither persists.
@DriftAccessor(tables: [SiteWalkFlags, PunchListItems, SyncQueue])
class SiteWalkFlagDao extends DatabaseAccessor<AppDatabase>
    with _$SiteWalkFlagDaoMixin {
  SiteWalkFlagDao(super.db);

  // ────────────────────────────────────────────────────────────────────────
  // Flag streams
  // ────────────────────────────────────────────────────────────────────────

  /// Reactive stream of all active (non-deleted) flags for a project.
  ///
  /// Ordered newest-first for the site walk flag list view.
  Stream<List<SiteWalkFlag>> watchByProjectId(String projectId) {
    return (select(siteWalkFlags)
          ..where(
            (tbl) =>
                tbl.projectId.equals(projectId) & tbl.deletedAt.isNull(),
          )
          ..orderBy([(tbl) => OrderingTerm.desc(tbl.createdAt)]))
        .watch();
  }

  // ────────────────────────────────────────────────────────────────────────
  // Flag mutations (transactional outbox pattern)
  // ────────────────────────────────────────────────────────────────────────

  /// Insert a new site walk flag and atomically enqueue a CREATE sync item.
  ///
  /// Both the entity write and sync_queue insert happen in a single
  /// transaction — if either fails, both are rolled back.
  Future<void> createFlag(SiteWalkFlagsCompanion flag) async {
    await db.transaction(() async {
      await into(siteWalkFlags).insert(flag);
      await into(syncQueue).insert(
        _buildQueueEntry(
          entityType: 'site_walk_flag',
          entityId: flag.id.present ? flag.id.value : '',
          operation: 'CREATE',
          payload: _flagPayload(flag),
        ),
      );
    });
  }

  /// Update the status of a site walk flag and enqueue an UPDATE sync item.
  ///
  /// Used for standalone status transitions (e.g., 'open' → 'resolved' or
  /// 'dismissed'). For 'converted' status transitions, use [convertFlag]
  /// which also creates a punch list item in the same transaction.
  Future<void> updateStatus(String flagId, String status) async {
    await db.transaction(() async {
      await (update(siteWalkFlags)..where((f) => f.id.equals(flagId))).write(
        SiteWalkFlagsCompanion(
          status: Value(status),
          updatedAt: Value(DateTime.now()),
        ),
      );
      await into(syncQueue).insert(
        _buildQueueEntry(
          entityType: 'site_walk_flag',
          entityId: flagId,
          operation: 'UPDATE',
          payload: {'id': flagId, 'status': status},
        ),
      );
    });
  }

  /// Convert a site walk flag to a punch list item in a single Drift transaction.
  ///
  /// Atomically performs FOUR writes:
  /// 1. Update the flag status to 'converted' in [siteWalkFlags]
  /// 2. Enqueue an UPDATE sync item for the flag status change
  /// 3. Insert the new punch list item in [punchListItems]
  /// 4. Enqueue a CREATE sync item for the punch list item
  ///
  /// If ANY of these writes fails, ALL are rolled back — the flag remains
  /// 'open' and no punch list item is created. This guarantees consistency
  /// between the flag and punch list item state.
  ///
  /// The caller constructs [punchItem] with [sourceFlagId] set to [flagId]
  /// and copies the relevant fields (description, photoUrl, annotationData)
  /// from the flag.
  Future<void> convertFlag(
    String flagId,
    PunchListItemsCompanion punchItem,
  ) {
    return db.transaction(() async {
      // 1. Update flag status to 'converted'
      await (update(siteWalkFlags)..where((f) => f.id.equals(flagId))).write(
        SiteWalkFlagsCompanion(
          status: const Value('converted'),
          updatedAt: Value(DateTime.now()),
        ),
      );
      // 2. Enqueue UPDATE sync item for flag
      await into(syncQueue).insert(
        _buildQueueEntry(
          entityType: 'site_walk_flag',
          entityId: flagId,
          operation: 'UPDATE',
          payload: {'id': flagId, 'status': 'converted'},
        ),
      );
      // 3. Insert punch list item
      await into(punchListItems).insert(punchItem);
      // 4. Enqueue CREATE sync item for punch list item
      await into(syncQueue).insert(
        _buildQueueEntry(
          entityType: 'punch_list_item',
          entityId: punchItem.id.present ? punchItem.id.value : '',
          operation: 'CREATE',
          payload: {
            if (punchItem.id.present) 'id': punchItem.id.value,
            if (punchItem.companyId.present)
              'companyId': punchItem.companyId.value,
            if (punchItem.projectId.present)
              'projectId': punchItem.projectId.value,
            if (punchItem.tradeScopeId.present)
              'tradeScopeId': punchItem.tradeScopeId.value,
            if (punchItem.description.present)
              'description': punchItem.description.value,
            'sourceFlagId': flagId,
          },
        ),
      );
    });
  }

  /// Upsert a site walk flag received from the server during delta sync.
  ///
  /// Used by [SiteWalkFlagSyncHandler.applyPulled] to apply server-pushed
  /// flag data without enqueuing another sync item.
  Future<void> upsertFromServer(SiteWalkFlagsCompanion data) {
    return into(siteWalkFlags).insertOnConflictUpdate(data);
  }

  // ────────────────────────────────────────────────────────────────────────
  // Internal helpers
  // ────────────────────────────────────────────────────────────────────────

  /// Build a [SyncQueueCompanion] outbox entry for the given mutation.
  SyncQueueCompanion _buildQueueEntry({
    required String entityType,
    required String entityId,
    required String operation,
    required Map<String, dynamic> payload,
  }) {
    return SyncQueueCompanion.insert(
      id: Value(const Uuid().v4()),
      entityType: entityType,
      entityId: entityId,
      operation: operation,
      payload: jsonEncode(payload),
      status: const Value('pending'),
      attemptCount: const Value(0),
      createdAt: DateTime.now(),
    );
  }

  /// Build a JSON-serializable payload map from a [SiteWalkFlagsCompanion].
  Map<String, dynamic> _flagPayload(SiteWalkFlagsCompanion entry) {
    return {
      if (entry.id.present) 'id': entry.id.value,
      if (entry.companyId.present) 'companyId': entry.companyId.value,
      if (entry.projectId.present) 'projectId': entry.projectId.value,
      if (entry.flaggedBy.present) 'flaggedBy': entry.flaggedBy.value,
      if (entry.description.present) 'description': entry.description.value,
      if (entry.severity.present) 'severity': entry.severity.value,
      if (entry.locationLabel.present)
        'locationLabel': entry.locationLabel.value,
      if (entry.status.present) 'status': entry.status.value,
      if (entry.createdAt.present)
        'createdAt': entry.createdAt.value.toIso8601String(),
      if (entry.updatedAt.present)
        'updatedAt': entry.updatedAt.value.toIso8601String(),
    };
  }
}
