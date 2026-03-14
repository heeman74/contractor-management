import 'package:drift/drift.dart';
import 'package:uuid/uuid.dart';

import 'companies.dart';

/// Drift table definition for InvoiceLineItem entities.
///
/// Line items belong to a parent [Invoices] row and represent individual
/// billable items on an invoice. The structure mirrors [QuoteLineItems] —
/// when an invoice is created from a quote, line items are copied over.
///
/// Line items are synced as children of their parent invoice — the parent
/// sync payload includes the full line_items array.
///
/// [sortOrder] controls display order in the UI.
class InvoiceLineItems extends Table {
  TextColumn get id => text().clientDefault(() => const Uuid().v4())();

  /// FK to Companies.id — tenant scope.
  TextColumn get companyId => text().references(Companies, #id)();

  /// FK to Invoices.id — the invoice this line item belongs to.
  TextColumn get invoiceId => text()();

  /// Item type: 'labor' or 'material'.
  TextColumn get itemType => text()();

  /// Description of the line item (e.g., 'Replace circuit breaker').
  TextColumn get description => text()();

  /// Quantity of units (e.g., 3.0 hours, 5 units).
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
