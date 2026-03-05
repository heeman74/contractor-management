import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../../../core/di/service_locator.dart';
import '../../../../core/database/app_database.dart';
import '../../domain/user_entity.dart';
import '../../domain/user_role_entity.dart';

part 'user_providers.g.dart';

/// Reactive stream of all users for a specific company from local Drift DB.
///
/// Offline-first pattern: UI watches this stream, HTTP sync (Phase 2)
/// writes to the local DB, which automatically notifies this stream.
///
/// The [companyId] parameter provides local tenant scoping, mirroring
/// the backend RLS policy.
///
/// Usage:
/// ```dart
/// final usersAsync = ref.watch(companyUsersProvider('company-id'));
/// ```
@riverpod
Stream<List<UserEntity>> companyUsers(Ref ref, String companyId) {
  final db = getIt<AppDatabase>();
  return db.userDao.watchUsersByCompany(companyId);
}

/// Reactive stream of all roles for a specific user.
@riverpod
Stream<List<UserRoleEntity>> userRoles(Ref ref, String userId) {
  final db = getIt<AppDatabase>();
  return db.userDao.watchRolesForUser(userId);
}
