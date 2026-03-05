import 'dart:convert';

import 'package:drift/drift.dart';

import '../../database/app_database.dart';
import '../../network/dio_client.dart';
import '../sync_handler.dart';
import '../sync_queue_dao.dart';

/// SyncHandler implementation for the UserRole entity.
///
/// Pushes user role mutations to [POST /api/v1/users/{userId}/roles] with an
/// [Idempotency-Key] header set to the sync_queue item's UUID.
///
/// Applies pulled entities by upserting into the Drift [userRoles] table.
/// Tombstones (non-null [deleted_at] in the response) are propagated by
/// setting the local [deletedAt] column.
class UserRoleSyncHandler extends SyncHandler {
  final DioClient _dioClient;
  final AppDatabase _db;

  UserRoleSyncHandler(this._dioClient, this._db);

  @override
  String get entityType => 'user_role';

  @override
  Future<void> push(SyncQueueData item) async {
    final payload = jsonDecode(item.payload) as Map<String, dynamic>;
    final userId = payload['userId'] as String;
    await _dioClient.pushWithIdempotency(
      '/users/$userId/roles',
      payload,
      item.id,
    );
  }

  @override
  Future<void> applyPulled(Map<String, dynamic> data) async {
    final deletedAt = data['deleted_at'] != null
        ? DateTime.parse(data['deleted_at'] as String)
        : null;

    final companion = UserRolesCompanion(
      id: Value(data['id'] as String),
      userId: Value(data['user_id'] as String),
      companyId: Value(data['company_id'] as String),
      role: Value(data['role'] as String),
      createdAt: data['created_at'] != null
          ? Value(DateTime.parse(data['created_at'] as String))
          : const Value.absent(),
      deletedAt: Value(deletedAt),
    );

    await _db.into(_db.userRoles).insertOnConflictUpdate(companion);
  }
}
