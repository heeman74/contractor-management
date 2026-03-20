import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:uuid/uuid.dart';

import '../../../core/database/app_database.dart';
import '../../../core/database/tables/sync_queue.dart';
import '../../../core/database/tables/trade_catalog.dart';

part 'trade_catalog_dao.g.dart';

/// Drift DAO for TradeCatalogEntry CRUD operations.
///
/// TradeCatalogEntries define the company's available trade types.
/// Changes are synced to backend via the outbox queue.
@DriftAccessor(tables: [TradeCatalogEntries, SyncQueue])
class TradeCatalogDao extends DatabaseAccessor<AppDatabase>
    with _$TradeCatalogDaoMixin {
  TradeCatalogDao(super.db);

  /// Reactive stream of all active (non-deleted) catalog entries for a company.
  ///
  /// Ordered alphabetically by name for consistent display.
  Stream<List<TradeCatalogEntry>> watchCatalogByCompany(String companyId) {
    return (select(tradeCatalogEntries)
          ..where(
            (tbl) =>
                tbl.companyId.equals(companyId) & tbl.deletedAt.isNull(),
          )
          ..orderBy([(tbl) => OrderingTerm.asc(tbl.name)]))
        .watch();
  }

  /// Insert a new catalog entry and atomically enqueue a CREATE sync item.
  Future<void> insertCatalogEntry(TradeCatalogEntriesCompanion entry) async {
    await db.transaction(() async {
      await into(tradeCatalogEntries).insert(entry);
      await into(syncQueue).insert(
        _buildQueueEntry(
          entityType: 'trade_catalog',
          entityId: entry.id.value,
          operation: 'CREATE',
          payload: _catalogPayload(entry),
        ),
      );
    });
  }

  /// Update an existing catalog entry and atomically enqueue an UPDATE sync item.
  Future<void> updateCatalogEntry(
      String id, TradeCatalogEntriesCompanion entry) async {
    await db.transaction(() async {
      await (update(tradeCatalogEntries)..where((tbl) => tbl.id.equals(id)))
          .write(entry);
      await into(syncQueue).insert(
        _buildQueueEntry(
          entityType: 'trade_catalog',
          entityId: id,
          operation: 'UPDATE',
          payload: _catalogPayload(entry),
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

  /// Build a JSON-serializable payload map from a [TradeCatalogEntriesCompanion].
  Map<String, dynamic> _catalogPayload(TradeCatalogEntriesCompanion entry) {
    return {
      if (entry.id.present) 'id': entry.id.value,
      if (entry.companyId.present) 'companyId': entry.companyId.value,
      if (entry.name.present) 'name': entry.name.value,
      if (entry.color.present) 'color': entry.color.value,
      if (entry.version.present) 'version': entry.version.value,
      if (entry.createdAt.present)
        'createdAt': entry.createdAt.value.toIso8601String(),
      if (entry.updatedAt.present)
        'updatedAt': entry.updatedAt.value.toIso8601String(),
    };
  }
}
