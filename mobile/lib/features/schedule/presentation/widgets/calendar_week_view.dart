import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../features/jobs/domain/job_entity.dart';
import '../../../../features/users/domain/user_entity.dart';
import '../../domain/booking_entity.dart';
import '../../domain/overdue_service.dart';
import '../providers/calendar_providers.dart';

/// Week view: collapsed 7-column grid with contractor rows.
///
/// Layout:
///   - Column headers: day abbreviations + date numbers (Mon 10, Tue 11, etc.)
///   - Today's column header highlighted
///   - Contractor rows: contractor name on left, 7 day cells across
///   - Each job card: small colored chip with truncated job description
///   - Overdue jobs get warning/critical border per OverdueService
///   - More than 3 jobs per cell: "+N more" badge with tap to show full list
///
/// Navigation:
///   - Tap day cell: drill down to day view for that date
///   - Swipe left/right: navigate to previous/next week
///   - Contractor pagination: 5 per page (same as day view)
class CalendarWeekView extends ConsumerStatefulWidget {
  const CalendarWeekView({
    required this.bookings,
    required this.contractors,
    required this.jobs,
    super.key,
  });

  /// All bookings for the 7-day week range.
  final List<BookingEntity> bookings;

  /// Contractors for the current page.
  final List<UserEntity> contractors;

  /// Map of jobId → JobEntity for display.
  final Map<String, JobEntity> jobs;

  @override
  ConsumerState<CalendarWeekView> createState() => _CalendarWeekViewState();
}

class _CalendarWeekViewState extends ConsumerState<CalendarWeekView> {
  @override
  Widget build(BuildContext context) {
    final selectedDate = ref.watch(calendarDateProvider);
    final theme = Theme.of(context);

    // Compute the Monday of the selected week
    final weekStart = _getMondayOfWeek(selectedDate);

    // Build 7 days for the week (Mon–Sun)
    final weekDays = List.generate(7, (i) => weekStart.add(Duration(days: i)));
    final today = DateTime.now();
    final todayDate = DateTime(today.year, today.month, today.day);

    return GestureDetector(
      onHorizontalDragEnd: (details) {
        if (details.primaryVelocity == null) return;
        if (details.primaryVelocity! < -300) {
          // Swipe left: next week
          ref.read(calendarDateProvider.notifier).state =
              selectedDate.add(const Duration(days: 7));
        } else if (details.primaryVelocity! > 300) {
          // Swipe right: previous week
          ref.read(calendarDateProvider.notifier).state =
              selectedDate.subtract(const Duration(days: 7));
        }
      },
      child: Column(
        children: [
          // Column headers row
          _WeekHeaderRow(weekDays: weekDays, today: todayDate, theme: theme),

          // Contractor rows
          Expanded(
            child: widget.contractors.isEmpty
                ? const _EmptyWeekPlaceholder()
                : ListView.builder(
                    itemCount: widget.contractors.length,
                    itemBuilder: (context, index) {
                      final contractor = widget.contractors[index];
                      return _ContractorWeekRow(
                        contractor: contractor,
                        weekDays: weekDays,
                        today: todayDate,
                        bookings: widget.bookings
                            .where((b) => b.contractorId == contractor.id)
                            .toList(),
                        jobs: widget.jobs,
                        onDayTap: (date) {
                          // Drill down to day view for tapped date
                          ref.read(calendarDateProvider.notifier).state = date;
                          ref.read(calendarViewModeProvider.notifier).state =
                              CalendarViewMode.day;
                        },
                        theme: theme,
                      );
                    },
                  ),
          ),

          // Pagination controls
          const _WeekPaginationControls(),
        ],
      ),
    );
  }

  /// Returns the Monday of the week containing [date].
  DateTime _getMondayOfWeek(DateTime date) {
    final dayOfWeek = date.weekday; // 1=Mon, 7=Sun
    return DateTime(
      date.year,
      date.month,
      date.day,
    ).subtract(Duration(days: dayOfWeek - 1));
  }
}

// ─── Week header row ──────────────────────────────────────────────────────────

class _WeekHeaderRow extends StatelessWidget {
  const _WeekHeaderRow({
    required this.weekDays,
    required this.today,
    required this.theme,
  });

  final List<DateTime> weekDays;
  final DateTime today;
  final ThemeData theme;

  static const _dayAbbreviations = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];

  @override
  Widget build(BuildContext context) {
    return Container(
      color: theme.colorScheme.surface,
      child: Row(
        children: [
          // Contractor name column header (empty spacer)
          Container(
            width: 72,
            height: 44,
            decoration: BoxDecoration(
              border: Border(
                right: BorderSide(color: theme.dividerColor),
                bottom: BorderSide(color: theme.dividerColor),
              ),
            ),
          ),
          // Day headers
          ...weekDays.asMap().entries.map((entry) {
            final index = entry.key;
            final day = entry.value;
            final isToday = day.year == today.year &&
                day.month == today.month &&
                day.day == today.day;

            return Expanded(
              child: Container(
                height: 44,
                decoration: BoxDecoration(
                  color: isToday
                      ? theme.colorScheme.primaryContainer.withValues(alpha: 0.4)
                      : null,
                  border: Border(
                    right: index < 6
                        ? BorderSide(color: theme.dividerColor)
                        : BorderSide.none,
                    bottom: BorderSide(color: theme.dividerColor),
                  ),
                ),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      _dayAbbreviations[index],
                      style: TextStyle(
                        fontSize: 10,
                        color: isToday
                            ? theme.colorScheme.primary
                            : theme.textTheme.labelSmall?.color,
                        fontWeight:
                            isToday ? FontWeight.w700 : FontWeight.w500,
                      ),
                    ),
                    Text(
                      '${day.day}',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight:
                            isToday ? FontWeight.w700 : FontWeight.w400,
                        color: isToday
                            ? theme.colorScheme.primary
                            : theme.textTheme.bodyMedium?.color,
                      ),
                    ),
                  ],
                ),
              ),
            );
          }),
        ],
      ),
    );
  }
}

// ─── Single contractor week row ────────────────────────────────────────────────

class _ContractorWeekRow extends StatelessWidget {
  const _ContractorWeekRow({
    required this.contractor,
    required this.weekDays,
    required this.today,
    required this.bookings,
    required this.jobs,
    required this.onDayTap,
    required this.theme,
  });

  final UserEntity contractor;
  final List<DateTime> weekDays;
  final DateTime today;
  final List<BookingEntity> bookings;
  final Map<String, JobEntity> jobs;
  final ValueChanged<DateTime> onDayTap;
  final ThemeData theme;

  @override
  Widget build(BuildContext context) {
    final displayName = _contractorName(contractor);

    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Contractor name label
          Container(
            width: 72,
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
            decoration: BoxDecoration(
              color: theme.colorScheme.surface,
              border: Border(
                right: BorderSide(color: theme.dividerColor),
                bottom: BorderSide(color: theme.dividerColor),
              ),
            ),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                CircleAvatar(
                  radius: 10,
                  backgroundColor:
                      theme.colorScheme.primary.withValues(alpha: 0.15),
                  child: Text(
                    _initials(displayName),
                    style: TextStyle(
                      fontSize: 8,
                      fontWeight: FontWeight.w600,
                      color: theme.colorScheme.primary,
                    ),
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  displayName,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontSize: 9),
                ),
              ],
            ),
          ),

          // Day cells
          ...weekDays.asMap().entries.map((entry) {
            final index = entry.key;
            final day = entry.value;
            final isToday = day.year == today.year &&
                day.month == today.month &&
                day.day == today.day;

            // Find bookings for this contractor on this day
            final dayBookings = bookings.where((b) {
              final bDate = DateTime(
                b.timeRangeStart.year,
                b.timeRangeStart.month,
                b.timeRangeStart.day,
              );
              final cellDate = DateTime(day.year, day.month, day.day);
              return bDate == cellDate;
            }).toList();

            return Expanded(
              child: GestureDetector(
                onTap: () => onDayTap(day),
                child: Container(
                  constraints: const BoxConstraints(minHeight: 60),
                  decoration: BoxDecoration(
                    color: isToday
                        ? theme.colorScheme.primaryContainer
                            .withValues(alpha: 0.08)
                        : null,
                    border: Border(
                      right: index < 6
                          ? BorderSide(color: theme.dividerColor)
                          : BorderSide.none,
                      bottom: BorderSide(color: theme.dividerColor),
                    ),
                  ),
                  padding: const EdgeInsets.all(2),
                  child: _DayCellContent(
                    bookings: dayBookings,
                    jobs: jobs,
                    context: context,
                    theme: theme,
                  ),
                ),
              ),
            );
          }),
        ],
      ),
    );
  }

  String _contractorName(UserEntity user) {
    final firstName = user.firstName ?? '';
    final lastName = user.lastName ?? '';
    if (firstName.isNotEmpty && lastName.isNotEmpty) {
      return '$firstName $lastName';
    }
    if (firstName.isNotEmpty) return firstName;
    return user.email.split('@').first;
  }

  String _initials(String name) {
    final parts = name.split(' ');
    if (parts.length >= 2) {
      return '${parts[0][0]}${parts[1][0]}'.toUpperCase();
    }
    return name.isNotEmpty ? name[0].toUpperCase() : '?';
  }
}

// ─── Day cell content ─────────────────────────────────────────────────────────

class _DayCellContent extends StatelessWidget {
  const _DayCellContent({
    required this.bookings,
    required this.jobs,
    required this.context,
    required this.theme,
  });

  final List<BookingEntity> bookings;
  final Map<String, JobEntity> jobs;
  final BuildContext context;
  final ThemeData theme;

  static const _maxVisible = 3;

  @override
  Widget build(BuildContext buildContext) {
    if (bookings.isEmpty) return const SizedBox.shrink();

    final visible = bookings.take(_maxVisible).toList();
    final overflow = bookings.length - _maxVisible;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        ...visible.map((booking) {
          final job = jobs[booking.jobId];
          final status = job?.status ?? 'scheduled';
          final color =
              statusColorMap[status] ?? theme.colorScheme.primary;
          final severity = job != null
              ? OverdueService.computeSeverity(job.scheduledCompletionDate)
              : OverdueSeverity.none;

          Color? borderColor;
          if (severity == OverdueSeverity.critical) {
            borderColor = Colors.red;
          } else if (severity == OverdueSeverity.warning) {
            borderColor = Colors.orange;
          }

          return Container(
            margin: const EdgeInsets.only(bottom: 2),
            padding: const EdgeInsets.symmetric(horizontal: 3, vertical: 1),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(3),
              border: borderColor != null
                  ? Border.all(color: borderColor)
                  : null,
            ),
            child: Text(
              job?.description ?? 'Job',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 9,
                color: color,
                fontWeight: FontWeight.w500,
              ),
            ),
          );
        }),

        // "+N more" overflow badge
        if (overflow > 0)
          GestureDetector(
            onTap: () => _showOverflowPopup(buildContext),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 3, vertical: 1),
              decoration: BoxDecoration(
                color: theme.colorScheme.outlineVariant.withValues(alpha: 0.3),
                borderRadius: BorderRadius.circular(3),
              ),
              child: Text(
                '+$overflow more',
                style: TextStyle(
                  fontSize: 8,
                  color: theme.colorScheme.onSurfaceVariant,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
          ),
      ],
    );
  }

  void _showOverflowPopup(BuildContext context) {
    showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text('${bookings.length} jobs'),
        content: SizedBox(
          width: double.maxFinite,
          child: ListView.separated(
            shrinkWrap: true,
            itemCount: bookings.length,
            separatorBuilder: (_, __) => const Divider(height: 1),
            itemBuilder: (context, index) {
              final booking = bookings[index];
              final job = jobs[booking.jobId];
              final status = job?.status ?? 'scheduled';
              final color = statusColorMap[status] ?? Colors.blue;

              return ListTile(
                dense: true,
                leading: Container(
                  width: 10,
                  height: 10,
                  decoration: BoxDecoration(
                    color: color,
                    shape: BoxShape.circle,
                  ),
                ),
                title: Text(
                  job?.description ?? 'Job',
                  style: const TextStyle(fontSize: 12),
                ),
                subtitle: Text(
                  _formatTimeRange(
                      booking.timeRangeStart, booking.timeRangeEnd),
                  style: const TextStyle(fontSize: 10),
                ),
              );
            },
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  String _formatTimeRange(DateTime start, DateTime end) {
    return '${_formatTime(start)} - ${_formatTime(end)}';
  }

  String _formatTime(DateTime time) {
    final hour = time.hour;
    final minute = time.minute.toString().padLeft(2, '0');
    final period = hour < 12 ? 'AM' : 'PM';
    final h = hour == 0 ? 12 : (hour > 12 ? hour - 12 : hour);
    return '$h:$minute $period';
  }
}

// ─── Pagination controls ──────────────────────────────────────────────────────

class _WeekPaginationControls extends ConsumerWidget {
  const _WeekPaginationControls();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final pageCount = ref.watch(contractorPageCountProvider);
    if (pageCount <= 1) return const SizedBox.shrink();

    final pageIndex = ref.watch(contractorPageIndexProvider);

    return Container(
      height: 40,
      color: Theme.of(context).colorScheme.surface,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          IconButton(
            icon: const Icon(Icons.chevron_left),
            onPressed: pageIndex > 0
                ? () => ref.read(contractorPageIndexProvider.notifier).state =
                    pageIndex - 1
                : null,
            iconSize: 20,
            padding: EdgeInsets.zero,
            constraints:
                const BoxConstraints(minWidth: 36, minHeight: 36),
          ),
          Text(
            'Page ${pageIndex + 1} of $pageCount',
            style: const TextStyle(fontSize: 12),
          ),
          IconButton(
            icon: const Icon(Icons.chevron_right),
            onPressed: pageIndex < pageCount - 1
                ? () => ref.read(contractorPageIndexProvider.notifier).state =
                    pageIndex + 1
                : null,
            iconSize: 20,
            padding: EdgeInsets.zero,
            constraints:
                const BoxConstraints(minWidth: 36, minHeight: 36),
          ),
        ],
      ),
    );
  }
}

// ─── Empty state ──────────────────────────────────────────────────────────────

class _EmptyWeekPlaceholder extends StatelessWidget {
  const _EmptyWeekPlaceholder();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.people_outline, size: 48, color: Colors.grey[400]),
          const SizedBox(height: 12),
          Text(
            'No contractors found',
            style: TextStyle(color: Colors.grey[600], fontSize: 14),
          ),
        ],
      ),
    );
  }
}
