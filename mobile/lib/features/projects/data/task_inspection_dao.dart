import 'dart:convert';

import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:uuid/uuid.dart';

import '../../../core/database/app_database.dart';
import '../../../core/database/tables/sync_queue.dart';
import '../../../core/database/tables/task_inspections.dart';

part 'task_inspection_dao.g.dart';

/// Drift DAO for TaskInspection CRUD with transactional outbox dual-write.
///
/// All read methods return [Stream] — offline-first, reactive to local DB changes.
///
/// Every mutating method uses [db.transaction] to atomically write to BOTH
/// the task_inspections table AND sync_queue outbox. If either write fails,
/// both are rolled back — no orphaned queue items, no untracked mutations.
@DriftAccessor(tables: [TaskInspections, SyncQueue])
class TaskInspectionDao extends DatabaseAccessor<AppDatabase>
    with _$TaskInspectionDaoMixin {
  TaskInspectionDao(super.db);

  // ────────────────────────────────────────────────────────────────────────
  // Inspection streams
  // ────────────────────────────────────────────────────────────────────────

  /// Reactive stream of all active (non-deleted) inspections for a task.
  ///
  /// Returns the full audit trail ordered newest-first — each inspection
  /// represents one approve/reject cycle on the task.
  Stream<List<TaskInspection>> watchByTaskId(String taskId) {
    return (select(taskInspections)
          ..where(
            (tbl) =>
                tbl.taskId.equals(taskId) & tbl.deletedAt.isNull(),
          )
          ..orderBy([(tbl) => OrderingTerm.desc(tbl.createdAt)]))
        .watch();
  }

  // ────────────────────────────────────────────────────────────────────────
  // Inspection mutations (transactional outbox pattern)
  // ────────────────────────────────────────────────────────────────────────

  /// Insert a new task inspection and atomically enqueue a CREATE sync item.
  ///
  /// Both the entity write and sync_queue insert happen in a single
  /// transaction — if either fails, both are rolled back.
  Future<void> createInspection(TaskInspectionsCompanion inspection) async {
    await db.transaction(() async {
      await into(taskInspections).insert(inspection);
      await into(syncQueue).insert(
        _buildQueueEntry(
          entityType: 'task_inspection',
          entityId: inspection.id.present ? inspection.id.value : '',
          operation: 'CREATE',
          payload: _inspectionPayload(inspection),
        ),
      );
    });
  }

  /// Upsert a task inspection received from the server during delta sync.
  ///
  /// Used by [TaskInspectionSyncHandler.applyPulled] to apply server-pushed
  /// inspection data without enqueuing another sync item.
  Future<void> upsertFromServer(TaskInspectionsCompanion data) {
    return into(taskInspections).insertOnConflictUpdate(data);
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

  /// Build a JSON-serializable payload map from a [TaskInspectionsCompanion].
  Map<String, dynamic> _inspectionPayload(TaskInspectionsCompanion entry) {
    return {
      if (entry.id.present) 'id': entry.id.value,
      if (entry.companyId.present) 'companyId': entry.companyId.value,
      if (entry.taskId.present) 'taskId': entry.taskId.value,
      if (entry.inspectorId.present) 'inspectorId': entry.inspectorId.value,
      if (entry.decision.present) 'decision': entry.decision.value,
      if (entry.checklistResults.present)
        'checklistResults': entry.checklistResults.value,
      if (entry.rejectionReason.present)
        'rejectionReason': entry.rejectionReason.value,
      if (entry.rejectionComment.present)
        'rejectionComment': entry.rejectionComment.value,
      if (entry.createdAt.present)
        'createdAt': entry.createdAt.value.toIso8601String(),
      if (entry.updatedAt.present)
        'updatedAt': entry.updatedAt.value.toIso8601String(),
    };
  }
}
