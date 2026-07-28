// Phase 33 Plan 05 E2E: Mobile Margin Section
//
// Covers MARG-01/02/03 on the field surfaces — the 33-UI-SPEC state matrix
// proven on device widgets:
// 1.  State 1 invoiced margin — Revenue + Margin rows, no caption, no chip
//     (D-04: invoice-backed margin is unlabeled).
// 2.  State 2 quoted basis — "Based on approved quote — not yet invoiced."
// 3.  State 3 mixed basis — project-variant caption for part-quoted revenue.
// 4.  State 4 flagged margin (keystone) — the amber "Incomplete cost data"
//     chip and its caption render WITH the figure on an empty breakdown
//     (D-06: partial number + flag, never suppressed).
// 5.  State 5 negative margin — signed figure in colorScheme.error, numerals
//     only.
// 6.  State 6 percent absent — dollars alone, no separator (D-06: percent
//     honestly absent at zero revenue).
// 7.  State 7 no revenue — the neutral note replaces both rows (D-07).
// 8.  State 10 margin absent — old-backend response renders no margin rows.
// 9.  Trade-scope variant — margin rows alongside "Tracked at job level".
// 10. Pure helpers — formatMarginPercent/Dollars/Figure.
// 11. Gating — no margin strings without finance.view (D-10 boundary).
//
// Strategy mirrors the phase-32 harness: MockDioClient/MockDio at the HTTP
// layer, ProviderScope overrides for repository and permissions, no real
// network, nothing persisted to Drift (D-10 — margin rides the existing
// online breakdown fetches).
library;

import 'package:contractorhub/core/database/app_database.dart';
import 'package:contractorhub/core/network/dio_client.dart';
import 'package:contractorhub/features/finance/data/cost_breakdown.dart';
import 'package:contractorhub/features/finance/data/finance_repository.dart';
import 'package:contractorhub/features/finance/presentation/providers/cost_providers.dart';
import 'package:contractorhub/features/finance/presentation/widgets/cost_breakdown_summary.dart';
import 'package:contractorhub/features/finance/presentation/widgets/margin_summary_section.dart';
import 'package:dio/dio.dart';
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
const _projectId = 'project-1';
const _jobBreakdownPath = '/jobs/$_jobId/cost-breakdown';
const _scopeBreakdownPath = '/trade-scopes/$_scopeId/cost-breakdown';
const _quotedCaption = 'Based on approved quote — not yet invoiced.';
const _mixedCaption = 'Includes approved quote amounts not yet invoiced.';
const _incompleteChip = 'Incomplete cost data';
const _incompleteCaption =
    'Margin may overstate profit — some costs are missing or unrated.';
const _noRevenueNote =
    'No revenue recorded — margin will appear once an invoice or approved quote exists.';

Map<String, dynamic> _marginJson({
  String? revenue = '20000.00',
  String basis = 'invoiced',
  String? margin = '4200.00',
  String? percent = '21.0',
  bool incomplete = false,
  List<String> reasons = const [],
}) =>
    {
      'revenue': revenue,
      'revenue_basis': basis,
      'margin': margin,
      'margin_percent': percent,
      'incomplete': incomplete,
      'incomplete_reasons': reasons,
    };

Map<String, dynamic> _breakdownJson({
  Map<String, dynamic>? margin,
  bool empty = false,
}) =>
    {
      'categories': empty
          ? <Map<String, dynamic>>[]
          : [
              {
                'category_id': 'cat-materials',
                'category_name': 'materials',
                'total': '150.00',
              },
            ],
      'labor': {
        'total': empty ? '0.00' : '240.00',
        'rated_seconds': empty ? 0 : 28800,
        'unrated_seconds': 0,
        'basis': 'unburdened',
      },
      'labor_tracked_at_job_level': false,
      'grand_total': empty ? '0.00' : '390.00',
      if (margin != null) 'margin': margin,
    };

Map<String, dynamic> _tradeScopeBreakdownJson({Map<String, dynamic>? margin}) =>
    {
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
      if (margin != null) 'margin': margin,
    };

/// Mirrors the job-detail mount: finance.view gate, then the breakdown
/// summary fed by the online-only job breakdown provider.
class _JobCostsSurface extends ConsumerWidget {
  const _JobCostsSurface();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final canView = ref.watch(financePermissionProvider).canView;
    final breakdownAsync = ref.watch(jobCostBreakdownProvider(_jobId));

    return Scaffold(
      body: !canView
          ? const SizedBox.shrink()
          : SingleChildScrollView(
              child: CostBreakdownSummary(
                breakdown: breakdownAsync.value,
                variant: CostBreakdownVariant.job,
                isLoading: breakdownAsync.isLoading,
                isUnavailable: breakdownAsync.hasError,
              ),
            ),
    );
  }
}

/// Mirrors the trade-scope mount.
class _TradeScopeCostsSurface extends ConsumerWidget {
  const _TradeScopeCostsSurface();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final breakdownAsync = ref.watch(tradeScopeCostBreakdownProvider(_scopeId));

    return Scaffold(
      body: SingleChildScrollView(
        child: CostBreakdownSummary(
          breakdown: breakdownAsync.value,
          variant: CostBreakdownVariant.tradeScope,
          isLoading: breakdownAsync.isLoading,
          isUnavailable: breakdownAsync.hasError,
        ),
      ),
    );
  }
}

/// Mirrors the project-detail rollup mount.
class _ProjectCostsSurface extends ConsumerWidget {
  const _ProjectCostsSurface();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final breakdownAsync = ref.watch(projectCostBreakdownProvider(_projectId));

    return Scaffold(
      body: SingleChildScrollView(
        child: CostBreakdownSummary(
          breakdown: breakdownAsync.value,
          variant: CostBreakdownVariant.project,
          isLoading: breakdownAsync.isLoading,
          isUnavailable: breakdownAsync.hasError,
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

  Future<void> pumpSurface(
    WidgetTester tester,
    Widget surface, {
    Set<String> permissions = const {'finance.view'},
    List<Override> extraOverrides = const [],
  }) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          myPermissionsProvider.overrideWith((ref) async => permissions),
          financeRepositoryProvider.overrideWithValue(repository),
          ...extraOverrides,
        ],
        child: MaterialApp(home: surface),
      ),
    );
    await tester.pump();
    await tester.pump();
  }

  group('MARG-01 job margin states', () {
    testWidgets('state 1: invoiced margin renders rows without caption or chip',
        (tester) async {
      stubBreakdownResponse(
        _jobBreakdownPath,
        _breakdownJson(margin: _marginJson()),
      );

      await pumpSurface(tester, const _JobCostsSurface());

      expect(find.text('Revenue'), findsOneWidget);
      expect(find.text('Margin'), findsOneWidget);
      expect(find.text(r'$20000.00'), findsOneWidget);
      expect(find.text(r'$4200.00 · 21%'), findsOneWidget);
      expect(find.text(_quotedCaption), findsNothing);
      expect(find.text(_incompleteChip), findsNothing);
    });

    testWidgets('state 2: quoted basis carries the approved-quote caption',
        (tester) async {
      stubBreakdownResponse(
        _jobBreakdownPath,
        _breakdownJson(margin: _marginJson(basis: 'quoted')),
      );

      await pumpSurface(tester, const _JobCostsSurface());

      expect(find.text(_quotedCaption), findsOneWidget);
    });

    testWidgets(
        'state 4 keystone: flagged margin on an empty breakdown shows chip, '
        'caption, AND the figure', (tester) async {
      stubBreakdownResponse(
        _jobBreakdownPath,
        _breakdownJson(
          empty: true,
          margin: _marginJson(
            margin: '2000.00',
            percent: '100.0',
            incomplete: true,
            reasons: ['no_cost_data'],
          ),
        ),
      );

      await pumpSurface(tester, const _JobCostsSurface());

      expect(find.text(_incompleteChip), findsOneWidget);
      expect(find.text(_incompleteCaption), findsOneWidget);
      expect(find.text(r'$2000.00 · 100%'), findsOneWidget);
    });

    testWidgets('state 5: negative margin renders numerals in the error color',
        (tester) async {
      stubBreakdownResponse(
        _jobBreakdownPath,
        _breakdownJson(margin: _marginJson(margin: '-350.00', percent: '-8.3')),
      );

      await pumpSurface(tester, const _JobCostsSurface());

      final figureFinder = find.text(r'-$350.00 · -8.3%');
      expect(figureFinder, findsOneWidget);
      final figure = tester.widget<Text>(figureFinder);
      final theme = Theme.of(tester.element(figureFinder));
      expect(figure.style?.color, theme.colorScheme.error);
    });

    testWidgets('state 6: absent percent renders dollars alone',
        (tester) async {
      stubBreakdownResponse(
        _jobBreakdownPath,
        _breakdownJson(margin: _marginJson(percent: null)),
      );

      await pumpSurface(tester, const _JobCostsSurface());

      expect(find.text(r'$4200.00'), findsOneWidget);
      expect(find.textContaining('·'), findsNothing);
    });

    testWidgets('state 7: no revenue renders the neutral note, no rows',
        (tester) async {
      stubBreakdownResponse(
        _jobBreakdownPath,
        _breakdownJson(
          margin: _marginJson(
            revenue: null,
            basis: 'none',
            margin: null,
            percent: null,
          ),
        ),
      );

      await pumpSurface(tester, const _JobCostsSurface());

      expect(find.text(_noRevenueNote), findsOneWidget);
      expect(find.text('Revenue'), findsNothing);
      expect(find.text('Margin'), findsNothing);
    });

    testWidgets('state 10: a response without a margin block renders no '
        'margin rows', (tester) async {
      stubBreakdownResponse(_jobBreakdownPath, _breakdownJson());

      await pumpSurface(tester, const _JobCostsSurface());

      expect(find.text('Total'), findsOneWidget);
      expect(find.text(r'$390.00'), findsOneWidget);
      expect(find.text('Revenue'), findsNothing);
      expect(find.text('Margin'), findsNothing);
      expect(find.text(_noRevenueNote), findsNothing);
    });
  });

  group('MARG-02 project rollup margin', () {
    testWidgets('state 3: mixed basis carries the part-quoted caption',
        (tester) async {
      // The real provider path requires an authenticated session
      // (_projectRollupFetchProvider reads authNotifierProvider), so the
      // project surface overrides its breakdown provider with the same
      // fixture parsed through CostBreakdown.fromJson — the parser path is
      // covered by the unit suite and the job-surface tests above.
      final breakdown = CostBreakdown.fromJson(
        _breakdownJson(margin: _marginJson(basis: 'mixed')),
      );

      await pumpSurface(
        tester,
        const _ProjectCostsSurface(),
        extraOverrides: [
          projectCostBreakdownProvider.overrideWith(
            (ref, projectId) async => breakdown,
          ),
        ],
      );

      expect(find.text(_mixedCaption), findsOneWidget);
      expect(find.text('Revenue'), findsOneWidget);
      expect(find.text('Margin'), findsOneWidget);
    });
  });

  group('MARG-02 trade-scope margin', () {
    testWidgets('margin rows render alongside the job-level labor note',
        (tester) async {
      stubBreakdownResponse(
        _scopeBreakdownPath,
        _tradeScopeBreakdownJson(margin: _marginJson()),
      );

      await pumpSurface(tester, const _TradeScopeCostsSurface());

      expect(find.text('Tracked at job level'), findsOneWidget);
      expect(find.text('Revenue'), findsOneWidget);
      expect(find.text('Margin'), findsOneWidget);
      expect(find.text(r'$4200.00 · 21%'), findsOneWidget);
    });
  });

  group('pure helpers', () {
    test('formatMarginPercent drops only a trailing .0', () {
      expect(formatMarginPercent('21.0'), '21');
      expect(formatMarginPercent('8.3'), '8.3');
      expect(formatMarginPercent('100.0'), '100');
      expect(formatMarginPercent('-8.3'), '-8.3');
    });

    test('formatMarginDollars keeps the sign ahead of the symbol', () {
      expect(formatMarginDollars('-350.00'), r'-$350.00');
      expect(formatMarginDollars('4200.00'), r'$4200.00');
    });

    test('formatMarginFigure renders dollars alone when percent is null', () {
      expect(formatMarginFigure('4200.00', null), r'$4200.00');
      expect(formatMarginFigure('4200.00', '21.0'), r'$4200.00 · 21%');
    });
  });

  group('gating', () {
    testWidgets('renders no margin strings without finance.view',
        (tester) async {
      stubBreakdownResponse(
        _jobBreakdownPath,
        _breakdownJson(margin: _marginJson()),
      );

      await pumpSurface(
        tester,
        const _JobCostsSurface(),
        permissions: const {},
      );

      expect(find.byType(CostBreakdownSummary), findsNothing);
      expect(find.text('Revenue'), findsNothing);
      expect(find.text('Margin'), findsNothing);
    });
  });
}
