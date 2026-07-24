/// Shared date formatting utilities (no intl dependency).
class DateFormatUtils {
  DateFormatUtils._();

  static const _weekdays = [
    'Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday', 'Sunday',
  ];
  static const _months = [
    'January', 'February', 'March', 'April', 'May', 'June',
    'July', 'August', 'September', 'October', 'November', 'December',
  ];
  static const _monthsShort = [
    'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
    'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
  ];

  /// Format a [DateTime] as "Mar 26, 2025 3:07 PM" (no intl dependency).
  static String formatDateTime(DateTime dateTime) {
    final hour = dateTime.hour % 12 == 0 ? 12 : dateTime.hour % 12;
    final minute = dateTime.minute.toString().padLeft(2, '0');
    final meridiem = dateTime.hour < 12 ? 'AM' : 'PM';
    final month = _monthsShort[dateTime.month - 1];
    return '$month ${dateTime.day}, ${dateTime.year} $hour:$minute $meridiem';
  }

  /// Format a [DateTime] as "Wednesday, March 26" (no intl dependency).
  static String formatReadableDate(DateTime date) {
    final weekday = _weekdays[date.weekday - 1];
    final month = _months[date.month - 1];
    return '$weekday, $month ${date.day}';
  }

  /// Format a [DateTime] as "March 26, 2025" (full month + year).
  static String formatLongDate(DateTime date) {
    final month = _months[date.month - 1];
    return '$month ${date.day}, ${date.year}';
  }

  /// Human-friendly elapsed time: "just now", "5m ago", "3h ago",
  /// "Yesterday", then a short "Mon D" date for older timestamps.
  static String relativeTime(DateTime dateTime) {
    final difference = DateTime.now().difference(dateTime);
    if (difference.inMinutes < 1) return 'just now';
    if (difference.inHours < 1) return '${difference.inMinutes}m ago';
    if (difference.inHours < 24) return '${difference.inHours}h ago';
    if (difference.inDays == 1) return 'Yesterday';
    final local = dateTime.toLocal();
    return '${_monthsShort[local.month - 1]} ${local.day}';
  }

  /// Format a [DateTime] as "D/M/YYYY".
  static String formatNumericDate(DateTime date) =>
      '${date.day}/${date.month}/${date.year}';

  /// Returns today's date as an ISO date string (YYYY-MM-DD).
  static String todayDateStr() {
    final now = DateTime.now();
    return '${now.year.toString().padLeft(4, '0')}'
        '-${now.month.toString().padLeft(2, '0')}'
        '-${now.day.toString().padLeft(2, '0')}';
  }
}
