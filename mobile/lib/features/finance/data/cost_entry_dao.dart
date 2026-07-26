import 'dart:convert';

import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:uuid/uuid.dart';

import '../../../core/database/app_database.dart';
import '../../../core/database/tables/cost_entries.dart';
import '../../../core/database/tables/sync_queue.dart';
import '../../../core/database/tables/trade_scopes.dart';

part 'cost_entry_dao.g.dart';

/// Drift DAO for CostEntry CRUD with transactional outbox dual-write.
///
/// All read methods return [Stream] — offline-first, reactive to local DB
/// changes. Every mutating method uses [db.transaction] to atomically write
/// to BOTH the cost_entries table AND sync_queue outbox — mirrors
/// [NoteDao]'s pattern.
///
/// [upsertFromRemote] is the ON-DEMAND fetch upsert path (used by
/// `FinanceRepository` and `CostEntrySyncHandler.applyPulled`), NEVER the
/// company-wide /sync delta pull (31-RESEARCH.md Pitfall 2). It does NOT
/// write to sync_queue — this IS the sync.
@DriftAccessor(tables: [CostEntries, TradeScopes, SyncQueue])
class CostEntryDao extends DatabaseAccessor<AppDatabase>
    with _$CostEntryDaoMixin {
  CostEntryDao(super.db);

  // ────────────────────────────────────────────────────────────────────────
  // Cost entry streams
  // ────────────────────────────────────────────────────────────────────────

  /// Reactive stream of active (non-deleted) cost entries anchored to a job.
  Stream<List<CostEntry>> watchByJob(String jobId) {
    return (select(costEntries)
          ..where(
            (tbl) => tbl.jobId.equals(jobId) & tbl.deletedAt.isNull(),
          )
          ..orderBy([(tbl) => OrderingTerm.desc(tbl.incurredDate)]))
        .watch();
  }

  /// Reactive stream of active (non-deleted) cost entries anchored to a
  /// trade scope.
  Stream<List<CostEntry>> watchByTradeScope(String tradeScopeId) {
    return (select(costEntries)
          ..where(
            (tbl) =>
                tbl.tradeScopeId.equals(tradeScopeId) &
                tbl.deletedAt.isNull(),
          )
          ..orderBy([(tbl) => OrderingTerm.desc(tbl.incurredDate)]))
        .watch();
  }

  /// Reactive stream of active cost entries rolling up to a project: entries
  /// anchored to any of the project's trade scopes, PLUS entries anchored to
  /// [jobIds] (mirrors the backend D-02/D-05 rollup: trade-scope-anchored
  /// costs + costs on jobs whose project_id matches).
  ///
  /// The mobile `Jobs` table carries no `projectId` FK, so job-anchored
  /// membership cannot be derived locally via a join — callers (the project
  /// detail screen, landing in 31-05) must supply the project's known job
  /// IDs explicitly. Trade-scope membership IS derivable locally and is
  /// looked up via a two-stream approach (Drift selectOnly+JOIN fails with
  /// readTable for joined queries — STATE.md's `watchProjectsForContractor`
  /// precedent).
  Stream<List<CostEntry>> watchByProject(
    String companyId,
    String projectId, {
    List<String> jobIds = const [],
  }) {
    final scopeIdsStream = (select(tradeScopes)
          ..where(
            (tbl) => tbl.projectId.equals(projectId) & tbl.deletedAt.isNull(),
          ))
        .watch()
        .map((scopes) => scopes.map((s) => s.id).toSet());

    final allEntriesStream = (select(costEntries)
          ..where(
            (tbl) => tbl.companyId.equals(companyId) & tbl.deletedAt.isNull(),
          ))
        .watch();

    final jobIdSet = jobIds.toSet();

    return allEntriesStream.asyncExpand((entries) => scopeIdsStream.map(
          (scopeIds) => entries
              .where((e) =>
                  (e.tradeScopeId != null &&
                      scopeIds.contains(e.tradeScopeId)) ||
                  (e.jobId != null && jobIdSet.contains(e.jobId)))
              .toList(),
        ));
  }

  // ────────────────────────────────────────────────────────────────────────
  // Cost entry mutations (transactional outbox pattern)
  // ────────────────────────────────────────────────────────────────────────

  /// Insert a new cost entry and atomically enqueue a CREATE sync item.
  ///
  /// Exactly one of [jobId]/[tradeScopeId] must be provided — mirrors the
  /// backend's `CostEntryCreate.validate_fields` XOR anchor validator.
  /// Returns the generated cost-entry UUID.
  Future<String> insertCostEntry({
    required String companyId,
    required String categoryId,
    required double amount,
    required String incurredDate,
    String? jobId,
    String? tradeScopeId,
    String? vendor,
    String? note,
  }) async {
    if ((jobId == null) == (tradeScopeId == null)) {
      throw ArgumentError(
        'CostEntryDao.insertCostEntry: exactly one of jobId/tradeScopeId '
        'must be provided (XOR anchor)',
      );
    }

    final now = DateTime.now();
    final entryId = const Uuid().v4();

    await db.transaction(() async {
      await into(costEntries).insert(
        CostEntriesCompanion.insert(
          id: Value(entryId),
          companyId: companyId,
          jobId: Value(jobId),
          tradeScopeId: Value(tradeScopeId),
          categoryId: categoryId,
          amount: amount,
          incurredDate: incurredDate,
          vendor: Value(vendor),
          note: Value(note),
          createdAt: now,
          updatedAt: now,
        ),
      );
      await into(syncQueue).insert(
        _buildQueueEntry(
          entityType: 'cost_entry',
          entityId: entryId,
          operation: 'CREATE',
          payload: {
            'id': entryId,
            if (jobId != null) 'job_id': jobId,
            if (tradeScopeId != null) 'trade_scope_id': tradeScopeId,
            'category_id': categoryId,
            'amount': amount,
            'incurred_date': incurredDate,
            if (vendor != null) 'vendor': vendor,
            if (note != null) 'note': note,
          },
        ),
      );
    });

    return entryId;
  }

  /// Update a cost entry's amount/category/date/vendor/note and atomically
  /// enqueue an UPDATE sync item. The anchor (job/trade-scope) is immutable
  /// after creation — mirrors `CostEntryUpdate` on the backend.
  Future<void> updateCostEntry(
    String id, {
    String? categoryId,
    double? amount,
    String? incurredDate,
    String? vendor,
    String? note,
  }) async {
    final now = DateTime.now();

    await db.transaction(() async {
      await (update(costEntries)..where((tbl) => tbl.id.equals(id))).write(
        CostEntriesCompanion(
          categoryId:
              categoryId != null ? Value(categoryId) : const Value.absent(),
          amount: amount != null ? Value(amount) : const Value.absent(),
          incurredDate: incurredDate != null
              ? Value(incurredDate)
              : const Value.absent(),
          vendor: vendor != null ? Value(vendor) : const Value.absent(),
          note: note != null ? Value(note) : const Value.absent(),
          updatedAt: Value(now),
        ),
      );
      await into(syncQueue).insert(
        _buildQueueEntry(
          entityType: 'cost_entry',
          entityId: id,
          operation: 'UPDATE',
          payload: {
            if (categoryId != null) 'category_id': categoryId,
            if (amount != null) 'amount': amount,
            if (incurredDate != null) 'incurred_date': incurredDate,
            if (vendor != null) 'vendor': vendor,
            if (note != null) 'note': note,
          },
        ),
      );
    });
  }

  /// Soft-delete a cost entry and atomically enqueue a DELETE sync item.
  ///
  /// Soft-deleted entries drop out of [watchByJob]/[watchByTradeScope]/
  /// [watchByProject] (D-05).
  Future<void> softDeleteCostEntry(String id) async {
    final now = DateTime.now();

    await db.transaction(() async {
      await (update(costEntries)..where((tbl) => tbl.id.equals(id))).write(
        CostEntriesCompanion(
          deletedAt: Value(now),
          updatedAt: Value(now),
        ),
      );
      await into(syncQueue).insert(
        _buildQueueEntry(
          entityType: 'cost_entry',
          entityId: id,
          operation: 'DELETE',
          payload: {'id': id},
        ),
      );
    });
  }

  // ────────────────────────────────────────────────────────────────────────
  // On-demand fetch upsert
  // ────────────────────────────────────────────────────────────────────────

  /// Upsert a cost entry from an on-demand fetch or sync-handler pull
  /// (server-wins on conflict). Does NOT write to sync_queue.
  ///
  /// `CostEntryResponse` extends `BaseResponseSchema` (not
  /// `TenantResponseSchema`) so it carries no `company_id` — callers MUST
  /// inject a `'company_id'` key into [data] before calling this method
  /// (see `FinanceRepository`).
  Future<void> upsertFromRemote(Map<String, dynamic> data) async {
    final id = data['id'];
    final companyId = data['company_id'];
    final categoryId = data['category_id'];
    final incurredDate = data['incurred_date'];
    if (id is! String ||
        companyId is! String ||
        categoryId is! String ||
        incurredDate is! String) {
      throw const FormatException(
        'CostEntryDao.upsertFromRemote: missing required '
        'id/company_id/category_id/incurred_date',
      );
    }

    final rawAmount = data['amount'];
    final amount = rawAmount is String
        ? double.tryParse(rawAmount)
        : (rawAmount is num ? rawAmount.toDouble() : null);
    if (amount == null) {
      throw const FormatException(
        'CostEntryDao.upsertFromRemote: invalid or missing "amount"',
      );
    }

    final deletedAt = data['deleted_at'] != null
        ? DateTime.parse(data['deleted_at'] as String)
        : null;

    final companion = CostEntriesCompanion(
      id: Value(id),
      companyId: Value(companyId),
      jobId: Value(data['job_id'] as String?),
      tradeScopeId: Value(data['trade_scope_id'] as String?),
      categoryId: Value(categoryId),
      amount: Value(amount),
      incurredDate: Value(incurredDate),
      vendor: Value(data['vendor'] as String?),
      note: Value(data['note'] as String?),
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

    await into(costEntries).insertOnConflictUpdate(companion);
  }

  // ────────────────────────────────────────────────────────────────────────
  // Internal helpers
  // ────────────────────────────────────────────────────────────────────────

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
