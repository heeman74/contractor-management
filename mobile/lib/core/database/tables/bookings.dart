import 'package:drift/drift.dart';
import 'package:uuid/uuid.dart';

/// Drift table definition for the Booking entity.
///
/// A Booking represents a scheduled time block for a contractor. It mirrors
/// the backend Booking model and the TSTZRANGE stored on the server as
/// discrete [timeRangeStart] and [timeRangeEnd] DateTime columns in SQLite.
///
/// Multi-day jobs generate multiple Booking rows linked by [parentBookingId],
/// distinguished by [dayIndex] (0-based). Single-day bookings have null
/// [dayIndex] and null [parentBookingId].
///
/// Offline-first: bookings are created locally via BookingDao (with outbox
/// dual-write) and synced to the backend when connectivity is restored.
class Bookings extends Table {
  TextColumn get id => text().clientDefault(() => const Uuid().v4())();

  /// FK to Companies.id — tenant scope.
  TextColumn get companyId => text()();

  /// FK to Users.id (contractor role) — the contractor this booking is for.
  TextColumn get contractorId => text()();

  /// FK to Jobs.id — the job this booking is associated with.
  TextColumn get jobId => text()();

  /// FK to JobSites.id — nullable (job site may not be set at booking time).
  TextColumn get jobSiteId => text().nullable()();

  /// Start of the scheduled time block (UTC).
  DateTimeColumn get timeRangeStart => dateTime()();

  /// End of the scheduled time block (UTC).
  DateTimeColumn get timeRangeEnd => dateTime()();

  /// 0-based index for multi-day bookings. Null for single-day bookings.
  IntColumn get dayIndex => integer().nullable()();

  /// Links all booking records for the same multi-day job.
  /// Null for single-day bookings or the first day of a multi-day job.
  TextColumn get parentBookingId => text().nullable()();

  /// Optional notes/instructions for this booking.
  TextColumn get notes => text().nullable()();

  IntColumn get version => integer().withDefault(const Constant(1))();
  DateTimeColumn get createdAt => dateTime()();
  DateTimeColumn get updatedAt => dateTime()();

  /// Soft-delete for sync tombstone propagation across devices.
  DateTimeColumn get deletedAt => dateTime().nullable()();

  @override
  Set<Column> get primaryKey => {id};
}
