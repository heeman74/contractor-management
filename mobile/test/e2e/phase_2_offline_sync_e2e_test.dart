// Phase 2 E2E: Offline Sync Engine
//
// Covers the sync engine core: SyncQueueDao, SyncCursorDao, SyncEngine
// drainQueue/pullDelta, and SyncStatus subtitle formatting.
//
// Strategy: Use real Drift in-memory DB for DAO tests. Mock DioClient,
// SyncRegistry, SyncHandler, and ConnectivityService for SyncEngine tests.
// Do NOT use pumpAndSettle() — Drift streams never settle.

import 'dart:convert';

import 'package:contractorhub/core/database/app_database.dart' hide UserRole;
import 'package:contractorhub/core/network/dio_client.dart';
import 'package:contractorhub/core/sync/connectivity_service.dart';
import 'package:contractorhub/core/sync/sync_engine.dart';
import 'package:contractorhub/core/sync/sync_handler.dart';
import 'package:contractorhub/core/sync/sync_queue_dao.dart';
import 'package:contractorhub/core/sync/sync_registry.dart';
import 'package:dio/dio.dart';
import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:drift/native.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

// ---------------------------------------------------------------------------
// Mocks
// ---------------------------------------------------------------------------

class MockDioClient extends Mock implements DioClient {}

class MockDio extends Mock implements Dio {}

class MockSyncRegistry extends Mock implements SyncRegistry {}

class MockSyncHandler extends Mock implements SyncHandler {}

class MockConnectivityService extends Mock implements ConnectivityService {}

// Fake for SyncQueueData to satisfy mocktail's registerFallbackValue
class FakeSyncQueueData extends Fake implements SyncQueueData {}

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

AppDatabase _openTestDb() => AppDatabase(NativeDatabase.memory());

SyncQueueCompanion _makeQueueItem({
  required String id,
  String entityType = 'company',
  String entityId = 'entity-1',
  String operation = 'CREATE',
  String payload = '{}',
  String status = 'pending',
  int attemptCount = 0,
  String? errorMessage,
  required DateTime createdAt,
}) {
  return SyncQueueCompanion.insert(
    id: Value(id),
    entityType: entityType,
    entityId: entityId,
    operation: operation,
    payload: payload,
    status: Value(status),
    attemptCount: Value(attemptCount),
    errorMessage: Value(errorMessage),
    createdAt: createdAt,
  );
}

void main() {
  setUpAll(() {
    registerFallbackValue(FakeSyncQueueData());
    registerFallbackValue(<String, dynamic>{});
    registerFallbackValue(() {}); // VoidCallback fallback
  });

  // =========================================================================
  // 1. SyncQueue DAO E2E
  // =========================================================================
  group('SyncQueue DAO E2E', () {
    late AppDatabase db;
    late SyncQueueDao dao;

    setUp(() {
      db = _openTestDb();
      dao = db.syncQueueDao;
    });

    tearDown(() => db.close());

    test('insert queue item → getPendingItems returns it', () async {
      final now = DateTime.now();
      await dao.insertQueueItem(_makeQueueItem(
        id: 'q-1',
        entityType: 'company',
        entityId: 'co-1',
        operation: 'CREATE',
        payload: jsonEncode({'name': 'Acme'}),
        createdAt: now,
      ));

      final items = await dao.getPendingItems();
      expect(items, hasLength(1));
      expect(items.first.id, 'q-1');
      expect(items.first.entityType, 'company');
      expect(items.first.entityId, 'co-1');
      expect(items.first.operation, 'CREATE');
      expect(items.first.status, 'pending');
      expect(items.first.attemptCount, 0);
    });

    test('FIFO ordering — multiple items returned in createdAt ASC order',
        () async {
      final t1 = DateTime(2025, 1, 1, 10, 0);
      final t2 = DateTime(2025, 1, 1, 10, 1);
      final t3 = DateTime(2025, 1, 1, 10, 2);

      // Insert out of order to verify sorting
      await dao.insertQueueItem(
          _makeQueueItem(id: 'q-3', createdAt: t3, entityId: 'e-3'));
      await dao.insertQueueItem(
          _makeQueueItem(id: 'q-1', createdAt: t1, entityId: 'e-1'));
      await dao.insertQueueItem(
          _makeQueueItem(id: 'q-2', createdAt: t2, entityId: 'e-2'));

      final items = await dao.getPendingItems();
      expect(items, hasLength(3));
      expect(items[0].id, 'q-1');
      expect(items[1].id, 'q-2');
      expect(items[2].id, 'q-3');
    });

    test('markSynced deletes the row', () async {
      await dao.insertQueueItem(
          _makeQueueItem(id: 'q-1', createdAt: DateTime.now()));
      expect(await dao.getPendingItems(), hasLength(1));

      await dao.markSynced('q-1');

      expect(await dao.getPendingItems(), isEmpty);
      // Also verify it's truly gone via getAllItems
      expect(await dao.getAllItems(), isEmpty);
    });

    test('markParked sets status=parked and stores errorMessage', () async {
      await dao.insertQueueItem(
          _makeQueueItem(id: 'q-1', createdAt: DateTime.now()));

      await dao.markParked('q-1', error: 'HTTP 422 Unprocessable');

      final all = await dao.getAllItems();
      expect(all, hasLength(1));
      expect(all.first.status, 'parked');
      expect(all.first.errorMessage, 'HTTP 422 Unprocessable');
    });

    test('parked items excluded from getPendingItems', () async {
      final now = DateTime.now();
      await dao.insertQueueItem(_makeQueueItem(id: 'q-1', createdAt: now));
      await dao.insertQueueItem(_makeQueueItem(
          id: 'q-2', createdAt: now.add(const Duration(seconds: 1))));

      await dao.markParked('q-1', error: 'bad request');

      final pending = await dao.getPendingItems();
      expect(pending, hasLength(1));
      expect(pending.first.id, 'q-2');
    });

    test('updateAttemptCount persists new count', () async {
      await dao.insertQueueItem(
          _makeQueueItem(id: 'q-1', createdAt: DateTime.now()));

      await dao.updateAttemptCount('q-1', 3);

      final all = await dao.getAllItems();
      expect(all.first.attemptCount, 3);
      // Item should still be pending
      expect(all.first.status, 'pending');
    });

    test('watchPendingCount stream emits correct count', () async {
      final stream = dao.watchPendingCount();
      final counts = <int>[];
      final sub = stream.listen(counts.add);

      // Allow initial emission
      await Future<void>.delayed(const Duration(milliseconds: 50));

      await dao.insertQueueItem(
          _makeQueueItem(id: 'q-1', createdAt: DateTime.now()));
      await Future<void>.delayed(const Duration(milliseconds: 50));

      await dao.insertQueueItem(_makeQueueItem(
          id: 'q-2',
          createdAt: DateTime.now().add(const Duration(seconds: 1))));
      await Future<void>.delayed(const Duration(milliseconds: 50));

      await dao.markSynced('q-1');
      await Future<void>.delayed(const Duration(milliseconds: 50));

      await sub.cancel();

      // Should see: 0 (initial), 1 (after first insert), 2 (after second), 1 (after markSynced)
      expect(counts, contains(0));
      expect(counts, contains(1));
      expect(counts, contains(2));
      // After deleting q-1, back to 1
      expect(counts.last, 1);
    });
  });

  // =========================================================================
  // 2. SyncCursor DAO E2E
  // =========================================================================
  group('SyncCursor DAO E2E', () {
    late AppDatabase db;

    setUp(() {
      db = _openTestDb();
    });

    tearDown(() => db.close());

    test('getCursor returns null on first launch', () async {
      final cursor = await db.syncCursorDao.getCursor();
      expect(cursor, isNull);
    });

    test('updateCursor stores timestamp and getCursor retrieves it', () async {
      final timestamp = DateTime.utc(2025, 6, 15, 12, 30);
      await db.syncCursorDao.updateCursor(timestamp);

      final cursor = await db.syncCursorDao.getCursor();
      expect(cursor, isNotNull);
      // Drift stores DateTimes as unix epoch integers — compare milliseconds
      expect(
        cursor!.millisecondsSinceEpoch,
        timestamp.millisecondsSinceEpoch,
      );
    });

    test('getCursor returns updated timestamp after second update', () async {
      final ts1 = DateTime.utc(2025, 1, 1);
      final ts2 = DateTime.utc(2025, 6, 15);

      await db.syncCursorDao.updateCursor(ts1);
      final cursor1 = await db.syncCursorDao.getCursor();
      expect(cursor1!.millisecondsSinceEpoch, ts1.millisecondsSinceEpoch);

      // Update to a newer cursor
      await db.syncCursorDao.updateCursor(ts2);
      final cursor2 = await db.syncCursorDao.getCursor();
      expect(cursor2!.millisecondsSinceEpoch, ts2.millisecondsSinceEpoch);
    });
  });

  // =========================================================================
  // 3. SyncEngine drainQueue E2E
  // =========================================================================
  group('SyncEngine drainQueue E2E', () {
    late AppDatabase db;
    late MockDioClient mockDioClient;
    late MockSyncRegistry mockRegistry;
    late MockSyncHandler mockHandler;
    late MockConnectivityService mockConnectivity;
    late SyncEngine engine;

    setUp(() {
      db = _openTestDb();
      mockDioClient = MockDioClient();
      mockRegistry = MockSyncRegistry();
      mockHandler = MockSyncHandler();
      mockConnectivity = MockConnectivityService();

      when(() => mockRegistry.getHandler(any())).thenReturn(mockHandler);

      engine = SyncEngine(db, mockDioClient, mockRegistry, mockConnectivity);
    });

    tearDown(() {
      engine.dispose();
      return db.close();
    });

    test('empty queue → emits allSynced status', () async {
      final statuses = <SyncStatus>[];
      final sub = engine.statusStream.listen(statuses.add);

      await engine.drainQueue();
      await Future<void>.delayed(const Duration(milliseconds: 50));

      await sub.cancel();

      expect(statuses, isNotEmpty);
      expect(statuses.last.state, SyncState.allSynced);
      expect(statuses.last.pendingCount, 0);
    });

    test('successful drain → markSynced called, allSynced emitted', () async {
      // Insert a pending item
      await db.syncQueueDao.insertQueueItem(_makeQueueItem(
        id: 'q-1',
        entityType: 'company',
        createdAt: DateTime.now(),
      ));

      when(() => mockHandler.push(any())).thenAnswer((_) async {});

      final statuses = <SyncStatus>[];
      final sub = engine.statusStream.listen(statuses.add);

      await engine.drainQueue();
      await Future<void>.delayed(const Duration(milliseconds: 50));

      await sub.cancel();

      // Handler was called
      verify(() => mockHandler.push(any())).called(1);

      // Item should be deleted (markSynced)
      final remaining = await db.syncQueueDao.getAllItems();
      expect(remaining, isEmpty);

      // Final status is allSynced
      expect(statuses.last.state, SyncState.allSynced);
    });

    test('4xx error → markParked (no retry)', () async {
      await db.syncQueueDao.insertQueueItem(_makeQueueItem(
        id: 'q-1',
        entityType: 'company',
        createdAt: DateTime.now(),
      ));

      when(() => mockHandler.push(any())).thenThrow(DioException(
        requestOptions: RequestOptions(path: '/test'),
        response: Response(
          requestOptions: RequestOptions(path: '/test'),
          statusCode: 422,
        ),
        message: 'Unprocessable Entity',
      ));

      await engine.drainQueue();

      final items = await db.syncQueueDao.getAllItems();
      expect(items, hasLength(1));
      expect(items.first.status, 'parked');
      expect(items.first.errorMessage, isNotNull);
    });

    test('5xx error → attemptCount incremented', () async {
      await db.syncQueueDao.insertQueueItem(_makeQueueItem(
        id: 'q-1',
        entityType: 'company',
        createdAt: DateTime.now(),
      ));

      when(() => mockHandler.push(any())).thenThrow(DioException(
        requestOptions: RequestOptions(path: '/test'),
        response: Response(
          requestOptions: RequestOptions(path: '/test'),
          statusCode: 500,
        ),
        message: 'Internal Server Error',
      ));

      await engine.drainQueue();

      final items = await db.syncQueueDao.getAllItems();
      expect(items, hasLength(1));
      expect(items.first.status, 'pending'); // NOT parked
      expect(items.first.attemptCount, 1); // incremented from 0
    });

    test('concurrent drain guard — _isSyncing prevents re-entry', () async {
      // Insert an item that takes a while to push
      await db.syncQueueDao.insertQueueItem(_makeQueueItem(
        id: 'q-1',
        entityType: 'company',
        createdAt: DateTime.now(),
      ));

      when(() => mockHandler.push(any())).thenAnswer(
        (_) => Future<void>.delayed(const Duration(milliseconds: 200)),
      );

      // Start two drain calls concurrently
      final drain1 = engine.drainQueue();
      final drain2 = engine.drainQueue(); // Should return immediately

      await Future.wait([drain1, drain2]);

      // Handler should only be called once (second drain was a no-op)
      verify(() => mockHandler.push(any())).called(1);
    });
  });

  // =========================================================================
  // 4. SyncEngine pullDelta E2E
  // =========================================================================
  group('SyncEngine pullDelta E2E', () {
    late AppDatabase db;
    late MockDioClient mockDioClient;
    late MockDio mockDio;
    late MockSyncRegistry mockRegistry;
    late MockSyncHandler mockHandler;
    late MockConnectivityService mockConnectivity;
    late SyncEngine engine;

    setUp(() {
      db = _openTestDb();
      mockDioClient = MockDioClient();
      mockDio = MockDio();
      mockRegistry = MockSyncRegistry();
      mockHandler = MockSyncHandler();
      mockConnectivity = MockConnectivityService();

      when(() => mockDioClient.instance).thenReturn(mockDio);
      when(() => mockRegistry.getHandler(any())).thenReturn(mockHandler);
      when(() => mockHandler.applyPulled(any())).thenAnswer((_) async {});

      engine = SyncEngine(db, mockDioClient, mockRegistry, mockConnectivity);
    });

    tearDown(() {
      engine.dispose();
      return db.close();
    });

    test('first launch (null cursor) → GET /sync with no cursor param',
        () async {
      when(() => mockDio.get<Map<String, dynamic>>(
            '/sync',
            queryParameters: any(named: 'queryParameters'),
          )).thenAnswer((_) async => Response(
            requestOptions: RequestOptions(path: '/sync'),
            data: <String, dynamic>{
              'server_timestamp': '2025-06-15T12:00:00Z',
              'companies': <dynamic>[],
            },
            statusCode: 200,
          ));

      await engine.pullDelta();

      final captured = verify(() => mockDio.get<Map<String, dynamic>>(
            '/sync',
            queryParameters: captureAny(named: 'queryParameters'),
          )).captured;

      // First launch: no cursor param → queryParameters should be null
      expect(captured.first, isNull);
    });

    test('with cursor → GET /sync?cursor=timestamp', () async {
      // Set a cursor first
      final cursorTime = DateTime.utc(2025, 6, 10, 8, 0);
      await db.syncCursorDao.updateCursor(cursorTime);

      when(() => mockDio.get<Map<String, dynamic>>(
            '/sync',
            queryParameters: any(named: 'queryParameters'),
          )).thenAnswer((_) async => Response(
            requestOptions: RequestOptions(path: '/sync'),
            data: <String, dynamic>{
              'server_timestamp': '2025-06-15T12:00:00Z',
              'companies': <dynamic>[],
            },
            statusCode: 200,
          ));

      await engine.pullDelta();

      final captured = verify(() => mockDio.get<Map<String, dynamic>>(
            '/sync',
            queryParameters: captureAny(named: 'queryParameters'),
          )).captured;

      final queryParams = captured.first as Map<String, dynamic>;
      expect(queryParams, contains('cursor'));
      // Verify the cursor value matches the stored timestamp
      final cursorValue = queryParams['cursor'] as String;
      final parsedCursor = DateTime.parse(cursorValue);
      expect(
        parsedCursor.millisecondsSinceEpoch,
        cursorTime.millisecondsSinceEpoch,
      );
    });

    test('cursor updated after successful pull', () async {
      when(() => mockDio.get<Map<String, dynamic>>(
            '/sync',
            queryParameters: any(named: 'queryParameters'),
          )).thenAnswer((_) async => Response(
            requestOptions: RequestOptions(path: '/sync'),
            data: <String, dynamic>{
              'server_timestamp': '2025-06-15T12:00:00Z',
              'companies': <dynamic>[],
            },
            statusCode: 200,
          ));

      // Cursor should be null before pull
      expect(await db.syncCursorDao.getCursor(), isNull);

      await engine.pullDelta();

      // Cursor should now be updated to server_timestamp
      final cursor = await db.syncCursorDao.getCursor();
      expect(cursor, isNotNull);
      expect(
        cursor!.millisecondsSinceEpoch,
        DateTime.utc(2025, 6, 15, 12, 0).millisecondsSinceEpoch,
      );
    });
  });

  // =========================================================================
  // 5. SyncStatus subtitle format
  // =========================================================================
  group('SyncStatus subtitle format', () {
    test('offline → "Offline"', () {
      const status = SyncStatus(SyncState.offline, 0);
      expect(status.subtitle, 'Offline');
    });

    test('allSynced → "All synced"', () {
      const status = SyncStatus(SyncState.allSynced, 0);
      expect(status.subtitle, 'All synced');
    });

    test('pending with count → "N item(s) pending"', () {
      const status = SyncStatus(SyncState.pending, 3);
      expect(status.subtitle, '3 item(s) pending');
    });

    test('syncing → "Syncing M of N..."', () {
      const status = SyncStatus(SyncState.syncing, 5, syncingOf: 2);
      expect(status.subtitle, 'Syncing 2 of 5...');
    });

    test('allSynced with upload progress → includes photo upload info', () {
      final status = const SyncStatus(SyncState.allSynced, 3)
          .withUploadProgress(uploadTotal: 5, uploadCompleted: 2);
      expect(status.subtitle, '3 item(s) synced, 5 photos uploading (2/5)');
    });

    test('offline overrides upload progress', () {
      final status = const SyncStatus(SyncState.offline, 0)
          .withUploadProgress(uploadTotal: 3, uploadCompleted: 1);
      expect(status.subtitle, 'Offline');
    });
  });
}
