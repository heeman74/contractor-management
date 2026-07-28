// Phase 34 Plan 05: tolerant BudgetVsActual parsing on CostBreakdown.
//
// The budget block is additive on the Phase 32 breakdown/rollup responses —
// an older backend that omits it, or a malformed block, must degrade to a
// null budget (no rows rendered), never a FormatException that hides the
// whole breakdown. Fixtures mirror the locked wire contract: budget_id UUID,
// total/spent/remaining/percent_used all Decimal-as-String.

import 'package:contractorhub/features/finance/data/cost_breakdown.dart';
import 'package:contractorhub/features/finance/presentation/widgets/finance_formatters.dart';
import 'package:flutter_test/flutter_test.dart';

Map<String, dynamic> _validBudgetJson() => {
      'budget_id': 'budget-uuid-1',
      'total': '10000.00',
      'spent': '8200.00',
      'remaining': '1800.00',
      'percent_used': '82.0',
    };

Map<String, dynamic> _breakdownJson({Object? budget, bool includeBudgetKey = false}) => {
      'categories': [
        {
          'category_id': 'cat-materials',
          'category_name': 'materials',
          'total': '150.00',
        },
      ],
      'labor': null,
      'labor_tracked_at_job_level': false,
      'grand_total': '150.00',
      if (includeBudgetKey) 'budget': budget,
    };

void main() {
  group('BudgetVsActual.tryFromJson', () {
    test('returns null for null input', () {
      expect(BudgetVsActual.tryFromJson(null), isNull);
    });

    test('returns null for non-map input', () {
      expect(BudgetVsActual.tryFromJson('budget'), isNull);
      expect(BudgetVsActual.tryFromJson(['budget']), isNull);
      expect(BudgetVsActual.tryFromJson(42), isNull);
    });

    test('returns null when any required field is missing', () {
      for (final field in [
        'budget_id',
        'total',
        'spent',
        'remaining',
        'percent_used',
      ]) {
        final json = _validBudgetJson()..remove(field);

        expect(BudgetVsActual.tryFromJson(json), isNull,
            reason: 'missing $field should yield null');
      }
    });

    test('returns null when a field has the wrong type', () {
      final json = _validBudgetJson()..['total'] = 10000;

      expect(BudgetVsActual.tryFromJson(json), isNull);
    });

    test('parses the full block keeping every value as the backend String',
        () {
      final budget = BudgetVsActual.tryFromJson(_validBudgetJson());

      expect(budget, isNotNull);
      expect(budget!.budgetId, 'budget-uuid-1');
      expect(budget.total, '10000.00');
      expect(budget.spent, '8200.00');
      expect(budget.remaining, '1800.00');
      expect(budget.percentUsed, '82.0');
    });
  });

  group('CostBreakdown budget', () {
    test('parses a response without a budget key to a null budget', () {
      final breakdown = CostBreakdown.fromJson(_breakdownJson());

      expect(breakdown.budget, isNull);
      expect(breakdown.grandTotal, '150.00');
      expect(breakdown.categories, hasLength(1));
    });

    test('exposes the budget block when present', () {
      final breakdown = CostBreakdown.fromJson(
        _breakdownJson(budget: _validBudgetJson(), includeBudgetKey: true),
      );

      expect(breakdown.budget, isNotNull);
      expect(breakdown.budget!.percentUsed, '82.0');
    });

    test('parses a malformed budget to null without breaking the breakdown',
        () {
      final breakdown = CostBreakdown.fromJson(
        _breakdownJson(budget: 'nope', includeBudgetKey: true),
      );

      expect(breakdown.budget, isNull);
      expect(breakdown.grandTotal, '150.00');
    });

    test('parses an explicit null budget key to a null budget', () {
      final breakdown = CostBreakdown.fromJson(
        _breakdownJson(includeBudgetKey: true),
      );

      expect(breakdown.budget, isNull);
    });

    test('carries the budget through the lenient rollup tryFromJson', () {
      final breakdown = CostBreakdown.tryFromJson(
        _breakdownJson(budget: _validBudgetJson(), includeBudgetKey: true),
      );

      expect(breakdown, isNotNull);
      expect(breakdown!.budget, isNotNull);
      expect(breakdown.budget!.spent, '8200.00');
    });
  });

  group('formatPercentUsed', () {
    test('drops a trailing .0', () {
      expect(formatPercentUsed('82.0'), '82');
    });

    test('keeps a meaningful decimal', () {
      expect(formatPercentUsed('82.5'), '82.5');
    });

    test('drops the trailing .0 over 100 percent', () {
      expect(formatPercentUsed('112.0'), '112');
    });
  });
}
