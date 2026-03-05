/// Unit tests for SyncQueueDao — the transactional outbox DAO.
///
/// Uses Drift in-memory database (NativeDatabase.memory()) to test actual
/// SQL queries without mocking. This proves the DAO's SQL correctness:
/// FIFO ordering, status transitions, reactive stream counts.
///
/// Tests cover:
/// 1. getPendingItems returns items in FIFO (createdAt ASC) order
/// 2. markSynced removes the item from the queue
/// 3. markParked sets status to 'parked' and stores error message
/// 4. watchPendingCount stream emits correct count on changes
/// 5. updateAttemptCount persists the new count
///
/// NOTE: Requires Flutter SDK + drift_flutter (NativeDatabase.memory()) to run.
/// Run setup: cd mobile && dart run build_runner build --delete-conflicting-outputs
library;

import 'package:contractorhub/core/database/app_database.dart';
import 'package:contractorhub/core/sync/sync_queue_dao.dart';
import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:uuid/uuid.dart';

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

/// Open an in-memory AppDatabase for testing.
///
/// NativeDatabase.memory() creates a temporary SQLite database that is
/// destroyed when the test completes. Each test should open its own
/// instance to ensure isolation.
AppDatabase openTestDatabase() {
  return AppDatabase(NativeDatabase.memory());
}

/// Insert a sync queue item into [db] for testing.
///
/// [createdAt] must be provided explicitly to control FIFO ordering.
Future<void> insertTestItem(
  AppDatabase db, {
  required String id,
  required DateTime createdAt,
  String entityType = 'company',
  String entityId = 'entity-1',
  String operation = 'CREATE',
  String payload = '{}',
  String status = 'pending',
  int attemptCount = 0,
  String? errorMessage,
}) async {
  await db.syncQueueDao.insertQueueItem(
    SyncQueueCompanion.insert(
      id: Value(id),
      entityType: entityType,
      entityId: entityId,
      operation: operation,
      payload: payload,
      status: Value(status),
      attemptCount: Value(attemptCount),
      errorMessage: Value(errorMessage),
      createdAt: createdAt,
    ),
  );
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

void main() {
  group('SyncQueueDao', () {
    late AppDatabase db;

    setUp(() {
      db = openTestDatabase();
    });

    tearDown(() async {
      await db.close();
    });

    test('1. getPendingItems returns items in FIFO (createdAt ASC) order',
        () async {
      // Insert items out of order to verify DAO sorts by createdAt ASC
      await insertTestItem(
        db,
        id: 'item-third',
        createdAt: DateTime.utc(2024, 1, 1, 12, 0, 2),
      );
      await insertTestItem(
        db,
        id: 'item-first',
        createdAt: DateTime.utc(2024, 1, 1, 12, 0, 0),
      );
      await insertTestItem(
        db,
        id: 'item-second',
        createdAt: DateTime.utc(2024, 1, 1, 12, 0, 1),
      );

      final items = await db.syncQueueDao.getPendingItems();

      expect(items, hasLength(3));
      expect(items[0].id, equals('item-first'),
          reason: 'Oldest item must be first (FIFO causality ordering)');
      expect(items[1].id, equals('item-second'));
      expect(items[2].id, equals('item-third'));
    });

    test('2. markSynced removes item — getPendingItems returns empty', () async {
      await insertTestItem(
        db,
        id: 'item-to-sync',
        createdAt: DateTime.utc(2024, 1, 1, 12, 0, 0),
      );

      // Verify item is in queue
      expect(await db.syncQueueDao.getPendingItems(), hasLength(1));

      // Mark as synced (deletes the row)
      await db.syncQueueDao.markSynced('item-to-sync');

      // Queue should now be empty
      final remaining = await db.syncQueueDao.getPendingItems();
      expect(remaining, isEmpty,
          reason: 'markSynced must delete the row — synced items are not kept');
    });

    test('3. markParked sets status to parked and stores error message',
        () async {
      await insertTestItem(
        db,
        id: 'item-to-park',
        createdAt: DateTime.utc(2024, 1, 1, 12, 0, 0),
      );

      const errorMsg = 'HTTP 400 Bad Request: invalid payload';
      await db.syncQueueDao.markParked('item-to-park', error: errorMsg);

      // Parked items are NOT in getPendingItems (status = 'parked', not 'pending')
      final pendingItems = await db.syncQueueDao.getPendingItems();
      expect(pendingItems, isEmpty,
          reason: 'Parked items must be excluded from pending queue');

      // Verify the row still exists with correct status and error message
      final allItems = await db.syncQueueDao.getAllItems();
      expect(allItems, hasLength(1));
      expect(allItems.first.status, equals('parked'));
      expect(allItems.first.errorMessage, equals(errorMsg));
    });

    test('4. watchPendingCount emits correct count on changes', () async {
      await insertTestItem(
        db,
        id: 'item-a',
        createdAt: DateTime.utc(2024, 1, 1, 12, 0, 0),
      );
      await insertTestItem(
        db,
        id: 'item-b',
        createdAt: DateTime.utc(2024, 1, 1, 12, 0, 1),
      );

      final emittedCounts = <int>[];
      final sub = db.syncQueueDao.watchPendingCount().listen(emittedCounts.add);

      // Allow stream to emit initial count
      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect(emittedCounts.last, equals(2),
          reason: 'Should emit 2 pending items initially');

      // Mark one as synced
      await db.syncQueueDao.markSynced('item-a');
      await Future<void>.delayed(const Duration(milliseconds: 50));

      expect(emittedCounts.last, equals(1),
          reason: 'After markSynced, count should drop to 1');

      await sub.cancel();
    });

    test('5. updateAttemptCount persists the new count', () async {
      await insertTestItem(
        db,
        id: 'item-retry',
        createdAt: DateTime.utc(2024, 1, 1, 12, 0, 0),
        attemptCount: 0,
      );

      // Increment to 3
      await db.syncQueueDao.updateAttemptCount('item-retry', 3);

      final items = await db.syncQueueDao.getPendingItems();
      expect(items, hasLength(1));
      expect(items.first.attemptCount, equals(3),
          reason: 'updateAttemptCount must persist the new count value');
    });
  });
}
