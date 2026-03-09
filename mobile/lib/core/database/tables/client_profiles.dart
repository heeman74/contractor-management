import 'package:drift/drift.dart';
import 'package:uuid/uuid.dart';

import 'companies.dart';
import 'users.dart';

/// Drift table definition for the ClientProfile entity.
///
/// A ClientProfile extends a User (who has the 'client' role) with CRM-specific
/// data. One profile exists per client per company (userId + companyId is
/// effectively unique in practice, enforced at application level).
///
/// [tags] is a JSON-encoded list of string labels.
class ClientProfiles extends Table {
  TextColumn get id => text().clientDefault(() => const Uuid().v4())();
  TextColumn get companyId => text().references(Companies, #id)();

  /// FK to Users.id — the user who has the 'client' role.
  TextColumn get userId => text().references(Users, #id)();

  /// Full billing address as a plain text block (street, city, state, postcode).
  TextColumn get billingAddress => text().nullable()();

  /// JSON-encoded list of string labels for client segmentation.
  TextColumn get tags => text().withDefault(const Constant('[]'))();

  /// Internal admin notes not visible to the client.
  TextColumn get adminNotes => text().nullable()();

  /// How the client was referred to the company (e.g., 'word_of_mouth', 'google').
  TextColumn get referralSource => text().nullable()();

  /// FK to Users.id with contractor role — preferred contractor for this client.
  TextColumn get preferredContractorId => text().nullable()();

  /// Preferred contact method: 'email' | 'phone' | 'sms' | 'app'
  TextColumn get preferredContactMethod => text().nullable()();

  /// Cached average rating (1.0–5.0) from mutual ratings. Recomputed on sync.
  RealColumn get averageRating => real().nullable()();

  IntColumn get version => integer().withDefault(const Constant(1))();
  DateTimeColumn get createdAt => dateTime()();
  DateTimeColumn get updatedAt => dateTime()();

  /// Soft-delete for sync tombstone propagation across devices.
  DateTimeColumn get deletedAt => dateTime().nullable()();

  @override
  Set<Column> get primaryKey => {id};
}
