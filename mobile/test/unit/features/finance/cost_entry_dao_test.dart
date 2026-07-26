/// Unit tests for CostEntryDao — Drift in-memory database.
///
/// Tests cover:
/// 1. insertCostEntry persists a job-anchored entry with correct fields
/// 2. insertCostEntry enqueues a sync_queue CREATE entry (entityType 'cost_entry')
/// 3. insertCostEntry rejects both-anchors-set and neither-anchor-set (XOR)
/// 4. softDeleteCostEntry hides the row from watchByJob + enqueues a DELETE
/// 5. watchByTradeScope filters by tradeScopeId
/// 6. watchByProject returns both a trade-scope-anchored and a
///    job-anchored entry (and excludes an unrelated one)
/// 7. upsertFromRemote inserts a new entry from an on-demand fetch response
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

Future<void> _seedProject(
  AppDatabase db, {
  required String id,
  required String companyId,
}) async {
  final now = DateTime.now();
  await db.into(db.projects).insert(ProjectsCompanion.insert(
        id: Value(id),
        companyId: companyId,
        name: 'Project $id',
        createdAt: now,
        updatedAt: now,
      ));
}

Future<void> _seedTradeScope(
  AppDatabase db, {
  required String id,
  required String companyId,
  required String projectId,
}) async {
  final now = DateTime.now();
  await db.into(db.tradeScopes).insert(TradeScopesCompanion.insert(
        id: Value(id),
        companyId: companyId,
        projectId: projectId,
        tradeName: 'Plumbing',
        createdAt: now,
        updatedAt: now,
      ));
}

void main() {
  group('CostEntryDao', () {
    late AppDatabase db;

    setUp(() async {
      db = _openTestDb();
      await _seedCompany(db, 'co-1');
      await _seedProject(db, id: 'proj-1', companyId: 'co-1');
      await _seedTradeScope(
        db,
        id: 'scope-1',
        companyId: 'co-1',
        projectId: 'proj-1',
      );
    });

    tearDown(() async => await db.close());

    test('insertCostEntry persists a job-anchored entry with correct fields',
        () async {
      final entryId = await db.costEntryDao.insertCostEntry(
        companyId: 'co-1',
        jobId: 'job-1',
        categoryId: 'cat-materials',
        amount: 125.50,
        incurredDate: '2026-07-25',
        vendor: 'ACME Supply',
        note: 'Lumber for framing',
      );

      final entries = await db.costEntryDao.watchByJob('job-1').first;
      expect(entries, hasLength(1));
      expect(entries.first.id, entryId);
      expect(entries.first.jobId, 'job-1');
      expect(entries.first.tradeScopeId, isNull);
      expect(entries.first.categoryId, 'cat-materials');
      expect(entries.first.amount, 125.50);
      expect(entries.first.vendor, 'ACME Supply');
      expect(entries.first.deletedAt, isNull);
    });

    test(
        'insertCostEntry enqueues a sync_queue CREATE entry with entityType cost_entry',
        () async {
      final entryId = await db.costEntryDao.insertCostEntry(
        companyId: 'co-1',
        tradeScopeId: 'scope-1',
        categoryId: 'cat-materials',
        amount: 50.0,
        incurredDate: '2026-07-25',
      );

      final queueItems = await db.syncQueueDao.getAllItems();
      final entryItems = queueItems
          .where((item) =>
              item.entityType == 'cost_entry' && item.entityId == entryId)
          .toList();
      expect(entryItems, hasLength(1));
      expect(entryItems.first.operation, 'CREATE');
      expect(entryItems.first.status, 'pending');
    });

    test('insertCostEntry rejects both jobId and tradeScopeId set', () async {
      expect(
        () => db.costEntryDao.insertCostEntry(
          companyId: 'co-1',
          jobId: 'job-1',
          tradeScopeId: 'scope-1',
          categoryId: 'cat-materials',
          amount: 10.0,
          incurredDate: '2026-07-25',
        ),
        throwsArgumentError,
      );
    });

    test('insertCostEntry rejects neither jobId nor tradeScopeId set',
        () async {
      expect(
        () => db.costEntryDao.insertCostEntry(
          companyId: 'co-1',
          categoryId: 'cat-materials',
          amount: 10.0,
          incurredDate: '2026-07-25',
        ),
        throwsArgumentError,
      );
    });

    test('softDeleteCostEntry hides the row from watchByJob and enqueues DELETE',
        () async {
      final entryId = await db.costEntryDao.insertCostEntry(
        companyId: 'co-1',
        jobId: 'job-1',
        categoryId: 'cat-materials',
        amount: 75.0,
        incurredDate: '2026-07-25',
      );

      var entries = await db.costEntryDao.watchByJob('job-1').first;
      expect(entries, hasLength(1));

      await db.costEntryDao.softDeleteCostEntry(entryId);

      entries = await db.costEntryDao.watchByJob('job-1').first;
      expect(entries, isEmpty);

      final queueItems = await db.syncQueueDao.getAllItems();
      final deleteItems = queueItems
          .where((item) =>
              item.entityType == 'cost_entry' &&
              item.entityId == entryId &&
              item.operation == 'DELETE')
          .toList();
      expect(deleteItems, hasLength(1));
    });

    test('watchByTradeScope filters by tradeScopeId', () async {
      await db.costEntryDao.insertCostEntry(
        companyId: 'co-1',
        tradeScopeId: 'scope-1',
        categoryId: 'cat-materials',
        amount: 20.0,
        incurredDate: '2026-07-25',
      );
      await db.costEntryDao.insertCostEntry(
        companyId: 'co-1',
        jobId: 'job-1',
        categoryId: 'cat-materials',
        amount: 20.0,
        incurredDate: '2026-07-25',
      );

      final entries =
          await db.costEntryDao.watchByTradeScope('scope-1').first;
      expect(entries, hasLength(1));
      expect(entries.first.tradeScopeId, 'scope-1');
    });

    test(
        'watchByProject returns entries for both a trade-scope-anchored and a job-anchored entry',
        () async {
      await db.costEntryDao.insertCostEntry(
        companyId: 'co-1',
        tradeScopeId: 'scope-1',
        categoryId: 'cat-materials',
        amount: 30.0,
        incurredDate: '2026-07-25',
      );
      await db.costEntryDao.insertCostEntry(
        companyId: 'co-1',
        jobId: 'job-1',
        categoryId: 'cat-other',
        amount: 40.0,
        incurredDate: '2026-07-25',
      );
      // Unrelated entry — job not in the supplied jobIds — must be excluded.
      await db.costEntryDao.insertCostEntry(
        companyId: 'co-1',
        jobId: 'job-unrelated',
        categoryId: 'cat-other',
        amount: 99.0,
        incurredDate: '2026-07-25',
      );

      final entries = await db.costEntryDao
          .watchByProject('co-1', 'proj-1', jobIds: ['job-1'])
          .first;

      expect(entries, hasLength(2));
      expect(entries.map((e) => e.amount), containsAll(<double>[30.0, 40.0]));
    });

    test(
        'upsertFromRemote inserts a new entry from an on-demand fetch response',
        () async {
      await db.costEntryDao.upsertFromRemote({
        'id': 'remote-entry-1',
        'company_id': 'co-1',
        'job_id': 'job-1',
        'category_id': 'cat-materials',
        'amount': '125.50',
        'incurred_date': '2026-07-20',
        'vendor': 'Remote Vendor',
        'version': 1,
        'created_at': DateTime.now().toIso8601String(),
        'updated_at': DateTime.now().toIso8601String(),
      });

      final entries = await db.costEntryDao.watchByJob('job-1').first;
      expect(entries, hasLength(1));
      expect(entries.first.id, 'remote-entry-1');
      expect(entries.first.amount, 125.50);
      expect(entries.first.vendor, 'Remote Vendor');
    });
  });
}
