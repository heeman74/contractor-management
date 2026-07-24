/// Unit tests for [TeamManagementService] using a real in-memory Drift DB.
///
/// Covers the membership logic extracted out of the team management screen:
/// 1. addMember inserts the user and assigns the role
/// 2. addMember with the client role auto-creates a client profile
/// 3. assignRole adds a role to an existing user
/// 4. assignRole with the client role auto-creates a client profile
library;

import 'package:contractorhub/core/database/app_database.dart' hide UserRole;
import 'package:contractorhub/features/admin/data/team_management_service.dart';
import 'package:contractorhub/shared/models/user_role.dart';
import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

AppDatabase _openTestDb() => AppDatabase(NativeDatabase.memory());

const _companyId = 'co-1';

Future<void> _seedCompany(AppDatabase db) {
  final now = DateTime.now();
  return db.companyDao.insertCompany(CompaniesCompanion.insert(
    id: const Value(_companyId),
    name: 'Company',
    version: const Value(1),
    createdAt: now,
    updatedAt: now,
  ));
}

Future<void> _seedUser(AppDatabase db, String id) {
  final now = DateTime.now();
  return db.userDao.insertUser(UsersCompanion.insert(
    id: Value(id),
    companyId: _companyId,
    email: '$id@test.com',
    version: const Value(1),
    createdAt: now,
    updatedAt: now,
  ));
}

Future<int> _roleCount(AppDatabase db, String userId) async {
  final roles = await db.userDao.watchRolesForUser(userId).first;
  return roles.length;
}

Future<int> _clientProfileCount(AppDatabase db) async {
  final profiles = await db.jobDao.watchClientProfiles(_companyId).first;
  return profiles.length;
}

void main() {
  late AppDatabase db;
  late TeamManagementService service;

  setUp(() async {
    db = _openTestDb();
    await _seedCompany(db);
    service = TeamManagementService(database: db);
  });

  tearDown(() async => db.close());

  group('addMember', () {
    test('inserts the user and assigns the role', () async {
      final userId = await service.addMember(
        companyId: _companyId,
        member: const NewMember(
          email: 'alice@test.com',
          role: UserRole.contractor,
          firstName: 'Alice',
        ),
      );

      final user = await db.userDao.getUserById(userId);
      expect(user, isNotNull);
      expect(user!.email, 'alice@test.com');
      expect(user.firstName, 'Alice');
      expect(await _roleCount(db, userId), 1);
      expect(await _clientProfileCount(db), 0);
    });

    test('auto-creates a client profile for the client role', () async {
      final userId = await service.addMember(
        companyId: _companyId,
        member: const NewMember(
          email: 'client@test.com',
          role: UserRole.client,
        ),
      );

      expect(await _roleCount(db, userId), 1);
      expect(await _clientProfileCount(db), 1);
    });
  });

  group('assignRole', () {
    test('adds a role to an existing user', () async {
      await _seedUser(db, 'user-1');

      await service.assignRole(
        userId: 'user-1',
        companyId: _companyId,
        role: UserRole.admin,
      );

      expect(await _roleCount(db, 'user-1'), 1);
      expect(await _clientProfileCount(db), 0);
    });

    test('auto-creates a client profile for the client role', () async {
      await _seedUser(db, 'user-2');

      await service.assignRole(
        userId: 'user-2',
        companyId: _companyId,
        role: UserRole.client,
      );

      expect(await _clientProfileCount(db), 1);
    });
  });
}
