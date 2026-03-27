import 'dart:convert';

import 'package:drift/drift.dart';

import '../../database/app_database.dart';
import '../../network/dio_client.dart';
import '../sync_handler.dart';

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
    final userId = payload['userId'];
    if (userId is! String) {
      throw StateError('UserRoleSyncHandler: userId is required in payload');
    }
    await _dioClient.pushWithIdempotency(
      '/users/$userId/roles',
      payload,
      item.id,
    );
  }

  @override
  Future<void> applyPulled(Map<String, dynamic> data) async {
    final id = data['id'];
    final userId = data['user_id'];
    final companyId = data['company_id'];
    final role = data['role'];
    if (id is! String || userId is! String || companyId is! String || role is! String) {
      throw const FormatException('UserRole missing required fields');
    }

    final deletedAt = data['deleted_at'] != null
        ? DateTime.parse(data['deleted_at'].toString())
        : null;

    final companion = UserRolesCompanion(
      id: Value(id),
      userId: Value(userId),
      companyId: Value(companyId),
      role: Value(role),
      createdAt: data['created_at'] != null
          ? Value(DateTime.parse(data['created_at'].toString()))
          : const Value.absent(),
      deletedAt: Value(deletedAt),
    );

    await _db.into(_db.userRoles).insertOnConflictUpdate(companion);
  }
}
