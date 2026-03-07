/// Unit tests for UserSyncHandler — user entity sync logic.
///
/// Tests cover:
/// 1. entityType returns 'user'
/// 2. push calls pushWithIdempotency with /users path
/// 3. applyPulled inserts new user into Drift DB
/// 4. applyPulled propagates tombstone (deleted_at)
library;

import 'package:contractorhub/core/database/app_database.dart';
import 'package:contractorhub/core/network/dio_client.dart';
import 'package:contractorhub/core/sync/handlers/user_sync_handler.dart';
import 'package:dio/dio.dart';
import 'package:drift/drift.dart' hide isNotNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

class MockDioClient extends Mock implements DioClient {}

AppDatabase openTestDatabase() {
  return AppDatabase(NativeDatabase.memory());
}

void main() {
  late MockDioClient mockDioClient;
  late AppDatabase db;
  late UserSyncHandler handler;

  setUp(() async {
    mockDioClient = MockDioClient();
    db = openTestDatabase();
    handler = UserSyncHandler(mockDioClient, db);

    // Insert a company (FK constraint for users)
    await db.into(db.companies).insert(CompaniesCompanion.insert(
          id: const Value('co-1'),
          name: 'Test Co',
          version: const Value(1),
          createdAt: DateTime.now(),
          updatedAt: DateTime.now(),
        ));
  });

  tearDown(() async {
    await db.close();
  });

  test('entityType is user', () {
    expect(handler.entityType, equals('user'));
  });

  test('push calls pushWithIdempotency with /users path', () async {
    when(() => mockDioClient.pushWithIdempotency(
          any(),
          any(),
          any(),
        )).thenAnswer((_) async => Response(
          statusCode: 201,
          requestOptions: RequestOptions(path: '/users'),
        ));

    final item = SyncQueueData(
      id: 'queue-1',
      entityType: 'user',
      entityId: 'u-1',
      operation: 'CREATE',
      payload: '{"id":"u-1","companyId":"co-1","email":"a@t.com"}',
      status: 'pending',
      attemptCount: 0,
      errorMessage: null,
      createdAt: DateTime.now(),
    );

    await handler.push(item);

    verify(() => mockDioClient.pushWithIdempotency(
          '/users',
          {'id': 'u-1', 'companyId': 'co-1', 'email': 'a@t.com'},
          'queue-1',
        )).called(1);
  });

  test('applyPulled inserts new user into Drift DB', () async {
    await handler.applyPulled({
      'id': 'u-1',
      'company_id': 'co-1',
      'email': 'user@test.com',
      'first_name': 'Jane',
      'last_name': 'Doe',
      'phone': null,
      'version': 1,
      'created_at': '2024-01-01T00:00:00.000Z',
      'updated_at': '2024-01-01T00:00:00.000Z',
      'deleted_at': null,
    });

    final row = await (db.select(db.users)
          ..where((tbl) => tbl.id.equals('u-1')))
        .getSingleOrNull();
    expect(row, isNotNull);
    expect(row!.email, equals('user@test.com'));
    expect(row.firstName, equals('Jane'));
  });

  test('applyPulled propagates tombstone (deleted_at)', () async {
    await handler.applyPulled({
      'id': 'u-1',
      'company_id': 'co-1',
      'email': 'user@test.com',
      'first_name': null,
      'last_name': null,
      'phone': null,
      'version': 1,
      'created_at': '2024-01-01T00:00:00.000Z',
      'updated_at': '2024-01-01T00:00:00.000Z',
      'deleted_at': '2024-06-01T00:00:00.000Z',
    });

    final row = await (db.select(db.users)
          ..where((tbl) => tbl.id.equals('u-1')))
        .getSingleOrNull();
    expect(row, isNotNull);
    expect(row!.deletedAt, isNotNull);
  });
}
