import 'dart:convert';

import 'package:drift/drift.dart';

import '../../database/app_database.dart';
import '../../network/dio_client.dart';
import '../sync_handler.dart';
import '../sync_queue_dao.dart';

/// SyncHandler implementation for the TimeEntry entity.
///
/// Pushes time entry mutations to the backend:
/// - CREATE: POST to /api/v1/jobs/{job_id}/time-entries
/// - UPDATE: PATCH to /api/v1/jobs/{job_id}/time-entries/{entry_id}
///
/// Applies pulled entities by upserting into the Drift [timeEntries] table.
/// Tombstones (non-null [deleted_at] in the response) are propagated by
/// setting the local [deletedAt] column.
class TimeEntrySyncHandler extends SyncHandler {
  final DioClient _dioClient;
  final AppDatabase _db;

  TimeEntrySyncHandler(this._dioClient, this._db);

  @override
  String get entityType => 'time_entry';

  @override
  Future<void> push(SyncQueueData item) async {
    final payload = jsonDecode(item.payload) as Map<String, dynamic>;
    final jobId = payload['job_id'] as String?;

    if (item.operation == 'CREATE') {
      await _dioClient.pushWithIdempotency(
        '/jobs/$jobId/time-entries',
        payload,
        item.id,
      );
    } else if (item.operation == 'UPDATE') {
      await _dioClient.pushWithIdempotency(
        '/jobs/$jobId/time-entries/${item.entityId}',
        payload,
        item.id,
        method: 'PATCH',
      );
    } else if (item.operation == 'DELETE') {
      await _dioClient.pushWithIdempotency(
        '/jobs/$jobId/time-entries/${item.entityId}',
        payload,
        item.id,
        method: 'DELETE',
      );
    }
  }

  @override
  Future<void> applyPulled(Map<String, dynamic> data) async {
    final deletedAt = data['deleted_at'] != null
        ? DateTime.parse(data['deleted_at'] as String)
        : null;
    final clockedOutAt = data['clocked_out_at'] != null
        ? DateTime.parse(data['clocked_out_at'] as String)
        : null;

    final companion = TimeEntriesCompanion(
      id: Value(data['id'] as String),
      companyId: Value(data['company_id'] as String),
      jobId: Value(data['job_id'] as String),
      contractorId: Value(data['contractor_id'] as String),
      clockedInAt: Value(DateTime.parse(data['clocked_in_at'] as String)),
      clockedOutAt: Value(clockedOutAt),
      durationSeconds: Value(data['duration_seconds'] as int?),
      sessionStatus: data['session_status'] != null
          ? Value(data['session_status'] as String)
          : const Value.absent(),
      adjustmentLog: data['adjustment_log'] != null
          ? Value(data['adjustment_log'] as String)
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

    await _db.into(_db.timeEntries).insertOnConflictUpdate(companion);
  }
}
