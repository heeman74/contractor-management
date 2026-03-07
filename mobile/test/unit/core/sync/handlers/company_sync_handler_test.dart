/// Unit tests for CompanySyncHandler — company entity sync logic.
///
/// Tests cover:
/// 1. entityType returns 'company'
/// 2. push calls pushWithIdempotency with correct path
/// 3. applyPulled inserts new company into Drift DB
/// 4. applyPulled upserts existing company
/// 5. applyPulled propagates tombstone (deleted_at)
library;

import 'package:contractorhub/core/database/app_database.dart';
import 'package:contractorhub/core/network/dio_client.dart';
import 'package:contractorhub/core/sync/handlers/company_sync_handler.dart';
import 'package:dio/dio.dart';
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
  late CompanySyncHandler handler;

  setUp(() {
    mockDioClient = MockDioClient();
    db = openTestDatabase();
    handler = CompanySyncHandler(mockDioClient, db);
  });

  tearDown(() async {
    await db.close();
  });

  test('entityType is company', () {
    expect(handler.entityType, equals('company'));
  });

  test('push calls pushWithIdempotency with /companies path', () async {
    when(() => mockDioClient.pushWithIdempotency(
          any(),
          any(),
          any(),
        )).thenAnswer((_) async => Response(
          statusCode: 201,
          requestOptions: RequestOptions(path: '/companies'),
        ));

    final item = SyncQueueData(
      id: 'queue-1',
      entityType: 'company',
      entityId: 'co-1',
      operation: 'CREATE',
      payload: '{"id":"co-1","name":"Test"}',
      status: 'pending',
      attemptCount: 0,
      errorMessage: null,
      createdAt: DateTime.now(),
    );

    await handler.push(item);

    verify(() => mockDioClient.pushWithIdempotency(
          '/companies',
          {'id': 'co-1', 'name': 'Test'},
          'queue-1',
        )).called(1);
  });

  test('applyPulled inserts new company into Drift DB', () async {
    await handler.applyPulled({
      'id': 'co-1',
      'name': 'New Corp',
      'address': '123 Main St',
      'phone': null,
      'business_number': null,
      'logo_url': null,
      'trade_types': null,
      'version': 1,
      'created_at': '2024-01-01T00:00:00.000Z',
      'updated_at': '2024-01-01T00:00:00.000Z',
      'deleted_at': null,
    });

    final row = await (db.select(db.companies)
          ..where((tbl) => tbl.id.equals('co-1')))
        .getSingleOrNull();
    expect(row, isNotNull);
    expect(row!.name, equals('New Corp'));
    expect(row.address, equals('123 Main St'));
  });

  test('applyPulled upserts existing company', () async {
    // Insert first
    await handler.applyPulled({
      'id': 'co-1',
      'name': 'Old Name',
      'address': null,
      'phone': null,
      'business_number': null,
      'logo_url': null,
      'trade_types': null,
      'version': 1,
      'created_at': '2024-01-01T00:00:00.000Z',
      'updated_at': '2024-01-01T00:00:00.000Z',
      'deleted_at': null,
    });

    // Upsert with new name
    await handler.applyPulled({
      'id': 'co-1',
      'name': 'New Name',
      'address': null,
      'phone': null,
      'business_number': null,
      'logo_url': null,
      'trade_types': null,
      'version': 2,
      'created_at': '2024-01-01T00:00:00.000Z',
      'updated_at': '2024-01-02T00:00:00.000Z',
      'deleted_at': null,
    });

    final row = await (db.select(db.companies)
          ..where((tbl) => tbl.id.equals('co-1')))
        .getSingleOrNull();
    expect(row!.name, equals('New Name'));
    expect(row.version, equals(2));
  });

  test('applyPulled propagates tombstone (deleted_at)', () async {
    await handler.applyPulled({
      'id': 'co-1',
      'name': 'To Delete',
      'address': null,
      'phone': null,
      'business_number': null,
      'logo_url': null,
      'trade_types': null,
      'version': 1,
      'created_at': '2024-01-01T00:00:00.000Z',
      'updated_at': '2024-01-01T00:00:00.000Z',
      'deleted_at': '2024-06-01T00:00:00.000Z',
    });

    final row = await (db.select(db.companies)
          ..where((tbl) => tbl.id.equals('co-1')))
        .getSingleOrNull();
    expect(row, isNotNull);
    expect(row!.deletedAt, isNotNull);
  });
}
