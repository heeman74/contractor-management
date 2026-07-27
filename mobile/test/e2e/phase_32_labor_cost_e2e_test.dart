// Phase 32 Plan 05 E2E: Mobile Labor Cost Breakdown
//
// Covers COST-06 on the field surface:
// 1. Breakdown render — category totals, backend-computed labor amount, and
//    grand total on the job Costs surface (D-11: amounts are backend strings
//    displayed verbatim, never recomputed locally).
// 2. D-05 unrated indicator — the hours-visible "{H} hrs unrated" chip, and
//    its absence when every hour is rated.
// 3. D-06 unburdened caption — the static wage-cost-only caption under the
//    labor row (mobile has no hover, so a caption, not a tooltip).
// 4. D-08 trade-scope note — "Tracked at job level" instead of a labor amount.
// 5. Offline state — "Breakdown unavailable offline" while the cached cost
//    list below still renders; never a fabricated $0.
// 6. Permission gating — no breakdown surface without finance.view.
// 7. Labor picker filter — the reserved Labor category never appears in the
//    add-cost sheet.
// 8. Pure formatting helpers — formatUnratedHours and orderedCategories.
//
// Strategy: real Drift in-memory DB (never mock what a real DB can cover),
// MockDioClient/MockDio for the HTTP layer, ProviderScope overrides for the
// finance repository, permissions, and Drift-backed streams (Stream.value to
// avoid pending-timer assertions). The suite runs fully offline.
library;

import 'package:contractorhub/core/database/app_database.dart';
import 'package:contractorhub/core/network/dio_client.dart';
import 'package:contractorhub/features/finance/data/cost_breakdown.dart';
import 'package:contractorhub/features/finance/data/finance_repository.dart';
import 'package:contractorhub/features/finance/presentation/providers/cost_providers.dart';
import 'package:contractorhub/features/finance/presentation/widgets/add_cost_sheet.dart';
import 'package:contractorhub/features/finance/presentation/widgets/cost_breakdown_summary.dart';
import 'package:contractorhub/features/finance/presentation/widgets/cost_list_section.dart';
import 'package:dio/dio.dart';
import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

class MockDioClient extends Mock implements DioClient {}

class MockDio extends Mock implements Dio {}

const _jobId = 'job-1';
const _scopeId = 'scope-1';
const _jobBreakdownPath = '/jobs/$_jobId/cost-breakdown';
const _scopeBreakdownPath = '/trade-scopes/$_scopeId/cost-breakdown';
const _unburdenedCaption =
    'Wage cost only — excludes payroll tax, insurance, overhead.';

const _stubCategories = [
  {'id': 'cat-materials', 'name': 'Materials'},
  {'id': 'cat-subcontractor', 'name': 'Subcontractor'},
  {'id': 'cat-other', 'name': 'Other'},
  {'id': 'cat-labor', 'name': 'Labor'},
];

Map<String, dynamic> _jobBreakdownJson({int unratedSeconds = 45000}) => {
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
        'unrated_seconds': unratedSeconds,
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

/// Mirrors the job-detail mount: finance.view gate, then the breakdown
/// summary directly above the cached CostListSection.
class _JobCostsSurface extends ConsumerWidget {
  const _JobCostsSurface();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final canView = ref.watch(financePermissionProvider).canView;
    final breakdownAsync = ref.watch(jobCostBreakdownProvider(_jobId));
    final costEntries = ref.watch(costEntriesForJobProvider(_jobId)).maybeWhen(
          data: (entries) => entries,
          orElse: () => const <CostEntry>[],
        );

    return Scaffold(
      body: !canView
          ? const SizedBox.shrink()
          : SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  CostBreakdownSummary(
                    breakdown: breakdownAsync.value,
                    variant: CostBreakdownVariant.job,
                    isLoading: breakdownAsync.isLoading,
                    isUnavailable: breakdownAsync.hasError,
                  ),
                  CostListSection(entries: costEntries, jobId: _jobId),
                ],
              ),
            ),
    );
  }
}

/// Mirrors the trade-scope mount: summary above the scope's cost list.
class _TradeScopeCostsSurface extends ConsumerWidget {
  const _TradeScopeCostsSurface();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final breakdownAsync = ref.watch(tradeScopeCostBreakdownProvider(_scopeId));

    return Scaffold(
      body: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            CostBreakdownSummary(
              breakdown: breakdownAsync.value,
              variant: CostBreakdownVariant.tradeScope,
              isLoading: breakdownAsync.isLoading,
              isUnavailable: breakdownAsync.hasError,
            ),
            const CostListSection(entries: [], tradeScopeId: _scopeId),
          ],
        ),
      ),
    );
  }
}

class _AddCostSheetLauncher extends StatelessWidget {
  const _AddCostSheetLauncher();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: ElevatedButton(
          onPressed: () => AddCostSheet.show(context, jobId: _jobId),
          child: const Text('Open add cost'),
        ),
      ),
    );
  }
}

void main() {
  late AppDatabase db;
  late MockDioClient mockDioClient;
  late MockDio mockDio;
  late FinanceRepository repository;

  setUp(() {
    db = AppDatabase(NativeDatabase.memory());
    mockDioClient = MockDioClient();
    mockDio = MockDio();
    when(() => mockDioClient.instance).thenReturn(mockDio);
    repository = FinanceRepository(
      dioClient: mockDioClient,
      costEntryDao: db.costEntryDao,
      costReceiptDao: db.costReceiptDao,
    );
  });

  tearDown(() async => await db.close());

  void stubBreakdownResponse(String path, Map<String, dynamic> data) {
    when(() => mockDio.get<dynamic>(path))
        .thenAnswer((_) async => Response<dynamic>(
              requestOptions: RequestOptions(path: path),
              statusCode: 200,
              data: data,
            ));
  }

  List<Override> surfaceOverrides({
    Set<String> permissions = const {'finance.view'},
    List<CostEntry> costEntries = const [],
  }) {
    return [
      myPermissionsProvider.overrideWith((ref) async => permissions),
      financeRepositoryProvider.overrideWithValue(repository),
      costEntriesForJobProvider.overrideWith(
        (ref, jobId) => Stream.value(costEntries),
      ),
      receiptsForCostEntryProvider.overrideWith(
        (ref, costEntryId) => Stream.value(const <CostReceipt>[]),
      ),
      costCategoriesProvider.overrideWith((ref) async => _stubCategories),
    ];
  }

  Future<void> pumpSurface(
    WidgetTester tester,
    Widget surface, {
    Set<String> permissions = const {'finance.view'},
    List<CostEntry> costEntries = const [],
  }) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: surfaceOverrides(
          permissions: permissions,
          costEntries: costEntries,
        ),
        child: MaterialApp(home: surface),
      ),
    );
    await tester.pump();
    await tester.pump();
  }

  group('COST-06 job breakdown', () {
    testWidgets('renders category totals, labor amount, and grand total',
        (tester) async {
      stubBreakdownResponse(_jobBreakdownPath, _jobBreakdownJson());

      await pumpSurface(tester, const _JobCostsSurface());

      expect(find.text('Labor'), findsOneWidget);
      expect(find.text(r'$240.00'), findsOneWidget);
      expect(find.text('Materials'), findsOneWidget);
      expect(find.text(r'$150.00'), findsOneWidget);
      expect(find.text('Total'), findsOneWidget);
      expect(find.text(r'$390.00'), findsOneWidget);
    });

    testWidgets('shows the hours-visible unrated chip', (tester) async {
      stubBreakdownResponse(_jobBreakdownPath, _jobBreakdownJson());

      await pumpSurface(tester, const _JobCostsSurface());

      expect(find.text('12.5 hrs unrated'), findsOneWidget);
    });

    testWidgets('shows the unburdened caption under the labor row',
        (tester) async {
      stubBreakdownResponse(_jobBreakdownPath, _jobBreakdownJson());

      await pumpSurface(tester, const _JobCostsSurface());

      expect(find.text(_unburdenedCaption), findsOneWidget);
    });

    testWidgets('omits the unrated chip when every hour is rated',
        (tester) async {
      stubBreakdownResponse(
        _jobBreakdownPath,
        _jobBreakdownJson(unratedSeconds: 0),
      );

      await pumpSurface(tester, const _JobCostsSurface());

      expect(find.text(r'$240.00'), findsOneWidget);
      expect(find.textContaining('unrated'), findsNothing);
    });
  });

  group('COST-06 trade-scope breakdown', () {
    testWidgets('shows Tracked at job level instead of a labor amount',
        (tester) async {
      stubBreakdownResponse(_scopeBreakdownPath, _tradeScopeBreakdownJson());

      await pumpSurface(tester, const _TradeScopeCostsSurface());

      expect(find.text('Tracked at job level'), findsOneWidget);
      expect(find.text(_unburdenedCaption), findsNothing);
      // Categories-only scope: the materials row and the grand total both
      // show the same backend string.
      expect(find.text(r'$150.00'), findsNWidgets(2));
    });
  });

  group('offline and gating', () {
    testWidgets(
        'shows the offline note and still renders cached costs when the '
        'fetch fails', (tester) async {
      when(() => mockDio.get<dynamic>(_jobBreakdownPath)).thenThrow(
        DioException(
          requestOptions: RequestOptions(path: _jobBreakdownPath),
          type: DioExceptionType.connectionError,
        ),
      );

      final cachedEntries = await tester.runAsync(() async {
        await db.companyDao.insertCompany(CompaniesCompanion.insert(
          id: const Value('co-1'),
          name: 'Company co-1',
          version: const Value(1),
          createdAt: DateTime.now(),
          updatedAt: DateTime.now(),
        ));
        await db.costEntryDao.insertCostEntry(
          companyId: 'co-1',
          jobId: _jobId,
          categoryId: 'cat-materials',
          amount: 125.50,
          incurredDate: '2026-07-25',
          vendor: 'ACME Supply',
        );
        return db.costEntryDao.watchByJob(_jobId).first;
      });

      await pumpSurface(
        tester,
        const _JobCostsSurface(),
        costEntries: cachedEntries!,
      );

      expect(find.text('Breakdown unavailable offline'), findsOneWidget);
      expect(find.text(r'$125.50'), findsOneWidget);
      expect(find.textContaining(r'$0.00'), findsNothing);
    });

    testWidgets('hides the whole Costs surface without finance.view',
        (tester) async {
      stubBreakdownResponse(_jobBreakdownPath, _jobBreakdownJson());

      await pumpSurface(
        tester,
        const _JobCostsSurface(),
        permissions: const {},
      );

      expect(find.byType(CostBreakdownSummary), findsNothing);
      expect(find.byType(CostListSection), findsNothing);
    });
  });

  group('labor category is not manually selectable', () {
    testWidgets('add-cost sheet omits the Labor option', (tester) async {
      await pumpSurface(tester, const _AddCostSheetLauncher());

      await tester.tap(find.text('Open add cost'));
      await tester.pumpAndSettle();

      await tester.tap(find.byType(DropdownButtonFormField<String>));
      await tester.pumpAndSettle();

      expect(find.text('Materials'), findsOneWidget);
      expect(find.text('Subcontractor'), findsOneWidget);
      expect(find.text('Other'), findsOneWidget);
      expect(find.text('Labor'), findsNothing);
    });
  });

  group('pure helpers', () {
    test('formatUnratedHours keeps hours visible and drops trailing .0', () {
      expect(formatUnratedHours(0), '');
      expect(formatUnratedHours(3600), '1 hr unrated');
      expect(formatUnratedHours(5400), '1.5 hrs unrated');
      expect(formatUnratedHours(7200), '2 hrs unrated');
      expect(formatUnratedHours(45000), '12.5 hrs unrated');
    });

    test('orderedCategories drops labor and orders fixed-then-custom', () {
      const categories = [
        CategoryTotal(
            categoryId: 'c-paint', categoryName: 'paint', total: '5.00'),
        CategoryTotal(
            categoryId: 'c-other', categoryName: 'other', total: '10.00'),
        CategoryTotal(
            categoryId: 'c-labor', categoryName: 'labor', total: '99.00'),
        CategoryTotal(
            categoryId: 'c-sub',
            categoryName: 'subcontractor',
            total: '20.00'),
        CategoryTotal(
            categoryId: 'c-mat', categoryName: 'materials', total: '30.00'),
        CategoryTotal(
            categoryId: 'c-equip',
            categoryName: 'equipment',
            total: '40.00'),
      ];

      final ordered = orderedCategories(categories);

      expect(
        ordered.map((category) => category.categoryName).toList(),
        ['materials', 'subcontractor', 'other', 'equipment', 'paint'],
      );
    });
  });
}
