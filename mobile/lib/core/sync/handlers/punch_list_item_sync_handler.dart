import 'dart:convert';

import 'package:drift/drift.dart';

import '../../database/app_database.dart';
import '../../network/dio_client.dart';
import '../sync_handler.dart';

/// SyncHandler implementation for the PunchListItem entity.
///
/// Pushes item mutations to [POST /api/v1/scopes/{trade_scope_id}/punch-items]
/// and [PATCH /api/v1/punch-items/{item_id}] with an [Idempotency-Key] header
/// set to the sync_queue item's UUID.
///
/// Applies pulled entities by upserting into the Drift [punchListItems] table.
class PunchListItemSyncHandler extends SyncHandler {
  final DioClient _dioClient;
  final AppDatabase _db;

  PunchListItemSyncHandler(this._dioClient, this._db);

  @override
  String get entityType => 'punch_list_item';

  @override
  Future<void> push(SyncQueueData item) async {
    final payload = jsonDecode(item.payload) as Map<String, dynamic>;
    final tradeScopeId = payload['tradeScopeId'] as String?;

    if (item.operation == 'CREATE') {
      if (tradeScopeId == null) {
        throw StateError(
            'PunchListItemSyncHandler: tradeScopeId is required in CREATE payload');
      }
      await _dioClient.pushWithIdempotency(
        '/scopes/$tradeScopeId/punch-items',
        payload,
        item.id,
      );
    } else if (item.operation == 'UPDATE') {
      await _dioClient.pushWithIdempotency(
        '/punch-items/${item.entityId}',
        payload,
        item.id,
        method: 'PATCH',
      );
    } else if (item.operation == 'DELETE') {
      await _dioClient.pushWithIdempotency(
        '/punch-items/${item.entityId}',
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

    final dueDate = data['due_date'] != null
        ? DateTime.parse(data['due_date'] as String)
        : null;

    final companion = PunchListItemsCompanion(
      id: Value(data['id'] as String),
      companyId: Value(data['company_id'] as String),
      projectId: Value(data['project_id'] as String),
      tradeScopeId: Value(data['trade_scope_id'] as String),
      createdBy: Value(data['created_by'] as String),
      assignedTo: Value(data['assigned_to'] as String?),
      description: Value(data['description'] as String),
      priority: data['priority'] != null
          ? Value(data['priority'] as String)
          : const Value.absent(),
      status: data['status'] != null
          ? Value(data['status'] as String)
          : const Value.absent(),
      photoUrl: Value(data['photo_url'] as String?),
      annotationData: Value(data['annotation_data'] as String?),
      sourceFlagId: Value(data['source_flag_id'] as String?),
      dueDate: Value(dueDate),
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

    await _db.into(_db.punchListItems).insertOnConflictUpdate(companion);
  }
}
