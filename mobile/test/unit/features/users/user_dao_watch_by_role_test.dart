/// Unit tests for UserDao.watchUsersByRole and JobDao.insertClientProfile.
///
/// Tests cover:
/// 1. watchUsersByRole returns only users with the specified role
/// 2. watchUsersByRole excludes soft-deleted users
/// 3. watchUsersByRole scopes to company
/// 4. insertClientProfile creates profile and sync queue entry
library;

import 'package:contractorhub/core/database/app_database.dart';
import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

AppDatabase _openTestDb() => AppDatabase(NativeDatabase.memory());

Future<void> _seedCompany(AppDatabase db, String id) async {
  await db.companyDao.insertCompany(CompaniesCompanion.insert(
    id: Value(id),
    name: 'Company $id',
    version: const Value(1),
    createdAt: DateTime.now(),
    updatedAt: DateTime.now(),
  ));
}

Future<void> _seedUser(AppDatabase db,
    {required String id,
    required String companyId,
    String email = 'user@test.com'}) async {
  final now = DateTime.now();
  await db.userDao.insertUser(UsersCompanion.insert(
    id: Value(id),
    companyId: companyId,
    email: email,
    version: const Value(1),
    createdAt: now,
    updatedAt: now,
  ));
}

Future<void> _seedRole(AppDatabase db,
    {required String userId,
    required String companyId,
    required String role}) async {
  await db.userDao.assignRole(UserRolesCompanion.insert(
    id: Value('role-$userId-$role'),
    userId: userId,
    companyId: companyId,
    role: role,
    createdAt: DateTime.now(),
  ));
}

void main() {
  group('UserDao.watchUsersByRole', () {
    late AppDatabase db;

    setUp(() async {
      db = _openTestDb();
      await _seedCompany(db, 'co-1');
      await _seedCompany(db, 'co-2');
    });

    tearDown(() async => await db.close());

    test('returns only users with the specified role', () async {
      await _seedUser(db,
          id: 'u-admin', companyId: 'co-1', email: 'admin@test.com');
      await _seedRole(db,
          userId: 'u-admin', companyId: 'co-1', role: 'admin');

      await _seedUser(db,
          id: 'u-client', companyId: 'co-1', email: 'client@test.com');
      await _seedRole(db,
          userId: 'u-client', companyId: 'co-1', role: 'client');

      await _seedUser(db,
          id: 'u-con', companyId: 'co-1', email: 'con@test.com');
      await _seedRole(db,
          userId: 'u-con', companyId: 'co-1', role: 'contractor');

      final clients =
          await db.userDao.watchUsersByRole('co-1', 'client').first;
      expect(clients, hasLength(1));
      expect(clients.first.email, 'client@test.com');

      final contractors =
          await db.userDao.watchUsersByRole('co-1', 'contractor').first;
      expect(contractors, hasLength(1));
      expect(contractors.first.email, 'con@test.com');

      final admins =
          await db.userDao.watchUsersByRole('co-1', 'admin').first;
      expect(admins, hasLength(1));
      expect(admins.first.email, 'admin@test.com');
    });

    test('excludes soft-deleted users', () async {
      await _seedUser(db,
          id: 'u-1', companyId: 'co-1', email: 'alive@test.com');
      await _seedRole(db,
          userId: 'u-1', companyId: 'co-1', role: 'client');

      await _seedUser(db,
          id: 'u-2', companyId: 'co-1', email: 'deleted@test.com');
      await _seedRole(db,
          userId: 'u-2', companyId: 'co-1', role: 'client');

      // Soft-delete u-2
      await (db.update(db.users)..where((tbl) => tbl.id.equals('u-2')))
          .write(UsersCompanion(deletedAt: Value(DateTime.now())));

      final clients =
          await db.userDao.watchUsersByRole('co-1', 'client').first;
      expect(clients, hasLength(1));
      expect(clients.first.id, 'u-1');
    });

    test('scopes to company', () async {
      await _seedUser(db,
          id: 'u-1', companyId: 'co-1', email: 'co1@test.com');
      await _seedRole(db,
          userId: 'u-1', companyId: 'co-1', role: 'client');

      await _seedUser(db,
          id: 'u-2', companyId: 'co-2', email: 'co2@test.com');
      await _seedRole(db,
          userId: 'u-2', companyId: 'co-2', role: 'client');

      final co1Clients =
          await db.userDao.watchUsersByRole('co-1', 'client').first;
      expect(co1Clients, hasLength(1));
      expect(co1Clients.first.email, 'co1@test.com');
    });

    test('returns empty list when no users with role', () async {
      await _seedUser(db,
          id: 'u-1', companyId: 'co-1', email: 'admin@test.com');
      await _seedRole(db,
          userId: 'u-1', companyId: 'co-1', role: 'admin');

      final clients =
          await db.userDao.watchUsersByRole('co-1', 'client').first;
      expect(clients, isEmpty);
    });

    test('user with multiple roles appears in both queries', () async {
      await _seedUser(db,
          id: 'u-1', companyId: 'co-1', email: 'multi@test.com');
      await _seedRole(db,
          userId: 'u-1', companyId: 'co-1', role: 'admin');
      await _seedRole(db,
          userId: 'u-1', companyId: 'co-1', role: 'contractor');

      final admins =
          await db.userDao.watchUsersByRole('co-1', 'admin').first;
      expect(admins, hasLength(1));

      final contractors =
          await db.userDao.watchUsersByRole('co-1', 'contractor').first;
      expect(contractors, hasLength(1));
    });
  });

  group('JobDao.insertClientProfile', () {
    late AppDatabase db;

    setUp(() async {
      db = _openTestDb();
      await _seedCompany(db, 'co-1');
      await _seedUser(db,
          id: 'u-1', companyId: 'co-1', email: 'client@test.com');
    });

    tearDown(() async => await db.close());

    test('creates profile row', () async {
      final now = DateTime.now();
      await db.jobDao.insertClientProfile(ClientProfilesCompanion.insert(
        id: const Value('cp-1'),
        companyId: 'co-1',
        userId: 'u-1',
        createdAt: now,
        updatedAt: now,
      ));

      final profiles = await db.jobDao.watchClientProfiles('co-1').first;
      expect(profiles, hasLength(1));
      expect(profiles.first.userId, 'u-1');
    });

    test('creates sync queue entry', () async {
      final now = DateTime.now();
      await db.jobDao.insertClientProfile(ClientProfilesCompanion.insert(
        id: const Value('cp-1'),
        companyId: 'co-1',
        userId: 'u-1',
        createdAt: now,
        updatedAt: now,
      ));

      final queueItems = await db.syncQueueDao.getAllItems();
      final profileItems = queueItems
          .where((item) =>
              item.entityType == 'client_profile' &&
              item.entityId == 'cp-1')
          .toList();
      expect(profileItems, hasLength(1));
      expect(profileItems.first.operation, 'CREATE');
    });
  });
}
