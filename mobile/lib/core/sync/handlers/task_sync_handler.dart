import 'dart:convert';

import 'package:drift/drift.dart';

import '../../database/app_database.dart';
import '../../network/dio_client.dart';
import '../sync_handler.dart';

/// SyncHandler implementation for the ProjectTask entity.
///
/// Pushes task mutations to [POST /api/v1/tasks] with an
/// [Idempotency-Key] header set to the sync_queue item's UUID.
///
/// Applies pulled entities by upserting into the Drift [projectTasks] table.
class TaskSyncHandler extends SyncHandler {
  final DioClient _dioClient;
  final AppDatabase _db;

  TaskSyncHandler(this._dioClient, this._db);

  @override
  String get entityType => 'task';

  @override
  Future<void> push(SyncQueueData item) async {
    final payload = jsonDecode(item.payload) as Map<String, dynamic>;
    await _dioClient.pushWithIdempotency(
      '/tasks',
      payload,
      item.id,
    );
  }

  @override
  Future<void> applyPulled(Map<String, dynamic> data) async {
    final deletedAt = data['deleted_at'] != null
        ? DateTime.parse(data['deleted_at'] as String)
        : null;

    final companion = ProjectTasksCompanion(
      id: Value(data['id'] as String),
      companyId: Value(data['company_id'] as String),
      tradeScopeId: Value(data['trade_scope_id'] as String),
      title: Value(data['title'] as String),
      description: Value(data['description'] as String?),
      status: data['status'] != null
          ? Value(data['status'] as String)
          : const Value.absent(),
      sortOrder: data['sort_order'] != null
          ? Value(data['sort_order'] as int)
          : const Value.absent(),
      priority: data['priority'] != null
          ? Value(data['priority'] as String)
          : const Value.absent(),
      estimatedHours: data['estimated_hours'] != null
          ? Value((data['estimated_hours'] as num).toDouble())
          : const Value(null),
      estimatedCost: data['estimated_cost'] != null
          ? Value((data['estimated_cost'] as num).toDouble())
          : const Value(null),
      dueDate: data['due_date'] != null
          ? Value(DateTime.parse(data['due_date'] as String))
          : const Value(null),
      photoRequired: data['photo_required'] != null
          ? Value(data['photo_required'] as bool)
          : const Value.absent(),
      assignedTo: Value(data['assigned_to'] as String?),
      materialsNeeded: data['materials_needed'] != null
          ? Value(data['materials_needed'] as String)
          : const Value.absent(),
      dependsOn: data['depends_on'] != null
          ? Value(data['depends_on'] as String)
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

    await _db.into(_db.projectTasks).insertOnConflictUpdate(companion);
  }
}
