import 'package:flutter/material.dart';

/// View mode for the contractor's personal schedule (list vs calendar).
enum ContractorScheduleViewMode { list, calendar }

/// Header for the contractor schedule screen: view toggle + date navigation.
class ContractorScheduleHeader extends StatelessWidget {
  const ContractorScheduleHeader({
    required this.selectedDate,
    required this.viewMode,
    required this.onViewModeChanged,
    required this.onDateChanged,
    super.key,
  });

  final DateTime selectedDate;
  final ContractorScheduleViewMode viewMode;
  final ValueChanged<ContractorScheduleViewMode> onViewModeChanged;
  final ValueChanged<DateTime> onDateChanged;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Container(
      color: theme.colorScheme.surface,
      padding: const EdgeInsets.fromLTRB(8, 6, 8, 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // List / Calendar toggle
          SegmentedButton<ContractorScheduleViewMode>(
            segments: const [
              ButtonSegment<ContractorScheduleViewMode>(
                value: ContractorScheduleViewMode.list,
                label: Text('List'),
                icon: Icon(Icons.list, size: 16),
              ),
              ButtonSegment<ContractorScheduleViewMode>(
                value: ContractorScheduleViewMode.calendar,
                label: Text('Calendar'),
                icon: Icon(Icons.calendar_today, size: 16),
              ),
            ],
            selected: {viewMode},
            onSelectionChanged: (modes) {
              if (modes.isNotEmpty) onViewModeChanged(modes.first);
            },
            style: const ButtonStyle(
              visualDensity: VisualDensity.compact,
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
          ),
          const SizedBox(height: 6),

          // Date navigation (only shown in calendar mode, but useful in list too)
          Row(
            children: [
              IconButton(
                icon: const Icon(Icons.chevron_left),
                onPressed: () => onDateChanged(
                  selectedDate.subtract(const Duration(days: 1)),
                ),
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                iconSize: 20,
              ),
              Expanded(
                child: GestureDetector(
                  onTap: () async {
                    final picked = await showDatePicker(
                      context: context,
                      initialDate: selectedDate,
                      firstDate: DateTime(2020),
                      lastDate: DateTime(2030),
                    );
                    if (picked != null) onDateChanged(picked);
                  },
                  child: Text(
                    _formatDate(selectedDate),
                    textAlign: TextAlign.center,
                    style: theme.textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w600,
                      decoration: TextDecoration.underline,
                      decorationStyle: TextDecorationStyle.dotted,
                    ),
                  ),
                ),
              ),
              IconButton(
                icon: const Icon(Icons.chevron_right),
                onPressed: () => onDateChanged(
                  selectedDate.add(const Duration(days: 1)),
                ),
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                iconSize: 20,
              ),
              TextButton(
                onPressed: () => onDateChanged(DateTime.now()),
                style: TextButton.styleFrom(
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  minimumSize: const Size(48, 32),
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
                child: const Text('Today', style: TextStyle(fontSize: 12)),
              ),
            ],
          ),
        ],
      ),
    );
  }

  String _formatDate(DateTime date) {
    const months = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
    ];
    const weekdays = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
    return '${weekdays[date.weekday - 1]}, ${months[date.month - 1]} ${date.day}';
  }
}
