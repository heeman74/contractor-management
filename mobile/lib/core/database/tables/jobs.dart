import 'package:drift/drift.dart';
import 'package:uuid/uuid.dart';

import 'companies.dart';

/// Drift table definition for the Job entity.
///
/// A Job is the core business entity in ContractorHub. It tracks a piece of
/// work from initial quote through completion and invoicing.
///
/// [statusHistory] is a JSON-encoded list of status transition audit entries:
/// [{status, timestamp, userId, reason}]. SQLite has no JSONB; TEXT is used
/// and decoded at the domain layer.
///
/// [tags] is a JSON-encoded list of string labels for flexible categorisation.
///
/// Both offline creation (Quote stage) and status transitions work offline;
/// the sync handler pushes them when connectivity is restored.
class Jobs extends Table {
  TextColumn get id => text().clientDefault(() => const Uuid().v4())();
  TextColumn get companyId => text().references(Companies, #id)();

  /// FK to Users.id with client role. Nullable — a job may not be
  /// client-linked if created directly by admin.
  TextColumn get clientId => text().nullable()();

  /// FK to Users.id with contractor role. Nullable at Quote stage;
  /// required at Scheduled stage and beyond.
  TextColumn get contractorId => text().nullable()();

  TextColumn get description => text()();

  /// Comma-separated trade type(s). Mirrors TradeType backend enum.
  TextColumn get tradeType => text()();

  /// Lifecycle state. Matches [JobStatus] enum: quote | scheduled |
  /// in_progress | complete | invoiced | cancelled
  TextColumn get status =>
      text().withDefault(const Constant('quote'))();

  /// JSON-encoded audit trail: [{status, timestamp, userId, reason}]
  TextColumn get statusHistory =>
      text().withDefault(const Constant('[]'))();

  /// Priority level: low | medium | high | urgent
  TextColumn get priority =>
      text().withDefault(const Constant('medium'))();

  TextColumn get purchaseOrderNumber => text().nullable()();
  TextColumn get externalReference => text().nullable()();

  /// JSON-encoded list of string tags/labels.
  TextColumn get tags => text().withDefault(const Constant('[]'))();

  TextColumn get notes => text().nullable()();
  IntColumn get estimatedDurationMinutes => integer().nullable()();
  DateTimeColumn get scheduledCompletionDate => dateTime().nullable()();

  IntColumn get version => integer().withDefault(const Constant(1))();
  DateTimeColumn get createdAt => dateTime()();
  DateTimeColumn get updatedAt => dateTime()();

  /// Soft-delete for sync tombstone propagation across devices.
  DateTimeColumn get deletedAt => dateTime().nullable()();

  @override
  Set<Column> get primaryKey => {id};
}
