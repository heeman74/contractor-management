import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:uuid/uuid.dart';

import '../../../core/database/app_database.dart';
import '../../../core/database/tables/sync_queue.dart';
import '../../../core/database/tables/user_roles.dart';
import '../../../core/database/tables/users.dart';
import '../../../shared/models/user_role.dart' as role_enum;
import '../domain/user_entity.dart';
import '../domain/user_role_entity.dart';

part 'user_dao.g.dart';

/// Drift DAO for User and UserRole CRUD operations.
///
/// All read methods return [Stream] — offline-first pattern.
/// The [watchUsersByCompany] and [watchRolesForUser] streams are the
/// primary data sources for all user-related UI widgets.
///
/// Every mutating method uses [db.transaction] to atomically write to BOTH
/// the entity table AND sync_queue outbox. If either write fails, both are
/// rolled back — no orphaned queue items, no untracked mutations.
@DriftAccessor(tables: [Users, UserRoles, SyncQueue])
class UserDao extends DatabaseAccessor<AppDatabase> with _$UserDaoMixin {
  UserDao(super.db);

  /// Reactive stream of all active (non-deleted) users scoped to a specific company.
  ///
  /// This is the local-side tenant filter — mirrors the backend RLS policy.
  /// Soft-deleted users (deletedAt != null) are excluded.
  /// UI should watch this stream to display the users list.
  Stream<List<UserEntity>> watchUsersByCompany(String companyId) {
    return (select(users)
          ..where(
            (tbl) =>
                tbl.companyId.equals(companyId) & tbl.deletedAt.isNull(),
          ))
        .watch()
        .map((rows) => rows.map(_rowToUserEntity).toList());
  }

  /// Reactive stream of active users who hold a specific role within a company.
  ///
  /// Joins [users] with [userRoles] to filter by role name. Used by the job
  /// wizard to populate client and contractor selector dropdowns.
  Stream<List<UserEntity>> watchUsersByRole(String companyId, String role) {
    final query = select(users).join([
      innerJoin(
        userRoles,
        userRoles.userId.equalsExp(users.id) &
            userRoles.companyId.equalsExp(users.companyId),
      ),
    ])
      ..where(
        users.companyId.equals(companyId) &
            users.deletedAt.isNull() &
            userRoles.role.equals(role),
      );

    return query.watch().map(
          (rows) => rows
              .map((row) => _rowToUserEntity(row.readTable(users)))
              .toList(),
        );
  }

  /// Fetch a single user by ID. Returns null if not found.
  Future<UserEntity?> getUserById(String id) async {
    final row = await (select(users)
          ..where((tbl) => tbl.id.equals(id)))
        .getSingleOrNull();
    return row == null ? null : _rowToUserEntity(row);
  }

  /// Reactive stream of all roles for a specific user.
  Stream<List<UserRoleEntity>> watchRolesForUser(String userId) {
    return (select(userRoles)
          ..where((tbl) => tbl.userId.equals(userId)))
        .watch()
        .map((rows) => rows.map(_rowToUserRoleEntity).toList());
  }

  /// Insert a new user and atomically enqueue a CREATE sync item.
  ///
  /// Both the entity write and sync_queue insert happen in a single
  /// transaction — if either fails, both are rolled back.
  Future<void> insertUser(UsersCompanion entry) async {
    await db.transaction(() async {
      await into(users).insert(entry);
      await into(syncQueue).insert(
        _buildQueueEntry(
          entityType: 'user',
          entityId: entry.id.value,
          operation: 'CREATE',
          payload: _userPayload(entry),
        ),
      );
    });
  }

  /// Assign a role to a user within a company and atomically enqueue a
  /// CREATE sync item for the user_role entity.
  ///
  /// Both writes are in a single transaction.
  Future<void> assignRole(UserRolesCompanion entry) async {
    await db.transaction(() async {
      await into(userRoles).insert(entry);
      await into(syncQueue).insert(
        _buildQueueEntry(
          entityType: 'user_role',
          entityId: entry.id.value,
          operation: 'CREATE',
          payload: _userRolePayload(entry),
        ),
      );
    });
  }

  /// Build a [SyncQueueCompanion] outbox entry for the given mutation.
  SyncQueueCompanion _buildQueueEntry({
    required String entityType,
    required String entityId,
    required String operation,
    required Map<String, dynamic> payload,
  }) {
    return SyncQueueCompanion.insert(
      id: Value(const Uuid().v4()),
      entityType: entityType,
      entityId: entityId,
      operation: operation,
      payload: jsonEncode(payload),
      status: const Value('pending'),
      attemptCount: const Value(0),
      createdAt: DateTime.now(),
    );
  }

  /// Build a JSON-serializable payload map from a [UsersCompanion].
  Map<String, dynamic> _userPayload(UsersCompanion entry) {
    return {
      'id': entry.id.value,
      'companyId': entry.companyId.value,
      'email': entry.email.value,
      if (entry.firstName.present) 'firstName': entry.firstName.value,
      if (entry.lastName.present) 'lastName': entry.lastName.value,
      if (entry.phone.present) 'phone': entry.phone.value,
      if (entry.version.present) 'version': entry.version.value,
      if (entry.createdAt.present)
        'createdAt': entry.createdAt.value.toIso8601String(),
      if (entry.updatedAt.present)
        'updatedAt': entry.updatedAt.value.toIso8601String(),
    };
  }

  /// Build a JSON-serializable payload map from a [UserRolesCompanion].
  Map<String, dynamic> _userRolePayload(UserRolesCompanion entry) {
    return {
      'id': entry.id.value,
      'userId': entry.userId.value,
      'companyId': entry.companyId.value,
      'role': entry.role.value,
      if (entry.createdAt.present)
        'createdAt': entry.createdAt.value.toIso8601String(),
    };
  }

  /// Map a Drift [User] row to a [UserEntity] domain object.
  UserEntity _rowToUserEntity(User row) {
    return UserEntity(
      id: row.id,
      companyId: row.companyId,
      email: row.email,
      firstName: row.firstName,
      lastName: row.lastName,
      phone: row.phone,
      version: row.version,
      createdAt: row.createdAt,
      updatedAt: row.updatedAt,
    );
  }

  /// Map a Drift [UserRole] row to a [UserRoleEntity] domain object.
  UserRoleEntity _rowToUserRoleEntity(UserRole row) {
    return UserRoleEntity(
      id: row.id,
      userId: row.userId,
      companyId: row.companyId,
      role: role_enum.UserRole.fromString(row.role),
      createdAt: row.createdAt,
    );
  }
}
