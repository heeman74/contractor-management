import 'dart:convert';

import 'package:drift/drift.dart';

import '../../database/app_database.dart';
import '../../network/dio_client.dart';
import '../sync_handler.dart';
import '../sync_queue_dao.dart';

/// SyncHandler implementation for the JobNote entity.
///
/// Pushes note mutations to [POST /api/v1/jobs/{job_id}/notes] with an
/// [Idempotency-Key] header set to the sync_queue item's UUID.
///
/// Applies pulled entities by upserting into the Drift [jobNotes] table.
/// Tombstones (non-null [deleted_at] in the response) are propagated by
/// setting the local [deletedAt] column.
class NoteSyncHandler extends SyncHandler {
  final DioClient _dioClient;
  final AppDatabase _db;

  NoteSyncHandler(this._dioClient, this._db);

  @override
  String get entityType => 'job_note';

  @override
  Future<void> push(SyncQueueData item) async {
    final payload = jsonDecode(item.payload) as Map<String, dynamic>;
    final jobId = payload['job_id'] as String?;

    if (item.operation == 'CREATE') {
      await _dioClient.pushWithIdempotency(
        '/jobs/$jobId/notes',
        payload,
        item.id,
      );
    } else if (item.operation == 'UPDATE') {
      await _dioClient.pushWithIdempotency(
        '/jobs/$jobId/notes/${item.entityId}',
        payload,
        item.id,
        method: 'PATCH',
      );
    } else if (item.operation == 'DELETE') {
      await _dioClient.pushWithIdempotency(
        '/jobs/$jobId/notes/${item.entityId}',
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

    final companion = JobNotesCompanion(
      id: Value(data['id'] as String),
      companyId: Value(data['company_id'] as String),
      jobId: Value(data['job_id'] as String),
      authorId: Value(data['author_id'] as String),
      body: Value(data['body'] as String),
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

    await _db.into(_db.jobNotes).insertOnConflictUpdate(companion);
  }
}
