/// Unit tests for UserDao — Drift DAO for User and UserRole CRUD.
///
/// Uses Drift in-memory database (NativeDatabase.memory()) to test actual
/// SQL queries without mocking.
///
/// Tests cover:
/// 1. insertUser adds a row
/// 2. watchUsersByCompany filters by company
/// 3. watchUsersByCompany excludes soft-deleted
/// 4. getUserById returns correct entity
/// 5. assignRole creates user_role row
/// 6. watchRolesForUser returns roles
library;

import 'package:contractorhub/core/database/app_database.dart';
import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:uuid/uuid.dart';

AppDatabase openTestDatabase() {
  return AppDatabase(NativeDatabase.memory());
}

/// Insert a company (required FK for users).
Future<void> insertCompany(AppDatabase db, String id) async {
  await db.companyDao.insertCompany(CompaniesCompanion.insert(
    id: Value(id),
    name: 'Company $id',
    version: const Value(1),
    createdAt: DateTime.now(),
    updatedAt: DateTime.now(),
  ));
}

UsersCompanion makeUser({
  String? id,
  required String companyId,
  String email = 'user@test.com',
  String? firstName,
}) {
  return UsersCompanion.insert(
    id: Value(id ?? const Uuid().v4()),
    companyId: companyId,
    email: email,
    version: const Value(1),
    createdAt: DateTime.now(),
    updatedAt: DateTime.now(),
    firstName: Value(firstName),
  );
}

void main() {
  group('UserDao', () {
    late AppDatabase db;

    setUp(() async {
      db = openTestDatabase();
      // Create a company for FK constraints
      await insertCompany(db, 'co-1');
      await insertCompany(db, 'co-2');
    });

    tearDown(() async {
      await db.close();
    });

    test('insertUser adds a row', () async {
      await db.userDao.insertUser(
        makeUser(id: 'u-1', companyId: 'co-1', email: 'a@test.com'),
      );

      final entity = await db.userDao.getUserById('u-1');
      expect(entity, isNotNull);
      expect(entity!.email, equals('a@test.com'));
    });

    test('watchUsersByCompany filters by company', () async {
      await db.userDao.insertUser(
        makeUser(id: 'u-1', companyId: 'co-1', email: 'a@test.com'),
      );
      await db.userDao.insertUser(
        makeUser(id: 'u-2', companyId: 'co-2', email: 'b@test.com'),
      );

      final users = await db.userDao.watchUsersByCompany('co-1').first;
      expect(users, hasLength(1));
      expect(users.first.email, equals('a@test.com'));
    });

    test('watchUsersByCompany excludes soft-deleted', () async {
      await db.userDao.insertUser(
        makeUser(id: 'u-1', companyId: 'co-1', email: 'a@test.com'),
      );
      await db.userDao.insertUser(
        makeUser(id: 'u-2', companyId: 'co-1', email: 'b@test.com'),
      );

      // Soft-delete u-1
      await (db.update(db.users)..where((tbl) => tbl.id.equals('u-1')))
          .write(UsersCompanion(deletedAt: Value(DateTime.now())));

      final users = await db.userDao.watchUsersByCompany('co-1').first;
      expect(users, hasLength(1));
      expect(users.first.id, equals('u-2'));
    });

    test('getUserById returns correct entity', () async {
      await db.userDao.insertUser(
        makeUser(id: 'u-1', companyId: 'co-1', firstName: 'Jane'),
      );

      final entity = await db.userDao.getUserById('u-1');
      expect(entity, isNotNull);
      expect(entity!.firstName, equals('Jane'));
    });

    test('assignRole creates user_role row', () async {
      await db.userDao.insertUser(
        makeUser(id: 'u-1', companyId: 'co-1'),
      );

      await db.userDao.assignRole(UserRolesCompanion.insert(
        id: Value('role-1'),
        userId: 'u-1',
        companyId: 'co-1',
        role: 'admin',
        createdAt: DateTime.now(),
      ));

      final roles = await db.userDao.watchRolesForUser('u-1').first;
      expect(roles, hasLength(1));
      expect(roles.first.role.name, equals('admin'));
    });

    test('watchRolesForUser returns multiple roles', () async {
      await db.userDao.insertUser(
        makeUser(id: 'u-1', companyId: 'co-1'),
      );

      await db.userDao.assignRole(UserRolesCompanion.insert(
        id: Value('role-1'),
        userId: 'u-1',
        companyId: 'co-1',
        role: 'admin',
        createdAt: DateTime.now(),
      ));
      await db.userDao.assignRole(UserRolesCompanion.insert(
        id: Value('role-2'),
        userId: 'u-1',
        companyId: 'co-1',
        role: 'contractor',
        createdAt: DateTime.now(),
      ));

      final roles = await db.userDao.watchRolesForUser('u-1').first;
      expect(roles, hasLength(2));
      final roleNames = roles.map((r) => r.role.name).toSet();
      expect(roleNames, containsAll(['admin', 'contractor']));
    });
  });
}
