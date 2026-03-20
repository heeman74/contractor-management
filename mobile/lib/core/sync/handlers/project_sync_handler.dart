import 'dart:convert';

import 'package:drift/drift.dart';

import '../../database/app_database.dart';
import '../../network/dio_client.dart';
import '../sync_handler.dart';

/// SyncHandler implementation for the Project entity.
///
/// Pushes project mutations to [POST /api/v1/projects] with an
/// [Idempotency-Key] header set to the sync_queue item's UUID.
///
/// Applies pulled entities by upserting into the Drift [projects] table.
/// Tombstones (non-null [deleted_at] in the response) propagate via [deletedAt].
class ProjectSyncHandler extends SyncHandler {
  final DioClient _dioClient;
  final AppDatabase _db;

  ProjectSyncHandler(this._dioClient, this._db);

  @override
  String get entityType => 'project';

  @override
  Future<void> push(SyncQueueData item) async {
    final payload = jsonDecode(item.payload) as Map<String, dynamic>;
    await _dioClient.pushWithIdempotency(
      '/projects',
      payload,
      item.id,
    );
  }

  @override
  Future<void> applyPulled(Map<String, dynamic> data) async {
    final deletedAt = data['deleted_at'] != null
        ? DateTime.parse(data['deleted_at'] as String)
        : null;

    final companion = ProjectsCompanion(
      id: Value(data['id'] as String),
      companyId: Value(data['company_id'] as String),
      name: Value(data['name'] as String),
      description: Value(data['description'] as String?),
      address: Value(data['address'] as String?),
      clientId: Value(data['client_id'] as String?),
      status: data['status'] != null
          ? Value(data['status'] as String)
          : const Value.absent(),
      statusHistory: data['status_history'] != null
          ? Value(data['status_history'] as String)
          : const Value.absent(),
      targetStartDate: data['target_start_date'] != null
          ? Value(DateTime.parse(data['target_start_date'] as String))
          : const Value(null),
      targetEndDate: data['target_end_date'] != null
          ? Value(DateTime.parse(data['target_end_date'] as String))
          : const Value(null),
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

    await _db.into(_db.projects).insertOnConflictUpdate(companion);
  }
}
