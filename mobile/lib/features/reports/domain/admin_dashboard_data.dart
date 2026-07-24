/// Typed view of the raw `/reports/dashboard` JSON.
///
/// Parsing all of the loosely-typed API map happens here, once, with defensive
/// `is` checks — so the chart widgets never perform bare `as` casts on network
/// data (CLAUDE.md type-safety rule).
class AdminDashboardData {
  const AdminDashboardData({
    required this.jobsByStatus,
    required this.revenueByMonth,
    required this.contractorUtilization,
    required this.quoteConversion,
  });

  /// Job status backend key → count (e.g. {'scheduled': 5, 'complete': 3}).
  final Map<String, int> jobsByStatus;
  final List<MonthlyRevenue> revenueByMonth;
  final List<ContractorUtilization> contractorUtilization;
  final QuoteConversion quoteConversion;

  bool get isEmpty =>
      jobsByStatus.isEmpty &&
      revenueByMonth.isEmpty &&
      contractorUtilization.isEmpty &&
      quoteConversion.isEmpty;

  factory AdminDashboardData.fromJson(Map<String, dynamic> json) {
    return AdminDashboardData(
      jobsByStatus: _parseCounts(json['jobs_by_status']),
      revenueByMonth: _parseList(json['revenue_by_month'], MonthlyRevenue.fromJson),
      contractorUtilization:
          _parseList(json['contractor_utilization'], ContractorUtilization.fromJson),
      quoteConversion: QuoteConversion.fromJson(json['quote_conversion']),
    );
  }

  static Map<String, int> _parseCounts(Object? raw) {
    if (raw is! Map) return const {};
    final counts = <String, int>{};
    raw.forEach((key, value) {
      if (key is String) counts[key] = _asInt(value);
    });
    return counts;
  }

  static List<T> _parseList<T>(
    Object? raw,
    T Function(Map<String, dynamic>) fromJson,
  ) {
    if (raw is! List) return const [];
    return raw
        .whereType<Map<String, dynamic>>()
        .map(fromJson)
        .toList(growable: false);
  }

  static int _asInt(Object? value) => value is num ? value.toInt() : 0;
  static double _asDouble(Object? value) => value is num ? value.toDouble() : 0;
}

/// One month of revenue split into paid vs unpaid totals.
class MonthlyRevenue {
  const MonthlyRevenue({
    required this.month,
    required this.paid,
    required this.unpaid,
  });

  final String month;
  final double paid;
  final double unpaid;

  double get total => paid + unpaid;

  factory MonthlyRevenue.fromJson(Map<String, dynamic> json) {
    return MonthlyRevenue(
      month: json['month'] is String ? json['month'] as String : '',
      paid: AdminDashboardData._asDouble(json['paid']),
      unpaid: AdminDashboardData._asDouble(json['unpaid']),
    );
  }
}

/// A contractor's utilization percentage (0–100).
class ContractorUtilization {
  const ContractorUtilization({required this.name, required this.utilization});

  final String name;
  final double utilization;

  factory ContractorUtilization.fromJson(Map<String, dynamic> json) {
    return ContractorUtilization(
      name: json['name'] is String ? json['name'] as String : 'Unknown',
      utilization: AdminDashboardData._asDouble(json['utilization']),
    );
  }
}

/// Approved / declined / pending quote counts.
class QuoteConversion {
  const QuoteConversion({
    required this.approved,
    required this.declined,
    required this.pending,
  });

  final int approved;
  final int declined;
  final int pending;

  int get total => approved + declined + pending;

  bool get isEmpty => total == 0;

  /// Percentage of decided quotes that were approved (0 when none decided).
  double get conversionRate {
    final decided = approved + declined;
    return decided > 0 ? approved / decided * 100 : 0;
  }

  factory QuoteConversion.fromJson(Object? raw) {
    if (raw is! Map<String, dynamic>) {
      return const QuoteConversion(approved: 0, declined: 0, pending: 0);
    }
    return QuoteConversion(
      approved: AdminDashboardData._asInt(raw['approved']),
      declined: AdminDashboardData._asInt(raw['declined']),
      pending: AdminDashboardData._asInt(raw['pending']),
    );
  }
}
