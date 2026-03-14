import 'package:drift/drift.dart';
import 'package:uuid/uuid.dart';

import 'companies.dart';

/// Drift table definition for QuoteLineItem entities.
///
/// Line items belong to a parent [Quotes] row and represent individual
/// billable items on a quote. Each item has a type (labor or material),
/// quantity, unit, and unit price.
///
/// Line items are synced as children of their parent quote — the parent
/// sync payload includes the full line_items array.
///
/// [sortOrder] controls display order in the UI.
class QuoteLineItems extends Table {
  TextColumn get id => text().clientDefault(() => const Uuid().v4())();

  /// FK to Companies.id — tenant scope.
  TextColumn get companyId => text().references(Companies, #id)();

  /// FK to Quotes.id — the quote this line item belongs to.
  TextColumn get quoteId => text()();

  /// Item type: 'labor' or 'material'.
  TextColumn get itemType => text()();

  /// Description of the line item (e.g., 'Install smoke detectors').
  TextColumn get description => text()();

  /// Quantity of units (e.g., 2.5 hours, 10 units).
  RealColumn get quantity => real()();

  /// Unit label (e.g., 'hr', 'unit', 'm2').
  TextColumn get unit => text()();

  /// Price per unit in the company's currency.
  RealColumn get unitPrice => real()();

  /// Display sort order (ascending). Lower values appear first.
  IntColumn get sortOrder => integer().withDefault(const Constant(0))();

  IntColumn get version => integer().withDefault(const Constant(1))();
  DateTimeColumn get createdAt => dateTime()();
  DateTimeColumn get updatedAt => dateTime()();

  /// Soft-delete for sync tombstone propagation across devices.
  DateTimeColumn get deletedAt => dateTime().nullable()();

  @override
  Set<Column> get primaryKey => {id};
}
