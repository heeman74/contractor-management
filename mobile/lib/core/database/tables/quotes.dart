import 'package:drift/drift.dart';
import 'package:uuid/uuid.dart';

import 'companies.dart';

/// Drift table definition for the Quote entity.
///
/// A Quote is a price estimate sent to a client before a job begins.
/// Quotes have line items (see [QuoteLineItems]) and go through a lifecycle:
/// draft → sent → viewed → approved/declined.
///
/// [taxRate] and [discountValue] are stored as-is; totals are computed by
/// [QuoteEntity] computed properties (subtotal, discountAmount, taxAmount, total).
///
/// Offline-first: quotes are created locally via QuoteDao (with outbox
/// dual-write) and synced to the backend when connectivity is restored.
class Quotes extends Table {
  TextColumn get id => text().clientDefault(() => const Uuid().v4())();

  /// FK to Companies.id — tenant scope.
  TextColumn get companyId => text().references(Companies, #id)();

  /// FK to Jobs.id — the job this quote belongs to.
  /// Nullable for trade-scoped quotes that are not tied to a specific job.
  TextColumn get jobId => text().nullable()();

  /// Soft FK to TradeScopes.id — the trade scope this quote belongs to.
  /// Populated for per-trade quotes; null for legacy job-based quotes.
  TextColumn get tradeScopeId => text().nullable()();

  /// Lifecycle state: draft | sent | viewed | approved | declined | expired.
  TextColumn get status => text().withDefault(const Constant('draft'))();

  /// Revision number for tracking quote iterations (starts at 1).
  IntColumn get revisionNumber => integer().withDefault(const Constant(1))();

  /// Tax rate as a percentage (e.g., 10.0 for 10%). Applied to subtotal after discount.
  RealColumn get taxRate => real().withDefault(const Constant(0.0))();

  /// Discount type: 'percentage' or 'fixed'. Null if no discount applied.
  TextColumn get discountType => text().nullable()();

  /// Discount value — percentage (0-100) or fixed dollar amount depending on [discountType].
  RealColumn get discountValue => real().withDefault(const Constant(0.0))();

  /// Date after which the quote is no longer valid. Null means no expiry.
  DateTimeColumn get expiryDate => dateTime().nullable()();

  /// Timestamp when the quote was sent to the client. Null if not yet sent.
  DateTimeColumn get sentAt => dateTime().nullable()();

  /// Timestamp when the client first viewed the quote. Null if not yet viewed.
  DateTimeColumn get viewedAt => dateTime().nullable()();

  /// Timestamp when the client approved the quote. Null if not approved.
  DateTimeColumn get approvedAt => dateTime().nullable()();

  /// Timestamp when the client declined the quote. Null if not declined.
  DateTimeColumn get declinedAt => dateTime().nullable()();

  /// Brief reason for declining (e.g., 'too_expensive', 'not_needed').
  TextColumn get declineReason => text().nullable()();

  /// Additional decline detail text provided by the client.
  TextColumn get declineDetail => text().nullable()();

  /// Internal notes for admins/contractors — not visible to clients.
  TextColumn get adminNotes => text().nullable()();

  IntColumn get version => integer().withDefault(const Constant(1))();
  DateTimeColumn get createdAt => dateTime()();
  DateTimeColumn get updatedAt => dateTime()();

  /// Soft-delete for sync tombstone propagation across devices.
  DateTimeColumn get deletedAt => dateTime().nullable()();

  @override
  Set<Column> get primaryKey => {id};
}
