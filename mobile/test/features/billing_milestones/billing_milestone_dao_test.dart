// Drift DAO tests for BillingMilestoneDao.
//
// Covers:
//   test_create_milestone: Create milestone, verify stored in DB and sync_queue
//   test_watch_by_scope: watchByScope returns only milestones for the given scope
//   test_update_milestone: Update milestone, verify via watch stream
//   test_delete_milestone: Soft delete, verify excluded from watch stream
//   test_upsert_from_sync: upsertFromSync creates/updates row without sync_queue entry
//   test_upsert_from_sync_no_sync_queue: upsertFromSync does NOT write to sync_queue
//
// Patterns:
//   - NativeDatabase.memory() for in-memory Drift DB
//   - pump() not pumpAndSettle() for stream assertions (project rule)
//   - tester.runAsync() for one-shot DB queries (Drift one-shot .get() in testWidgets)
//   - Seed Company row before any milestone rows (FK constraint)

import 'package:contractorhub/core/database/app_database.dart' hide UserRole;
import 'package:contractorhub/features/billing_milestones/domain/billing_milestone_entity.dart';
import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

// ---------------------------------------------------------------------------
// Test constants
// ---------------------------------------------------------------------------

const _companyId = 'company-dao-001';
const _scopeA = 'scope-dao-a';
const _scopeB = 'scope-dao-b';

// ---------------------------------------------------------------------------
// Helper: open in-memory DB
// ---------------------------------------------------------------------------

AppDatabase _openDb() => AppDatabase(NativeDatabase.memory());

// ---------------------------------------------------------------------------
// Helper: seed Company row (FK dependency for billing_milestones.company_id)
// ---------------------------------------------------------------------------

Future<void> _seedCompany(AppDatabase db) async {
  final now = DateTime.now();
  await db.into(db.companies).insert(
    CompaniesCompanion.insert(
      id: const Value(_companyId),
      name: 'Test Company',
      createdAt: now,
      updatedAt: now,
    ),
  );
}

// ---------------------------------------------------------------------------
// Helper: build a BillingMilestoneEntity
// ---------------------------------------------------------------------------

BillingMilestoneEntity _makeEntity({
  String? id,
  String scopeId = _scopeA,
  String name = 'Test Milestone',
  double percentage = 40.0,
  bool isInvoiced = false,
  int sortOrder = 0,
  DateTime? deletedAt,
}) {
  final now = DateTime.now();
  return BillingMilestoneEntity(
    id: id ?? 'ms-${DateTime.now().microsecondsSinceEpoch}',
    companyId: _companyId,
    tradeScopeId: scopeId,
    name: name,
    percentage: percentage,
    isInvoiced: isInvoiced,
    sortOrder: sortOrder,
    version: 1,
    createdAt: now,
    updatedAt: now,
    deletedAt: deletedAt,
  );
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

void main() {
  group('BillingMilestoneDao', () {
    // ──────────────────────────────────────────────────────────────────────
    // test_create_milestone
    // ──────────────────────────────────────────────────────────────────────

    testWidgets('test_create_milestone: creates milestone and enqueues sync entry',
        (tester) async {
      final db = _openDb();
      addTearDown(db.close);
      final dao = BillingMilestoneDao(db);

      await tester.runAsync(() async {
        await _seedCompany(db);
        final entity = _makeEntity(id: 'ms-create-001', name: 'Mobilisation');
        final id = await dao.createMilestone(entity);

        expect(id, equals('ms-create-001'));

        // Verify milestone row exists
        final rows = await (db.select(db.billingMilestones)
              ..where((tbl) => tbl.id.equals('ms-create-001')))
            .get();
        expect(rows, hasLength(1));
        expect(rows.first.name, equals('Mobilisation'));
        expect(rows.first.isInvoiced, isFalse);

        // Verify sync_queue has a CREATE entry
        final queue = await (db.select(db.syncQueue)
              ..where((tbl) =>
                  tbl.entityId.equals('ms-create-001') &
                  tbl.operation.equals('CREATE')))
            .get();
        expect(queue, hasLength(1));
        expect(queue.first.entityType, equals('billing_milestone'));
        expect(queue.first.status, equals('pending'));
      });
    });

    // ──────────────────────────────────────────────────────────────────────
    // test_watch_by_scope
    // ──────────────────────────────────────────────────────────────────────

    testWidgets('test_watch_by_scope: returns milestones for scope ordered by sortOrder',
        (tester) async {
      final db = _openDb();
      addTearDown(db.close);
      final dao = BillingMilestoneDao(db);

      await tester.runAsync(() async {
        await _seedCompany(db);

        // Seed 3 milestones for scope A (out of order) + 1 for scope B
        await dao.createMilestone(
            _makeEntity(id: 'ms-a1', name: 'Third', sortOrder: 2));
        await dao.createMilestone(
            _makeEntity(id: 'ms-a2', name: 'First'));
        await dao.createMilestone(
            _makeEntity(id: 'ms-a3', name: 'Second', sortOrder: 1));
        await dao.createMilestone(
            _makeEntity(id: 'ms-b1', scopeId: _scopeB, name: 'B-Milestone'));

        // Watch scope A — should return 3 in sort_order order
        final milestones = await dao.watchByScope(_scopeA).first;
        expect(milestones, hasLength(3));
        expect(milestones.map((m) => m.name).toList(),
            equals(['First', 'Second', 'Third']));
      });
    });

    // ──────────────────────────────────────────────────────────────────────
    // test_update_milestone
    // ──────────────────────────────────────────────────────────────────────

    testWidgets('test_update_milestone: update name and verify via watch stream',
        (tester) async {
      final db = _openDb();
      addTearDown(db.close);
      final dao = BillingMilestoneDao(db);

      await tester.runAsync(() async {
        await _seedCompany(db);
        final entity = _makeEntity(id: 'ms-update-001', name: 'Original Name');
        await dao.createMilestone(entity);

        // Update name
        final updated = entity.copyWith(name: 'Updated Name');
        await dao.updateMilestone(updated);

        // Verify updated row visible via watch (inside runAsync for Drift stream)
        final milestones = await dao.watchByScope(_scopeA).first;
        expect(milestones, hasLength(1));
        expect(milestones.first.name, equals('Updated Name'));
      });
    });

    // ──────────────────────────────────────────────────────────────────────
    // test_delete_milestone
    // ──────────────────────────────────────────────────────────────────────

    testWidgets('test_delete_milestone: soft delete excludes from watch stream',
        (tester) async {
      final db = _openDb();
      addTearDown(db.close);
      final dao = BillingMilestoneDao(db);

      await tester.runAsync(() async {
        await _seedCompany(db);
        await dao.createMilestone(
            _makeEntity(id: 'ms-delete-001', name: 'To Delete'));
        await dao.createMilestone(
            _makeEntity(id: 'ms-keep-001', name: 'Keep This'));

        // Before delete — both visible
        final before = await dao.watchByScope(_scopeA).first;
        expect(before, hasLength(2));

        // Delete one
        await dao.deleteMilestone('ms-delete-001');

        // After delete — only the kept one visible
        final after = await dao.watchByScope(_scopeA).first;
        expect(after, hasLength(1));
        expect(after.first.name, equals('Keep This'));
      });
    });

    // ──────────────────────────────────────────────────────────────────────
    // test_upsert_from_sync
    // ──────────────────────────────────────────────────────────────────────

    testWidgets('test_upsert_from_sync: inserts and updates row from sync data',
        (tester) async {
      final db = _openDb();
      addTearDown(db.close);
      final dao = BillingMilestoneDao(db);

      final now = DateTime.now().toUtc().toIso8601String();

      await tester.runAsync(() async {
        await _seedCompany(db);

        // First upsert — creates the row
        await dao.upsertFromSync({
          'id': 'ms-sync-001',
          'company_id': _companyId,
          'trade_scope_id': _scopeA,
          'name': 'Sync Milestone',
          'percentage': 40.0,
          'description': null,
          'is_invoiced': false,
          'sort_order': 0,
          'version': 1,
          'created_at': now,
          'updated_at': now,
          'deleted_at': null,
        });

        // Verify row exists
        final rows = await (db.select(db.billingMilestones)
              ..where((tbl) => tbl.id.equals('ms-sync-001')))
            .get();
        expect(rows, hasLength(1));
        expect(rows.first.name, equals('Sync Milestone'));

        // Second upsert — updates name
        await dao.upsertFromSync({
          'id': 'ms-sync-001',
          'company_id': _companyId,
          'trade_scope_id': _scopeA,
          'name': 'Updated Sync Milestone',
          'percentage': 50.0,
          'description': null,
          'is_invoiced': false,
          'sort_order': 0,
          'version': 2,
          'created_at': now,
          'updated_at': now,
          'deleted_at': null,
        });

        // Still only one row with updated data
        final updated = await (db.select(db.billingMilestones)
              ..where((tbl) => tbl.id.equals('ms-sync-001')))
            .get();
        expect(updated, hasLength(1));
        expect(updated.first.name, equals('Updated Sync Milestone'));
        expect(updated.first.percentage, closeTo(50.0, 0.001));
        expect(updated.first.version, equals(2));
      });
    });

    // ──────────────────────────────────────────────────────────────────────
    // test_upsert_from_sync_no_sync_queue
    // ──────────────────────────────────────────────────────────────────────

    testWidgets(
        'test_upsert_from_sync_no_sync_queue: upsertFromSync does NOT write to sync_queue',
        (tester) async {
      final db = _openDb();
      addTearDown(db.close);
      final dao = BillingMilestoneDao(db);

      final now = DateTime.now().toUtc().toIso8601String();

      await tester.runAsync(() async {
        await _seedCompany(db);

        await dao.upsertFromSync({
          'id': 'ms-nosync-001',
          'company_id': _companyId,
          'trade_scope_id': _scopeA,
          'name': 'No Queue Entry',
          'percentage': 30.0,
          'description': null,
          'is_invoiced': false,
          'sort_order': 0,
          'version': 1,
          'created_at': now,
          'updated_at': now,
          'deleted_at': null,
        });

        // Verify sync_queue has NO entry for this milestone
        final queue = await (db.select(db.syncQueue)
              ..where((tbl) => tbl.entityId.equals('ms-nosync-001')))
            .get();
        expect(queue, isEmpty,
            reason: 'upsertFromSync must NOT write to sync_queue '
                '(it IS the sync — writing to queue would cause infinite loop)');
      });
    });
  });
}
