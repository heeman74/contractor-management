import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:drift/drift.dart';

import '../../database/app_database.dart';
import '../../network/dio_client.dart';
import '../sync_handler.dart';
import '../../../features/projects/data/project_zone_dao.dart';

/// SyncHandler implementation for the ProjectZone entity.
///
/// Pushes zone mutations to the backend:
/// - CREATE: POST /projects/{projectId}/zones with Idempotency-Key
/// - DELETE: DELETE /zones/{id}
///
/// Applies pulled entities by upserting into the Drift [projectZones] table.
class ProjectZoneSyncHandler extends SyncHandler {
  final DioClient _dioClient;
  final ProjectZoneDao _dao;

  ProjectZoneSyncHandler(this._dioClient, this._dao);

  @override
  String get entityType => 'project_zone';

  @override
  Future<void> push(SyncQueueData item) async {
    final payload = jsonDecode(item.payload) as Map<String, dynamic>;
    switch (item.operation) {
      case 'CREATE':
        await _dioClient.instance.post(
          '/projects/${payload['project_id']}/zones',
          data: {
            'name': payload['name'],
          },
          options: Options(headers: {'Idempotency-Key': item.id}),
        );
      case 'DELETE':
        await _dioClient.instance.delete('/zones/${payload['id']}');
    }
  }

  @override
  Future<void> applyPulled(Map<String, dynamic> data) async {
    final deletedAt = data['deleted_at'] != null
        ? DateTime.parse(data['deleted_at'] as String)
        : null;

    await _dao.upsertZone(
      ProjectZonesCompanion(
        id: Value(data['id'] as String),
        companyId: Value(data['company_id'] as String),
        projectId: Value(data['project_id'] as String),
        name: Value(data['name'] as String),
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
