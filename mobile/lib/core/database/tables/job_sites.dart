import 'package:drift/drift.dart';
import 'package:uuid/uuid.dart';

/// Drift table definition for the JobSite entity.
///
/// A JobSite is a geocoded job location used by bookings. JobSites are
/// created by admin on the backend via geocoding — this table is read-only
/// from the mobile client's perspective (sync pull only, no push).
///
/// [lat] and [lng] store WGS84 coordinates as Real (double precision)
/// which provides ~10cm precision — matching Numeric(9,6) on the backend.
///
/// [formattedAddress] is the geocoder's normalized address string for display.
class JobSites extends Table {
  TextColumn get id => text().clientDefault(() => const Uuid().v4())();

  /// FK to Companies.id — tenant scope.
  TextColumn get companyId => text()();

  /// Raw address string submitted for geocoding.
  TextColumn get address => text()();

  /// Geocoded latitude in WGS84. Nullable — geocoding may fail.
  RealColumn get lat => real().nullable()();

  /// Geocoded longitude in WGS84. Nullable — geocoding may fail.
  RealColumn get lng => real().nullable()();

  /// Geocoder's canonical formatted address for display.
  TextColumn get formattedAddress => text().nullable()();

  IntColumn get version => integer().withDefault(const Constant(1))();
  DateTimeColumn get createdAt => dateTime()();
  DateTimeColumn get updatedAt => dateTime()();

  /// Soft-delete for sync tombstone propagation across devices.
  DateTimeColumn get deletedAt => dateTime().nullable()();

  @override
  Set<Column> get primaryKey => {id};
}
