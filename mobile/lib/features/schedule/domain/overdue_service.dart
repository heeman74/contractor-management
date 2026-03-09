/// Pure Dart overdue computation service — no Flutter or external dependencies.
///
/// Computes overdue severity based on scheduled completion date and job status.
/// Used by booking cards to show tiered warning/critical indicators.
///
/// Severity tiers:
///   none     — job is not overdue (not past due, or status is terminal)
///   warning  — 1–3 days overdue (yellow/orange border)
///   critical — 4+ days overdue (red border + warning icon)
class OverdueService {
  OverdueService._(); // Pure static methods — no instantiation needed

  /// Compute the overdue [OverdueSeverity] for a job given its scheduled
  /// completion date.
  ///
  /// Returns [OverdueSeverity.none] if:
  ///   - [scheduledCompletionDate] is null (no deadline set)
  ///   - today is not past the scheduled completion date
  ///
  /// Returns [OverdueSeverity.warning] if 1–3 days overdue.
  /// Returns [OverdueSeverity.critical] if 4+ days overdue.
  ///
  /// Compare whole-day difference: strips time component so a booking on
  /// the scheduled date is not considered overdue until the next calendar day.
  static OverdueSeverity computeSeverity(DateTime? scheduledCompletionDate) {
    if (scheduledCompletionDate == null) return OverdueSeverity.none;

    final now = DateTime.now();
    final todayStart = DateTime(now.year, now.month, now.day);
    final dueDate = DateTime(
      scheduledCompletionDate.year,
      scheduledCompletionDate.month,
      scheduledCompletionDate.day,
    );

    final daysOverdue = todayStart.difference(dueDate).inDays;

    if (daysOverdue <= 0) return OverdueSeverity.none;
    if (daysOverdue <= 3) return OverdueSeverity.warning;
    return OverdueSeverity.critical;
  }

  /// Whether a job with the given [status] and [scheduledCompletionDate] is
  /// considered overdue.
  ///
  /// Only 'scheduled' and 'in_progress' jobs can be overdue — completed,
  /// invoiced, and cancelled jobs are terminal and excluded.
  ///
  /// Returns true if status is active AND today > scheduledCompletionDate.
  static bool isOverdue(String status, DateTime? scheduledCompletionDate) {
    const activeStatuses = {'scheduled', 'in_progress'};
    if (!activeStatuses.contains(status)) return false;
    if (scheduledCompletionDate == null) return false;

    final now = DateTime.now();
    final todayStart = DateTime(now.year, now.month, now.day);
    final dueDate = DateTime(
      scheduledCompletionDate.year,
      scheduledCompletionDate.month,
      scheduledCompletionDate.day,
    );

    return todayStart.isAfter(dueDate);
  }
}

/// Tiered overdue severity for booking card visual indicators.
enum OverdueSeverity {
  /// Job is not overdue — no indicator shown.
  none,

  /// 1–3 days overdue — yellow/orange border indicator.
  warning,

  /// 4+ days overdue — red border + warning icon.
  critical,
}
