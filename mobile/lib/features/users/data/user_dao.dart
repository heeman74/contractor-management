import 'package:drift/drift.dart';

import '../../../core/database/app_database.dart';
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
@DriftAccessor(tables: [Users, UserRoles])
class UserDao extends DatabaseAccessor<AppDatabase> with _$UserDaoMixin {
  UserDao(super.db);

  /// Reactive stream of all users scoped to a specific company.
  ///
  /// This is the local-side tenant filter — mirrors the backend RLS policy.
  /// UI should watch this stream to display the users list.
  Stream<List<UserEntity>> watchUsersByCompany(String companyId) {
    return (select(users)
          ..where((tbl) => tbl.companyId.equals(companyId)))
        .watch()
        .map((rows) => rows.map(_rowToUserEntity).toList());
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

  /// Insert a new user.
  Future<void> insertUser(UsersCompanion entry) async {
    await into(users).insert(entry);
  }

  /// Assign a role to a user within a company.
  Future<void> assignRole(UserRolesCompanion entry) async {
    await into(userRoles).insert(entry);
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
