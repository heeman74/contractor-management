import 'package:drift/drift.dart';
import 'package:uuid/uuid.dart';

import 'companies.dart';

/// Drift table definition for the JobRequest entity.
///
/// A JobRequest is a client-initiated enquiry before a formal Job exists.
/// Clients (or anonymous web form submitters) describe their need; admins
/// review the queue and either Accept (creating a Job) or Decline (with reason).
///
/// [photos] is a JSON-encoded list of file paths/URLs for attached photos.
/// [status] lifecycle: pending → accepted | declined
class JobRequests extends Table {
  TextColumn get id => text().clientDefault(() => const Uuid().v4())();
  TextColumn get companyId => text().references(Companies, #id)();

  /// FK to Users.id (client role). Null for anonymous web form submissions
  /// until a User account is created/matched on the backend.
  TextColumn get clientId => text().nullable()();

  TextColumn get description => text()();

  /// Requested trade type (may be null if client is unsure).
  TextColumn get tradeType => text().nullable()();

  /// Urgency level: normal | urgent | emergency
  TextColumn get urgency =>
      text().withDefault(const Constant('normal'))();

  DateTimeColumn get preferredDateStart => dateTime().nullable()();
  DateTimeColumn get preferredDateEnd => dateTime().nullable()();

  RealColumn get budgetMin => real().nullable()();
  RealColumn get budgetMax => real().nullable()();

  /// JSON-encoded list of photo file paths or URLs (1–5 photos).
  TextColumn get photos => text().withDefault(const Constant('[]'))();

  /// Request status: pending | accepted | declined
  TextColumn get requestStatus =>
      text().withDefault(const Constant('pending'))();

  /// Short reason code for decline (required when status = 'declined').
  TextColumn get declineReason => text().nullable()();

  /// Optional longer decline message shown to the client.
  TextColumn get declineMessage => text().nullable()();

  /// UUID of the Job created when this request is accepted. Null until accepted.
  TextColumn get convertedJobId => text().nullable()();

  // Anonymous web form submitter fields (populated if clientId is null):
  TextColumn get submittedName => text().nullable()();
  TextColumn get submittedEmail => text().nullable()();
  TextColumn get submittedPhone => text().nullable()();

  IntColumn get version => integer().withDefault(const Constant(1))();
  DateTimeColumn get createdAt => dateTime()();
  DateTimeColumn get updatedAt => dateTime()();

  /// Soft-delete for sync tombstone propagation across devices.
  DateTimeColumn get deletedAt => dateTime().nullable()();

  @override
  Set<Column> get primaryKey => {id};
}
