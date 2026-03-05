import 'dart:convert';

import 'package:drift/drift.dart';

import '../../database/app_database.dart';
import '../../network/dio_client.dart';
import '../sync_handler.dart';
import '../sync_queue_dao.dart';

/// SyncHandler implementation for the Company entity.
///
/// Pushes company mutations to [POST /api/v1/companies] with an
/// [Idempotency-Key] header set to the sync_queue item's UUID.
///
/// Applies pulled entities by upserting into the Drift [companies] table.
/// Tombstones (non-null [deleted_at] in the response) are propagated by
/// setting the local [deletedAt] column.
class CompanySyncHandler extends SyncHandler {
  final DioClient _dioClient;
  final AppDatabase _db;

  CompanySyncHandler(this._dioClient, this._db);

  @override
  String get entityType => 'company';

  @override
  Future<void> push(SyncQueueData item) async {
    final payload = jsonDecode(item.payload) as Map<String, dynamic>;
    await _dioClient.pushWithIdempotency(
      '/companies',
      payload,
      item.id,
    );
  }

  @override
  Future<void> applyPulled(Map<String, dynamic> data) async {
    final deletedAt = data['deleted_at'] != null
        ? DateTime.parse(data['deleted_at'] as String)
        : null;

    final companion = CompaniesCompanion(
      id: Value(data['id'] as String),
      name: Value(data['name'] as String),
      address: Value(data['address'] as String?),
      phone: Value(data['phone'] as String?),
      businessNumber: Value(data['business_number'] as String?),
      logoUrl: Value(data['logo_url'] as String?),
      tradeTypes: Value(data['trade_types'] as String?),
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

    await _db.into(_db.companies).insertOnConflictUpdate(companion);
  }
}
