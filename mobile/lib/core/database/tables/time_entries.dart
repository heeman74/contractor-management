import 'package:drift/drift.dart';
import 'package:uuid/uuid.dart';

/// Drift table definition for the TimeEntry entity.
///
/// A TimeEntry records a clock-in/clock-out session for a contractor on a job.
/// The [TimeEntryDao] enforces one active session per contractor — clocking in
/// while a session is open auto-closes the previous session.
///
/// [sessionStatus] lifecycle:
///   - 'active': contractor is currently clocked in (clockedOutAt is null)
///   - 'completed': clock-out recorded (clockedOutAt and durationSeconds are set)
///   - 'adjusted': admin manually corrected timestamps (captured in adjustmentLog)
///
/// [adjustmentLog] is a JSON-encoded list of adjustment records:
/// [{adjustedBy, originalClockIn, originalClockOut, reason, timestamp}]
/// Stored as TEXT because SQLite has no JSONB.
///
/// [durationSeconds] is computed on clock-out: clockedOutAt - clockedInAt.
/// Stored for fast query/display without re-computation.
class TimeEntries extends Table {
  TextColumn get id => text().clientDefault(() => const Uuid().v4())();

  /// FK to Companies.id — tenant scope.
  TextColumn get companyId => text()();

  /// FK to Jobs.id — the job this time entry is for.
  TextColumn get jobId => text()();

  /// FK to Users.id (contractor role) — the contractor clocking time.
  TextColumn get contractorId => text()();

  /// When the contractor clocked in (device UTC time).
  DateTimeColumn get clockedInAt => dateTime()();

  /// When the contractor clocked out (null while session is active).
  DateTimeColumn get clockedOutAt => dateTime().nullable()();

  /// Total elapsed seconds. Null until clock-out; computed from timestamps.
  IntColumn get durationSeconds => integer().nullable()();

  /// Session state. See class-level documentation.
  TextColumn get sessionStatus =>
      text().withDefault(const Constant('active'))();

  /// JSON-encoded list of admin adjustment records (TEXT, no JSONB in SQLite).
  TextColumn get adjustmentLog =>
      text().withDefault(const Constant('[]'))();

  IntColumn get version => integer().withDefault(const Constant(1))();
  DateTimeColumn get createdAt => dateTime()();
  DateTimeColumn get updatedAt => dateTime()();

  /// Soft-delete for sync tombstone propagation across devices.
  DateTimeColumn get deletedAt => dateTime().nullable()();

  @override
  Set<Column> get primaryKey => {id};
}
