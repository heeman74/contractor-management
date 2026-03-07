/// Unit tests for CompanyDao — Drift DAO for Company CRUD.
///
/// Uses Drift in-memory database (NativeDatabase.memory()) to test actual
/// SQL queries without mocking.
///
/// Tests cover:
/// 1. insertCompany adds a row
/// 2. watchAllCompanies emits reactively
/// 3. watchAllCompanies excludes soft-deleted
/// 4. getCompanyById returns correct entity
/// 5. getCompanyById returns null for missing ID
/// 6. updateCompany modifies the row
/// 7. deleteCompany soft-deletes (sets deletedAt)
library;

import 'package:contractorhub/core/database/app_database.dart';
import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:uuid/uuid.dart';

AppDatabase openTestDatabase() {
  return AppDatabase(NativeDatabase.memory());
}

CompaniesCompanion makeCompany({
  String? id,
  String name = 'Test Company',
  String? address,
}) {
  return CompaniesCompanion.insert(
    id: Value(id ?? const Uuid().v4()),
    name: name,
    version: const Value(1),
    createdAt: DateTime.now(),
    updatedAt: DateTime.now(),
    address: Value(address),
  );
}

void main() {
  group('CompanyDao', () {
    late AppDatabase db;

    setUp(() {
      db = openTestDatabase();
    });

    tearDown(() async {
      await db.close();
    });

    test('insertCompany adds a row', () async {
      final companion = makeCompany(id: 'co-1', name: 'Acme');
      await db.companyDao.insertCompany(companion);

      final entity = await db.companyDao.getCompanyById('co-1');
      expect(entity, isNotNull);
      expect(entity!.name, equals('Acme'));
    });

    test('watchAllCompanies emits reactively', () async {
      final emissions = <int>[];
      final sub = db.companyDao
          .watchAllCompanies()
          .listen((list) => emissions.add(list.length));

      await Future<void>.delayed(const Duration(milliseconds: 50));

      await db.companyDao.insertCompany(makeCompany(id: 'co-1', name: 'A'));
      await Future<void>.delayed(const Duration(milliseconds: 50));

      await db.companyDao.insertCompany(makeCompany(id: 'co-2', name: 'B'));
      await Future<void>.delayed(const Duration(milliseconds: 50));

      expect(emissions.last, equals(2));
      await sub.cancel();
    });

    test('watchAllCompanies excludes soft-deleted', () async {
      await db.companyDao.insertCompany(makeCompany(id: 'co-1'));
      await db.companyDao.insertCompany(makeCompany(id: 'co-2'));

      // Soft-delete co-1
      await db.companyDao.deleteCompany('co-1');

      final companies =
          await db.companyDao.watchAllCompanies().first;
      expect(companies, hasLength(1));
      expect(companies.first.id, equals('co-2'));
    });

    test('getCompanyById returns correct entity', () async {
      await db.companyDao
          .insertCompany(makeCompany(id: 'co-1', name: 'Found'));

      final entity = await db.companyDao.getCompanyById('co-1');
      expect(entity, isNotNull);
      expect(entity!.name, equals('Found'));
      expect(entity.id, equals('co-1'));
    });

    test('getCompanyById returns null for missing ID', () async {
      final entity = await db.companyDao.getCompanyById('nonexistent');
      expect(entity, isNull);
    });

    test('updateCompany modifies the row', () async {
      final id = 'co-1';
      await db.companyDao.insertCompany(makeCompany(id: id, name: 'Old'));

      await db.companyDao.updateCompany(CompaniesCompanion(
        id: Value(id),
        name: const Value('New'),
        version: const Value(2),
        createdAt: Value(DateTime.now()),
        updatedAt: Value(DateTime.now()),
      ));

      final entity = await db.companyDao.getCompanyById(id);
      expect(entity!.name, equals('New'));
      expect(entity.version, equals(2));
    });

    test('deleteCompany soft-deletes (sets deletedAt)', () async {
      await db.companyDao.insertCompany(makeCompany(id: 'co-1'));

      final count = await db.companyDao.deleteCompany('co-1');
      expect(count, equals(1));

      // Still in DB (raw query), but excluded from watchAllCompanies
      final row = await (db.select(db.companies)
            ..where((tbl) => tbl.id.equals('co-1')))
          .getSingleOrNull();
      expect(row, isNotNull);
      expect(row!.deletedAt, isNotNull);
    });
  });
}
