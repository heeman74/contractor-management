import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:drift/drift.dart';

import '../../database/app_database.dart';
import '../../network/dio_client.dart';
import '../sync_handler.dart';

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
    final id = data['id'];
    final companyId = data['company_id'];
    final projectId = data['project_id'];
    final name = data['name'];
    if (id is! String || companyId is! String || projectId is! String || name is! String) {
      throw const FormatException('ProjectZone missing required fields');
    }

    final deletedAt = data['deleted_at'] != null
        ? DateTime.parse(data['deleted_at'].toString())
        : null;

    await _dao.upsertZone(
      ProjectZonesCompanion(
        id: Value(id),
        companyId: Value(companyId),
        projectId: Value(projectId),
        name: Value(name),
        version: data['version'] is int
            ? Value(data['version'] as int)
            : const Value(1),
        createdAt: data['created_at'] != null
            ? Value(DateTime.parse(data['created_at'].toString()))
            : Value(DateTime.now()),
        updatedAt: data['updated_at'] != null
            ? Value(DateTime.parse(data['updated_at'].toString()))
            : Value(DateTime.now()),
        deletedAt: Value(deletedAt),
      ),
    );
  }
}
