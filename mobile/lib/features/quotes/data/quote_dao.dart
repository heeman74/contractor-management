import 'dart:convert';

import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:uuid/uuid.dart';

import '../../../core/database/app_database.dart';
import '../../../core/database/tables/quote_line_items.dart';
import '../../../core/database/tables/quote_templates.dart';
import '../../../core/database/tables/quotes.dart';
import '../../../core/database/tables/sync_queue.dart';
import '../domain/line_item_entity.dart';
import '../domain/quote_entity.dart';

part 'quote_dao.g.dart';

/// Drift DAO for Quote CRUD with transactional outbox dual-write.
///
/// All read methods return [Stream] — offline-first, reactive to local DB changes.
///
/// Every mutating method uses [db.transaction] to atomically write to BOTH
/// the quotes/quote_line_items tables AND the sync_queue outbox. If either
/// write fails, both are rolled back — no orphaned queue items, no untracked mutations.
///
/// Template operations (watchTemplates, createTemplate, deleteTemplate) are
/// local-only and do NOT write to the sync_queue — templates are never synced.
///
/// [upsertFromSync] is the sync-pull path and does NOT write to the
/// sync_queue — this IS the sync; writing to the queue would cause an infinite loop.
@DriftAccessor(
  tables: [Quotes, QuoteLineItems, QuoteTemplates, SyncQueue],
)
class QuoteDao extends DatabaseAccessor<AppDatabase> with _$QuoteDaoMixin {
  QuoteDao(super.db);

  // ────────────────────────────────────────────────────────────────────────
  // Quote streams
  // ────────────────────────────────────────────────────────────────────────

  /// Reactive stream of all non-deleted quotes for a job.
  ///
  /// Ordered by revisionNumber descending (latest revision first).
  /// Each [QuoteEntity] is populated with its line items via a two-query
  /// approach (parent + children) to avoid duplicate parent rows from JOIN.
  Stream<List<QuoteEntity>> watchQuotesForJob(String jobId) {
    final parentQuery = (select(quotes)
          ..where(
            (tbl) =>
                tbl.jobId.equals(jobId) & tbl.deletedAt.isNull(),
          )
          ..orderBy([(tbl) => OrderingTerm.desc(tbl.revisionNumber)]))
        .watch();

    return parentQuery.asyncMap(_populateLineItems);
  }

  /// Reactive stream of all non-deleted quotes for a trade scope.
  ///
  /// Ordered by revisionNumber descending (latest revision first).
  /// Each [QuoteEntity] is populated with its line items via a two-query
  /// approach (parent + children) to avoid duplicate parent rows from JOIN.
  Stream<List<QuoteEntity>> watchQuotesForScope(String scopeId) {
    final parentQuery = (select(quotes)
          ..where(
            (tbl) =>
                tbl.tradeScopeId.equals(scopeId) & tbl.deletedAt.isNull(),
          )
          ..orderBy([(tbl) => OrderingTerm.desc(tbl.revisionNumber)]))
        .watch();

    return parentQuery.asyncMap(_populateLineItems);
  }

  /// Reactive stream of a single quote with its line items.
  ///
  /// Emits null if the quote is not found or has been soft-deleted.
  Stream<QuoteEntity?> watchQuote(String quoteId) {
    final parentQuery = (select(quotes)
          ..where(
            (tbl) =>
                tbl.id.equals(quoteId) & tbl.deletedAt.isNull(),
          )
          ..limit(1))
        .watch();

    return parentQuery.asyncMap((rows) async {
      if (rows.isEmpty) return null;
      final populated = await _populateLineItems([rows.first]);
      return populated.firstOrNull;
    });
  }

  /// Stream of all non-deleted quotes. Used for sync listing.
  Stream<List<QuoteEntity>> getAllQuotes() {
    final parentQuery = (select(quotes)
          ..where((tbl) => tbl.deletedAt.isNull()))
        .watch();

    return parentQuery.asyncMap(_populateLineItems);
  }

  // ────────────────────────────────────────────────────────────────────────
  // Quote mutations (transactional outbox dual-write pattern)
  // ────────────────────────────────────────────────────────────────────────

  /// Insert a new quote and its line items, and atomically enqueue a CREATE sync item.
  ///
  /// The parent quote + all line items + sync_queue entry are written in a
  /// single transaction. Returns the generated quote UUID.
  Future<String> createQuote(QuoteEntity entity) async {
    await db.transaction(() async {
      final now = DateTime.now();

      // Insert parent quote row
      await into(quotes).insert(
        QuotesCompanion.insert(
          id: Value(entity.id),
          companyId: entity.companyId,
          jobId: Value(entity.jobId),
          tradeScopeId: Value(entity.tradeScopeId),
          status: Value(entity.status),
          revisionNumber: Value(entity.revisionNumber),
          taxRate: Value(entity.taxRate),
          discountType: Value(entity.discountType),
          discountValue: Value(entity.discountValue),
          expiryDate: Value(entity.expiryDate),
          sentAt: Value(entity.sentAt),
          viewedAt: Value(entity.viewedAt),
          approvedAt: Value(entity.approvedAt),
          declinedAt: Value(entity.declinedAt),
          declineReason: Value(entity.declineReason),
          declineDetail: Value(entity.declineDetail),
          adminNotes: Value(entity.adminNotes),
          createdAt: entity.createdAt,
          updatedAt: entity.updatedAt,
        ),
      );

      // Insert all line item rows
      for (final item in entity.lineItems) {
        await into(quoteLineItems).insert(
          QuoteLineItemsCompanion.insert(
            id: Value(item.id),
            companyId: entity.companyId,
            quoteId: entity.id,
            itemType: item.itemType,
            description: item.description,
            quantity: item.quantity,
            unit: item.unit,
            unitPrice: item.unitPrice,
            sortOrder: Value(item.sortOrder),
            createdAt: now,
            updatedAt: now,
          ),
        );
      }

      // Enqueue sync CREATE with parent + line items payload
      await into(syncQueue).insert(
        _buildQueueEntry(
          entityType: 'quote',
          entityId: entity.id,
          operation: 'CREATE',
          payload: _buildQuotePayload(entity),
        ),
      );
    });

    return entity.id;
  }

  /// Update an existing quote and replace all its line items.
  ///
  /// Soft-deletes existing line items and inserts the new set. Enqueues UPDATE.
  Future<void> updateQuote(QuoteEntity entity) async {
    await db.transaction(() async {
      final now = DateTime.now();

      // Update parent quote
      await (update(quotes)..where((tbl) => tbl.id.equals(entity.id))).write(
        QuotesCompanion(
          status: Value(entity.status),
          revisionNumber: Value(entity.revisionNumber),
          taxRate: Value(entity.taxRate),
          discountType: Value(entity.discountType),
          discountValue: Value(entity.discountValue),
          expiryDate: Value(entity.expiryDate),
          sentAt: Value(entity.sentAt),
          viewedAt: Value(entity.viewedAt),
          approvedAt: Value(entity.approvedAt),
          declinedAt: Value(entity.declinedAt),
          declineReason: Value(entity.declineReason),
          declineDetail: Value(entity.declineDetail),
          adminNotes: Value(entity.adminNotes),
          updatedAt: Value(now),
        ),
      );

      // Soft-delete existing line items for this quote
      await (update(quoteLineItems)
            ..where((tbl) => tbl.quoteId.equals(entity.id)))
          .write(QuoteLineItemsCompanion(deletedAt: Value(now)));

      // Insert new line items
      for (final item in entity.lineItems) {
        await into(quoteLineItems).insert(
          QuoteLineItemsCompanion.insert(
            id: Value(item.id),
            companyId: entity.companyId,
            quoteId: entity.id,
            itemType: item.itemType,
            description: item.description,
            quantity: item.quantity,
            unit: item.unit,
            unitPrice: item.unitPrice,
            sortOrder: Value(item.sortOrder),
            createdAt: now,
            updatedAt: now,
          ),
        );
      }

      // Enqueue sync UPDATE
      await into(syncQueue).insert(
        _buildQueueEntry(
          entityType: 'quote',
          entityId: entity.id,
          operation: 'UPDATE',
          payload: _buildQuotePayload(entity),
        ),
      );
    });
  }

  /// Soft-delete a quote and enqueue a DELETE sync item.
  Future<void> deleteQuote(String quoteId) async {
    final now = DateTime.now();

    await db.transaction(() async {
      await (update(quotes)..where((tbl) => tbl.id.equals(quoteId)))
          .write(QuotesCompanion(deletedAt: Value(now)));

      await into(syncQueue).insert(
        _buildQueueEntry(
          entityType: 'quote',
          entityId: quoteId,
          operation: 'DELETE',
          payload: {'id': quoteId, 'deleted_at': now.toIso8601String()},
        ),
      );
    });
  }

  // ────────────────────────────────────────────────────────────────────────
  // Template operations (local only — no sync queue)
  // ────────────────────────────────────────────────────────────────────────

  /// Reactive stream of all non-deleted quote templates.
  Stream<List<QuoteTemplate>> watchTemplates() {
    return (select(quoteTemplates)
          ..where((tbl) => tbl.deletedAt.isNull())
          ..orderBy([(tbl) => OrderingTerm.asc(tbl.name)]))
        .watch();
  }

  /// Create a new quote template. Local only — not synced.
  Future<void> createTemplate({
    required String companyId,
    required String name,
    required String lineItemsJson,
    required double taxRate,
    String? description,
  }) async {
    final now = DateTime.now();
    await into(quoteTemplates).insert(
      QuoteTemplatesCompanion.insert(
        id: Value(const Uuid().v4()),
        companyId: companyId,
        name: name,
        description: Value(description),
        lineItemsJson: Value(lineItemsJson),
        taxRate: Value(taxRate),
        createdAt: now,
        updatedAt: now,
      ),
    );
  }

  /// Soft-delete a quote template by id. Local only — not synced.
  Future<void> deleteTemplate(String templateId) async {
    await (update(quoteTemplates)
          ..where((tbl) => tbl.id.equals(templateId)))
        .write(QuoteTemplatesCompanion(deletedAt: Value(DateTime.now())));
  }

  // ────────────────────────────────────────────────────────────────────────
  // Sync pull upsert
  // ────────────────────────────────────────────────────────────────────────

  /// Upsert a quote and its line items from a sync pull response.
  ///
  /// Processes the nested [line_items] array: upserts each child row.
  /// No sync_queue entry — this IS the sync pull; writing to the queue
  /// would cause an infinite sync loop.
  Future<void> upsertFromSync(Map<String, dynamic> data) async {
    final id = data['id'];
    final companyId = data['company_id'];
    if (id is! String || companyId is! String) {
      throw FormatException(
        'Quote missing required fields: id=${id.runtimeType}, '
        'company_id=${companyId.runtimeType}',
      );
    }
    await db.transaction(() async {
      final companion = QuotesCompanion(
        id: Value(id),
        companyId: Value(companyId),
        jobId: Value(data['job_id'] as String?),
        tradeScopeId: Value(data['trade_scope_id'] as String?),
        status: data['status'] != null ? Value(data['status'] as String) : const Value.absent(),
        revisionNumber: data['revision_number'] != null ? Value(data['revision_number'] as int) : const Value.absent(),
        taxRate: data['tax_rate'] != null ? Value((data['tax_rate'] as num).toDouble()) : const Value.absent(),
        discountType: Value(data['discount_type'] as String?),
        discountValue: data['discount_value'] != null ? Value((data['discount_value'] as num).toDouble()) : const Value.absent(),
        expiryDate: Value(data['expiry_date'] != null ? DateTime.parse(data['expiry_date'] as String) : null),
        sentAt: Value(data['sent_at'] != null ? DateTime.parse(data['sent_at'] as String) : null),
        viewedAt: Value(data['viewed_at'] != null ? DateTime.parse(data['viewed_at'] as String) : null),
        approvedAt: Value(data['approved_at'] != null ? DateTime.parse(data['approved_at'] as String) : null),
        declinedAt: Value(data['declined_at'] != null ? DateTime.parse(data['declined_at'] as String) : null),
        declineReason: Value(data['decline_reason'] as String?),
        declineDetail: Value(data['decline_detail'] as String?),
        adminNotes: Value(data['admin_notes'] as String?),
        version: data['version'] != null ? Value(data['version'] as int) : const Value.absent(),
        createdAt: data['created_at'] != null ? Value(DateTime.parse(data['created_at'] as String)) : const Value.absent(),
        updatedAt: data['updated_at'] != null ? Value(DateTime.parse(data['updated_at'] as String)) : const Value.absent(),
        deletedAt: Value(data['deleted_at'] != null ? DateTime.parse(data['deleted_at'] as String) : null),
      );

      await into(quotes).insertOnConflictUpdate(companion);

      // Process nested line items
      final lineItemsData = data['line_items'];
      if (lineItemsData is List) {
        for (final item in lineItemsData) {
          if (item is! Map<String, dynamic>) continue;
          final itemCompanion = QuoteLineItemsCompanion(
            id: Value(item['id'] as String),
            companyId: Value(data['company_id'] as String),
            quoteId: Value(data['id'] as String),
            itemType: item['item_type'] != null ? Value(item['item_type'] as String) : const Value.absent(),
            description: item['description'] != null ? Value(item['description'] as String) : const Value.absent(),
            quantity: item['quantity'] != null ? Value((item['quantity'] as num).toDouble()) : const Value.absent(),
            unit: item['unit'] != null ? Value(item['unit'] as String) : const Value.absent(),
            unitPrice: item['unit_price'] != null ? Value((item['unit_price'] as num).toDouble()) : const Value.absent(),
            sortOrder: item['sort_order'] != null ? Value(item['sort_order'] as int) : const Value.absent(),
            version: item['version'] != null ? Value(item['version'] as int) : const Value.absent(),
            createdAt: item['created_at'] != null ? Value(DateTime.parse(item['created_at'] as String)) : const Value.absent(),
            updatedAt: item['updated_at'] != null ? Value(DateTime.parse(item['updated_at'] as String)) : const Value.absent(),
            deletedAt: Value(item['deleted_at'] != null ? DateTime.parse(item['deleted_at'] as String) : null),
          );
          await into(quoteLineItems).insertOnConflictUpdate(itemCompanion);
        }
      }
    });
  }

  // ────────────────────────────────────────────────────────────────────────
  // Internal helpers
  // ────────────────────────────────────────────────────────────────────────

  /// Fetch line items for a list of quote rows and assemble [QuoteEntity] objects.
  ///
  /// Uses two queries (parent list already fetched, this fetches children in one
  /// query) to avoid N+1 and duplicate parent rows from JOIN.
  Future<List<QuoteEntity>> _populateLineItems(List<Quote> quoteRows) async {
    if (quoteRows.isEmpty) return [];

    final quoteIds = quoteRows.map((q) => q.id).toList();

    final lineItemRows = await (select(quoteLineItems)
          ..where(
            (tbl) =>
                tbl.quoteId.isIn(quoteIds) & tbl.deletedAt.isNull(),
          )
          ..orderBy([(tbl) => OrderingTerm.asc(tbl.sortOrder)]))
        .get();

    // Group line items by quoteId
    final itemsByQuoteId = <String, List<QuoteLineItem>>{};
    for (final item in lineItemRows) {
      itemsByQuoteId.putIfAbsent(item.quoteId, () => []).add(item);
    }

    return quoteRows.map((quoteRow) {
      final items = itemsByQuoteId[quoteRow.id] ?? [];
      return QuoteEntity(
        id: quoteRow.id,
        companyId: quoteRow.companyId,
        jobId: quoteRow.jobId,
        tradeScopeId: quoteRow.tradeScopeId,
        status: quoteRow.status,
        revisionNumber: quoteRow.revisionNumber,
        taxRate: quoteRow.taxRate,
        discountType: quoteRow.discountType,
        discountValue: quoteRow.discountValue,
        expiryDate: quoteRow.expiryDate,
        sentAt: quoteRow.sentAt,
        viewedAt: quoteRow.viewedAt,
        approvedAt: quoteRow.approvedAt,
        declinedAt: quoteRow.declinedAt,
        declineReason: quoteRow.declineReason,
        declineDetail: quoteRow.declineDetail,
        adminNotes: quoteRow.adminNotes,
        lineItems: items.map(_mapLineItem).toList(),
        createdAt: quoteRow.createdAt,
        updatedAt: quoteRow.updatedAt,
      );
    }).toList();
  }

  LineItemEntity _mapLineItem(QuoteLineItem row) => LineItemEntity(
        id: row.id,
        itemType: row.itemType,
        description: row.description,
        quantity: row.quantity,
        unit: row.unit,
        unitPrice: row.unitPrice,
        sortOrder: row.sortOrder,
      );

  /// Build the sync payload for a quote mutation (parent + line items).
  Map<String, dynamic> _buildQuotePayload(QuoteEntity entity) {
    return {
      'id': entity.id,
      'company_id': entity.companyId,
      'job_id': entity.jobId,
      'trade_scope_id': entity.tradeScopeId,
      'status': entity.status,
      'revision_number': entity.revisionNumber,
      'tax_rate': entity.taxRate,
      'discount_type': entity.discountType,
      'discount_value': entity.discountValue,
      'expiry_date': entity.expiryDate?.toIso8601String(),
      'sent_at': entity.sentAt?.toIso8601String(),
      'viewed_at': entity.viewedAt?.toIso8601String(),
      'approved_at': entity.approvedAt?.toIso8601String(),
      'declined_at': entity.declinedAt?.toIso8601String(),
      'decline_reason': entity.declineReason,
      'decline_detail': entity.declineDetail,
      'admin_notes': entity.adminNotes,
      'created_at': entity.createdAt.toIso8601String(),
      'updated_at': entity.updatedAt.toIso8601String(),
      'line_items': entity.lineItems
          .map((item) => {
                'id': item.id,
                'item_type': item.itemType,
                'description': item.description,
                'quantity': item.quantity,
                'unit': item.unit,
                'unit_price': item.unitPrice,
                'sort_order': item.sortOrder,
              })
          .toList(),
    };
  }

  /// Build a [SyncQueueCompanion] outbox entry for the given mutation.
  SyncQueueCompanion _buildQueueEntry({
    required String entityType,
    required String entityId,
    required String operation,
    required Map<String, dynamic> payload,
  }) {
    return SyncQueueCompanion.insert(
      id: Value(const Uuid().v4()),
      entityType: entityType,
      entityId: entityId,
      operation: operation,
      payload: jsonEncode(payload),
      status: const Value('pending'),
      attemptCount: const Value(0),
      createdAt: DateTime.now(),
    );
  }
}
