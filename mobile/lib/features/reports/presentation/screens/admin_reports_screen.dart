import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers/reports_providers.dart';

/// Admin reporting dashboard — 4 metric charts with date range filter.
///
/// Charts:
///   1. Jobs by Status — PieChart (fl_chart)
///   2. Revenue Summary — BarChart (monthly grouped bars, paid vs unpaid)
///   3. Contractor Utilization — Horizontal BarChart ranked by %
///   4. Quote Conversion Rate — PieChart (approved vs declined)
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
          // Date range selector
          _DateRangeSelector(currentPreset: currentPreset),
          const Divider(height: 1),
          // Dashboard content
          Expanded(
            child: dashboardAsync.when(
              data: (data) => _DashboardContent(data: data),
              loading: () =>
                  const Center(child: CircularProgressIndicator()),
              error: (e, _) => Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.error_outline,
                      size: 48,
                      color: Theme.of(context).colorScheme.error,
                    ),
                    const SizedBox(height: 8),
                    Text('Failed to load reports: $e'),
                    const SizedBox(height: 16),
                    FilledButton(
                      onPressed: () =>
                          ref.invalidate(adminDashboardProvider),
                      child: const Text('Retry'),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Date range selector ───────────────────────────────────────────────────────

class _DateRangeSelector extends ConsumerWidget {
  final String currentPreset;

  const _DateRangeSelector({required this.currentPreset});

  static const _presets = [
    'This Week',
    'This Month',
    'Last 30 Days',
    'This Quarter',
    'This Year',
    'All Time',
    'Custom',
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
          final isSelected = preset == currentPreset;

          return FilterChip(
            label: Text(preset),
            selected: isSelected,
            onSelected: (selected) async {
              if (preset == 'Custom') {
                final picked = await showDateRangePicker(
                  context: context,
                  firstDate: DateTime(2020),
                  lastDate: DateTime.now(),
                  initialDateRange: ref.read(dateRangeProvider),
                );
                if (picked != null) {
                  ref.read(datePresetProvider.notifier).state = 'Custom';
                  ref.read(dateRangeProvider.notifier).state = picked;
                  ref.invalidate(adminDashboardProvider);
                }
              } else {
                ref.read(datePresetProvider.notifier).state = preset;
                ref.read(dateRangeProvider.notifier).state =
                    presetToRange(preset);
                ref.invalidate(adminDashboardProvider);
              }
            },
          );
        },
      ),
    );
  }
}

// ─── Dashboard content ────────────────────────────────────────────────────────

class _DashboardContent extends StatelessWidget {
  final Map<String, dynamic> data;

  const _DashboardContent({required this.data});

  @override
  Widget build(BuildContext context) {
    if (data.isEmpty) {
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

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        // Chart 1: Jobs by Status
        _ChartCard(
          title: 'Jobs by Status',
          child: _JobsByStatusChart(data: data),
        ),
        const SizedBox(height: 16),

        // Chart 2: Revenue Summary
        _ChartCard(
          title: 'Revenue Summary',
          child: _RevenueSummaryChart(data: data),
        ),
        const SizedBox(height: 16),

        // Chart 3: Contractor Utilization
        _ChartCard(
          title: 'Contractor Utilization',
          child: _ContractorUtilizationChart(data: data),
        ),
        const SizedBox(height: 16),

        // Chart 4: Quote Conversion Rate
        _ChartCard(
          title: 'Quote Conversion Rate',
          child: _QuoteConversionChart(data: data),
        ),
        const SizedBox(height: 16),
      ],
    );
  }
}

// ─── Chart wrapper ────────────────────────────────────────────────────────────

class _ChartCard extends StatelessWidget {
  final String title;
  final Widget child;

  const _ChartCard({required this.title, required this.child});

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
            ),
            const SizedBox(height: 16),
            child,
          ],
        ),
      ),
    );
  }
}

// ─── Chart 1: Jobs by Status PieChart ─────────────────────────────────────────

class _JobsByStatusChart extends StatelessWidget {
  final Map<String, dynamic> data;

  const _JobsByStatusChart({required this.data});

  @override
  Widget build(BuildContext context) {
    // Extract job status counts from API data
    final statusCounts =
        data['jobs_by_status'] as Map<String, dynamic>? ?? {};

    if (statusCounts.isEmpty) {
      return const _EmptyChartState(message: 'No jobs in selected period');
    }

    final statusColors = {
      'quote': Colors.grey,
      'scheduled': Colors.blue,
      'in_progress': Colors.amber,
      'complete': Colors.green,
      'invoiced': Colors.purple,
      'cancelled': Colors.red,
    };

    final statusLabels = {
      'quote': 'Quote',
      'scheduled': 'Scheduled',
      'in_progress': 'In Progress',
      'complete': 'Complete',
      'invoiced': 'Invoiced',
      'cancelled': 'Cancelled',
    };

    final sections = statusCounts.entries
        .where((e) => (e.value as num? ?? 0) > 0)
        .map((e) {
      final count = (e.value as num).toDouble();
      final color = statusColors[e.key] ?? Colors.grey;
      return PieChartSectionData(
        value: count,
        color: color,
        title: count.toInt().toString(),
        titleStyle: const TextStyle(
          color: Colors.white,
          fontWeight: FontWeight.bold,
          fontSize: 12,
        ),
        radius: 80,
      );
    }).toList();

    final total = statusCounts.values
        .fold<int>(0, (sum, v) => sum + ((v as num?)?.toInt() ?? 0));

    return Column(
      children: [
        SizedBox(
          height: 200,
          child: Stack(
            alignment: Alignment.center,
            children: [
              PieChart(
                PieChartData(
                  sections: sections,
                  centerSpaceRadius: 50,
                  sectionsSpace: 2,
                ),
              ),
              Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    '$total',
                    style: Theme.of(context)
                        .textTheme
                        .headlineSmall
                        ?.copyWith(fontWeight: FontWeight.bold),
                  ),
                  Text(
                    'Total',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color:
                              Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                  ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        // Legend
        Wrap(
          spacing: 12,
          runSpacing: 4,
          children: statusCounts.entries
              .where((e) => (e.value as num? ?? 0) > 0)
              .map((e) {
            final color = statusColors[e.key] ?? Colors.grey;
            final label = statusLabels[e.key] ?? e.key;
            return Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 10,
                  height: 10,
                  decoration: BoxDecoration(
                    color: color,
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 4),
                Text('$label (${e.value})',
                    style: const TextStyle(fontSize: 11)),
              ],
            );
          }).toList(),
        ),
      ],
    );
  }
}

// ─── Chart 2: Revenue Summary BarChart ────────────────────────────────────────

class _RevenueSummaryChart extends StatelessWidget {
  final Map<String, dynamic> data;

  const _RevenueSummaryChart({required this.data});

  @override
  Widget build(BuildContext context) {
    final revenueData =
        data['revenue_by_month'] as List<dynamic>? ?? [];

    if (revenueData.isEmpty) {
      return const _EmptyChartState(message: 'No revenue data in selected period');
    }

    // Take up to last 12 months
    final months = revenueData
        .whereType<Map<String, dynamic>>()
        .take(12)
        .toList();

    final maxY = months.fold<double>(0, (max, m) {
      final paid = (m['paid'] as num? ?? 0).toDouble();
      final unpaid = (m['unpaid'] as num? ?? 0).toDouble();
      final total = paid + unpaid;
      return total > max ? total : max;
    });

    final barGroups = months.asMap().entries.map((entry) {
      final i = entry.key;
      final m = entry.value;
      final paid = (m['paid'] as num? ?? 0).toDouble();
      final unpaid = (m['unpaid'] as num? ?? 0).toDouble();

      return BarChartGroupData(
        x: i,
        barRods: [
          BarChartRodData(
            toY: paid + unpaid,
            color: Colors.orange.shade300,
            width: 16,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(4)),
            rodStackItems: [
              BarChartRodStackItem(0, paid, Colors.green.shade400),
              BarChartRodStackItem(paid, paid + unpaid, Colors.orange.shade300),
            ],
          ),
        ],
      );
    }).toList();

    return Column(
      children: [
        SizedBox(
          height: 180,
          child: BarChart(
            BarChartData(
              maxY: maxY * 1.2,
              barGroups: barGroups,
              gridData: const FlGridData(),
              borderData: FlBorderData(show: false),
              titlesData: FlTitlesData(
                leftTitles: AxisTitles(
                  sideTitles: SideTitles(
                    showTitles: true,
                    getTitlesWidget: (val, meta) => Text(
                      '\$${(val / 1000).toStringAsFixed(0)}k',
                      style: const TextStyle(fontSize: 9),
                    ),
                    reservedSize: 40,
                  ),
                ),
                bottomTitles: AxisTitles(
                  sideTitles: SideTitles(
                    showTitles: true,
                    getTitlesWidget: (val, meta) {
                      final idx = val.toInt();
                      if (idx < 0 || idx >= months.length) {
                        return const SizedBox.shrink();
                      }
                      final label = months[idx]['month'] as String? ?? '';
                      // Show first 3 chars of month label
                      return Text(
                        label.length > 3 ? label.substring(0, 3) : label,
                        style: const TextStyle(fontSize: 9),
                      );
                    },
                    reservedSize: 20,
                  ),
                ),
                rightTitles: const AxisTitles(
                  
                ),
                topTitles: const AxisTitles(
                  
                ),
              ),
            ),
          ),
        ),
        const SizedBox(height: 8),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            _LegendDot(color: Colors.green.shade400, label: 'Paid'),
            const SizedBox(width: 16),
            _LegendDot(color: Colors.orange.shade300, label: 'Unpaid'),
          ],
        ),
      ],
    );
  }
}

// ─── Chart 3: Contractor Utilization ─────────────────────────────────────────

class _ContractorUtilizationChart extends StatelessWidget {
  final Map<String, dynamic> data;

  const _ContractorUtilizationChart({required this.data});

  @override
  Widget build(BuildContext context) {
    final utilizationData =
        data['contractor_utilization'] as List<dynamic>? ?? [];

    if (utilizationData.isEmpty) {
      return const _EmptyChartState(message: 'No utilization data');
    }

    final contractors = utilizationData
        .whereType<Map<String, dynamic>>()
        .toList();

    // Sort by utilization descending
    contractors.sort((a, b) {
      final aVal = (a['utilization'] as num? ?? 0).toDouble();
      final bVal = (b['utilization'] as num? ?? 0).toDouble();
      return bVal.compareTo(aVal);
    });

    return Column(
      children: contractors.map((c) {
        final name = c['name'] as String? ?? 'Unknown';
        final utilization = (c['utilization'] as num? ?? 0).toDouble();
        final pct = utilization.clamp(0.0, 100.0);

        final color = pct < 50
            ? Colors.red.shade400
            : pct < 75
                ? Colors.yellow.shade700
                : Colors.green.shade400;

        return Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: Row(
            children: [
              SizedBox(
                width: 80,
                child: Text(
                  name,
                  style: const TextStyle(fontSize: 11),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: LinearProgressIndicator(
                    value: pct / 100,
                    backgroundColor: Colors.grey.shade200,
                    valueColor: AlwaysStoppedAnimation<Color>(color),
                    minHeight: 16,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Text(
                '${pct.toStringAsFixed(0)}%',
                style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600),
              ),
            ],
          ),
        );
      }).toList(),
    );
  }
}

// ─── Chart 4: Quote Conversion Rate PieChart ──────────────────────────────────

class _QuoteConversionChart extends StatelessWidget {
  final Map<String, dynamic> data;

  const _QuoteConversionChart({required this.data});

  @override
  Widget build(BuildContext context) {
    final conversionData =
        data['quote_conversion'] as Map<String, dynamic>? ?? {};

    final approved = (conversionData['approved'] as num? ?? 0).toDouble();
    final declined = (conversionData['declined'] as num? ?? 0).toDouble();
    final pending = (conversionData['pending'] as num? ?? 0).toDouble();
    final total = approved + declined + pending;

    if (total == 0) {
      return const _EmptyChartState(message: 'No quote data in selected period');
    }

    final conversionRate = total > 0 ? (approved / (approved + declined) * 100) : 0.0;

    final sections = <PieChartSectionData>[
      if (approved > 0)
        PieChartSectionData(
          value: approved,
          color: Colors.green,
          title: approved.toInt().toString(),
          titleStyle: const TextStyle(color: Colors.white, fontSize: 12),
          radius: 80,
        ),
      if (declined > 0)
        PieChartSectionData(
          value: declined,
          color: Colors.red,
          title: declined.toInt().toString(),
          titleStyle: const TextStyle(color: Colors.white, fontSize: 12),
          radius: 80,
        ),
    ];

    if (sections.isEmpty) {
      return const _EmptyChartState(message: 'No approved or declined quotes');
    }

    return Column(
      children: [
        SizedBox(
          height: 180,
          child: Stack(
            alignment: Alignment.center,
            children: [
              PieChart(
                PieChartData(
                  sections: sections,
                  centerSpaceRadius: 50,
                  sectionsSpace: 2,
                ),
              ),
              Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    '${conversionRate.toStringAsFixed(0)}%',
                    style: Theme.of(context)
                        .textTheme
                        .headlineSmall
                        ?.copyWith(fontWeight: FontWeight.bold),
                  ),
                  Text(
                    'Conversion',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color:
                              Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                  ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        Text(
          '${approved.toInt()} approved · ${declined.toInt()} declined · ${pending.toInt()} pending',
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
        ),
      ],
    );
  }
}

// ─── Shared widgets ───────────────────────────────────────────────────────────

class _EmptyChartState extends StatelessWidget {
  final String message;

  const _EmptyChartState({required this.message});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 24),
      child: Center(
        child: Text(
          message,
          style: TextStyle(
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
        ),
      ),
    );
  }
}

class _LegendDot extends StatelessWidget {
  final Color color;
  final String label;

  const _LegendDot({required this.color, required this.label});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 10,
          height: 10,
          decoration: BoxDecoration(
            color: color,
            shape: BoxShape.circle,
          ),
        ),
        const SizedBox(width: 4),
        Text(label, style: const TextStyle(fontSize: 11)),
      ],
    );
  }
}
