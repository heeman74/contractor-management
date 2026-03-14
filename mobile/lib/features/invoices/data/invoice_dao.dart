import 'dart:convert';

import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:uuid/uuid.dart';

import '../../../core/database/app_database.dart';
import '../../../core/database/tables/invoice_line_items.dart';
import '../../../core/database/tables/invoices.dart';
import '../../../core/database/tables/sync_queue.dart';
import '../../quotes/domain/line_item_entity.dart';
import '../domain/invoice_entity.dart';

part 'invoice_dao.g.dart';

/// Drift DAO for Invoice CRUD with transactional outbox dual-write.
///
/// All read methods return [Stream] — offline-first, reactive to local DB changes.
///
/// Every mutating method uses [db.transaction] to atomically write to BOTH
/// the invoices/invoice_line_items tables AND the sync_queue outbox.
///
/// [upsertFromSync] is the sync-pull path and does NOT write to the
/// sync_queue — this IS the sync; writing to the queue would cause an infinite loop.
@DriftAccessor(
  tables: [Invoices, InvoiceLineItems, SyncQueue],
)
class InvoiceDao extends DatabaseAccessor<AppDatabase> with _$InvoiceDaoMixin {
  InvoiceDao(super.db);

  // ────────────────────────────────────────────────────────────────────────
  // Invoice streams
  // ────────────────────────────────────────────────────────────────────────

  /// Reactive stream of all non-deleted invoices for a job.
  ///
  /// Ordered by issuedAt descending (most recently issued first).
  /// Each [InvoiceEntity] is populated with its line items.
  Stream<List<InvoiceEntity>> watchInvoicesForJob(String jobId) {
    final parentQuery = (select(invoices)
          ..where(
            (tbl) =>
                tbl.jobId.equals(jobId) & tbl.deletedAt.isNull(),
          )
          ..orderBy([(tbl) => OrderingTerm.desc(tbl.issuedAt)]))
        .watch();

    return parentQuery.asyncMap(_populateLineItems);
  }

  /// Reactive stream of a single invoice with its line items.
  ///
  /// Emits null if the invoice is not found or has been soft-deleted.
  Stream<InvoiceEntity?> watchInvoice(String invoiceId) {
    final parentQuery = (select(invoices)
          ..where(
            (tbl) =>
                tbl.id.equals(invoiceId) & tbl.deletedAt.isNull(),
          )
          ..limit(1))
        .watch();

    return parentQuery.asyncMap((rows) async {
      if (rows.isEmpty) return null;
      final populated = await _populateLineItems([rows.first]);
      return populated.firstOrNull;
    });
  }

  /// Stream of all non-deleted invoices. Used for sync listing.
  Stream<List<InvoiceEntity>> getAllInvoices() {
    final parentQuery = (select(invoices)
          ..where((tbl) => tbl.deletedAt.isNull()))
        .watch();

    return parentQuery.asyncMap(_populateLineItems);
  }

  // ────────────────────────────────────────────────────────────────────────
  // Invoice mutations (transactional outbox dual-write pattern)
  // ────────────────────────────────────────────────────────────────────────

  /// Insert a new invoice and its line items, and atomically enqueue a CREATE sync item.
  ///
  /// Returns the generated invoice UUID.
  Future<String> createInvoice(InvoiceEntity entity) async {
    await db.transaction(() async {
      final now = DateTime.now();

      // Insert parent invoice row
      await into(invoices).insert(
        InvoicesCompanion.insert(
          id: Value(entity.id),
          companyId: entity.companyId,
          jobId: entity.jobId,
          quoteId: Value(entity.quoteId),
          invoiceNumber: entity.invoiceNumber,
          status: Value(entity.status),
          taxRate: Value(entity.taxRate),
          discountType: Value(entity.discountType),
          discountValue: Value(entity.discountValue),
          dueDate: Value(entity.dueDate),
          issuedAt: entity.issuedAt,
          finalizedAt: Value(entity.finalizedAt),
          createdAt: entity.createdAt,
          updatedAt: entity.updatedAt,
        ),
      );

      // Insert all line item rows
      for (final item in entity.lineItems) {
        await into(invoiceLineItems).insert(
          InvoiceLineItemsCompanion.insert(
            id: Value(item.id),
            companyId: entity.companyId,
            invoiceId: entity.id,
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

      // Enqueue sync CREATE
      await into(syncQueue).insert(
        _buildQueueEntry(
          entityType: 'invoice',
          entityId: entity.id,
          operation: 'CREATE',
          payload: _buildInvoicePayload(entity),
        ),
      );
    });

    return entity.id;
  }

  /// Update an existing invoice and replace all its line items.
  ///
  /// Soft-deletes existing line items and inserts the new set. Enqueues UPDATE.
  Future<void> updateInvoice(InvoiceEntity entity) async {
    await db.transaction(() async {
      final now = DateTime.now();

      // Update parent invoice
      await (update(invoices)..where((tbl) => tbl.id.equals(entity.id))).write(
        InvoicesCompanion(
          quoteId: Value(entity.quoteId),
          status: Value(entity.status),
          taxRate: Value(entity.taxRate),
          discountType: Value(entity.discountType),
          discountValue: Value(entity.discountValue),
          dueDate: Value(entity.dueDate),
          issuedAt: Value(entity.issuedAt),
          finalizedAt: Value(entity.finalizedAt),
          updatedAt: Value(now),
        ),
      );

      // Soft-delete existing line items
      await (update(invoiceLineItems)
            ..where((tbl) => tbl.invoiceId.equals(entity.id)))
          .write(InvoiceLineItemsCompanion(deletedAt: Value(now)));

      // Insert new line items
      for (final item in entity.lineItems) {
        await into(invoiceLineItems).insert(
          InvoiceLineItemsCompanion.insert(
            id: Value(item.id),
            companyId: entity.companyId,
            invoiceId: entity.id,
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
          entityType: 'invoice',
          entityId: entity.id,
          operation: 'UPDATE',
          payload: _buildInvoicePayload(entity),
        ),
      );
    });
  }

  /// Update only the payment status of an invoice and enqueue a status-update sync.
  ///
  /// Used when admin/client marks invoice as paid/partial/overdue etc.
  Future<void> updatePaymentStatus(String invoiceId, String status) async {
    final now = DateTime.now();

    await db.transaction(() async {
      await (update(invoices)..where((tbl) => tbl.id.equals(invoiceId))).write(
        InvoicesCompanion(
          status: Value(status),
          updatedAt: Value(now),
          // Finalize the invoice if status indicates closure
          finalizedAt: (status == 'paid' || status == 'cancelled')
              ? Value(now)
              : const Value.absent(),
        ),
      );

      await into(syncQueue).insert(
        _buildQueueEntry(
          entityType: 'invoice',
          entityId: invoiceId,
          operation: 'UPDATE',
          payload: {
            'id': invoiceId,
            'status': status,
            'updated_at': now.toIso8601String(),
            if (status == 'paid' || status == 'cancelled')
              'finalized_at': now.toIso8601String(),
          },
        ),
      );
    });
  }

  // ────────────────────────────────────────────────────────────────────────
  // Sync pull upsert
  // ────────────────────────────────────────────────────────────────────────

  /// Upsert an invoice and its line items from a sync pull response.
  ///
  /// Processes the nested [line_items] array: upserts each child row.
  /// No sync_queue entry — this IS the sync pull.
  Future<void> upsertFromSync(Map<String, dynamic> data) async {
    await db.transaction(() async {
      final companion = InvoicesCompanion(
        id: Value(data['id'] as String),
        companyId: Value(data['company_id'] as String),
        jobId: Value(data['job_id'] as String),
        quoteId: Value(data['quote_id'] as String?),
        invoiceNumber: data['invoice_number'] != null ? Value(data['invoice_number'] as String) : const Value.absent(),
        status: data['status'] != null ? Value(data['status'] as String) : const Value.absent(),
        taxRate: data['tax_rate'] != null ? Value((data['tax_rate'] as num).toDouble()) : const Value.absent(),
        discountType: Value(data['discount_type'] as String?),
        discountValue: data['discount_value'] != null ? Value((data['discount_value'] as num).toDouble()) : const Value.absent(),
        dueDate: Value(data['due_date'] != null ? DateTime.parse(data['due_date'] as String) : null),
        issuedAt: data['issued_at'] != null ? Value(DateTime.parse(data['issued_at'] as String)) : const Value.absent(),
        finalizedAt: Value(data['finalized_at'] != null ? DateTime.parse(data['finalized_at'] as String) : null),
        version: data['version'] != null ? Value(data['version'] as int) : const Value.absent(),
        createdAt: data['created_at'] != null ? Value(DateTime.parse(data['created_at'] as String)) : const Value.absent(),
        updatedAt: data['updated_at'] != null ? Value(DateTime.parse(data['updated_at'] as String)) : const Value.absent(),
        deletedAt: Value(data['deleted_at'] != null ? DateTime.parse(data['deleted_at'] as String) : null),
      );

      await into(invoices).insertOnConflictUpdate(companion);

      // Process nested line items
      final lineItemsData = data['line_items'];
      if (lineItemsData is List) {
        for (final item in lineItemsData) {
          if (item is! Map<String, dynamic>) continue;
          final itemCompanion = InvoiceLineItemsCompanion(
            id: Value(item['id'] as String),
            companyId: Value(data['company_id'] as String),
            invoiceId: Value(data['id'] as String),
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
          await into(invoiceLineItems).insertOnConflictUpdate(itemCompanion);
        }
      }
    });
  }

  // ────────────────────────────────────────────────────────────────────────
  // Internal helpers
  // ────────────────────────────────────────────────────────────────────────

  /// Fetch line items for a list of invoice rows and assemble [InvoiceEntity] objects.
  Future<List<InvoiceEntity>> _populateLineItems(List<Invoice> invoiceRows) async {
    if (invoiceRows.isEmpty) return [];

    final invoiceIds = invoiceRows.map((i) => i.id).toList();

    final lineItemRows = await (select(invoiceLineItems)
          ..where(
            (tbl) =>
                tbl.invoiceId.isIn(invoiceIds) & tbl.deletedAt.isNull(),
          )
          ..orderBy([(tbl) => OrderingTerm.asc(tbl.sortOrder)]))
        .get();

    // Group line items by invoiceId
    final itemsByInvoiceId = <String, List<InvoiceLineItem>>{};
    for (final item in lineItemRows) {
      itemsByInvoiceId.putIfAbsent(item.invoiceId, () => []).add(item);
    }

    return invoiceRows.map((invoiceRow) {
      final items = itemsByInvoiceId[invoiceRow.id] ?? [];
      return InvoiceEntity(
        id: invoiceRow.id,
        companyId: invoiceRow.companyId,
        jobId: invoiceRow.jobId,
        quoteId: invoiceRow.quoteId,
        invoiceNumber: invoiceRow.invoiceNumber,
        status: invoiceRow.status,
        taxRate: invoiceRow.taxRate,
        discountType: invoiceRow.discountType,
        discountValue: invoiceRow.discountValue,
        dueDate: invoiceRow.dueDate,
        issuedAt: invoiceRow.issuedAt,
        finalizedAt: invoiceRow.finalizedAt,
        lineItems: items.map(_mapLineItem).toList(),
        createdAt: invoiceRow.createdAt,
        updatedAt: invoiceRow.updatedAt,
      );
    }).toList();
  }

  LineItemEntity _mapLineItem(InvoiceLineItem row) => LineItemEntity(
        id: row.id,
        itemType: row.itemType,
        description: row.description,
        quantity: row.quantity,
        unit: row.unit,
        unitPrice: row.unitPrice,
        sortOrder: row.sortOrder,
      );

  /// Build the sync payload for an invoice mutation (parent + line items).
  Map<String, dynamic> _buildInvoicePayload(InvoiceEntity entity) {
    return {
      'id': entity.id,
      'company_id': entity.companyId,
      'job_id': entity.jobId,
      'quote_id': entity.quoteId,
      'invoice_number': entity.invoiceNumber,
      'status': entity.status,
      'tax_rate': entity.taxRate,
      'discount_type': entity.discountType,
      'discount_value': entity.discountValue,
      'due_date': entity.dueDate?.toIso8601String(),
      'issued_at': entity.issuedAt.toIso8601String(),
      'finalized_at': entity.finalizedAt?.toIso8601String(),
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
