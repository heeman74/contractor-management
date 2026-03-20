import 'dart:convert';

import 'package:drift/drift.dart';

import '../../database/app_database.dart';
import '../../network/dio_client.dart';
import '../sync_handler.dart';

/// SyncHandler implementation for the TradeCatalogEntry entity.
///
/// Pushes trade catalog mutations to [POST /api/v1/trade-catalog] with an
/// [Idempotency-Key] header set to the sync_queue item's UUID.
///
/// Applies pulled entities by upserting into the Drift [tradeCatalogEntries] table.
class TradeCatalogSyncHandler extends SyncHandler {
  final DioClient _dioClient;
  final AppDatabase _db;

  TradeCatalogSyncHandler(this._dioClient, this._db);

  @override
  String get entityType => 'trade_catalog';

  @override
  Future<void> push(SyncQueueData item) async {
    final payload = jsonDecode(item.payload) as Map<String, dynamic>;
    await _dioClient.pushWithIdempotency(
      '/trade-catalog',
      payload,
      item.id,
    );
  }

  @override
  Future<void> applyPulled(Map<String, dynamic> data) async {
    final deletedAt = data['deleted_at'] != null
        ? DateTime.parse(data['deleted_at'] as String)
        : null;

    final companion = TradeCatalogEntriesCompanion(
      id: Value(data['id'] as String),
      companyId: Value(data['company_id'] as String),
      name: Value(data['name'] as String),
      color: data['color'] != null
          ? Value(data['color'] as String)
          : const Value.absent(),
      version: data['version'] != null
          ? Value(data['version'] as int)
          : const Value.absent(),
      createdAt: data['created_at'] != null
          ? Value(DateTime.parse(data['created_at'] as String))
          : const Value.absent(),
      updatedAt: data['updated_at'] != null
          ? Value(DateTime.parse(data['updated_at'] as String))
          : const Value.absent(),
      deletedAt: Value(deletedAt),
    );

    await _db.into(_db.tradeCatalogEntries).insertOnConflictUpdate(companion);
  }
}
