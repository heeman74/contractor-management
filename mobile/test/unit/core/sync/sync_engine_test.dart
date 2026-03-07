/// Unit tests for SyncEngine — core sync orchestration logic.
///
/// Tests cover all invariants from CONTEXT.md testing strategy:
/// 1.  FIFO queue drain (createdAt ASC ordering) — verifies push order
/// 2.  Successful sync removes item via markSynced
/// 3.  4xx error parks item immediately (no retry)
/// 4.  5xx error increments attemptCount and applies backoff
/// 5.  Max retries (5) resets attemptCount to 0 — stays pending
/// 6.  Concurrent drain prevention (_isSyncing guard)
/// 7.  pullDelta calls handler.applyPulled() for each entity in response
/// 8.  pullDelta updates cursor with server_timestamp
/// 9.  pullDelta on first launch (null cursor) omits cursor query param
/// 10. SyncStatus stream emits syncing then allSynced states
///
/// Uses mocktail for all dependencies.
///
/// NOTE: Requires Flutter SDK + build_runner to run.
/// Run: cd mobile && dart run build_runner build --delete-conflicting-outputs
library;

import 'dart:async';

import 'package:contractorhub/core/database/app_database.dart';
import 'package:contractorhub/core/network/dio_client.dart';
import 'package:contractorhub/core/sync/connectivity_service.dart';
import 'package:contractorhub/core/sync/sync_cursor_dao.dart';
import 'package:contractorhub/core/sync/sync_engine.dart';
import 'package:contractorhub/core/sync/sync_handler.dart';
import 'package:contractorhub/core/sync/sync_queue_dao.dart';
import 'package:contractorhub/core/sync/sync_registry.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

// ---------------------------------------------------------------------------
// Mocks
// ---------------------------------------------------------------------------

class MockAppDatabase extends Mock implements AppDatabase {}

class MockDioClient extends Mock implements DioClient {}

class MockDio extends Mock implements Dio {}

class MockSyncQueueDao extends Mock implements SyncQueueDao {}

class MockSyncCursorDao extends Mock implements SyncCursorDao {}

class MockSyncRegistry extends Mock implements SyncRegistry {}

class MockSyncHandler extends Mock implements SyncHandler {}

class MockConnectivityService extends Mock implements ConnectivityService {}

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

/// Create a [SyncQueueData] test instance with sensible defaults.
SyncQueueData makeSyncQueueItem({
  String id = 'item-1',
  String entityType = 'company',
  String entityId = 'entity-1',
  String operation = 'CREATE',
  String payload = '{}',
  String status = 'pending',
  int attemptCount = 0,
  String? errorMessage,
  DateTime? createdAt,
}) {
  return SyncQueueData(
    id: id,
    entityType: entityType,
    entityId: entityId,
    operation: operation,
    payload: payload,
    status: status,
    attemptCount: attemptCount,
    errorMessage: errorMessage,
    createdAt: createdAt ?? DateTime.utc(2024, 1, 1, 12, 0, 0),
  );
}

/// Container for test dependencies.
class TestDeps {
  final SyncEngine engine;
  final MockDioClient dioClient;
  final MockDio dio;
  final MockSyncQueueDao syncQueueDao;
  final MockSyncCursorDao syncCursorDao;
  final MockSyncRegistry registry;
  final MockSyncHandler companyHandler;
  final MockSyncHandler userHandler;
  final MockConnectivityService connectivityService;
  final MockAppDatabase db;

  TestDeps({
    required this.engine,
    required this.dioClient,
    required this.dio,
    required this.syncQueueDao,
    required this.syncCursorDao,
    required this.registry,
    required this.companyHandler,
    required this.userHandler,
    required this.connectivityService,
    required this.db,
  });
}

/// Build a [SyncEngine] with all dependencies mocked.
TestDeps buildEngine() {
  final db = MockAppDatabase();
  final dioClient = MockDioClient();
  final dio = MockDio();
  final syncQueueDao = MockSyncQueueDao();
  final syncCursorDao = MockSyncCursorDao();
  final registry = MockSyncRegistry();
  final companyHandler = MockSyncHandler();
  final userHandler = MockSyncHandler();
  final connectivityService = MockConnectivityService();

  // Wire MockDio into MockDioClient
  when(() => dioClient.instance).thenReturn(dio);

  // Wire DAO accessors on MockAppDatabase
  when(() => db.syncQueueDao).thenReturn(syncQueueDao);
  when(() => db.syncCursorDao).thenReturn(syncCursorDao);

  // Default handler entity types
  when(() => companyHandler.entityType).thenReturn('company');
  when(() => userHandler.entityType).thenReturn('user');

  final engine = SyncEngine(db, dioClient, registry, connectivityService);

  return TestDeps(
    engine: engine,
    dioClient: dioClient,
    dio: dio,
    syncQueueDao: syncQueueDao,
    syncCursorDao: syncCursorDao,
    registry: registry,
    companyHandler: companyHandler,
    userHandler: userHandler,
    connectivityService: connectivityService,
    db: db,
  );
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

void main() {
  setUpAll(() {
    registerFallbackValue(SyncQueueData(
      id: 'fallback-id',
      entityType: 'company',
      entityId: 'entity-fallback',
      operation: 'CREATE',
      payload: '{}',
      status: 'pending',
      attemptCount: 0,
      errorMessage: null,
      createdAt: DateTime.utc(2024),
    ));
    registerFallbackValue(<String, dynamic>{});
    registerFallbackValue(DateTime.utc(2024));
  });

  group('SyncEngine.drainQueue', () {
    test('1. FIFO queue drain — push called in createdAt ASC order', () async {
      final deps = buildEngine();

      // Items inserted with different createdAt — DAO returns in FIFO order
      final item1 = makeSyncQueueItem(
        id: 'item-first',
        createdAt: DateTime.utc(2024, 1, 1, 12, 0, 0),
      );
      final item2 = makeSyncQueueItem(
        id: 'item-second',
        createdAt: DateTime.utc(2024, 1, 1, 12, 0, 1),
      );
      final item3 = makeSyncQueueItem(
        id: 'item-third',
        createdAt: DateTime.utc(2024, 1, 1, 12, 0, 2),
      );

      // First call returns 3 items, second call (post-drain) returns empty
      var getPendingCallCount = 0;
      when(() => deps.syncQueueDao.getPendingItems()).thenAnswer((_) async {
        getPendingCallCount++;
        return getPendingCallCount == 1 ? [item1, item2, item3] : [];
      });

      when(() => deps.registry.getHandler('company'))
          .thenReturn(deps.companyHandler);
      when(() => deps.companyHandler.push(any())).thenAnswer((_) async {});
      when(() => deps.syncQueueDao.markSynced(any()))
          .thenAnswer((_) async => 1);

      await deps.engine.drainQueue();

      // Capture all push calls and verify FIFO order
      final capturedItems =
          verify(() => deps.companyHandler.push(captureAny()))
              .captured
              .cast<SyncQueueData>();
      expect(capturedItems, hasLength(3));
      expect(capturedItems[0].id, equals('item-first'));
      expect(capturedItems[1].id, equals('item-second'));
      expect(capturedItems[2].id, equals('item-third'));
    });

    test('2. Successful sync calls markSynced — row removed from queue',
        () async {
      final deps = buildEngine();

      final item = makeSyncQueueItem(id: 'item-synced');

      var getPendingCallCount = 0;
      when(() => deps.syncQueueDao.getPendingItems()).thenAnswer((_) async {
        getPendingCallCount++;
        return getPendingCallCount == 1 ? [item] : [];
      });

      when(() => deps.registry.getHandler('company'))
          .thenReturn(deps.companyHandler);
      when(() => deps.companyHandler.push(any())).thenAnswer((_) async {});
      when(() => deps.syncQueueDao.markSynced(any()))
          .thenAnswer((_) async => 1);

      await deps.engine.drainQueue();

      verify(() => deps.syncQueueDao.markSynced('item-synced')).called(1);
      verifyNever(() =>
          deps.syncQueueDao.markParked(any(), error: any(named: 'error')));
    });

    test('3. 4xx error parks item — markParked called, NOT retried', () async {
      final deps = buildEngine();

      final item = makeSyncQueueItem(id: 'item-4xx');
      final dioError = DioException(
        requestOptions: RequestOptions(path: '/companies'),
        response: Response(
          requestOptions: RequestOptions(path: '/companies'),
          statusCode: 400,
        ),
        type: DioExceptionType.badResponse,
      );

      var getPendingCallCount = 0;
      when(() => deps.syncQueueDao.getPendingItems()).thenAnswer((_) async {
        getPendingCallCount++;
        return getPendingCallCount == 1 ? [item] : [];
      });

      when(() => deps.registry.getHandler('company'))
          .thenReturn(deps.companyHandler);
      when(() => deps.companyHandler.push(any())).thenThrow(dioError);
      when(() =>
              deps.syncQueueDao.markParked(any(), error: any(named: 'error')))
          .thenAnswer((_) async {});

      await deps.engine.drainQueue();

      verify(
        () =>
            deps.syncQueueDao.markParked('item-4xx', error: any(named: 'error')),
      ).called(1);
      verifyNever(() => deps.syncQueueDao.markSynced(any()));
      verifyNever(() => deps.syncQueueDao.updateAttemptCount(any(), any()));
    });

    test('4. 5xx error increments attemptCount (0 -> 1)', () async {
      final deps = buildEngine();

      // Item starts at attemptCount = 0
      final item = makeSyncQueueItem(id: 'item-5xx', attemptCount: 0);
      final dioError = DioException(
        requestOptions: RequestOptions(path: '/companies'),
        response: Response(
          requestOptions: RequestOptions(path: '/companies'),
          statusCode: 500,
        ),
        type: DioExceptionType.badResponse,
      );

      var getPendingCallCount = 0;
      when(() => deps.syncQueueDao.getPendingItems()).thenAnswer((_) async {
        getPendingCallCount++;
        return getPendingCallCount == 1 ? [item] : [];
      });

      when(() => deps.registry.getHandler('company'))
          .thenReturn(deps.companyHandler);
      when(() => deps.companyHandler.push(any())).thenThrow(dioError);
      when(() => deps.syncQueueDao.updateAttemptCount(any(), any()))
          .thenAnswer((_) async {});

      await deps.engine.drainQueue();

      // newCount = 0 + 1 = 1 (not yet at max of 5)
      verify(() => deps.syncQueueDao.updateAttemptCount('item-5xx', 1))
          .called(1);
      verifyNever(() =>
          deps.syncQueueDao.markParked(any(), error: any(named: 'error')));
      verifyNever(() => deps.syncQueueDao.markSynced(any()));
    });

    test(
        '5. Max retries (attemptCount 4 -> 5) resets count to 0 — stays pending',
        () async {
      final deps = buildEngine();

      // Item is at attemptCount = 4; next failure = attempt 5 = max
      final item = makeSyncQueueItem(id: 'item-max-retry', attemptCount: 4);
      final dioError = DioException(
        requestOptions: RequestOptions(path: '/companies'),
        response: Response(
          requestOptions: RequestOptions(path: '/companies'),
          statusCode: 503,
        ),
        type: DioExceptionType.badResponse,
      );

      var getPendingCallCount = 0;
      when(() => deps.syncQueueDao.getPendingItems()).thenAnswer((_) async {
        getPendingCallCount++;
        return getPendingCallCount == 1 ? [item] : [];
      });

      when(() => deps.registry.getHandler('company'))
          .thenReturn(deps.companyHandler);
      when(() => deps.companyHandler.push(any())).thenThrow(dioError);
      when(() => deps.syncQueueDao.updateAttemptCount(any(), any()))
          .thenAnswer((_) async {});

      await deps.engine.drainQueue();

      // newCount = 4 + 1 = 5 >= _maxAttempts(5) -> reset to 0
      verify(() => deps.syncQueueDao.updateAttemptCount('item-max-retry', 0))
          .called(1);
      verifyNever(() =>
          deps.syncQueueDao.markParked(any(), error: any(named: 'error')));
    });

    test(
        '6. Concurrent drain prevention — second drainQueue() returns immediately',
        () async {
      final deps = buildEngine();

      final item = makeSyncQueueItem(id: 'item-concurrent');
      final pushCompleter = Completer<void>();

      // Push will block until we release pushCompleter
      var getPendingCallCount = 0;
      when(() => deps.syncQueueDao.getPendingItems()).thenAnswer((_) async {
        getPendingCallCount++;
        return getPendingCallCount == 1 ? [item] : [];
      });

      when(() => deps.registry.getHandler('company'))
          .thenReturn(deps.companyHandler);
      when(() => deps.companyHandler.push(any()))
          .thenAnswer((_) async => pushCompleter.future);
      when(() => deps.syncQueueDao.markSynced(any()))
          .thenAnswer((_) async => 1);

      // Start first drain — will block at handler.push()
      final firstDrain = deps.engine.drainQueue();

      // Yield to let the first drain start
      await Future<void>.delayed(Duration.zero);

      // Start second drain while first is still running
      await deps.engine.drainQueue();

      // Release the first drain's push
      pushCompleter.complete();
      await firstDrain;

      // The second drainQueue() should have returned immediately without
      // calling getPendingItems again. The first drain calls it once for
      // items + once for remaining = 2 total calls.
      expect(
        getPendingCallCount,
        lessThanOrEqualTo(2),
        reason: 'Second drain must not call getPendingItems (isSyncing guard)',
      );
    });

    test('10. SyncStatus stream emits syncing then allSynced', () async {
      final deps = buildEngine();

      final item = makeSyncQueueItem(id: 'item-status');
      final emittedStatuses = <SyncStatus>[];

      final sub = deps.engine.statusStream.listen(emittedStatuses.add);

      var getPendingCallCount = 0;
      when(() => deps.syncQueueDao.getPendingItems()).thenAnswer((_) async {
        getPendingCallCount++;
        return getPendingCallCount == 1 ? [item] : [];
      });

      when(() => deps.registry.getHandler('company'))
          .thenReturn(deps.companyHandler);
      when(() => deps.companyHandler.push(any())).thenAnswer((_) async {});
      when(() => deps.syncQueueDao.markSynced(any()))
          .thenAnswer((_) async => 1);

      await deps.engine.drainQueue();
      // Allow microtasks to deliver remaining stream events
      await Future<void>.delayed(Duration.zero);
      await sub.cancel();

      expect(emittedStatuses, isNotEmpty);

      // Final status must be allSynced (queue is empty after drain)
      expect(
        emittedStatuses.last.state,
        equals(SyncState.allSynced),
        reason: 'After successful drain, status must be allSynced',
      );

      // At least one syncing status must have been emitted during drain
      final syncingStatuses =
          emittedStatuses.where((s) => s.state == SyncState.syncing).toList();
      expect(
        syncingStatuses,
        isNotEmpty,
        reason: 'Syncing status must be emitted during drain',
      );
    });
  });

  group('SyncEngine.pullDelta', () {
    test(
        '7. pullDelta calls handler.applyPulled for each entity in response',
        () async {
      final deps = buildEngine();

      // Use a recent cursor to trigger delta pull (not null = not first launch)
      when(() => deps.syncCursorDao.getCursor())
          .thenAnswer((_) async => DateTime.utc(2024, 1, 1));

      final syncResponse = <String, dynamic>{
        'companies': [
          {'id': 'company-1', 'name': 'Acme Corp'},
          {'id': 'company-2', 'name': 'Beta LLC'},
        ],
        'users': [
          {'id': 'user-1', 'email': 'alice@example.com'},
        ],
        'user_roles': <dynamic>[],
        'server_timestamp': '2024-06-01T12:00:00.000000Z',
      };

      when(() => deps.dio.get<Map<String, dynamic>>(
            '/sync',
            queryParameters: any(named: 'queryParameters'),
          )).thenAnswer((_) async => Response(
            data: syncResponse,
            requestOptions: RequestOptions(path: '/sync'),
            statusCode: 200,
          ));

      when(() => deps.companyHandler.applyPulled(any()))
          .thenAnswer((_) async {});
      when(() => deps.userHandler.applyPulled(any()))
          .thenAnswer((_) async {});

      // Fallback handler for user_role (empty list, but handler must be registered)
      final userRoleHandler = MockSyncHandler();
      when(() => userRoleHandler.entityType).thenReturn('user_role');
      when(() => userRoleHandler.applyPulled(any()))
          .thenAnswer((_) async {});

      when(() => deps.registry.getHandler('company'))
          .thenReturn(deps.companyHandler);
      when(() => deps.registry.getHandler('user'))
          .thenReturn(deps.userHandler);
      when(() => deps.registry.getHandler('user_role'))
          .thenReturn(userRoleHandler);

      when(() => deps.syncCursorDao.updateCursor(any()))
          .thenAnswer((_) async {});

      await deps.engine.pullDelta();

      // 2 companies should be applied
      verify(() => deps.companyHandler.applyPulled(any())).called(2);
      // 1 user should be applied
      verify(() => deps.userHandler.applyPulled(any())).called(1);
    });

    test('8. pullDelta updates cursor with server_timestamp', () async {
      final deps = buildEngine();

      const serverTimestamp = '2024-06-15T08:30:00.000000Z';
      when(() => deps.syncCursorDao.getCursor())
          .thenAnswer((_) async => DateTime.utc(2024, 1, 1));

      final syncResponse = <String, dynamic>{
        'companies': <dynamic>[],
        'users': <dynamic>[],
        'user_roles': <dynamic>[],
        'server_timestamp': serverTimestamp,
      };

      when(() => deps.dio.get<Map<String, dynamic>>(
            '/sync',
            queryParameters: any(named: 'queryParameters'),
          )).thenAnswer((_) async => Response(
            data: syncResponse,
            requestOptions: RequestOptions(path: '/sync'),
            statusCode: 200,
          ));

      when(() => deps.registry.getHandler(any()))
          .thenReturn(deps.companyHandler);
      when(() => deps.companyHandler.applyPulled(any()))
          .thenAnswer((_) async {});

      final capturedTimestamps = <DateTime>[];
      when(() => deps.syncCursorDao.updateCursor(captureAny()))
          .thenAnswer((invocation) async {
        capturedTimestamps
            .add(invocation.positionalArguments[0] as DateTime);
      });

      await deps.engine.pullDelta();

      expect(capturedTimestamps, hasLength(1));
      expect(
        capturedTimestamps.first,
        equals(DateTime.parse(serverTimestamp)),
        reason:
            'Cursor must be updated to server_timestamp for next delta pull',
      );
    });

    test(
        '9. pullDelta with null cursor (first launch) omits cursor query param',
        () async {
      final deps = buildEngine();

      // null = first launch, no cursor param should be sent
      when(() => deps.syncCursorDao.getCursor()).thenAnswer((_) async => null);

      final syncResponse = <String, dynamic>{
        'companies': <dynamic>[],
        'users': <dynamic>[],
        'user_roles': <dynamic>[],
        'server_timestamp': '2024-06-01T00:00:00.000000Z',
      };

      Map<String, dynamic>? capturedQueryParams;
      when(() => deps.dio.get<Map<String, dynamic>>(
            '/sync',
            queryParameters: any(named: 'queryParameters'),
          )).thenAnswer((invocation) async {
        capturedQueryParams = invocation.namedArguments[
            const Symbol('queryParameters')] as Map<String, dynamic>?;
        return Response(
          data: syncResponse,
          requestOptions: RequestOptions(path: '/sync'),
          statusCode: 200,
        );
      });

      when(() => deps.registry.getHandler(any()))
          .thenReturn(deps.companyHandler);
      when(() => deps.companyHandler.applyPulled(any()))
          .thenAnswer((_) async {});
      when(() => deps.syncCursorDao.updateCursor(any()))
          .thenAnswer((_) async {});

      await deps.engine.pullDelta();

      // First launch: queryParameters must be null so server performs full download
      expect(
        capturedQueryParams,
        isNull,
        reason:
            'On first launch (null cursor), cursor param must be omitted — '
            'server defaults to full download from epoch 2000-01-01',
      );
    });
  });
}
