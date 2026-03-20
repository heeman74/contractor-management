import 'dart:convert';

import 'package:drift/drift.dart';

import '../../database/app_database.dart';
import '../../network/dio_client.dart';
import '../sync_handler.dart';

/// SyncHandler implementation for the TradeScope entity.
///
/// Pushes trade scope mutations to [POST /api/v1/trade-scopes] with an
/// [Idempotency-Key] header set to the sync_queue item's UUID.
///
/// Applies pulled entities by upserting into the Drift [tradeScopes] table.
class TradeScopeSyncHandler extends SyncHandler {
  final DioClient _dioClient;
  final AppDatabase _db;

  TradeScopeSyncHandler(this._dioClient, this._db);

  @override
  String get entityType => 'trade_scope';

  @override
  Future<void> push(SyncQueueData item) async {
    final payload = jsonDecode(item.payload) as Map<String, dynamic>;
    await _dioClient.pushWithIdempotency(
      '/trade-scopes',
      payload,
      item.id,
    );
  }

  @override
  Future<void> applyPulled(Map<String, dynamic> data) async {
    final deletedAt = data['deleted_at'] != null
        ? DateTime.parse(data['deleted_at'] as String)
        : null;

    final companion = TradeScopesCompanion(
      id: Value(data['id'] as String),
      companyId: Value(data['company_id'] as String),
      projectId: Value(data['project_id'] as String),
      tradeCatalogId: Value(data['trade_catalog_id'] as String?),
      tradeName: Value(data['trade_name'] as String),
      tradeColor: data['trade_color'] != null
          ? Value(data['trade_color'] as String)
          : const Value.absent(),
      contractorId: Value(data['contractor_id'] as String?),
      status: data['status'] != null
          ? Value(data['status'] as String)
          : const Value.absent(),
      statusOverride: data['status_override'] != null
          ? Value(data['status_override'] as bool)
          : const Value.absent(),
      sortOrder: data['sort_order'] != null
          ? Value(data['sort_order'] as int)
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

    await _db.into(_db.tradeScopes).insertOnConflictUpdate(companion);
  }
}
