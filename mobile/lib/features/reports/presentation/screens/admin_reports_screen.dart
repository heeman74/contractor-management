import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../domain/admin_dashboard_data.dart';
import '../providers/reports_providers.dart';
import '../widgets/admin_report_charts.dart';

/// Admin reporting dashboard — 4 metric charts with a date range filter.
///
/// Charts: Jobs by Status (pie), Revenue Summary (stacked bars), Contractor
/// Utilization (ranked bars), Quote Conversion Rate (pie).
///
/// Navigation: Reports tab in bottom nav (admin only).
class AdminReportsScreen extends ConsumerWidget {
  const AdminReportsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final currentPreset = ref.watch(datePresetProvider);
    final dashboardAsync = ref.watch(adminDashboardProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Reports')),
      body: Column(
        children: [
          _DateRangeSelector(currentPreset: currentPreset),
          const Divider(height: 1),
          Expanded(
            child: dashboardAsync.when(
              data: (raw) =>
                  _DashboardContent(data: AdminDashboardData.fromJson(raw)),
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (error, _) => _ErrorState(
                error: error,
                onRetry: () => ref.invalidate(adminDashboardProvider),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ErrorState extends StatelessWidget {
  const _ErrorState({required this.error, required this.onRetry});

  final Object error;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.error_outline,
              size: 48, color: Theme.of(context).colorScheme.error),
          const SizedBox(height: 8),
          Text('Failed to load reports: $error'),
          const SizedBox(height: 16),
          FilledButton(onPressed: onRetry, child: const Text('Retry')),
        ],
      ),
    );
  }
}

// ─── Date range selector ───────────────────────────────────────────────────────

class _DateRangeSelector extends ConsumerWidget {
  const _DateRangeSelector({required this.currentPreset});

  final String currentPreset;

  static const _customPreset = 'Custom';
  static const _presets = [
    'This Week',
    'This Month',
    'Last 30 Days',
    'This Quarter',
    'This Year',
    'All Time',
    _customPreset,
  ];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return SizedBox(
      height: 52,
      child: ListView.separated(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        scrollDirection: Axis.horizontal,
        itemCount: _presets.length,
        separatorBuilder: (_, __) => const SizedBox(width: 6),
        itemBuilder: (context, index) {
          final preset = _presets[index];
          return FilterChip(
            label: Text(preset),
            selected: preset == currentPreset,
            onSelected: (_) => _onPresetSelected(context, ref, preset),
          );
        },
      ),
    );
  }

  Future<void> _onPresetSelected(
    BuildContext context,
    WidgetRef ref,
    String preset,
  ) async {
    if (preset == _customPreset) {
      final picked = await showDateRangePicker(
        context: context,
        firstDate: DateTime(2020),
        lastDate: DateTime.now(),
        initialDateRange: ref.read(dateRangeProvider),
      );
      if (picked == null) return;
      ref.read(datePresetProvider.notifier).state = _customPreset;
      ref.read(dateRangeProvider.notifier).state = picked;
    } else {
      ref.read(datePresetProvider.notifier).state = preset;
      ref.read(dateRangeProvider.notifier).state = presetToRange(preset);
    }
    ref.invalidate(adminDashboardProvider);
  }
}

// ─── Dashboard content ────────────────────────────────────────────────────────

class _DashboardContent extends StatelessWidget {
  const _DashboardContent({required this.data});

  final AdminDashboardData data;

  @override
  Widget build(BuildContext context) {
    if (data.isEmpty) return const _NoDataState();

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        ReportChartCard(
          title: 'Jobs by Status',
          child: JobsByStatusChart(jobsByStatus: data.jobsByStatus),
        ),
        const SizedBox(height: 16),
        ReportChartCard(
          title: 'Revenue Summary',
          child: RevenueSummaryChart(revenueByMonth: data.revenueByMonth),
        ),
        const SizedBox(height: 16),
        ReportChartCard(
          title: 'Contractor Utilization',
          child: ContractorUtilizationChart(
              contractors: data.contractorUtilization),
        ),
        const SizedBox(height: 16),
        ReportChartCard(
          title: 'Quote Conversion Rate',
          child: QuoteConversionChart(conversion: data.quoteConversion),
        ),
        const SizedBox(height: 16),
      ],
    );
  }
}

class _NoDataState extends StatelessWidget {
  const _NoDataState();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.bar_chart_outlined,
            size: 64,
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
          const SizedBox(height: 12),
          Text(
            'No data for selected period',
            style: TextStyle(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
              fontSize: 16,
            ),
          ),
        ],
      ),
    );
  }
}
