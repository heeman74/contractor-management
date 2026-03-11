import 'package:flutter_riverpod/flutter_riverpod.dart';
// StateProvider moved to legacy in Riverpod 3 — explicitly imported.
// ignore: depend_on_referenced_packages
import 'package:riverpod/legacy.dart';

import '../../../../core/database/app_database.dart';
import '../../../../core/di/service_locator.dart';
import '../../domain/user_entity.dart';
import '../../domain/user_role_entity.dart';

/// StateProvider for the team member search query.
///
/// Updated by the search bar in [TeamManagementScreen]. The screen
/// filters [companyUsersProvider] results against this query string.
final teamSearchQueryProvider = StateProvider<String>((ref) => '');

/// Reactive stream of all users for a specific company from local Drift DB.
///
/// Offline-first pattern: UI watches this stream, HTTP sync (Phase 2)
/// writes to the local DB, which automatically notifies this stream.
///
/// The [companyId] parameter provides local tenant scoping, mirroring
/// the backend RLS policy.
final companyUsersProvider = StreamProvider.autoDispose
    .family<List<UserEntity>, String>((ref, companyId) {
  final db = getIt<AppDatabase>();
  return db.userDao.watchUsersByCompany(companyId);
});

/// Reactive stream of all roles for a specific user.
final userRolesProvider = StreamProvider.autoDispose
    .family<List<UserRoleEntity>, String>((ref, userId) {
  final db = getIt<AppDatabase>();
  return db.userDao.watchRolesForUser(userId);
});

/// Reactive stream of users with the 'client' role for a specific company.
///
/// Used by the job wizard client selector dropdown.
final companyClientsProvider = StreamProvider.autoDispose
    .family<List<UserEntity>, String>((ref, companyId) {
  final db = getIt<AppDatabase>();
  return db.userDao.watchUsersByRole(companyId, 'client');
});

/// Reactive stream of users with the 'contractor' role for a specific company.
///
/// Used by the job wizard contractor selector dropdown.
final companyContractorsProvider = StreamProvider.autoDispose
    .family<List<UserEntity>, String>((ref, companyId) {
  final db = getIt<AppDatabase>();
  return db.userDao.watchUsersByRole(companyId, 'contractor');
});
