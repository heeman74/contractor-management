/// One cost category's summed amount. Amounts stay backend Decimal-as-String —
/// mobile displays them verbatim and never re-sums with double.
class CategoryTotal {
  const CategoryTotal({
    required this.categoryId,
    required this.categoryName,
    required this.total,
  });

  final String categoryId;
  final String categoryName;
  final String total;

  /// Returns null on a malformed row so one bad category never crashes the
  /// whole breakdown parse.
  static CategoryTotal? tryFromJson(Object? json) {
    if (json is! Map<String, dynamic>) return null;
    final categoryId = json['category_id'];
    final categoryName = json['category_name'];
    final total = json['total'];
    if (categoryId is! String || categoryName is! String || total is! String) {
      return null;
    }
    return CategoryTotal(
      categoryId: categoryId,
      categoryName: categoryName,
      total: total,
    );
  }
}

/// Derived labor cost. [unratedSeconds] is the honesty contract — tracked time
/// with no rate effective on the work day is reported, never silently valued
/// at $0. [basis] is "unburdened" in v4.0: wage cost only.
class LaborCostSummary {
  const LaborCostSummary({
    required this.total,
    required this.ratedSeconds,
    required this.unratedSeconds,
    required this.basis,
  });

  final String total;
  final int ratedSeconds;
  final int unratedSeconds;
  final String basis;

  /// Returns null when the labor block is absent or malformed.
  static LaborCostSummary? tryFromJson(Object? json) {
    if (json is! Map<String, dynamic>) return null;
    final total = json['total'];
    final ratedSeconds = json['rated_seconds'];
    final unratedSeconds = json['unrated_seconds'];
    final basis = json['basis'];
    if (total is! String ||
        ratedSeconds is! int ||
        unratedSeconds is! int ||
        basis is! String) {
      return null;
    }
    return LaborCostSummary(
      total: total,
      ratedSeconds: ratedSeconds,
      unratedSeconds: unratedSeconds,
      basis: basis,
    );
  }
}

/// Itemized category totals plus derived labor for one job, trade scope, or
/// project. [labor] is null on trade scopes, where [laborTrackedAtJobLevel]
/// is true instead — time tracking is job-anchored in v4.0, so a scope has
/// no labor figure.
class CostBreakdown {
  const CostBreakdown({
    required this.categories,
    required this.labor,
    required this.laborTrackedAtJobLevel,
    required this.grandTotal,
  });

  final List<CategoryTotal> categories;
  final LaborCostSummary? labor;
  final bool laborTrackedAtJobLevel;
  final String grandTotal;

  factory CostBreakdown.fromJson(Map<String, dynamic> json) {
    final categories = json['categories'];
    if (categories is! List) {
      throw const FormatException(
        'Missing "categories" list in cost breakdown response',
      );
    }
    final grandTotal = json['grand_total'];
    if (grandTotal is! String) {
      throw const FormatException(
        'Missing "grand_total" string in cost breakdown response',
      );
    }
    final laborTrackedAtJobLevel = json['labor_tracked_at_job_level'];
    return CostBreakdown(
      categories: categories
          .map(CategoryTotal.tryFromJson)
          .whereType<CategoryTotal>()
          .toList(),
      labor: LaborCostSummary.tryFromJson(json['labor']),
      laborTrackedAtJobLevel:
          laborTrackedAtJobLevel is bool && laborTrackedAtJobLevel,
      grandTotal: grandTotal,
    );
  }

  /// Lenient variant for the project rollup, whose breakdown fields are
  /// optional so the app keeps working against a backend that predates
  /// Phase 32. Returns null instead of throwing when the fields are absent.
  static CostBreakdown? tryFromJson(Map<String, dynamic> json) {
    if (json['grand_total'] is! String || json['categories'] is! List) {
      return null;
    }
    return CostBreakdown.fromJson(json);
  }
}
