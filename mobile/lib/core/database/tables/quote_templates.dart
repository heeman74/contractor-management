import 'package:drift/drift.dart';
import 'package:uuid/uuid.dart';

import 'companies.dart';

/// Drift table definition for QuoteTemplate entities.
///
/// A QuoteTemplate is a reusable line-item set with a predefined tax rate.
/// When a quote is created from a template, the line items and tax rate
/// are pre-filled, saving time for common job types.
///
/// [lineItemsJson] stores the template's line items as a JSON array of
/// objects: [{itemType, description, quantity, unit, unitPrice, sortOrder}].
/// JSON TEXT is used because SQLite has no JSONB support; the service layer
/// parses and validates the JSON.
///
/// Templates are local-only (no sync queue) — they are created, managed,
/// and deleted on the device without server synchronisation.
class QuoteTemplates extends Table {
  TextColumn get id => text().clientDefault(() => const Uuid().v4())();

  /// FK to Companies.id — tenant scope.
  TextColumn get companyId => text().references(Companies, #id)();

  /// Display name for the template (e.g., 'Standard Electrical').
  TextColumn get name => text()();

  /// Optional longer description of what the template is for.
  TextColumn get description => text().nullable()();

  /// JSON-encoded line items array. See class doc for schema.
  TextColumn get lineItemsJson => text().withDefault(const Constant('[]'))();

  /// Tax rate as a percentage to pre-fill on quotes created from this template.
  RealColumn get taxRate => real().withDefault(const Constant(0.0))();

  IntColumn get version => integer().withDefault(const Constant(1))();
  DateTimeColumn get createdAt => dateTime()();
  DateTimeColumn get updatedAt => dateTime()();

  /// Soft-delete for local removal without hard deletion.
  DateTimeColumn get deletedAt => dateTime().nullable()();

  @override
  Set<Column> get primaryKey => {id};
}
