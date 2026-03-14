import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers/reports_providers.dart';

/// Contractor-specific reports screen — shows own stats only.
///
/// Deliberately excludes revenue data (per locked design decision:
/// contractors see own job counts and utilization, never financial metrics).
///
/// Charts:
///   1. My Jobs — PieChart of own jobs by status
///   2. My Utilization — single horizontal progress bar (booked vs available)
///
/// Navigation: Reports tab in bottom nav (contractor role).
class ContractorReportsScreen extends ConsumerWidget {
  const ContractorReportsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final currentPreset = ref.watch(datePresetProvider);
    final statsAsync = ref.watch(contractorStatsProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('My Stats')),
      body: Column(
        children: [
          // Date range selector
          _DateRangeSelector(currentPreset: currentPreset),
          const Divider(height: 1),
          // Stats content
          Expanded(
            child: statsAsync.when(
              data: (data) => _ContractorStatsContent(data: data),
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
                    Text('Failed to load stats: $e'),
                    const SizedBox(height: 16),
                    FilledButton(
                      onPressed: () =>
                          ref.invalidate(contractorStatsProvider),
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
                  ref.invalidate(contractorStatsProvider);
                }
              } else {
                ref.read(datePresetProvider.notifier).state = preset;
                ref.read(dateRangeProvider.notifier).state =
                    presetToRange(preset);
                ref.invalidate(contractorStatsProvider);
              }
            },
          );
        },
      ),
    );
  }
}

// ─── Stats content ────────────────────────────────────────────────────────────

class _ContractorStatsContent extends StatelessWidget {
  final Map<String, dynamic> data;

  const _ContractorStatsContent({required this.data});

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
        // Chart 1: My Jobs by Status
        _ChartCard(
          title: 'My Jobs',
          child: _MyJobsChart(data: data),
        ),
        const SizedBox(height: 16),

        // Chart 2: My Utilization
        _ChartCard(
          title: 'My Utilization',
          child: _MyUtilizationChart(data: data),
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

// ─── Chart 1: My Jobs PieChart ────────────────────────────────────────────────

class _MyJobsChart extends StatelessWidget {
  final Map<String, dynamic> data;

  const _MyJobsChart({required this.data});

  @override
  Widget build(BuildContext context) {
    final jobsByStatus =
        data['jobs_by_status'] as Map<String, dynamic>? ?? {};

    if (jobsByStatus.isEmpty) {
      return const _EmptyState(message: 'No jobs in selected period');
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

    final sections = jobsByStatus.entries
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
        radius: 70,
      );
    }).toList();

    if (sections.isEmpty) {
      return const _EmptyState(message: 'No active jobs');
    }

    final total = jobsByStatus.values
        .fold<int>(0, (sum, v) => sum + ((v as num?)?.toInt() ?? 0));

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
                  centerSpaceRadius: 45,
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
                    'Jobs',
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
        Wrap(
          spacing: 12,
          runSpacing: 4,
          children: jobsByStatus.entries
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

// ─── Chart 2: My Utilization ──────────────────────────────────────────────────

class _MyUtilizationChart extends StatelessWidget {
  final Map<String, dynamic> data;

  const _MyUtilizationChart({required this.data});

  @override
  Widget build(BuildContext context) {
    final utilizationData =
        data['utilization'] as Map<String, dynamic>? ?? {};

    final bookedHours = (utilizationData['booked_hours'] as num? ?? 0).toDouble();
    final availableHours =
        (utilizationData['available_hours'] as num? ?? 0).toDouble();
    final utilization =
        (utilizationData['utilization_pct'] as num? ?? 0).toDouble();

    if (availableHours == 0 && bookedHours == 0) {
      return const _EmptyState(message: 'No utilization data for this period');
    }

    final pct = utilization.clamp(0.0, 100.0);
    final color = pct < 50
        ? Colors.red.shade400
        : pct < 75
            ? Colors.yellow.shade700
            : Colors.green.shade400;

    return Column(
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              '${bookedHours.toStringAsFixed(1)}h booked',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            Text(
              '${pct.toStringAsFixed(0)}% utilized',
              style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                    fontWeight: FontWeight.w700,
                    color: color,
                  ),
            ),
            Text(
              '${availableHours.toStringAsFixed(1)}h available',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
        ),
        const SizedBox(height: 12),
        ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: LinearProgressIndicator(
            value: pct / 100,
            backgroundColor: Colors.grey.shade200,
            valueColor: AlwaysStoppedAnimation<Color>(color),
            minHeight: 24,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          pct < 50
              ? 'Low utilization — consider taking more jobs'
              : pct < 75
                  ? 'Good utilization'
                  : 'High utilization — fully booked',
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
        ),
      ],
    );
  }
}

// ─── Empty state ──────────────────────────────────────────────────────────────

class _EmptyState extends StatelessWidget {
  final String message;

  const _EmptyState({required this.message});

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
