import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:uuid/uuid.dart';

import '../../../core/database/app_database.dart';
import '../../../core/database/tables/sync_queue.dart';
import '../../../core/database/tables/task_dependencies.dart';
import '../../../core/database/tables/tasks.dart';
import '../../../core/database/tables/trade_scopes.dart';

part 'task_dependency_dao.g.dart';

/// Drift DAO for TaskDependency CRUD and reactive queries.
///
/// TaskDependencies model the directed edges in the task dependency graph.
/// Each edge has a predecessor and successor task, a type (FS/SS/FF/SE),
/// and optional lag/lead days.
///
/// The DAO provides reactive streams for watching dependencies by project
/// (through TradeScopes) and by individual task. Writes are transactional
/// with the sync queue for offline-first operation.
@DriftAccessor(tables: [TaskDependencies, ProjectTasks, TradeScopes, SyncQueue])
class TaskDependencyDao extends DatabaseAccessor<AppDatabase>
    with _$TaskDependencyDaoMixin {
  TaskDependencyDao(super.db);

  /// Watch all non-deleted dependencies for tasks in a given project.
  ///
  /// Joins through ProjectTasks → TradeScopes to filter by project ID.
  /// Emits a new list whenever any dependency in the project changes.
  Stream<List<TaskDependency>> watchByProject(String projectId) {
    final query = select(taskDependencies).join([
      innerJoin(
        projectTasks,
        projectTasks.id.equalsExp(taskDependencies.predecessorTaskId),
      ),
      innerJoin(
        tradeScopes,
        tradeScopes.id.equalsExp(projectTasks.tradeScopeId),
      ),
    ])
      ..where(tradeScopes.projectId.equals(projectId))
      ..where(taskDependencies.deletedAt.isNull());

    return query
        .watch()
        .map((rows) => rows.map((r) => r.readTable(taskDependencies)).toList());
  }

  /// Watch all non-deleted dependencies where [taskId] is the successor.
  ///
  /// Returns the predecessor edges of this task — tasks that must complete
  /// (or start) before this task can proceed.
  Stream<List<TaskDependency>> watchPredecessors(String taskId) {
    return (select(taskDependencies)
          ..where((t) => t.successorTaskId.equals(taskId))
          ..where((t) => t.deletedAt.isNull()))
        .watch();
  }

  /// Watch all non-deleted dependencies where [taskId] is the predecessor.
  ///
  /// Returns the successor edges of this task — tasks that are blocked
  /// until this task completes (or starts).
  Stream<List<TaskDependency>> watchSuccessors(String taskId) {
    return (select(taskDependencies)
          ..where((t) => t.predecessorTaskId.equals(taskId))
          ..where((t) => t.deletedAt.isNull()))
        .watch();
  }

  /// Upsert a dependency received from the backend sync pull.
  ///
  /// Uses insert-on-conflict-update for idempotency — safe to call
  /// multiple times with the same data.
  Future<void> upsertDependency(TaskDependenciesCompanion companion) async {
    await into(taskDependencies).insertOnConflictUpdate(companion);
  }

  /// Insert a new dependency and atomically enqueue a CREATE sync item.
  ///
  /// [companion.id] must already have a value (client-generated UUID).
  Future<void> insertWithSyncQueue(TaskDependenciesCompanion companion) async {
    await transaction(() async {
      await into(taskDependencies).insert(companion);
      await into(syncQueue).insert(
        _buildQueueEntry(
          entityType: 'task_dependency',
          entityId: companion.id.value,
          operation: 'CREATE',
          payload: {
            'id': companion.id.value,
            'predecessor_task_id': companion.predecessorTaskId.value,
            'successor_task_id': companion.successorTaskId.value,
            'dependency_type': companion.dependencyType.present
                ? companion.dependencyType.value
                : 'FS',
            'lag_days':
                companion.lagDays.present ? companion.lagDays.value : 0,
          },
        ),
      );
    });
  }

  /// Soft-delete a dependency and atomically enqueue a DELETE sync item.
  Future<void> softDeleteWithSyncQueue(String id) async {
    await transaction(() async {
      await (update(taskDependencies)..where((t) => t.id.equals(id)))
          .write(TaskDependenciesCompanion(deletedAt: Value(DateTime.now())));
      await into(syncQueue).insert(
        _buildQueueEntry(
          entityType: 'task_dependency',
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
}
