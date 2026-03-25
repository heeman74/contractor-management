import 'dart:convert';

import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:uuid/uuid.dart';

import '../../../core/database/app_database.dart';
import '../../../core/database/tables/punch_list_items.dart';
import '../../../core/database/tables/sync_queue.dart';

part 'punch_list_item_dao.g.dart';

/// Drift DAO for PunchListItem CRUD with transactional outbox dual-write.
///
/// All read methods return [Stream] — offline-first, reactive to local DB changes.
///
/// Every mutating method uses [db.transaction] to atomically write to BOTH
/// the punch_list_items table AND sync_queue outbox. If either write fails,
/// both are rolled back — no orphaned queue items, no untracked mutations.
///
/// [watchByScopeId] is the primary read method — GC punch list views are
/// scoped to a trade scope and ordered by priority (urgent first) then
/// creation date.
@DriftAccessor(tables: [PunchListItems, SyncQueue])
class PunchListItemDao extends DatabaseAccessor<AppDatabase>
    with _$PunchListItemDaoMixin {
  PunchListItemDao(super.db);

  // ────────────────────────────────────────────────────────────────────────
  // Punch list item streams
  // ────────────────────────────────────────────────────────────────────────

  /// Reactive stream of all active (non-deleted) punch list items for a
  /// trade scope.
  ///
  /// Ordered by priority (urgent → high → medium → low) then newest-first
  /// within each priority band — matches the GC punch list sort order.
  Stream<List<PunchListItem>> watchByScopeId(String tradeScopeId) {
    return (select(punchListItems)
          ..where(
            (tbl) =>
                tbl.tradeScopeId.equals(tradeScopeId) &
                tbl.deletedAt.isNull(),
          )
          ..orderBy([
            (tbl) => OrderingTerm(
                  expression: tbl.priority.caseMatch(whens: {
                    const Constant<String>('urgent'): const Constant<int>(0),
                    const Constant<String>('high'): const Constant<int>(1),
                    const Constant<String>('medium'): const Constant<int>(2),
                    const Constant<String>('low'): const Constant<int>(3),
                  }, orElse: const Constant<int>(2)),
                ),
            (tbl) => OrderingTerm.desc(tbl.createdAt),
          ]))
        .watch();
  }

  /// Reactive stream of all active (non-deleted) punch list items for a project.
  ///
  /// Ordered newest-first. Used by GC project-level punch list overview.
  Stream<List<PunchListItem>> watchByProjectId(String projectId) {
    return (select(punchListItems)
          ..where(
            (tbl) =>
                tbl.projectId.equals(projectId) & tbl.deletedAt.isNull(),
          )
          ..orderBy([(tbl) => OrderingTerm.desc(tbl.createdAt)]))
        .watch();
  }

  // ────────────────────────────────────────────────────────────────────────
  // Punch list item mutations (transactional outbox pattern)
  // ────────────────────────────────────────────────────────────────────────

  /// Insert a new punch list item and atomically enqueue a CREATE sync item.
  ///
  /// Both the entity write and sync_queue insert happen in a single
  /// transaction — if either fails, both are rolled back.
  ///
  /// Note: for punch list items created via flag conversion, use
  /// [SiteWalkFlagDao.convertFlag] which wraps both writes in a single
  /// transaction for atomicity.
  Future<void> createItem(PunchListItemsCompanion item) async {
    await db.transaction(() async {
      await into(punchListItems).insert(item);
      await into(syncQueue).insert(
        _buildQueueEntry(
          entityType: 'punch_list_item',
          entityId: item.id.present ? item.id.value : '',
          operation: 'CREATE',
          payload: _itemPayload(item),
        ),
      );
    });
  }

  /// Update a punch list item and atomically enqueue an UPDATE sync item.
  ///
  /// [updates] is a partial companion — only the fields to update need to
  /// be present. Both the entity write and sync_queue insert happen in a
  /// single transaction.
  Future<void> updateItem(
    String itemId,
    PunchListItemsCompanion updates,
  ) async {
    await db.transaction(() async {
      await (update(punchListItems)..where((tbl) => tbl.id.equals(itemId)))
          .write(updates);
      await into(syncQueue).insert(
        _buildQueueEntry(
          entityType: 'punch_list_item',
          entityId: itemId,
          operation: 'UPDATE',
          payload: {
            'id': itemId,
            if (updates.status.present) 'status': updates.status.value,
            if (updates.assignedTo.present)
              'assignedTo': updates.assignedTo.value,
            if (updates.priority.present) 'priority': updates.priority.value,
          },
        ),
      );
    });
  }

  /// Upsert a punch list item received from the server during delta sync.
  ///
  /// Used by [PunchListItemSyncHandler.applyPulled] to apply server-pushed
  /// item data without enqueuing another sync item.
  Future<void> upsertFromServer(PunchListItemsCompanion data) {
    return into(punchListItems).insertOnConflictUpdate(data);
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

  /// Build a JSON-serializable payload map from a [PunchListItemsCompanion].
  Map<String, dynamic> _itemPayload(PunchListItemsCompanion entry) {
    return {
      if (entry.id.present) 'id': entry.id.value,
      if (entry.companyId.present) 'companyId': entry.companyId.value,
      if (entry.projectId.present) 'projectId': entry.projectId.value,
      if (entry.tradeScopeId.present)
        'tradeScopeId': entry.tradeScopeId.value,
      if (entry.createdBy.present) 'createdBy': entry.createdBy.value,
      if (entry.assignedTo.present) 'assignedTo': entry.assignedTo.value,
      if (entry.description.present) 'description': entry.description.value,
      if (entry.priority.present) 'priority': entry.priority.value,
      if (entry.status.present) 'status': entry.status.value,
      if (entry.sourceFlagId.present)
        'sourceFlagId': entry.sourceFlagId.value,
      if (entry.createdAt.present)
        'createdAt': entry.createdAt.value.toIso8601String(),
      if (entry.updatedAt.present)
        'updatedAt': entry.updatedAt.value.toIso8601String(),
    };
  }
}
