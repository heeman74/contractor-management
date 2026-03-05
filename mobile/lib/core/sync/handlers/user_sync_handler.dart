import 'dart:convert';

import 'package:drift/drift.dart';

import '../../database/app_database.dart';
import '../../network/dio_client.dart';
import '../sync_handler.dart';
import '../sync_queue_dao.dart';

/// SyncHandler implementation for the User entity.
///
/// Pushes user mutations to [POST /api/v1/users] with an
/// [Idempotency-Key] header set to the sync_queue item's UUID.
///
/// Applies pulled entities by upserting into the Drift [users] table.
/// Tombstones (non-null [deleted_at] in the response) are propagated by
/// setting the local [deletedAt] column.
class UserSyncHandler extends SyncHandler {
  final DioClient _dioClient;
  final AppDatabase _db;

  UserSyncHandler(this._dioClient, this._db);

  @override
  String get entityType => 'user';

  @override
  Future<void> push(SyncQueueData item) async {
    final payload = jsonDecode(item.payload) as Map<String, dynamic>;
    await _dioClient.pushWithIdempotency(
      '/users',
      payload,
      item.id,
    );
  }

  @override
  Future<void> applyPulled(Map<String, dynamic> data) async {
    final deletedAt = data['deleted_at'] != null
        ? DateTime.parse(data['deleted_at'] as String)
        : null;

    final companion = UsersCompanion(
      id: Value(data['id'] as String),
      companyId: Value(data['company_id'] as String),
      email: Value(data['email'] as String),
      firstName: Value(data['first_name'] as String?),
      lastName: Value(data['last_name'] as String?),
      phone: Value(data['phone'] as String?),
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

    await _db.into(_db.users).insertOnConflictUpdate(companion);
  }
}
