// Phase 33 Plan 05: tolerant MarginSummary parsing on CostBreakdown.
//
// The margin block is additive on the Phase 32 breakdown responses — an
// older backend that omits it, or a malformed block, must degrade to a null
// margin (no rows rendered), never a FormatException that hides the whole
// breakdown. Fixtures mirror the locked wire contract:
// revenue_basis in {invoiced, quoted, mixed, none},
// incomplete_reasons subset of {unrated_labor, no_cost_data},
// Decimal-as-String money fields.

import 'package:contractorhub/features/finance/data/cost_breakdown.dart';
import 'package:flutter_test/flutter_test.dart';

Map<String, dynamic> _validMarginJson() => {
      'revenue': '20000.00',
      'revenue_basis': 'invoiced',
      'margin': '4200.00',
      'margin_percent': '21.0',
      'incomplete': true,
      'incomplete_reasons': ['no_cost_data'],
    };

Map<String, dynamic> _breakdownJson({Object? margin}) => {
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
      if (margin != null) 'margin': margin,
    };

void main() {
  group('MarginSummary.tryFromJson', () {
    test('parses a full valid map into all six fields', () {
      final summary = MarginSummary.tryFromJson(_validMarginJson());

      expect(summary, isNotNull);
      expect(summary!.revenue, '20000.00');
      expect(summary.revenueBasis, 'invoiced');
      expect(summary.margin, '4200.00');
      expect(summary.marginPercent, '21.0');
      expect(summary.incomplete, isTrue);
      expect(summary.incompleteReasons, ['no_cost_data']);
    });

    test('returns null for null input', () {
      expect(MarginSummary.tryFromJson(null), isNull);
    });

    test('returns null for non-map input', () {
      expect(MarginSummary.tryFromJson('margin'), isNull);
      expect(MarginSummary.tryFromJson(['margin']), isNull);
    });

    test('returns null when revenue_basis is missing', () {
      final json = _validMarginJson()..remove('revenue_basis');

      expect(MarginSummary.tryFromJson(json), isNull);
    });

    test('parses all-null money fields with basis none', () {
      final summary = MarginSummary.tryFromJson({
        'revenue': null,
        'revenue_basis': 'none',
        'margin': null,
        'margin_percent': null,
        'incomplete': false,
        'incomplete_reasons': <String>[],
      });

      expect(summary, isNotNull);
      expect(summary!.revenue, isNull);
      expect(summary.margin, isNull);
      expect(summary.marginPercent, isNull);
      expect(summary.revenueBasis, 'none');
      expect(summary.incomplete, isFalse);
    });

    test('parses a numeric revenue as null while the rest survives', () {
      final json = _validMarginJson()..['revenue'] = 20000;

      final summary = MarginSummary.tryFromJson(json);

      expect(summary, isNotNull);
      expect(summary!.revenue, isNull);
      expect(summary.margin, '4200.00');
      expect(summary.revenueBasis, 'invoiced');
    });

    test('treats a non-list incomplete_reasons as empty without throwing', () {
      final json = _validMarginJson()..['incomplete_reasons'] = 'no_cost_data';

      final summary = MarginSummary.tryFromJson(json);

      expect(summary, isNotNull);
      expect(summary!.incompleteReasons, isEmpty);
    });

    test('treats a non-bool incomplete as false', () {
      final json = _validMarginJson()..['incomplete'] = 'yes';

      final summary = MarginSummary.tryFromJson(json);

      expect(summary, isNotNull);
      expect(summary!.incomplete, isFalse);
    });
  });

  group('CostBreakdown.fromJson margin', () {
    test('carries a valid margin block through', () {
      final breakdown = CostBreakdown.fromJson(
        _breakdownJson(margin: _validMarginJson()),
      );

      expect(breakdown.margin, isNotNull);
      expect(breakdown.margin!.revenueBasis, 'invoiced');
    });

    test('parses a response without a margin key to a null margin', () {
      final breakdown = CostBreakdown.fromJson(_breakdownJson());

      expect(breakdown.margin, isNull);
      expect(breakdown.grandTotal, '150.00');
    });

    test('parses a malformed margin to null without breaking the breakdown',
        () {
      final breakdown = CostBreakdown.fromJson(_breakdownJson(margin: 'nope'));

      expect(breakdown.margin, isNull);
      expect(breakdown.categories, hasLength(1));
      expect(breakdown.grandTotal, '150.00');
    });

    test('carries the margin through the lenient rollup tryFromJson', () {
      final breakdown = CostBreakdown.tryFromJson(
        _breakdownJson(margin: _validMarginJson()),
      );

      expect(breakdown, isNotNull);
      expect(breakdown!.margin, isNotNull);
      expect(breakdown.margin!.margin, '4200.00');
    });
  });
}
