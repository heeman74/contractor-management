import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';

import '../../domain/admin_dashboard_data.dart';
import '../../domain/job_status_chart_style.dart';

const double _pieRadius = 80;
const double _pieCenterRadius = 50;
const double _pieHeight = 200;
const double _quotePieHeight = 180;
const int _maxRevenueMonths = 12;

/// Card wrapper that gives every report chart a titled surface.
class ReportChartCard extends StatelessWidget {
  const ReportChartCard({required this.title, required this.child, super.key});

  final String title;
  final Widget child;

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
              style: Theme.of(context)
                  .textTheme
                  .titleMedium
                  ?.copyWith(fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 16),
            child,
          ],
        ),
      ),
    );
  }
}

/// Jobs-by-status donut chart with a center total and legend.
class JobsByStatusChart extends StatelessWidget {
  const JobsByStatusChart({required this.jobsByStatus, super.key});

  final Map<String, int> jobsByStatus;

  @override
  Widget build(BuildContext context) {
    final entries =
        jobsByStatus.entries.where((entry) => entry.value > 0).toList();
    if (entries.isEmpty) {
      return const ReportEmptyChartState(message: 'No jobs in selected period');
    }

    final total = entries.fold<int>(0, (sum, entry) => sum + entry.value);
    final sections = entries.map((entry) {
      return PieChartSectionData(
        value: entry.value.toDouble(),
        color: JobStatusChartStyle.color(entry.key),
        title: '${entry.value}',
        titleStyle: const TextStyle(
          color: Colors.white,
          fontWeight: FontWeight.bold,
          fontSize: 12,
        ),
        radius: _pieRadius,
      );
    }).toList();

    return Column(
      children: [
        SizedBox(
          height: _pieHeight,
          child: _CenteredPie(
            sections: sections,
            centerValue: '$total',
            centerLabel: 'Total',
          ),
        ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 12,
          runSpacing: 4,
          children: entries.map((entry) {
            return _LegendDot(
              color: JobStatusChartStyle.color(entry.key),
              label: '${JobStatusChartStyle.label(entry.key)} (${entry.value})',
            );
          }).toList(),
        ),
      ],
    );
  }
}

/// Monthly revenue stacked bar chart (paid vs unpaid).
class RevenueSummaryChart extends StatelessWidget {
  const RevenueSummaryChart({required this.revenueByMonth, super.key});

  final List<MonthlyRevenue> revenueByMonth;

  @override
  Widget build(BuildContext context) {
    if (revenueByMonth.isEmpty) {
      return const ReportEmptyChartState(
          message: 'No revenue data in selected period');
    }

    final months = revenueByMonth.take(_maxRevenueMonths).toList();
    final maxY = months.fold<double>(0, (max, m) => m.total > max ? m.total : max);

    final barGroups = months.asMap().entries.map((entry) {
      final month = entry.value;
      return BarChartGroupData(
        x: entry.key,
        barRods: [
          BarChartRodData(
            toY: month.total,
            color: Colors.orange.shade300,
            width: 16,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(4)),
            rodStackItems: [
              BarChartRodStackItem(0, month.paid, Colors.green.shade400),
              BarChartRodStackItem(
                  month.paid, month.total, Colors.orange.shade300),
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
              titlesData: _revenueTitles(months),
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

  FlTitlesData _revenueTitles(List<MonthlyRevenue> months) {
    return FlTitlesData(
      leftTitles: AxisTitles(
        sideTitles: SideTitles(
          showTitles: true,
          getTitlesWidget: (value, meta) => Text(
            '\$${(value / 1000).toStringAsFixed(0)}k',
            style: const TextStyle(fontSize: 9),
          ),
          reservedSize: 40,
        ),
      ),
      bottomTitles: AxisTitles(
        sideTitles: SideTitles(
          showTitles: true,
          getTitlesWidget: (value, meta) {
            final index = value.toInt();
            if (index < 0 || index >= months.length) {
              return const SizedBox.shrink();
            }
            final label = months[index].month;
            return Text(
              label.length > 3 ? label.substring(0, 3) : label,
              style: const TextStyle(fontSize: 9),
            );
          },
          reservedSize: 20,
        ),
      ),
      rightTitles: const AxisTitles(),
      topTitles: const AxisTitles(),
    );
  }
}

/// Horizontal ranked bars of contractor utilization percentages.
class ContractorUtilizationChart extends StatelessWidget {
  const ContractorUtilizationChart({required this.contractors, super.key});

  final List<ContractorUtilization> contractors;

  static const double _lowThreshold = 50;
  static const double _highThreshold = 75;

  @override
  Widget build(BuildContext context) {
    if (contractors.isEmpty) {
      return const ReportEmptyChartState(message: 'No utilization data');
    }

    final ranked = [...contractors]
      ..sort((a, b) => b.utilization.compareTo(a.utilization));

    return Column(
      children: ranked.map((contractor) {
        final pct = contractor.utilization.clamp(0.0, 100.0);
        return Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: Row(
            children: [
              SizedBox(
                width: 80,
                child: Text(
                  contractor.name,
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
                    valueColor: AlwaysStoppedAnimation<Color>(_barColor(pct)),
                    minHeight: 16,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Text(
                '${pct.toStringAsFixed(0)}%',
                style:
                    const TextStyle(fontSize: 11, fontWeight: FontWeight.w600),
              ),
            ],
          ),
        );
      }).toList(),
    );
  }

  Color _barColor(double pct) {
    if (pct < _lowThreshold) return Colors.red.shade400;
    if (pct < _highThreshold) return Colors.yellow.shade700;
    return Colors.green.shade400;
  }
}

/// Quote approval donut chart with the conversion-rate percentage in the center.
class QuoteConversionChart extends StatelessWidget {
  const QuoteConversionChart({required this.conversion, super.key});

  final QuoteConversion conversion;

  @override
  Widget build(BuildContext context) {
    if (conversion.isEmpty) {
      return const ReportEmptyChartState(
          message: 'No quote data in selected period');
    }

    final sections = <PieChartSectionData>[
      if (conversion.approved > 0)
        _section(conversion.approved, Colors.green),
      if (conversion.declined > 0)
        _section(conversion.declined, Colors.red),
    ];
    if (sections.isEmpty) {
      return const ReportEmptyChartState(
          message: 'No approved or declined quotes');
    }

    return Column(
      children: [
        SizedBox(
          height: _quotePieHeight,
          child: _CenteredPie(
            sections: sections,
            centerValue: '${conversion.conversionRate.toStringAsFixed(0)}%',
            centerLabel: 'Conversion',
          ),
        ),
        const SizedBox(height: 12),
        Text(
          '${conversion.approved} approved · ${conversion.declined} declined · '
          '${conversion.pending} pending',
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
        ),
      ],
    );
  }

  PieChartSectionData _section(int value, Color color) {
    return PieChartSectionData(
      value: value.toDouble(),
      color: color,
      title: '$value',
      titleStyle: const TextStyle(color: Colors.white, fontSize: 12),
      radius: _pieRadius,
    );
  }
}

/// A donut chart with a centered value + label overlay.
class _CenteredPie extends StatelessWidget {
  const _CenteredPie({
    required this.sections,
    required this.centerValue,
    required this.centerLabel,
  });

  final List<PieChartSectionData> sections;
  final String centerValue;
  final String centerLabel;

  @override
  Widget build(BuildContext context) {
    return Stack(
      alignment: Alignment.center,
      children: [
        PieChart(
          PieChartData(
            sections: sections,
            centerSpaceRadius: _pieCenterRadius,
            sectionsSpace: 2,
          ),
        ),
        Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              centerValue,
              style: Theme.of(context)
                  .textTheme
                  .headlineSmall
                  ?.copyWith(fontWeight: FontWeight.bold),
            ),
            Text(
              centerLabel,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
            ),
          ],
        ),
      ],
    );
  }
}

class ReportEmptyChartState extends StatelessWidget {
  const ReportEmptyChartState({required this.message, super.key});

  final String message;

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
  const _LegendDot({required this.color, required this.label});

  final Color color;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 10,
          height: 10,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 4),
        Text(label, style: const TextStyle(fontSize: 11)),
      ],
    );
  }
}
