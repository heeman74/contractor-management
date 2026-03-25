import 'dart:convert';

import 'package:drift/drift.dart';

import '../../../core/database/app_database.dart';
import '../../../core/network/dio_client.dart';
import '../../../core/sync/sync_handler.dart';

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
    // Validate required fields before building companion to give clear errors
    final id = data['id'];
    final companyId = data['company_id'];
    if (id is! String || companyId is! String) {
      throw FormatException(
        'Job missing required fields: id=${id.runtimeType}, company_id=${companyId.runtimeType}',
      );
    }

    final deletedAt = data['deleted_at'] != null
        ? DateTime.parse(data['deleted_at'].toString())
        : null;

    final companion = JobsCompanion(
      id: Value(id),
      companyId: Value(companyId),
      clientId: Value(data['client_id']?.toString()),
      contractorId: Value(data['contractor_id']?.toString()),
      description: Value((data['description'] ?? '') as String),
      tradeType: Value((data['trade_type'] ?? '') as String),
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
      gpsLatitude: data['gps_latitude'] is num
          ? Value((data['gps_latitude'] as num).toDouble())
          : const Value(null),
      gpsLongitude: data['gps_longitude'] is num
          ? Value((data['gps_longitude'] as num).toDouble())
          : const Value(null),
      gpsAddress: Value(data['gps_address'] as String?),
      quoteId: Value(data['quote_id'] as String?),
      invoiceId: Value(data['invoice_id'] as String?),
      estimatedDurationMinutes:
          data['estimated_duration_minutes'] is int
              ? Value(data['estimated_duration_minutes'] as int)
              : const Value(null),
      scheduledCompletionDate: data['scheduled_completion_date'] != null
          ? Value(
              DateTime.parse(data['scheduled_completion_date'].toString()),
            )
          : const Value.absent(),
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

    await _db.into(_db.jobs).insertOnConflictUpdate(companion);
  }
}
