import 'package:freezed_annotation/freezed_annotation.dart';

part 'time_entry_entity.freezed.dart';
part 'time_entry_entity.g.dart';

/// Freezed domain entity for a TimeEntry.
///
/// Represents a clock-in/clock-out session for a contractor on a job.
/// Created offline via [TimeEntryDao.clockIn]; completed via [TimeEntryDao.clockOut].
///
/// [sessionStatus] lifecycle:
///   - 'active': contractor is currently clocked in
///   - 'completed': clock-out recorded
///   - 'adjusted': admin manually corrected
///
/// [adjustmentLog] is a JSON-encoded string (TEXT in SQLite, no JSONB).
/// Parsed by the domain service when displaying adjustment history.
@freezed
abstract class TimeEntryEntity with _$TimeEntryEntity {
  const TimeEntryEntity._(); // Allow custom getters on the generated class

  const factory TimeEntryEntity({
    required String id,
    required String companyId,
    required String jobId,
    required String contractorId,
    required DateTime clockedInAt,
    DateTime? clockedOutAt,
    int? durationSeconds,
    required String sessionStatus,
    required String adjustmentLog,
    required int version,
    required DateTime createdAt,
    required DateTime updatedAt,
    DateTime? deletedAt,
  }) = _TimeEntryEntity;

  factory TimeEntryEntity.fromJson(Map<String, dynamic> json) =>
      _$TimeEntryEntityFromJson(json);

  /// True while the contractor is actively clocked in (no clock-out recorded).
  bool get isActive => clockedOutAt == null;
}
