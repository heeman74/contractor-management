import 'package:drift/drift.dart';

import '../../../core/database/app_database.dart';
import '../../../core/sync/sync_handler.dart';

/// SyncHandler implementation for the QuoteLineItem entity.
///
/// Quote line items are pull-only from the sync engine perspective:
/// - Pull: upserts received entities into the local Drift [quoteLineItems] table.
/// - Push: NOT supported — line items are pushed as part of the parent
///   [QuoteSyncHandler] payload, not individually via the sync queue.
///
/// The [push] method throws [StateError] if called, as no line item mutations
/// should ever be queued individually from the mobile client.
class QuoteLineItemSyncHandler extends SyncHandler {
  final AppDatabase _db;

  QuoteLineItemSyncHandler(this._db);

  @override
  String get entityType => 'quote_line_item';

  @override
  Future<void> push(SyncQueueData item) async {
    // Line items are pushed via parent QuoteSyncHandler.
    // If this is ever called, it indicates a programming error.
    throw StateError(
      'QuoteLineItemSyncHandler: push not supported. '
      'Quote line items are pushed via parent QuoteSyncHandler.',
    );
  }

  @override
  Future<void> applyPulled(Map<String, dynamic> data) async {
    final deletedAt = data['deleted_at'] != null
        ? DateTime.parse(data['deleted_at'] as String)
        : null;

    final companion = QuoteLineItemsCompanion(
      id: Value(data['id'] as String),
      companyId: Value(data['company_id'] as String),
      quoteId: Value(data['quote_id'] as String),
      itemType: Value(data['item_type'] as String),
      description: Value(data['description'] as String),
      quantity: Value((data['quantity'] as num).toDouble()),
      unit: Value(data['unit'] as String),
      unitPrice: Value((data['unit_price'] as num).toDouble()),
      sortOrder: data['sort_order'] != null
          ? Value(data['sort_order'] as int)
          : const Value.absent(),
      version: data['version'] != null
          ? Value(data['version'] as int)
          : const Value.absent(),
      createdAt: data['created_at'] != null
          ? Value(DateTime.parse(data['created_at'] as String))
          : const Value.absent(),
      updatedAt: data['updated_at'] != null
          ? Value(DateTime.parse(data['updated_at'] as String))
          : const Value.absent(),
      deletedAt: Value(deletedAt),
    );

    await _db.into(_db.quoteLineItems).insertOnConflictUpdate(companion);
  }
}
