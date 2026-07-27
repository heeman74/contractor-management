/// Unit tests for CostBreakdown parsing and FinanceRepository breakdown fetches.
///
/// Tests cover:
/// 1. CostBreakdown.fromJson on a full job payload (categories, labor, totals)
/// 2. CostBreakdown.fromJson on a trade-scope payload (labor null, job-level flag)
/// 3. FormatException when grand_total is a number instead of a String
/// 4. FormatException when categories is not a List
/// 5. Malformed category entries are skipped, not fatal
/// 6. fetchProjectRollup tolerates an older backend without breakdown fields
/// 7. fetchProjectRollup surfaces the breakdown when the new fields are present
/// 8. fetchProjectRollup stays strict about the "total" string
library;

import 'package:contractorhub/core/database/app_database.dart';
import 'package:contractorhub/core/network/dio_client.dart';
import 'package:contractorhub/features/finance/data/cost_breakdown.dart';
import 'package:contractorhub/features/finance/data/finance_repository.dart';
import 'package:dio/dio.dart';
import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

class MockDioClient extends Mock implements DioClient {}

class MockDio extends Mock implements Dio {}

const _rollupPath = '/projects/proj-1/cost-entries';

Map<String, dynamic> _jobBreakdownJson() => {
      'categories': [
        {
          'category_id': 'cat-materials',
          'category_name': 'materials',
          'total': '150.00',
        },
      ],
      'labor': {
        'total': '240.00',
        'rated_seconds': 28800,
        'unrated_seconds': 45000,
        'basis': 'unburdened',
      },
      'labor_tracked_at_job_level': false,
      'grand_total': '390.00',
    };

Map<String, dynamic> _tradeScopeBreakdownJson() => {
      'categories': [
        {
          'category_id': 'cat-materials',
          'category_name': 'materials',
          'total': '150.00',
        },
      ],
      'labor': null,
      'labor_tracked_at_job_level': true,
      'grand_total': '150.00',
    };

Map<String, dynamic> _remoteEntryJson() => {
      'id': 'remote-entry-1',
      'job_id': 'job-1',
      'category_id': 'cat-materials',
      'amount': '150.00',
      'incurred_date': '2026-07-20',
      'version': 1,
      'created_at': DateTime.now().toIso8601String(),
      'updated_at': DateTime.now().toIso8601String(),
    };

void main() {
  group('CostBreakdown.fromJson', () {
    test('parses a full job payload with categories, labor, and totals', () {
      final breakdown = CostBreakdown.fromJson(_jobBreakdownJson());

      expect(breakdown.labor, isNotNull);
      expect(breakdown.labor!.total, '240.00');
      expect(breakdown.labor!.ratedSeconds, 28800);
      expect(breakdown.labor!.unratedSeconds, 45000);
      expect(breakdown.labor!.basis, 'unburdened');
      expect(breakdown.laborTrackedAtJobLevel, isFalse);
      expect(breakdown.grandTotal, '390.00');
      expect(breakdown.categories, hasLength(1));
      expect(breakdown.categories.first.categoryName, 'materials');
      expect(breakdown.categories.first.total, '150.00');
    });

    test('parses a trade-scope payload with null labor and job-level flag', () {
      final breakdown = CostBreakdown.fromJson(_tradeScopeBreakdownJson());

      expect(breakdown.labor, isNull);
      expect(breakdown.laborTrackedAtJobLevel, isTrue);
    });

    test('throws FormatException when grand_total is a number', () {
      final json = _jobBreakdownJson()..['grand_total'] = 390.0;

      expect(
        () => CostBreakdown.fromJson(json),
        throwsA(isA<FormatException>()),
      );
    });

    test('throws FormatException when categories is not a List', () {
      final json = _jobBreakdownJson()..['categories'] = 'not-a-list';

      expect(
        () => CostBreakdown.fromJson(json),
        throwsA(isA<FormatException>()),
      );
    });

    test('skips a malformed category entry rather than crashing the parse', () {
      final json = _jobBreakdownJson()
        ..['categories'] = [
          {
            'category_id': 'cat-materials',
            'category_name': 'materials',
            'total': '150.00',
          },
          {'category_id': 'cat-bad', 'category_name': 'bad', 'total': 12.5},
          'not-even-a-map',
        ];

      final breakdown = CostBreakdown.fromJson(json);

      expect(breakdown.categories, hasLength(1));
      expect(breakdown.categories.first.categoryId, 'cat-materials');
    });
  });

  group('FinanceRepository.fetchProjectRollup breakdown tolerance', () {
    late AppDatabase db;
    late MockDioClient mockDioClient;
    late MockDio mockDio;
    late FinanceRepository repository;

    setUp(() async {
      db = AppDatabase(NativeDatabase.memory());
      mockDioClient = MockDioClient();
      mockDio = MockDio();
      when(() => mockDioClient.instance).thenReturn(mockDio);
      repository = FinanceRepository(
        dioClient: mockDioClient,
        costEntryDao: db.costEntryDao,
        costReceiptDao: db.costReceiptDao,
      );

      await db.companyDao.insertCompany(CompaniesCompanion.insert(
        id: const Value('co-1'),
        name: 'Company co-1',
        version: const Value(1),
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      ));
    });

    tearDown(() async => await db.close());

    void stubRollupResponse(Map<String, dynamic> data) {
      when(() => mockDio.get<dynamic>(_rollupPath))
          .thenAnswer((_) async => Response<dynamic>(
                requestOptions: RequestOptions(path: _rollupPath),
                statusCode: 200,
                data: data,
              ));
    }

    test('returns total and jobIds with a null breakdown on an older backend',
        () async {
      stubRollupResponse({
        'project_id': 'proj-1',
        'total': '150.00',
        'entries': [_remoteEntryJson()],
      });

      final fetch = await repository.fetchProjectRollup('co-1', 'proj-1');

      expect(fetch.total, '150.00');
      expect(fetch.jobIds, ['job-1']);
      expect(fetch.breakdown, isNull);
    });

    test('returns a populated breakdown alongside the unchanged total',
        () async {
      stubRollupResponse({
        'project_id': 'proj-1',
        'total': '150.00',
        'entries': [_remoteEntryJson()],
        ..._jobBreakdownJson(),
      });

      final fetch = await repository.fetchProjectRollup('co-1', 'proj-1');

      expect(fetch.total, '150.00');
      expect(fetch.jobIds, ['job-1']);
      expect(fetch.breakdown, isNotNull);
      expect(fetch.breakdown!.grandTotal, '390.00');
      expect(fetch.breakdown!.labor!.total, '240.00');
      expect(fetch.breakdown!.categories, hasLength(1));
    });

    test('still throws FormatException when total is missing', () async {
      stubRollupResponse({
        'project_id': 'proj-1',
        'entries': <Object?>[],
      });

      expect(
        () => repository.fetchProjectRollup('co-1', 'proj-1'),
        throwsA(isA<FormatException>()),
      );
    });

    test('still throws FormatException when total is a number', () async {
      stubRollupResponse({
        'project_id': 'proj-1',
        'total': 150.0,
        'entries': <Object?>[],
      });

      expect(
        () => repository.fetchProjectRollup('co-1', 'proj-1'),
        throwsA(isA<FormatException>()),
      );
    });
  });
}
