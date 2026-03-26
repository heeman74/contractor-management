import 'dart:convert';

import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:uuid/uuid.dart';

import '../../../core/database/app_database.dart';
import '../../../core/database/tables/billing_milestones.dart';
import '../../../core/database/tables/sync_queue.dart';
import '../domain/billing_milestone_entity.dart';

part 'billing_milestone_dao.g.dart';

/// Drift DAO for BillingMilestone CRUD with transactional outbox dual-write.
///
/// All read methods return [Stream] — offline-first, reactive to local DB changes.
///
/// Every mutating method uses [db.transaction] to atomically write to BOTH
/// the billing_milestones table AND the sync_queue outbox. If either write
/// fails, both are rolled back — no orphaned queue items, no untracked mutations.
///
/// [upsertFromSync] is the sync-pull path and does NOT write to the
/// sync_queue — this IS the sync; writing to the queue would cause an
/// infinite sync loop.
@DriftAccessor(tables: [BillingMilestones, SyncQueue])
class BillingMilestoneDao extends DatabaseAccessor<AppDatabase>
    with _$BillingMilestoneDaoMixin {
  BillingMilestoneDao(super.db);

  // ────────────────────────────────────────────────────────────────────────
  // Milestone streams
  // ────────────────────────────────────────────────────────────────────────

  /// Reactive stream of all non-deleted milestones for a trade scope.
  ///
  /// Ordered by [sortOrder] ascending (first milestone first).
  Stream<List<BillingMilestoneEntity>> watchByScope(String scopeId) {
    return (select(billingMilestones)
          ..where(
            (tbl) =>
                tbl.tradeScopeId.equals(scopeId) & tbl.deletedAt.isNull(),
          )
          ..orderBy([(tbl) => OrderingTerm.asc(tbl.sortOrder)]))
        .watch()
        .map(
          (rows) => rows.map(BillingMilestoneEntity.fromDrift).toList(),
        );
  }

  // ────────────────────────────────────────────────────────────────────────
  // Milestone mutations (transactional outbox dual-write pattern)
  // ────────────────────────────────────────────────────────────────────────

  /// Insert a new billing milestone and atomically enqueue a CREATE sync item.
  ///
  /// Returns the generated milestone UUID.
  Future<String> createMilestone(BillingMilestoneEntity entity) async {
    await db.transaction(() async {
      await into(billingMilestones).insert(entity.toCompanion());

      await into(syncQueue).insert(
        _buildQueueEntry(
          entityType: 'billing_milestone',
          entityId: entity.id,
          operation: 'CREATE',
          payload: _buildPayload(entity),
        ),
      );
    });

    return entity.id;
  }

  /// Update an existing billing milestone and enqueue an UPDATE sync item.
  Future<void> updateMilestone(BillingMilestoneEntity entity) async {
    final now = DateTime.now();

    await db.transaction(() async {
      await (update(billingMilestones)
            ..where((tbl) => tbl.id.equals(entity.id)))
          .write(entity.copyWith(updatedAt: now).toCompanion());

      await into(syncQueue).insert(
        _buildQueueEntry(
          entityType: 'billing_milestone',
          entityId: entity.id,
          operation: 'UPDATE',
          payload: _buildPayload(entity.copyWith(updatedAt: now)),
        ),
      );
    });
  }

  /// Soft-delete a billing milestone and enqueue a DELETE sync item.
  Future<void> deleteMilestone(String id) async {
    final now = DateTime.now();

    await db.transaction(() async {
      await (update(billingMilestones)..where((tbl) => tbl.id.equals(id)))
          .write(BillingMilestonesCompanion(deletedAt: Value(now)));

      await into(syncQueue).insert(
        _buildQueueEntry(
          entityType: 'billing_milestone',
          entityId: id,
          operation: 'DELETE',
          payload: {'id': id, 'deleted_at': now.toIso8601String()},
        ),
      );
    });
  }

  // ────────────────────────────────────────────────────────────────────────
  // Sync pull upsert
  // ────────────────────────────────────────────────────────────────────────

  /// Upsert a billing milestone from a sync pull response.
  ///
  /// No sync_queue entry — this IS the sync pull.
  Future<void> upsertFromSync(Map<String, dynamic> data) async {
    final id = data['id'];
    final companyId = data['company_id'];
    final tradeScopeId = data['trade_scope_id'];
    if (id is! String || companyId is! String || tradeScopeId is! String) {
      throw FormatException(
        'BillingMilestone missing required fields: id=${id.runtimeType}, '
        'company_id=${companyId.runtimeType}, '
        'trade_scope_id=${tradeScopeId.runtimeType}',
      );
    }

    final companion = BillingMilestonesCompanion(
      id: Value(id),
      companyId: Value(companyId),
      tradeScopeId: Value(tradeScopeId),
      name: data['name'] != null
          ? Value(data['name'] as String)
          : const Value.absent(),
      percentage: data['percentage'] != null
          ? Value((data['percentage'] as num).toDouble())
          : const Value.absent(),
      description: Value(data['description'] as String?),
      isInvoiced: data['is_invoiced'] != null
          ? Value(data['is_invoiced'] as bool)
          : const Value.absent(),
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
      deletedAt: Value(
        data['deleted_at'] != null
            ? DateTime.parse(data['deleted_at'] as String)
            : null,
      ),
    );

    await into(billingMilestones).insertOnConflictUpdate(companion);
  }

  // ────────────────────────────────────────────────────────────────────────
  // Internal helpers
  // ────────────────────────────────────────────────────────────────────────

  /// Build the sync payload for a billing milestone mutation.
  Map<String, dynamic> _buildPayload(BillingMilestoneEntity entity) {
    return {
      'id': entity.id,
      'company_id': entity.companyId,
      'trade_scope_id': entity.tradeScopeId,
      'name': entity.name,
      'percentage': entity.percentage,
      'description': entity.description,
      'is_invoiced': entity.isInvoiced,
      'sort_order': entity.sortOrder,
      'version': entity.version,
      'created_at': entity.createdAt.toIso8601String(),
      'updated_at': entity.updatedAt.toIso8601String(),
      if (entity.deletedAt != null)
        'deleted_at': entity.deletedAt!.toIso8601String(),
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
