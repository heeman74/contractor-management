// Phase 12 E2E: Client Profile Sync Fix
//
// Covers CLNT-01 (INT-04 gap closure):
// - ClientProfileSyncHandler.push() routes CREATE to POST /clients/{userId}/profile
// - ClientProfileSyncHandler.push() routes UPDATE to POST /clients/{userId}/profile
// - Full offline flow: Drift insert → sync queue → push → correct URL verified
//
// Strategy: Real Drift in-memory DB. MockDioClient for HTTP layer.
// Direct await on handler.push() — no pumpAndSettle (Drift streams never settle).

import 'dart:convert';

import 'package:contractorhub/core/database/app_database.dart' hide UserRole;
import 'package:contractorhub/core/network/dio_client.dart';
import 'package:contractorhub/features/jobs/data/client_profile_sync_handler.dart';
import 'package:dio/dio.dart';
import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

// ---------------------------------------------------------------------------
// Mocks
// ---------------------------------------------------------------------------

class MockDioClient extends Mock implements DioClient {}

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

/// Open an in-memory Drift DB for testing.
AppDatabase _openTestDb() => AppDatabase(NativeDatabase.memory());

/// Build a fake [SyncQueueData] row for testing without DB round-trip.
SyncQueueData _buildSyncQueueItem({
  required String id,
  required String entityId,
  required String operation,
  required String userId,
  String companyId = _companyId,
}) {
  final payload = jsonEncode({
    'id': entityId,
    'companyId': companyId,
    'userId': userId,
    'version': 1,
    'createdAt': '2026-01-01T00:00:00.000Z',
    'updatedAt': '2026-01-01T00:00:00.000Z',
  });

  return SyncQueueData(
    id: id,
    entityType: 'client_profile',
    entityId: entityId,
    operation: operation,
    payload: payload,
    status: 'pending',
    attemptCount: 0,
    createdAt: DateTime.utc(2026),
  );
}

/// Stub [mockDioClient.pushWithIdempotency] to return a 201 success response.
/// Matches both the 3-arg form (POST default) and the 4-arg form (custom method).
void _stubPushSuccess(MockDioClient mockDioClient) {
  when(
    () => mockDioClient.pushWithIdempotency(
      any(),
      any(),
      any(),
    ),
  ).thenAnswer(
    (_) async => Response(
      data: <String, dynamic>{},
      statusCode: 201,
      requestOptions: RequestOptions(),
    ),
  );
  when(
    () => mockDioClient.pushWithIdempotency(
      any(),
      any(),
      any(),
      method: any(named: 'method'),
    ),
  ).thenAnswer(
    (_) async => Response(
      data: <String, dynamic>{},
      statusCode: 201,
      requestOptions: RequestOptions(),
    ),
  );
}

// ---------------------------------------------------------------------------
// Shared test constants
// ---------------------------------------------------------------------------

const _companyId = 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa';
const _userId = 'bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb';
const _profileId = 'cccccccc-cccc-cccc-cccc-cccccccccccc';
const _queueItemId = 'dddddddd-dddd-dddd-dddd-dddddddddddd';
const _queueItemId2 = 'eeeeeeee-eeee-eeee-eeee-eeeeeeeeeeee';

void main() {
  setUpAll(() {
    registerFallbackValue(<String, dynamic>{});
  });

  // =========================================================================
  // Test 1: CREATE operation routes to POST /clients/{userId}/profile
  // =========================================================================
  group('CLNT-01: CREATE push routes to correct endpoint', () {
    late AppDatabase db;
    late MockDioClient mockDioClient;
    late ClientProfileSyncHandler handler;

    setUp(() {
      db = _openTestDb();
      mockDioClient = MockDioClient();
      handler = ClientProfileSyncHandler(mockDioClient, db);
      _stubPushSuccess(mockDioClient);
    });

    tearDown(() async {
      await db.close();
    });

    test(
        'push() with operation=CREATE calls pushWithIdempotency at '
        '/clients/{userId}/profile', () async {
      final item = _buildSyncQueueItem(
        id: _queueItemId,
        entityId: _profileId,
        operation: 'CREATE',
        userId: _userId,
      );

      await handler.push(item);

      verify(
        () => mockDioClient.pushWithIdempotency(
          '/clients/$_userId/profile',
          any(),
          _queueItemId,
        ),
      ).called(1);
    });

    test('push() with operation=CREATE does NOT call any /clients/profiles URL',
        () async {
      final item = _buildSyncQueueItem(
        id: _queueItemId,
        entityId: _profileId,
        operation: 'CREATE',
        userId: _userId,
      );

      await handler.push(item);

      // The old broken URL must NOT be called
      verifyNever(
        () => mockDioClient.pushWithIdempotency(
          '/clients/profiles',
          any(),
          any(),
        ),
      );
    });
  });

  // =========================================================================
  // Test 2: UPDATE operation routes to POST /clients/{userId}/profile (not PATCH)
  // =========================================================================
  group('CLNT-01: UPDATE push routes to correct endpoint with POST', () {
    late AppDatabase db;
    late MockDioClient mockDioClient;
    late ClientProfileSyncHandler handler;

    setUp(() {
      db = _openTestDb();
      mockDioClient = MockDioClient();
      handler = ClientProfileSyncHandler(mockDioClient, db);
      _stubPushSuccess(mockDioClient);
    });

    tearDown(() async {
      await db.close();
    });

    test(
        'push() with operation=UPDATE calls pushWithIdempotency at '
        '/clients/{userId}/profile (POST, not PATCH)', () async {
      final item = _buildSyncQueueItem(
        id: _queueItemId2,
        entityId: _profileId,
        operation: 'UPDATE',
        userId: _userId,
      );

      await handler.push(item);

      // UPDATE must use the same upsert endpoint as CREATE — no PATCH
      verify(
        () => mockDioClient.pushWithIdempotency(
          '/clients/$_userId/profile',
          any(),
          _queueItemId2,
        ),
      ).called(1);
    });

    test(
        'push() with operation=UPDATE does NOT use PATCH or old /clients/profiles/{id} URL',
        () async {
      final item = _buildSyncQueueItem(
        id: _queueItemId2,
        entityId: _profileId,
        operation: 'UPDATE',
        userId: _userId,
      );

      await handler.push(item);

      // The old broken PATCH URL must NOT be called
      verifyNever(
        () => mockDioClient.pushWithIdempotency(
          '/clients/profiles/$_profileId',
          any(),
          any(),
        ),
      );
    });
  });

  // =========================================================================
  // Test 3: Full offline flow — Drift insert → sync queue → push → URL verified
  // =========================================================================
  group('CLNT-01: Full offline flow with real Drift DB', () {
    late AppDatabase db;
    late MockDioClient mockDioClient;
    late ClientProfileSyncHandler handler;

    setUp(() {
      db = _openTestDb();
      mockDioClient = MockDioClient();
      handler = ClientProfileSyncHandler(mockDioClient, db);
      _stubPushSuccess(mockDioClient);
    });

    tearDown(() async {
      await db.close();
    });

    test(
        'seed client profile in Drift, enqueue CREATE, call push(), '
        'verify correct URL with userId from payload', () async {
      // Seed a client profile row in the local Drift DB
      final now = DateTime.utc(2026);
      final profileCompanion = ClientProfilesCompanion(
        id: const Value(_profileId),
        companyId: const Value(_companyId),
        userId: const Value(_userId),
        createdAt: Value(now),
        updatedAt: Value(now),
      );
      await db.into(db.clientProfiles).insert(profileCompanion);

      // Verify the profile was seeded
      final profiles = await db.select(db.clientProfiles).get();
      expect(profiles, hasLength(1));
      expect(profiles.first.id, equals(_profileId));
      expect(profiles.first.userId, equals(_userId));

      // Create a sync queue item as job_dao.dart would (entityId = profile UUID)
      final queueItem = _buildSyncQueueItem(
        id: _queueItemId,
        entityId: _profileId, // profile UUID — NOT userId
        operation: 'CREATE',
        userId: _userId,
      );

      // Call the handler — this exercises the actual push() logic
      await handler.push(queueItem);

      // Verify the correct URL was called with userId (not profileId) in path
      verify(
        () => mockDioClient.pushWithIdempotency(
          '/clients/$_userId/profile',
          any(),
          _queueItemId,
        ),
      ).called(1);

      // Confirm the handler did NOT use entityId (profileId) as the path param
      verifyNever(
        () => mockDioClient.pushWithIdempotency(
          '/clients/$_profileId/profile',
          any(),
          any(),
        ),
      );

      // Profile should still exist in Drift (push doesn't remove local data)
      final profilesAfter = await db.select(db.clientProfiles).get();
      expect(profilesAfter, hasLength(1));
    });

    test('push() throws StateError for unknown operation', () async {
      final item = _buildSyncQueueItem(
        id: _queueItemId,
        entityId: _profileId,
        operation: 'DELETE', // DELETE is not a supported operation
        userId: _userId,
      );

      expect(() => handler.push(item), throwsA(isA<StateError>()));
    });
  });
}
