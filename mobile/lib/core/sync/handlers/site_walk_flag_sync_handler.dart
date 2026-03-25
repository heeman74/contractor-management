import 'dart:convert';

import 'package:drift/drift.dart';

import '../../database/app_database.dart';
import '../../network/dio_client.dart';
import '../sync_handler.dart';

/// SyncHandler implementation for the SiteWalkFlag entity.
///
/// Pushes flag mutations to [POST /api/v1/projects/{project_id}/flags]
/// and [PATCH /api/v1/projects/{project_id}/flags/{flag_id}] with an
/// [Idempotency-Key] header set to the sync_queue item's UUID.
///
/// Applies pulled entities by upserting into the Drift [siteWalkFlags] table.
class SiteWalkFlagSyncHandler extends SyncHandler {
  final DioClient _dioClient;
  final AppDatabase _db;

  SiteWalkFlagSyncHandler(this._dioClient, this._db);

  @override
  String get entityType => 'site_walk_flag';

  @override
  Future<void> push(SyncQueueData item) async {
    final payload = jsonDecode(item.payload) as Map<String, dynamic>;
    final projectId = payload['projectId'] as String?;

    if (item.operation == 'CREATE') {
      if (projectId == null) {
        throw StateError(
            'SiteWalkFlagSyncHandler: projectId is required in CREATE payload');
      }
      await _dioClient.pushWithIdempotency(
        '/projects/$projectId/flags',
        payload,
        item.id,
      );
    } else if (item.operation == 'UPDATE') {
      // UPDATE payloads may only contain id + changed fields (e.g., status)
      // projectId may be absent; use entityId for the URL
      await _dioClient.pushWithIdempotency(
        '/projects/flags/${item.entityId}',
        payload,
        item.id,
        method: 'PATCH',
      );
    } else if (item.operation == 'DELETE') {
      await _dioClient.pushWithIdempotency(
        '/projects/flags/${item.entityId}',
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

    final companion = SiteWalkFlagsCompanion(
      id: Value(data['id'] as String),
      companyId: Value(data['company_id'] as String),
      projectId: Value(data['project_id'] as String),
      flaggedBy: Value(data['flagged_by'] as String),
      description: Value(data['description'] as String),
      severity: data['severity'] != null
          ? Value(data['severity'] as String)
          : const Value.absent(),
      locationLabel: Value(data['location_label'] as String?),
      photoUrl: Value(data['photo_url'] as String?),
      annotationData: Value(data['annotation_data'] as String?),
      status: data['status'] != null
          ? Value(data['status'] as String)
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

    await _db.into(_db.siteWalkFlags).insertOnConflictUpdate(companion);
  }
}
