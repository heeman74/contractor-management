import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:uuid/uuid.dart';

import '../../../core/database/app_database.dart';
import '../../../core/database/tables/sync_queue.dart';
import '../../../core/database/tables/tasks.dart';
import '../../../core/database/tables/trade_scopes.dart';

part 'task_dao.g.dart';

/// Drift DAO for ProjectTask CRUD operations.
///
/// ProjectTasks are the atomic units of work within a trade scope.
/// The DAO supports reactive streams, task completion counting
/// (for progress indicators), and transactional sync queue writes.
///
/// [countTasksByScope] and [countCompletedTasksByScope] are used to
/// compute scope-level progress percentages in the project detail view.
///
/// [watchTasksForContractor] is the cross-scope query for the contractor's
/// "My Tasks" view — returns all incomplete tasks assigned to a user across
/// all trade scopes, ordered by priority then due date.
@DriftAccessor(tables: [ProjectTasks, TradeScopes, SyncQueue])
class TaskDao extends DatabaseAccessor<AppDatabase> with _$TaskDaoMixin {
  TaskDao(super.db);

  /// Reactive stream of all active (non-deleted) tasks for a trade scope.
  ///
  /// Ordered by [sortOrder] for consistent task list display.
  Stream<List<ProjectTask>> watchTasksByScope(String tradeScopeId) {
    return (select(projectTasks)
          ..where(
            (tbl) =>
                tbl.tradeScopeId.equals(tradeScopeId) &
                tbl.deletedAt.isNull(),
          )
          ..orderBy([(tbl) => OrderingTerm.asc(tbl.sortOrder)]))
        .watch();
  }

  /// Count total active (non-deleted) tasks for a trade scope.
  ///
  /// Used with [countCompletedTasksByScope] to compute progress percentage.
  Future<int> countTasksByScope(String tradeScopeId) async {
    final countExpr = projectTasks.id.count();
    final query = selectOnly(projectTasks)
      ..addColumns([countExpr])
      ..where(
        projectTasks.tradeScopeId.equals(tradeScopeId) &
            projectTasks.deletedAt.isNull(),
      );
    final result = await query.getSingleOrNull();
    return result?.read(countExpr) ?? 0;
  }

  /// Count completed active tasks for a trade scope.
  ///
  /// A task is complete when its [status] equals 'complete'.
  Future<int> countCompletedTasksByScope(String tradeScopeId) async {
    final countExpr = projectTasks.id.count();
    final query = selectOnly(projectTasks)
      ..addColumns([countExpr])
      ..where(
        projectTasks.tradeScopeId.equals(tradeScopeId) &
            projectTasks.status.equals('complete') &
            projectTasks.deletedAt.isNull(),
      );
    final result = await query.getSingleOrNull();
    return result?.read(countExpr) ?? 0;
  }

  /// Reactive stream of all incomplete tasks assigned to a contractor.
  ///
  /// Cross-scope query: returns tasks from ANY trade scope where
  /// [assignedTo] matches the given userId and task is not completed/deleted.
  ///
  /// Ordered by priority (urgent → high → medium → low) then dueDate ASC
  /// with nulls last — surfaces the most critical work at the top of the
  /// contractor's "My Tasks" checklist.
  Stream<List<ProjectTask>> watchTasksForContractor(String userId) {
    return (select(projectTasks)
          ..where(
            (tbl) =>
                tbl.assignedTo.equals(userId) &
                tbl.deletedAt.isNull() &
                tbl.status.isNotIn(const ['complete']),
          )
          ..orderBy([
            (tbl) => OrderingTerm(
                  expression: tbl.priority.caseMatch(
                    when: {
                      const Constant('urgent'): const Constant(0),
                      const Constant('high'): const Constant(1),
                      const Constant('medium'): const Constant(2),
                    },
                    orElse: const Constant(3),
                  ),
                ),
            (tbl) => OrderingTerm(
                  expression: tbl.dueDate,
                ),
          ]))
        .watch();
  }

  /// Reactive stream of a single task by ID.
  ///
  /// Used by TaskDetailScreen to observe live status updates.
  /// Emits null when the task is not found (deleted or unknown ID).
  Stream<ProjectTask?> watchTaskById(String id) {
    return (select(projectTasks)
          ..where(
            (tbl) => tbl.id.equals(id) & tbl.deletedAt.isNull(),
          )
          ..limit(1))
        .watchSingleOrNull();
  }

  /// Reactive stream of all tasks for a trade scope including completed tasks.
  ///
  /// Used for GC read-only views where all task states must be visible.
  /// Ordered by [sortOrder] for consistent task list display.
  Stream<List<ProjectTask>> watchTasksByScopeWithStatus(String tradeScopeId) {
    return (select(projectTasks)
          ..where(
            (tbl) =>
                tbl.tradeScopeId.equals(tradeScopeId) &
                tbl.deletedAt.isNull(),
          )
          ..orderBy([(tbl) => OrderingTerm.asc(tbl.sortOrder)]))
        .watch();
  }

  /// Insert a new task and atomically enqueue a CREATE sync item.
  Future<void> insertTask(ProjectTasksCompanion entry) async {
    await db.transaction(() async {
      await into(projectTasks).insert(entry);
      await into(syncQueue).insert(
        _buildQueueEntry(
          entityType: 'task',
          entityId: entry.id.value,
          operation: 'CREATE',
          payload: _taskPayload(entry),
        ),
      );
    });
  }

  /// Update a task and atomically enqueue an UPDATE sync item.
  Future<void> updateTask(String id, ProjectTasksCompanion entry) async {
    await db.transaction(() async {
      await (update(projectTasks)..where((tbl) => tbl.id.equals(id)))
          .write(entry);
      await into(syncQueue).insert(
        _buildQueueEntry(
          entityType: 'task',
          entityId: id,
          operation: 'UPDATE',
          payload: _taskPayload(entry),
        ),
      );
    });
  }

  /// Soft-delete a task and atomically enqueue a DELETE sync item.
  Future<void> softDeleteTask(String id) async {
    await db.transaction(() async {
      await (update(projectTasks)..where((tbl) => tbl.id.equals(id))).write(
        ProjectTasksCompanion(deletedAt: Value(DateTime.now())),
      );
      await into(syncQueue).insert(
        _buildQueueEntry(
          entityType: 'task',
          entityId: id,
          operation: 'DELETE',
          payload: {'id': id},
        ),
      );
    });
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

  /// Build a JSON-serializable payload map from a [ProjectTasksCompanion].
  Map<String, dynamic> _taskPayload(ProjectTasksCompanion entry) {
    return {
      if (entry.id.present) 'id': entry.id.value,
      if (entry.companyId.present) 'companyId': entry.companyId.value,
      if (entry.tradeScopeId.present) 'tradeScopeId': entry.tradeScopeId.value,
      if (entry.title.present) 'title': entry.title.value,
      if (entry.description.present) 'description': entry.description.value,
      if (entry.status.present) 'status': entry.status.value,
      if (entry.sortOrder.present) 'sortOrder': entry.sortOrder.value,
      if (entry.priority.present) 'priority': entry.priority.value,
      if (entry.estimatedHours.present)
        'estimatedHours': entry.estimatedHours.value,
      if (entry.estimatedCost.present)
        'estimatedCost': entry.estimatedCost.value,
      if (entry.dueDate.present)
        'dueDate': entry.dueDate.value?.toIso8601String(),
      if (entry.photoRequired.present)
        'photoRequired': entry.photoRequired.value,
      if (entry.assignedTo.present) 'assignedTo': entry.assignedTo.value,
      if (entry.materialsNeeded.present)
        'materialsNeeded': entry.materialsNeeded.value,
      if (entry.zoneId.present) 'zoneId': entry.zoneId.value,
      if (entry.startDate.present)
        'startDate': entry.startDate.value?.toIso8601String(),
      if (entry.version.present) 'version': entry.version.value,
      if (entry.createdAt.present)
        'createdAt': entry.createdAt.value.toIso8601String(),
      if (entry.updatedAt.present)
        'updatedAt': entry.updatedAt.value.toIso8601String(),
    };
  }
}
