import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
// StateProvider moved to legacy in Riverpod 3 — explicitly imported.
// ignore: depend_on_referenced_packages
import 'package:riverpod/legacy.dart';

import '../../../../core/di/service_locator.dart';
import '../../../../core/network/dio_client.dart';

// ─── Date range state ─────────────────────────────────────────────────────────

/// Currently selected date preset label (e.g., 'This Month').
///
/// Used by the chip row in AdminReportsScreen / ContractorReportsScreen.
final datePresetProvider = StateProvider<String>((ref) => 'This Month');

/// Currently selected date range for report data queries.
///
/// Defaults to "This Month": from the 1st of the current month to today.
/// Automatically derived from [datePresetProvider] when a preset chip is tapped.
/// Overridden with a custom range when the Custom picker is used.
final dateRangeProvider = StateProvider<DateTimeRange>((ref) {
  final now = DateTime.now();
  final firstOfMonth = DateTime(now.year, now.month);
  return DateTimeRange(start: firstOfMonth, end: now);
});

// ─── Admin dashboard ──────────────────────────────────────────────────────────

/// Admin dashboard metrics loaded from GET /reports/dashboard.
///
/// Watches [dateRangeProvider] — automatically refetches when the date range
/// changes. Returns a [DashboardData] map (raw JSON) for the UI to render.
class AdminDashboardNotifier
    extends AsyncNotifier<Map<String, dynamic>> {
  @override
  Future<Map<String, dynamic>> build() async {
    // Watch date range — rebuild (refetch) whenever it changes.
    final dateRange = ref.watch(dateRangeProvider);

    final startStr = _formatDate(dateRange.start);
    final endStr = _formatDate(dateRange.end);

    final dio = getIt<DioClient>();
    final response = await dio.instance.get<Map<String, dynamic>>(
      '/reports/dashboard',
      queryParameters: {
        'start_date': startStr,
        'end_date': endStr,
      },
    );

    final data = response.data;
    if (data == null) {
      return {};
    }

    return data;
  }
}

/// Provider for [AdminDashboardNotifier].
final adminDashboardProvider =
    AsyncNotifierProvider<AdminDashboardNotifier, Map<String, dynamic>>(
  AdminDashboardNotifier.new,
);

// ─── Contractor stats ─────────────────────────────────────────────────────────

/// Contractor-specific stats loaded from GET /reports/contractor.
///
/// Returns the contractor's own job counts and utilization only.
/// Revenue data is excluded from this endpoint (per locked design decision).
class ContractorStatsNotifier
    extends AsyncNotifier<Map<String, dynamic>> {
  @override
  Future<Map<String, dynamic>> build() async {
    final dateRange = ref.watch(dateRangeProvider);

    final startStr = _formatDate(dateRange.start);
    final endStr = _formatDate(dateRange.end);

    final dio = getIt<DioClient>();
    final response = await dio.instance.get<Map<String, dynamic>>(
      '/reports/contractor',
      queryParameters: {
        'start_date': startStr,
        'end_date': endStr,
      },
    );

    final data = response.data;
    if (data == null) {
      return {};
    }

    return data;
  }
}

/// Provider for [ContractorStatsNotifier].
final contractorStatsProvider =
    AsyncNotifierProvider<ContractorStatsNotifier, Map<String, dynamic>>(
  ContractorStatsNotifier.new,
);

// ─── Helpers ──────────────────────────────────────────────────────────────────

String _formatDate(DateTime dt) {
  final y = dt.year.toString();
  final m = dt.month.toString().padLeft(2, '0');
  final d = dt.day.toString().padLeft(2, '0');
  return '$y-$m-$d';
}

/// Compute a [DateTimeRange] for a named preset.
DateTimeRange presetToRange(String preset) {
  final now = DateTime.now();
  return switch (preset) {
    'This Week' => DateTimeRange(
        start: now.subtract(Duration(days: now.weekday - 1)),
        end: now,
      ),
    'This Month' => DateTimeRange(
        start: DateTime(now.year, now.month),
        end: now,
      ),
    'Last 30 Days' => DateTimeRange(
        start: now.subtract(const Duration(days: 30)),
        end: now,
      ),
    'This Quarter' => DateTimeRange(
        start: DateTime(now.year, ((now.month - 1) ~/ 3) * 3 + 1),
        end: now,
      ),
    'This Year' => DateTimeRange(
        start: DateTime(now.year),
        end: now,
      ),
    'All Time' => DateTimeRange(
        start: DateTime(2020),
        end: now,
      ),
    _ => DateTimeRange(
        start: DateTime(now.year, now.month),
        end: now,
      ),
  };
}
