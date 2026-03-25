import 'dart:convert';

import 'package:drift/drift.dart';

import '../../database/app_database.dart';
import '../../network/dio_client.dart';
import '../sync_handler.dart';

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
    final id = data['id'];
    final name = data['name'];
    if (id is! String || name is! String) {
      throw FormatException('Company missing required fields');
    }

    final deletedAt = data['deleted_at'] != null
        ? DateTime.parse(data['deleted_at'].toString())
        : null;

    final companion = CompaniesCompanion(
      id: Value(id),
      name: Value(name),
      address: Value(data['address']?.toString()),
      phone: Value(data['phone']?.toString()),
      businessNumber: Value(data['business_number']?.toString()),
      logoUrl: Value(data['logo_url']?.toString()),
      tradeTypes: Value(data['trade_types']?.toString()),
      version: data['version'] is int
          ? Value(data['version'] as int)
          : const Value.absent(),
      createdAt: data['created_at'] != null
          ? Value(DateTime.parse(data['created_at'].toString()))
          : const Value.absent(),
      updatedAt: data['updated_at'] != null
          ? Value(DateTime.parse(data['updated_at'].toString()))
          : const Value.absent(),
      deletedAt: Value(deletedAt),
    );

    await _db.into(_db.companies).insertOnConflictUpdate(companion);
  }
}
