/// Shared scheduling constants used across the calendar/lane widgets.
///
/// Replaces magic numbers scattered through the schedule presentation layer.
abstract final class ScheduleConstants {
  /// First visible working hour (calendar slots start here).
  static const int workingHoursStart = 6; // 06:00

  /// Last visible working hour (calendar slots end here).
  static const int workingHoursEnd = 20; // 20:00

  /// Granularity of a draggable calendar slot, in minutes.
  static const int slotMinutes = 15;

  /// Default booking duration when a job has no estimate, in minutes.
  static const int defaultBookingMinutes = 60;

  /// Bookings longer than this trigger the multi-day scheduling wizard.
  static const int multiDayThresholdMinutes = 480; // 8 hours

  static const int minutesPerHour = 60;

  /// Gaps up to this length between consecutive bookings are treated as
  /// travel buffers; larger gaps count as free time.
  static const int maxTravelBufferMinutes = 60;

  /// Contractor lanes shown per calendar page.
  static const int contractorsPerPage = 5;

  /// Maximum number of booking operations retained for undo.
  static const int maxUndoDepth = 10;

  /// Pixels per minute for the time axis and booking card sizing
  /// (2.0 px/min = 120px/hour).
  static const double pixelsPerMinute = 2.0;
}

/// Reasons recorded on a [BlockedInterval]. Centralized to avoid magic
/// strings when creating and matching blocked/travel intervals.
abstract final class BlockedIntervalReason {
  static const String travelBuffer = 'travel_buffer';
  static const String outsideWorkingHours = 'outside_working_hours';
}
