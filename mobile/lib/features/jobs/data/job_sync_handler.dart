import 'dart:convert';

import 'package:drift/drift.dart';

import '../../../core/database/app_database.dart';
import '../../../core/network/dio_client.dart';
import '../../../core/sync/sync_handler.dart';
import '../../../core/sync/sync_queue_dao.dart';

/// SyncHandler implementation for the Job entity.
///
/// Push: routes CREATE/UPDATE/DELETE to the appropriate REST endpoints.
/// - CREATE → POST /api/v1/jobs/
/// - UPDATE → PATCH /api/v1/jobs/{id}
/// - DELETE → DELETE /api/v1/jobs/{id}
///
/// Pull: upserts received entities into the local Drift [jobs] table.
/// Tombstones (non-null [deleted_at]) are propagated as soft deletes.
class JobSyncHandler extends SyncHandler {
  final DioClient _dioClient;
  final AppDatabase _db;

  JobSyncHandler(this._dioClient, this._db);

  @override
  String get entityType => 'job';

  @override
  Future<void> push(SyncQueueData item) async {
    final payload = jsonDecode(item.payload) as Map<String, dynamic>;

    switch (item.operation.toUpperCase()) {
      case 'CREATE':
        await _dioClient.pushWithIdempotency(
          '/jobs/',
          payload,
          item.id,
        );
      case 'UPDATE':
        final jobId = item.entityId;
        await _dioClient.pushWithIdempotency(
          '/jobs/$jobId',
          payload,
          item.id,
          method: 'PATCH',
        );
      case 'DELETE':
        final jobId = item.entityId;
        await _dioClient.pushWithIdempotency(
          '/jobs/$jobId',
          payload,
          item.id,
          method: 'DELETE',
        );
      default:
        throw StateError(
          'JobSyncHandler: unknown operation "${item.operation}"',
        );
    }
  }

  @override
  Future<void> applyPulled(Map<String, dynamic> data) async {
    final deletedAt = data['deleted_at'] != null
        ? DateTime.parse(data['deleted_at'] as String)
        : null;

    final companion = JobsCompanion(
      id: Value(data['id'] as String),
      companyId: Value(data['company_id'] as String),
      clientId: Value(data['client_id'] as String?),
      contractorId: Value(data['contractor_id'] as String?),
      description: Value(data['description'] as String),
      tradeType: Value(data['trade_type'] as String),
      status: data['status'] != null
          ? Value(data['status'] as String)
          : const Value.absent(),
      statusHistory: data['status_history'] != null
          ? Value(
              data['status_history'] is String
                  ? data['status_history'] as String
                  : jsonEncode(data['status_history']),
            )
          : const Value.absent(),
      priority: data['priority'] != null
          ? Value(data['priority'] as String)
          : const Value.absent(),
      purchaseOrderNumber:
          Value(data['purchase_order_number'] as String?),
      externalReference: Value(data['external_reference'] as String?),
      tags: data['tags'] != null
          ? Value(
              data['tags'] is String
                  ? data['tags'] as String
                  : jsonEncode(data['tags']),
            )
          : const Value.absent(),
      notes: Value(data['notes'] as String?),
      estimatedDurationMinutes:
          Value(data['estimated_duration_minutes'] as int?),
      scheduledCompletionDate: data['scheduled_completion_date'] != null
          ? Value(
              DateTime.parse(data['scheduled_completion_date'] as String),
            )
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

    await _db.into(_db.jobs).insertOnConflictUpdate(companion);
  }
}
