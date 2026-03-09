import 'package:drift/drift.dart';
import 'package:uuid/uuid.dart';

import 'companies.dart';

/// Drift table definition for a client's saved property (job-site address).
///
/// Clients can save multiple property addresses for quick re-use when submitting
/// job requests. One can be marked as the default.
///
/// [jobSiteId] references a JobSite record from the Phase 3 scheduling engine
/// (stored on the backend; the UUID is synced to the mobile device).
class ClientProperties extends Table {
  TextColumn get id => text().clientDefault(() => const Uuid().v4())();
  TextColumn get companyId => text().references(Companies, #id)();

  /// FK to the client (Users.id with client role).
  TextColumn get clientId => text()();

  /// UUID of the corresponding JobSite record (Phase 3 scheduling engine).
  /// Stored as plain text — JobSite table is not present in mobile Drift schema.
  TextColumn get jobSiteId => text()();

  /// User-friendly label for this saved address (e.g., 'Home', 'Office').
  TextColumn get nickname => text().nullable()();

  /// Whether this is the client's primary/default property.
  BoolColumn get isDefault =>
      boolean().withDefault(const Constant(false))();

  IntColumn get version => integer().withDefault(const Constant(1))();
  DateTimeColumn get createdAt => dateTime()();
  DateTimeColumn get updatedAt => dateTime()();

  /// Soft-delete for sync tombstone propagation across devices.
  DateTimeColumn get deletedAt => dateTime().nullable()();

  @override
  Set<Column> get primaryKey => {id};
}
