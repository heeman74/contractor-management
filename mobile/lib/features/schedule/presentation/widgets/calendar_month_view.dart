import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../domain/booking_entity.dart';
import '../providers/calendar_providers.dart';

/// Month view: standard calendar grid with booking count badges per day.
///
/// Layout:
///   - Month header: "March 2026" with left/right navigation arrows
///   - Column headers: Mon, Tue, Wed, Thu, Fri, Sat, Sun
///   - Each day cell: date number + booking count badge
///   - Badge color: blue (normal), orange (any warning jobs), red (any critical)
///   - Today highlighted
///   - Days outside the current month are dimmed
///
/// Navigation:
///   - Tap day cell: drill down to day view for that date
///   - Swipe left/right OR arrow buttons: navigate to previous/next month
///   - No contractor lanes — this is a company-wide overview
class CalendarMonthView extends ConsumerStatefulWidget {
  const CalendarMonthView({
    required this.bookings,
    super.key,
  });

  /// All bookings for the full month range (company-scoped).
  final List<BookingEntity> bookings;

  @override
  ConsumerState<CalendarMonthView> createState() => _CalendarMonthViewState();
}

class _CalendarMonthViewState extends ConsumerState<CalendarMonthView> {
  @override
  Widget build(BuildContext context) {
    final selectedDate = ref.watch(calendarDateProvider);
    final theme = Theme.of(context);
    final today = DateTime.now();
    final todayDate = DateTime(today.year, today.month, today.day);

    // Build booking count map: date string -> (count, max severity)
    final bookingMap = _buildBookingMap(widget.bookings);

    return GestureDetector(
      onHorizontalDragEnd: (details) {
        if (details.primaryVelocity == null) return;
        if (details.primaryVelocity! < -300) {
          // Swipe left: next month
          _navigateMonth(ref, selectedDate, 1);
        } else if (details.primaryVelocity! > 300) {
          // Swipe right: previous month
          _navigateMonth(ref, selectedDate, -1);
        }
      },
      child: Column(
        children: [
          // Month header with nav arrows
          _MonthHeader(
            selectedDate: selectedDate,
            onPrevious: () => _navigateMonth(ref, selectedDate, -1),
            onNext: () => _navigateMonth(ref, selectedDate, 1),
            theme: theme,
          ),

          // Day-of-week column headers
          _DayOfWeekHeader(theme: theme),

          // Calendar grid
          Expanded(
            child: _MonthGrid(
              selectedDate: selectedDate,
              today: todayDate,
              bookingMap: bookingMap,
              theme: theme,
              onDayTap: (date) {
                ref.read(calendarDateProvider.notifier).state = date;
                ref.read(calendarViewModeProvider.notifier).state =
                    CalendarViewMode.day;
              },
            ),
          ),
        ],
      ),
    );
  }

  /// Navigate the selected date by [monthDelta] months.
  void _navigateMonth(WidgetRef ref, DateTime current, int monthDelta) {
    var newMonth = current.month + monthDelta;
    var newYear = current.year;

    if (newMonth > 12) {
      newMonth = 1;
      newYear++;
    } else if (newMonth < 1) {
      newMonth = 12;
      newYear--;
    }

    // Clamp day to valid range for new month
    final daysInMonth = DateTime(newYear, newMonth + 1, 0).day;
    final newDay = current.day.clamp(1, daysInMonth);

    ref.read(calendarDateProvider.notifier).state =
        DateTime(newYear, newMonth, newDay);
  }

  /// Builds a map from "yyyy-MM-dd" to [_DayBookingSummary].
  ///
  /// Groups bookings by day and computes worst-case severity for badge coloring.
  Map<String, _DayBookingSummary> _buildBookingMap(List<BookingEntity> bookings) {
    final map = <String, _DayBookingSummary>{};

    for (final booking in bookings) {
      final key = _dateKey(booking.timeRangeStart);
      final existing = map[key];
      if (existing == null) {
        map[key] = const _DayBookingSummary(count: 1, hasCritical: false, hasWarning: false);
      } else {
        map[key] = _DayBookingSummary(
          count: existing.count + 1,
          hasCritical: existing.hasCritical,
          hasWarning: existing.hasWarning,
        );
      }
    }

    return map;
  }

  String _dateKey(DateTime date) {
    return '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
  }
}

// ─── Booking summary for a day cell ──────────────────────────────────────────

class _DayBookingSummary {
  const _DayBookingSummary({
    required this.count,
    required this.hasCritical,
    required this.hasWarning,
  });

  final int count;
  final bool hasCritical;
  final bool hasWarning;

  Color badgeColor(ColorScheme colorScheme) {
    if (hasCritical) return Colors.red;
    if (hasWarning) return Colors.orange;
    return colorScheme.primary;
  }
}

// ─── Month header ─────────────────────────────────────────────────────────────

class _MonthHeader extends StatelessWidget {
  const _MonthHeader({
    required this.selectedDate,
    required this.onPrevious,
    required this.onNext,
    required this.theme,
  });

  final DateTime selectedDate;
  final VoidCallback onPrevious;
  final VoidCallback onNext;
  final ThemeData theme;

  static const _months = [
    'January', 'February', 'March', 'April', 'May', 'June',
    'July', 'August', 'September', 'October', 'November', 'December',
  ];

  @override
  Widget build(BuildContext context) {
    final monthName = _months[selectedDate.month - 1];

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
      color: theme.colorScheme.surface,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          IconButton(
            icon: const Icon(Icons.chevron_left),
            onPressed: onPrevious,
            iconSize: 20,
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
          ),
          const SizedBox(width: 8),
          Text(
            '$monthName ${selectedDate.year}',
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(width: 8),
          IconButton(
            icon: const Icon(Icons.chevron_right),
            onPressed: onNext,
            iconSize: 20,
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
          ),
        ],
      ),
    );
  }
}

// ─── Day-of-week header row ───────────────────────────────────────────────────

class _DayOfWeekHeader extends StatelessWidget {
  const _DayOfWeekHeader({required this.theme});

  final ThemeData theme;

  static const _dayLabels = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];

  @override
  Widget build(BuildContext context) {
    return Row(
      children: _dayLabels
          .map(
            (day) => Expanded(
              child: Container(
                height: 32,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  border: Border(
                    bottom: BorderSide(color: theme.dividerColor),
                  ),
                ),
                child: Text(
                  day,
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
            ),
          )
          .toList(),
    );
  }
}

// ─── Month grid ───────────────────────────────────────────────────────────────

class _MonthGrid extends StatelessWidget {
  const _MonthGrid({
    required this.selectedDate,
    required this.today,
    required this.bookingMap,
    required this.theme,
    required this.onDayTap,
  });

  final DateTime selectedDate;
  final DateTime today;
  final Map<String, _DayBookingSummary> bookingMap;
  final ThemeData theme;
  final ValueChanged<DateTime> onDayTap;

  @override
  Widget build(BuildContext context) {
    final cells = _buildCalendarCells();
    final numRows = cells.length ~/ 7;

    return LayoutBuilder(
      builder: (context, constraints) {
        final cellWidth = constraints.maxWidth / 7;
        final cellHeight = constraints.maxHeight / numRows;
        final aspectRatio = cellWidth / cellHeight;

        return GridView.builder(
          physics: const NeverScrollableScrollPhysics(),
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 7,
            childAspectRatio: aspectRatio,
          ),
          itemCount: cells.length,
          itemBuilder: (context, index) {
            final cell = cells[index];
            return _DayCell(
              cell: cell,
              today: today,
              selectedDate: selectedDate,
              bookingMap: bookingMap,
              theme: theme,
              onTap: cell.isCurrentMonth
                  ? () => onDayTap(cell.date)
                  : null,
            );
          },
        );
      },
    );
  }

  /// Builds the ordered list of calendar cells for the month.
  ///
  /// The first cell is the Monday on or before the first day of the month.
  /// The grid is always complete rows (7 columns × 5 or 6 rows).
  List<_CalendarCell> _buildCalendarCells() {
    final firstDayOfMonth = DateTime(selectedDate.year, selectedDate.month);
    final lastDayOfMonth =
        DateTime(selectedDate.year, selectedDate.month + 1, 0);

    // Find the Monday of the week containing the first day
    final firstMonday = firstDayOfMonth
        .subtract(Duration(days: firstDayOfMonth.weekday - 1));

    // Find the Sunday of the week containing the last day
    final lastSunday = lastDayOfMonth
        .add(Duration(days: 7 - lastDayOfMonth.weekday));

    final cells = <_CalendarCell>[];
    var current = firstMonday;
    while (!current.isAfter(lastSunday)) {
      cells.add(_CalendarCell(
        date: current,
        isCurrentMonth: current.month == selectedDate.month,
      ));
      current = current.add(const Duration(days: 1));
    }

    return cells;
  }
}

class _CalendarCell {
  const _CalendarCell({
    required this.date,
    required this.isCurrentMonth,
  });

  final DateTime date;
  final bool isCurrentMonth;
}

// ─── Individual day cell ──────────────────────────────────────────────────────

class _DayCell extends StatelessWidget {
  const _DayCell({
    required this.cell,
    required this.today,
    required this.selectedDate,
    required this.bookingMap,
    required this.theme,
    this.onTap,
  });

  final _CalendarCell cell;
  final DateTime today;
  final DateTime selectedDate;
  final Map<String, _DayBookingSummary> bookingMap;
  final ThemeData theme;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final date = cell.date;
    final isToday =
        date.year == today.year && date.month == today.month && date.day == today.day;
    final dateKey = _dateKey(date);
    final summary = bookingMap[dateKey];

    return GestureDetector(
      onTap: onTap,
      child: Container(
        decoration: BoxDecoration(
          color: isToday
              ? theme.colorScheme.primaryContainer.withValues(alpha: 0.3)
              : null,
          border: const Border(
            right: BorderSide(color: Color(0xFFE0E0E0), width: 0.5),
            bottom: BorderSide(color: Color(0xFFE0E0E0), width: 0.5),
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.all(4),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Date number
              Text(
                '${date.day}',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: isToday ? FontWeight.w700 : FontWeight.w400,
                  color: !cell.isCurrentMonth
                      ? theme.colorScheme.onSurface.withValues(alpha: 0.3)
                      : isToday
                          ? theme.colorScheme.primary
                          : theme.colorScheme.onSurface,
                ),
              ),

              // Booking count badge
              if (summary != null && summary.count > 0)
                Padding(
                  padding: const EdgeInsets.only(top: 2),
                  child: _BookingCountBadge(
                    count: summary.count,
                    color: summary.badgeColor(theme.colorScheme),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  String _dateKey(DateTime date) {
    return '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
  }
}

// ─── Booking count badge ──────────────────────────────────────────────────────

class _BookingCountBadge extends StatelessWidget {
  const _BookingCountBadge({
    required this.count,
    required this.color,
  });

  final int count;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withValues(alpha: 0.4)),
      ),
      child: Text(
        '$count',
        style: TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.w600,
          color: color,
        ),
      ),
    );
  }
}
