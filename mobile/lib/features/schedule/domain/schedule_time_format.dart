import 'schedule_constants.dart';

/// Time and duration formatting shared across schedule widgets.
///
/// Consolidates the identical `_formatTime` / `_formatTimeRange` /
/// `_formatDuration` helpers that were previously duplicated in every
/// calendar widget and screen.
class ScheduleTimeFormat {
  ScheduleTimeFormat._();

  /// Formats a [DateTime] as a 12-hour clock time, e.g. "3:07 PM".
  static String time(DateTime dateTime) {
    final minute = dateTime.minute.toString().padLeft(2, '0');
    final period = dateTime.hour < 12 ? 'AM' : 'PM';
    final hour = dateTime.hour == 0
        ? 12
        : (dateTime.hour > 12 ? dateTime.hour - 12 : dateTime.hour);
    return '$hour:$minute $period';
  }

  /// Formats a start/end pair as "3:00 PM - 4:30 PM".
  static String range(DateTime start, DateTime end) =>
      '${time(start)} - ${time(end)}';

  /// Formats a minute count as "45m", "2h", or "1h 30m".
  static String duration(int minutes) {
    if (minutes < ScheduleConstants.minutesPerHour) return '${minutes}m';
    final hours = minutes ~/ ScheduleConstants.minutesPerHour;
    final remainder = minutes % ScheduleConstants.minutesPerHour;
    return remainder == 0 ? '${hours}h' : '${hours}h ${remainder}m';
  }
}
