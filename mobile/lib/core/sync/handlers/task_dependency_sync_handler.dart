import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:drift/drift.dart';

import '../../database/app_database.dart';
import '../../network/dio_client.dart';
import '../sync_handler.dart';

/// SyncHandler implementation for the TaskDependency entity.
///
/// Pushes dependency mutations to the backend:
/// - CREATE: POST /tasks/{successorTaskId}/dependencies with Idempotency-Key
/// - DELETE: DELETE /dependencies/{id}
///
/// Applies pulled entities by upserting into the Drift [taskDependencies] table.
class TaskDependencySyncHandler extends SyncHandler {
  final DioClient _dioClient;
  final TaskDependencyDao _dao;

  TaskDependencySyncHandler(this._dioClient, this._dao);

  @override
  String get entityType => 'task_dependency';

  @override
  Future<void> push(SyncQueueData item) async {
    final payload = jsonDecode(item.payload) as Map<String, dynamic>;
    switch (item.operation) {
      case 'CREATE':
        await _dioClient.instance.post(
          '/tasks/${payload['successor_task_id']}/dependencies',
          data: {
            'predecessor_task_id': payload['predecessor_task_id'],
            'dependency_type': payload['dependency_type'],
            'lag_days': payload['lag_days'],
          },
          options: Options(headers: {'Idempotency-Key': item.id}),
        );
      case 'DELETE':
        await _dioClient.instance.delete('/dependencies/${payload['id']}');
    }
  }

  @override
  Future<void> applyPulled(Map<String, dynamic> data) async {
    final deletedAt = data['deleted_at'] != null
        ? DateTime.parse(data['deleted_at'] as String)
        : null;

    await _dao.upsertDependency(
      TaskDependenciesCompanion(
        id: Value(data['id'] as String),
        companyId: Value(data['company_id'] as String),
        predecessorTaskId: Value(data['predecessor_task_id'] as String),
        successorTaskId: Value(data['successor_task_id'] as String),
        dependencyType: data['dependency_type'] != null
            ? Value(data['dependency_type'] as String)
            : const Value('FS'),
        lagDays: data['lag_days'] != null
            ? Value(data['lag_days'] as int)
            : const Value(0),
        version: data['version'] != null
            ? Value(data['version'] as int)
            : const Value(1),
        createdAt: Value(DateTime.parse(data['created_at'] as String)),
        updatedAt: Value(DateTime.parse(data['updated_at'] as String)),
        deletedAt: Value(deletedAt),
      ),
    );
  }
}
