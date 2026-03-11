/// Tests for job wizard client & contractor selector data population.
///
/// These verify that the Drift DAOs correctly filter users by role,
/// which is the data source for the JobWizardScreen's dropdowns.
///
/// NOTE: Full widget-level tests of JobWizardScreen hang because
/// InternetConnection().hasInternetAccess (called in initState) starts
/// real HTTP sockets inside FakeAsync, poisoning the test event loop.
/// To fix, JobWizardScreen needs a mockable connectivity dependency.
/// The dropdown UI interaction patterns are covered by
/// team_management_screen_test.dart (18 tests, all passing).
library;

import 'package:contractorhub/core/database/app_database.dart' hide UserRole;
import 'package:contractorhub/core/di/service_locator.dart';
import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

AppDatabase _openTestDb() => AppDatabase(NativeDatabase.memory());

Future<void> _seedCompany(AppDatabase db) async {
  await db.into(db.companies).insert(CompaniesCompanion.insert(
        id: const Value('co-1'),
        name: 'Test Co',
        version: const Value(1),
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      ));
}

Future<void> _seedUserWithRole(
  AppDatabase db, {
  required String id,
  required String email,
  required String role,
  String? firstName,
  String? lastName,
}) async {
  final now = DateTime.now();
  await db.userDao.insertUser(UsersCompanion.insert(
    id: Value(id),
    companyId: 'co-1',
    email: email,
    firstName: Value(firstName),
    lastName: Value(lastName),
    version: const Value(1),
    createdAt: now,
    updatedAt: now,
  ));
  await db.userDao.assignRole(UserRolesCompanion.insert(
    id: Value('role-$id'),
    userId: id,
    companyId: 'co-1',
    role: role,
    createdAt: now,
  ));
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

void main() {
  late AppDatabase db;

  setUp(() async {
    db = _openTestDb();
    await _seedCompany(db);

    if (getIt.isRegistered<AppDatabase>()) getIt.unregister<AppDatabase>();
    getIt.registerSingleton<AppDatabase>(db);
  });

  tearDown(() async {
    if (getIt.isRegistered<AppDatabase>()) getIt.unregister<AppDatabase>();
    await db.close();
  });

  group('Job wizard — client selector data', () {
    test('watchUsersByRole returns only client users', () async {
      await _seedUserWithRole(db,
          id: 'u-client',
          email: 'alice@test.com',
          role: 'client',
          firstName: 'Alice',
          lastName: 'Wonder');
      await _seedUserWithRole(db,
          id: 'u-contractor',
          email: 'bob@test.com',
          role: 'contractor',
          firstName: 'Bob');

      final clients =
          await db.userDao.watchUsersByRole('co-1', 'client').first;
      expect(clients, hasLength(1));
      expect(clients.first.email, 'alice@test.com');
      expect(clients.first.firstName, 'Alice');
      expect(clients.first.lastName, 'Wonder');
    });

    test('does not include contractor users in client query', () async {
      await _seedUserWithRole(db,
          id: 'u-contractor',
          email: 'bob@test.com',
          role: 'contractor',
          firstName: 'Bob');

      final clients =
          await db.userDao.watchUsersByRole('co-1', 'client').first;
      expect(clients, isEmpty);
    });

    test('uses email when no name (display name fallback)', () async {
      await _seedUserWithRole(db,
          id: 'u-noname', email: 'noname@test.com', role: 'client');

      final clients =
          await db.userDao.watchUsersByRole('co-1', 'client').first;
      expect(clients, hasLength(1));
      expect(clients.first.firstName, isNull);
      expect(clients.first.lastName, isNull);
      expect(clients.first.email, 'noname@test.com');
    });
  });

  group('Job wizard — contractor selector data', () {
    test('watchUsersByRole returns only contractor users', () async {
      await _seedUserWithRole(db,
          id: 'u-con',
          email: 'con@test.com',
          role: 'contractor',
          firstName: 'Carl',
          lastName: 'Builder');
      await _seedUserWithRole(db,
          id: 'u-client',
          email: 'alice@test.com',
          role: 'client',
          firstName: 'Alice');

      final contractors =
          await db.userDao.watchUsersByRole('co-1', 'contractor').first;
      expect(contractors, hasLength(1));
      expect(contractors.first.email, 'con@test.com');
      expect(contractors.first.firstName, 'Carl');
      expect(contractors.first.lastName, 'Builder');
    });
  });
}
