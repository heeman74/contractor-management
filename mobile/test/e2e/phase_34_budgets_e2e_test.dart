// Phase 34 Plan 05 E2E: Mobile Budget vs Actual Section
//
// Covers BUDG-02's mobile half on the 34-UI-SPEC state matrix — view-only
// (D-13), online-fetched, never persisted to Drift:
// 1.  State 1/9: budget absent — no rows, no extra divider (additive
//     contract: an older backend renders exactly what it renders today).
// 2.  State 3: under 80% — plain triad, Spent shows "· {percent}%", no chip.
// 3.  State 4: warning band — amber "Nearing budget" chip on the Remaining
//     row, no error color (amber and red never co-render).
// 4.  State 6: over budget — negative Remaining numerals in
//     colorScheme.error, NO chip, >100% percent renders normally.
// 5.  State 5: exactly at budget — "$0.00" plain, no chip (the figure is
//     the signal).
// 6.  State 10: job variant never renders a budget group, even with data.
// 7.  Typography: Remaining is the punchline (titleMedium w700); Budget and
//     Spent match the shipped amount style (titleSmall w600).
//
// Widget-level half pumps CostBreakdownSummary directly; the network-driven
// half (mocked Dio → FinanceRepository → provider → widget) follows the
// phase-33 harness.
library;

import 'package:contractorhub/features/finance/data/cost_breakdown.dart';
import 'package:contractorhub/features/finance/presentation/widgets/cost_breakdown_summary.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

const _nearingBudgetChip = 'Nearing budget';

BudgetVsActual _budget({
  String total = '10000.00',
  String spent = '4200.00',
  String remaining = '5800.00',
  String percentUsed = '42.0',
}) =>
    BudgetVsActual(
      budgetId: 'budget-1',
      total: total,
      spent: spent,
      remaining: remaining,
      percentUsed: percentUsed,
    );

CostBreakdown _tradeScopeBreakdown({BudgetVsActual? budget}) => CostBreakdown(
      categories: const [
        CategoryTotal(
          categoryId: 'cat-materials',
          categoryName: 'materials',
          total: '150.00',
        ),
      ],
      labor: null,
      laborTrackedAtJobLevel: true,
      grandTotal: '150.00',
      budget: budget,
    );

Future<void> _pumpSummary(
  WidgetTester tester, {
  required CostBreakdown breakdown,
  CostBreakdownVariant variant = CostBreakdownVariant.tradeScope,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: SingleChildScrollView(
          child: CostBreakdownSummary(breakdown: breakdown, variant: variant),
        ),
      ),
    ),
  );
}

void main() {
  group('BUDG-02 budget section widget states', () {
    testWidgets('states 1/9: null budget renders no rows and no extra divider',
        (tester) async {
      await _pumpSummary(tester, breakdown: _tradeScopeBreakdown());

      expect(find.text('Budget'), findsNothing);
      expect(find.text('Spent'), findsNothing);
      expect(find.text('Remaining'), findsNothing);
      // Only the shipped pre-Total divider — the budget section adds none.
      expect(find.byType(Divider), findsOneWidget);
    });

    testWidgets('state 3: under 80% renders the plain triad without a chip',
        (tester) async {
      await _pumpSummary(
        tester,
        breakdown: _tradeScopeBreakdown(budget: _budget()),
      );

      expect(find.text('Budget'), findsOneWidget);
      expect(find.text('Spent'), findsOneWidget);
      expect(find.text('Remaining'), findsOneWidget);
      expect(find.text(r'$10000.00'), findsOneWidget);
      expect(find.text(r'$4200.00 · 42%'), findsOneWidget);
      expect(find.text(r'$5800.00'), findsOneWidget);
      expect(find.text(_nearingBudgetChip), findsNothing);
    });

    testWidgets(
        'state 4: 82% renders the Nearing budget chip and no error color',
        (tester) async {
      await _pumpSummary(
        tester,
        breakdown: _tradeScopeBreakdown(
          budget: _budget(
            spent: '8200.00',
            remaining: '1800.00',
            percentUsed: '82.0',
          ),
        ),
      );

      expect(find.text(_nearingBudgetChip), findsOneWidget);
      expect(find.text(r'$8200.00 · 82%'), findsOneWidget);
      final remainingFinder = find.text(r'$1800.00');
      expect(remainingFinder, findsOneWidget);
      final remaining = tester.widget<Text>(remainingFinder);
      final theme = Theme.of(tester.element(remainingFinder));
      expect(remaining.style?.color, isNot(theme.colorScheme.error));
    });

    testWidgets(
        'state 6: over budget renders red negative numerals and NO chip',
        (tester) async {
      await _pumpSummary(
        tester,
        breakdown: _tradeScopeBreakdown(
          budget: _budget(
            spent: '11200.00',
            remaining: '-1200.00',
            percentUsed: '112.0',
          ),
        ),
      );

      expect(find.text(_nearingBudgetChip), findsNothing);
      expect(find.text(r'$11200.00 · 112%'), findsOneWidget);
      final remainingFinder = find.text(r'-$1200.00');
      expect(remainingFinder, findsOneWidget);
      final remaining = tester.widget<Text>(remainingFinder);
      final theme = Theme.of(tester.element(remainingFinder));
      expect(remaining.style?.color, theme.colorScheme.error);
    });

    testWidgets('state 5: exactly at budget renders \$0.00 plain, no chip',
        (tester) async {
      await _pumpSummary(
        tester,
        breakdown: _tradeScopeBreakdown(
          budget: _budget(
            spent: '10000.00',
            remaining: '0.00',
            percentUsed: '100.0',
          ),
        ),
      );

      expect(find.text(_nearingBudgetChip), findsNothing);
      expect(find.text(r'$10000.00 · 100%'), findsOneWidget);
      final remainingFinder = find.text(r'$0.00');
      expect(remainingFinder, findsOneWidget);
      final remaining = tester.widget<Text>(remainingFinder);
      final theme = Theme.of(tester.element(remainingFinder));
      expect(remaining.style?.color, isNot(theme.colorScheme.error));
    });

    testWidgets('state 10: job variant never renders budget rows',
        (tester) async {
      await _pumpSummary(
        tester,
        breakdown: _tradeScopeBreakdown(budget: _budget()),
        variant: CostBreakdownVariant.job,
      );

      expect(find.text('Budget'), findsNothing);
      expect(find.text('Spent'), findsNothing);
      expect(find.text('Remaining'), findsNothing);
    });

    testWidgets('typography: Remaining is the w700 punchline, Budget and '
        'Spent stay w600 amounts', (tester) async {
      await _pumpSummary(
        tester,
        breakdown: _tradeScopeBreakdown(budget: _budget()),
      );

      final theme = Theme.of(tester.element(find.text('Budget')));
      final budgetAmount = tester.widget<Text>(find.text(r'$10000.00'));
      expect(budgetAmount.style?.fontWeight, FontWeight.w600);
      expect(budgetAmount.style?.fontSize, theme.textTheme.titleSmall?.fontSize);
      final spentFigure = tester.widget<Text>(find.text(r'$4200.00 · 42%'));
      expect(spentFigure.style?.fontWeight, FontWeight.w600);
      final remainingFigure = tester.widget<Text>(find.text(r'$5800.00'));
      expect(remainingFigure.style?.fontWeight, FontWeight.w700);
      expect(
        remainingFigure.style?.fontSize,
        theme.textTheme.titleMedium?.fontSize,
      );
    });
  });
}
