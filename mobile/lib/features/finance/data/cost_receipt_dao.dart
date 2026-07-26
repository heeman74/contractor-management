import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:uuid/uuid.dart';

import '../../../core/database/app_database.dart';
import '../../../core/database/tables/cost_receipts.dart';

part 'cost_receipt_dao.g.dart';

/// Drift DAO for CostReceipt CRUD.
///
/// Receipts are NOT dual-written to the sync_queue text outbox — they use a
/// dedicated binary upload service (`CostReceiptUploadService`) for
/// multipart file upload, mirroring [AttachmentDao] exactly (NOT
/// `TaskAttachmentDao`, which has no registered push handler —
/// 31-RESEARCH.md Pitfall 1).
///
/// Text-field state (remoteUrl, uploadStatus) flows via [upsertFromRemote]
/// only, driven by an on-demand fetch of a cost entry's receipts (never the
/// company-wide /sync delta — 31-RESEARCH.md Pitfall 2).
@DriftAccessor(tables: [CostReceipts])
class CostReceiptDao extends DatabaseAccessor<AppDatabase>
    with _$CostReceiptDaoMixin {
  CostReceiptDao(super.db);

  // ────────────────────────────────────────────────────────────────────────
  // Receipt streams
  // ────────────────────────────────────────────────────────────────────────

  /// Reactive stream of active (non-deleted) receipts for a cost entry.
  Stream<List<CostReceipt>> watchByCostEntry(String costEntryId) {
    return (select(costReceipts)
          ..where(
            (tbl) =>
                tbl.costEntryId.equals(costEntryId) & tbl.deletedAt.isNull(),
          )
          ..orderBy([(tbl) => OrderingTerm.asc(tbl.createdAt)]))
        .watch();
  }

  // ────────────────────────────────────────────────────────────────────────
  // Receipt mutations
  // ────────────────────────────────────────────────────────────────────────

  /// Insert a new receipt with [uploadStatus] = 'pending_upload'.
  ///
  /// Does NOT write to sync_queue — receipts use `CostReceiptUploadService`
  /// for binary upload. Returns the generated receipt UUID.
  Future<String> insertReceipt({
    required String companyId,
    required String costEntryId,
    required String localPath,
    String? thumbnailPath,
    String? caption,
  }) async {
    final now = DateTime.now();
    final receiptId = const Uuid().v4();

    await into(costReceipts).insert(
      CostReceiptsCompanion.insert(
        id: Value(receiptId),
        companyId: companyId,
        costEntryId: costEntryId,
        localPath: localPath,
        thumbnailPath: Value(thumbnailPath),
        caption: Value(caption),
        createdAt: now,
        updatedAt: now,
      ),
    );

    return receiptId;
  }

  /// Get all receipts that need uploading.
  ///
  /// Returns receipts with [uploadStatus] = 'pending_upload' or 'failed',
  /// excluding soft-deleted rows. Used by `CostReceiptUploadService`.
  Future<List<CostReceipt>> getPendingUploads() {
    return (select(costReceipts)
          ..where(
            (tbl) =>
                (tbl.uploadStatus.equals('pending_upload') |
                    tbl.uploadStatus.equals('failed')) &
                tbl.deletedAt.isNull(),
          )
          ..orderBy([(tbl) => OrderingTerm.asc(tbl.createdAt)]))
        .get();
  }

  /// Update the upload status for a receipt.
  Future<void> setUploadStatus(String id, String status) async {
    await (update(costReceipts)..where((tbl) => tbl.id.equals(id))).write(
      CostReceiptsCompanion(
        uploadStatus: Value(status),
        updatedAt: Value(DateTime.now()),
      ),
    );
  }

  /// Mark a receipt as successfully uploaded with its remote URL.
  ///
  /// Sets [uploadStatus] = 'uploaded' and [remoteUrl] = url.
  Future<void> markUploaded(String id, String remoteUrl) async {
    await (update(costReceipts)..where((tbl) => tbl.id.equals(id))).write(
      CostReceiptsCompanion(
        uploadStatus: const Value('uploaded'),
        remoteUrl: Value(remoteUrl),
        updatedAt: Value(DateTime.now()),
      ),
    );
  }

  /// Mark a receipt upload attempt as failed and bump the retry counter.
  ///
  /// `CostReceiptUploadService` tracks in-flight retry timing itself; this
  /// records the outcome after the retry budget is exhausted (or a 4xx
  /// no-retry failure).
  Future<void> incrementRetry(String id) async {
    final current = await (select(costReceipts)
          ..where((tbl) => tbl.id.equals(id)))
        .getSingleOrNull();
    final nextRetryCount = (current?.retryCount ?? 0) + 1;

    await (update(costReceipts)..where((tbl) => tbl.id.equals(id))).write(
      CostReceiptsCompanion(
        uploadStatus: const Value('failed'),
        retryCount: Value(nextRetryCount),
        updatedAt: Value(DateTime.now()),
      ),
    );
  }

  // ────────────────────────────────────────────────────────────────────────
  // On-demand fetch upsert
  // ────────────────────────────────────────────────────────────────────────

  /// Upsert a receipt from an on-demand fetch response (server-wins on
  /// conflict). Does NOT write to sync_queue.
  ///
  /// `CostReceiptResponse` extends `BaseResponseSchema` (not
  /// `TenantResponseSchema`) so it carries no `company_id` — callers MUST
  /// inject a `'company_id'` key into [data] before calling this method
  /// (see `FinanceRepository`).
  Future<void> upsertFromRemote(Map<String, dynamic> data) async {
    final id = data['id'];
    final companyId = data['company_id'];
    final costEntryId = data['cost_entry_id'];
    if (id is! String || companyId is! String || costEntryId is! String) {
      throw const FormatException(
        'CostReceiptDao.upsertFromRemote: missing required '
        'id/company_id/cost_entry_id',
      );
    }

    final deletedAt = data['deleted_at'] != null
        ? DateTime.parse(data['deleted_at'] as String)
        : null;

    final companion = CostReceiptsCompanion(
      id: Value(id),
      companyId: Value(companyId),
      costEntryId: Value(costEntryId),
      // Server-sourced receipts have no local file — default to empty
      // string (non-nullable column), mirroring AttachmentSyncHandler.
      localPath: Value(data['local_path'] as String? ?? ''),
      thumbnailPath: Value(data['thumbnail_path'] as String?),
      caption: Value(data['caption'] as String?),
      uploadStatus: const Value('uploaded'),
      remoteUrl: Value(data['remote_url'] as String?),
      createdAt: data['created_at'] != null
          ? Value(DateTime.parse(data['created_at'] as String))
          : const Value.absent(),
      updatedAt: data['updated_at'] != null
          ? Value(DateTime.parse(data['updated_at'] as String))
          : const Value.absent(),
      deletedAt: Value(deletedAt),
    );

    await into(costReceipts).insertOnConflictUpdate(companion);
  }
}
