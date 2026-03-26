import 'package:drift/drift.dart';
import 'package:uuid/uuid.dart';

import 'companies.dart';

/// Drift table definition for the Invoice entity.
///
/// An Invoice is a payment request sent to a client after a job is complete
/// or at agreed milestones. Invoices may be created from an approved [Quotes]
/// row (via [quoteId]) or independently.
///
/// [taxRate] and [discountValue] are stored as-is; totals are computed by
/// [InvoiceEntity] computed properties (subtotal, discountAmount, taxAmount, total).
///
/// Offline-first: invoices are accessible via InvoiceDao streams. Payment
/// status updates are synced via the outbox queue.
class Invoices extends Table {
  TextColumn get id => text().clientDefault(() => const Uuid().v4())();

  /// FK to Companies.id — tenant scope.
  TextColumn get companyId => text().references(Companies, #id)();

  /// FK to Jobs.id — the job this invoice belongs to.
  /// Nullable for trade-scoped invoices that are not tied to a specific job.
  TextColumn get jobId => text().nullable()();

  /// Soft FK to TradeScopes.id — the trade scope this invoice belongs to.
  /// Populated for per-trade invoices; null for legacy job-based invoices.
  TextColumn get tradeScopeId => text().nullable()();

  /// Soft FK to BillingMilestones.id — the milestone this invoice was raised against.
  /// Null for invoices not tied to a billing milestone.
  TextColumn get milestoneId => text().nullable()();

  /// FK to Quotes.id — the quote this invoice was created from. Nullable if
  /// the invoice was created independently without a quote.
  TextColumn get quoteId => text().nullable()();

  /// Human-readable invoice number (e.g., 'INV-2026-0042').
  TextColumn get invoiceNumber => text()();

  /// Payment status: unpaid | paid | partial | overdue | cancelled.
  TextColumn get status => text().withDefault(const Constant('unpaid'))();

  /// Tax rate as a percentage (e.g., 10.0 for 10%). Applied to subtotal after discount.
  RealColumn get taxRate => real().withDefault(const Constant(0.0))();

  /// Discount type: 'percentage' or 'fixed'. Null if no discount applied.
  TextColumn get discountType => text().nullable()();

  /// Discount value — percentage (0-100) or fixed dollar amount depending on [discountType].
  RealColumn get discountValue => real().withDefault(const Constant(0.0))();

  /// Payment due date. Null means no fixed due date.
  DateTimeColumn get dueDate => dateTime().nullable()();

  /// Timestamp when the invoice was issued/sent to the client.
  DateTimeColumn get issuedAt => dateTime()();

  /// Timestamp when the invoice was finalized (closed — paid or cancelled).
  DateTimeColumn get finalizedAt => dateTime().nullable()();

  IntColumn get version => integer().withDefault(const Constant(1))();
  DateTimeColumn get createdAt => dateTime()();
  DateTimeColumn get updatedAt => dateTime()();

  /// Soft-delete for sync tombstone propagation across devices.
  DateTimeColumn get deletedAt => dateTime().nullable()();

  @override
  Set<Column> get primaryKey => {id};
}
