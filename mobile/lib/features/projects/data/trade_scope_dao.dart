import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:uuid/uuid.dart';

import '../../../core/database/app_database.dart';
import '../../../core/database/tables/sync_queue.dart';
import '../../../core/database/tables/trade_scopes.dart';

part 'trade_scope_dao.g.dart';

/// Drift DAO for TradeScope CRUD operations.
///
/// TradeScopes represent a single trade's scope of work within a project.
/// Each scope can be assigned to a contractor and contains ordered tasks.
///
/// [watchScopesByProject] is the primary stream for project detail views.
@DriftAccessor(tables: [TradeScopes, SyncQueue])
class TradeScopeDao extends DatabaseAccessor<AppDatabase>
    with _$TradeScopeDaoMixin {
  TradeScopeDao(super.db);

  /// Reactive stream of all active (non-deleted) trade scopes for a company.
  ///
  /// Used in the My Tasks screen to build a scopeId → tradeName lookup map
  /// without needing to know which projects the contractor belongs to.
  Stream<List<TradeScope>> watchAllScopesByCompany(String companyId) {
    return (select(tradeScopes)
          ..where(
            (tbl) =>
                tbl.companyId.equals(companyId) & tbl.deletedAt.isNull(),
          ))
        .watch();
  }

  /// Reactive stream of all active (non-deleted) trade scopes for a project.
  ///
  /// Ordered by [sortOrder] for consistent display in project detail view.
  Stream<List<TradeScope>> watchScopesByProject(String projectId) {
    return (select(tradeScopes)
          ..where(
            (tbl) =>
                tbl.projectId.equals(projectId) & tbl.deletedAt.isNull(),
          )
          ..orderBy([(tbl) => OrderingTerm.asc(tbl.sortOrder)]))
        .watch();
  }

  /// Reactive stream for a single trade scope by its ID.
  ///
  /// Returns a stream emitting [TradeScope?] — null if the scope is not found
  /// or has been soft-deleted. Used by TaskDetailScreen to load the scope's
  /// [inspectionChecklist] JSON for the GC's inspection checklist section.
  Stream<TradeScope?> watchScopeById(String scopeId) {
    return (select(tradeScopes)
          ..where(
            (tbl) => tbl.id.equals(scopeId) & tbl.deletedAt.isNull(),
          )
          ..limit(1))
        .watchSingleOrNull();
  }

  /// Insert a new trade scope and atomically enqueue a CREATE sync item.
  Future<void> insertScope(TradeScopesCompanion entry) async {
    await db.transaction(() async {
      await into(tradeScopes).insert(entry);
      await into(syncQueue).insert(
        _buildQueueEntry(
          entityType: 'trade_scope',
          entityId: entry.id.value,
          operation: 'CREATE',
          payload: _scopePayload(entry),
        ),
      );
    });
  }

  /// Update a trade scope and atomically enqueue an UPDATE sync item.
  Future<void> updateScope(String id, TradeScopesCompanion entry) async {
    await db.transaction(() async {
      await (update(tradeScopes)..where((tbl) => tbl.id.equals(id)))
          .write(entry);
      await into(syncQueue).insert(
        _buildQueueEntry(
          entityType: 'trade_scope',
          entityId: id,
          operation: 'UPDATE',
          payload: _scopePayload(entry),
        ),
      );
    });
  }

  /// Soft-delete a trade scope and atomically enqueue a DELETE sync item.
  Future<void> softDeleteScope(String id) async {
    await db.transaction(() async {
      await (update(tradeScopes)..where((tbl) => tbl.id.equals(id))).write(
        TradeScopesCompanion(deletedAt: Value(DateTime.now())),
      );
      await into(syncQueue).insert(
        _buildQueueEntry(
          entityType: 'trade_scope',
          entityId: id,
          operation: 'DELETE',
          payload: {'id': id},
        ),
      );
    });
  }

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

  /// Build a JSON-serializable payload map from a [TradeScopesCompanion].
  Map<String, dynamic> _scopePayload(TradeScopesCompanion entry) {
    return {
      if (entry.id.present) 'id': entry.id.value,
      if (entry.companyId.present) 'companyId': entry.companyId.value,
      if (entry.projectId.present) 'projectId': entry.projectId.value,
      if (entry.tradeCatalogId.present)
        'tradeCatalogId': entry.tradeCatalogId.value,
      if (entry.tradeName.present) 'tradeName': entry.tradeName.value,
      if (entry.tradeColor.present) 'tradeColor': entry.tradeColor.value,
      if (entry.contractorId.present) 'contractorId': entry.contractorId.value,
      if (entry.status.present) 'status': entry.status.value,
      if (entry.statusOverride.present)
        'statusOverride': entry.statusOverride.value,
      if (entry.sortOrder.present) 'sortOrder': entry.sortOrder.value,
      if (entry.version.present) 'version': entry.version.value,
      if (entry.createdAt.present)
        'createdAt': entry.createdAt.value.toIso8601String(),
      if (entry.updatedAt.present)
        'updatedAt': entry.updatedAt.value.toIso8601String(),
    };
  }
}
