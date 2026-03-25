import 'dart:convert';

import 'package:drift/drift.dart';

import '../../database/app_database.dart';
import '../../network/dio_client.dart';
import '../sync_handler.dart';

/// SyncHandler implementation for the TaskInspection entity.
///
/// Pushes inspection mutations to [POST /api/v1/tasks/{task_id}/inspections]
/// with an [Idempotency-Key] header set to the sync_queue item's UUID.
///
/// Applies pulled entities by upserting into the Drift [taskInspections] table.
class TaskInspectionSyncHandler extends SyncHandler {
  final DioClient _dioClient;
  final AppDatabase _db;

  TaskInspectionSyncHandler(this._dioClient, this._db);

  @override
  String get entityType => 'task_inspection';

  @override
  Future<void> push(SyncQueueData item) async {
    final payload = jsonDecode(item.payload) as Map<String, dynamic>;
    final taskId = payload['taskId'] as String?;
    if (taskId == null) {
      throw StateError(
          'TaskInspectionSyncHandler: taskId is required in payload');
    }

    await _dioClient.pushWithIdempotency(
      '/tasks/$taskId/inspections',
      payload,
      item.id,
    );
  }

  @override
  Future<void> applyPulled(Map<String, dynamic> data) async {
    final deletedAt = data['deleted_at'] != null
        ? DateTime.parse(data['deleted_at'] as String)
        : null;

    final companion = TaskInspectionsCompanion(
      id: Value(data['id'] as String),
      companyId: Value(data['company_id'] as String),
      taskId: Value(data['task_id'] as String),
      inspectorId: Value(data['inspector_id'] as String),
      decision: Value(data['decision'] as String),
      checklistResults: data['checklist_results'] != null
          ? Value(data['checklist_results'] as String)
          : const Value.absent(),
      rejectionReason: Value(data['rejection_reason'] as String?),
      rejectionComment: Value(data['rejection_comment'] as String?),
      rejectionPhotoUrl: Value(data['rejection_photo_url'] as String?),
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

    await _db.into(_db.taskInspections).insertOnConflictUpdate(companion);
  }
}
