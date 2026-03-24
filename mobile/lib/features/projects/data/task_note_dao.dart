import 'dart:convert';

import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:uuid/uuid.dart';

import '../../../core/database/app_database.dart';
import '../../../core/database/tables/sync_queue.dart';
import '../../../core/database/tables/task_notes.dart';

part 'task_note_dao.g.dart';

/// Drift DAO for TaskNote CRUD with transactional outbox dual-write.
///
/// All read methods return [Stream] — offline-first, reactive to local DB changes.
///
/// Every mutating method uses [db.transaction] to atomically write to BOTH
/// the task_notes table AND sync_queue outbox. If either write fails, both
/// are rolled back — no orphaned queue items, no untracked mutations.
@DriftAccessor(tables: [TaskNotes, SyncQueue])
class TaskNoteDao extends DatabaseAccessor<AppDatabase>
    with _$TaskNoteDaoMixin {
  TaskNoteDao(super.db);

  // ────────────────────────────────────────────────────────────────────────
  // Note streams
  // ────────────────────────────────────────────────────────────────────────

  /// Reactive stream of active (non-deleted) notes for a task.
  ///
  /// Ordered newest-first for the field notes list view.
  Stream<List<TaskNote>> watchByTask(String taskId) {
    return (select(taskNotes)
          ..where(
            (tbl) =>
                tbl.taskId.equals(taskId) & tbl.deletedAt.isNull(),
          )
          ..orderBy([(tbl) => OrderingTerm.desc(tbl.createdAt)]))
        .watch();
  }

  /// Count of active (non-deleted) notes for a task.
  ///
  /// Used for progress indicators and badge counts.
  Future<int> countByTask(String taskId) async {
    final countExpr = taskNotes.id.count();
    final query = selectOnly(taskNotes)
      ..addColumns([countExpr])
      ..where(
        taskNotes.taskId.equals(taskId) & taskNotes.deletedAt.isNull(),
      );
    final result = await query.getSingleOrNull();
    return result?.read(countExpr) ?? 0;
  }

  // ────────────────────────────────────────────────────────────────────────
  // Note mutations (transactional outbox pattern)
  // ────────────────────────────────────────────────────────────────────────

  /// Insert a new task note and atomically enqueue a CREATE sync item.
  ///
  /// Both the entity write and sync_queue insert happen in a single
  /// transaction — if either fails, both are rolled back.
  Future<void> insertNote(TaskNotesCompanion entry) async {
    await db.transaction(() async {
      await into(taskNotes).insert(entry);
      await into(syncQueue).insert(
        _buildQueueEntry(
          entityType: 'task_note',
          entityId: entry.id.present ? entry.id.value : '',
          operation: 'CREATE',
          payload: _notePayload(entry),
        ),
      );
    });
  }

  /// Soft-delete a task note and atomically enqueue a DELETE sync item.
  ///
  /// Sets [deletedAt] to the current timestamp — the record is retained
  /// for sync tombstone propagation and excluded from all live queries.
  Future<void> deleteNote(String id) async {
    await db.transaction(() async {
      await (update(taskNotes)..where((tbl) => tbl.id.equals(id))).write(
        TaskNotesCompanion(deletedAt: Value(DateTime.now())),
      );
      await into(syncQueue).insert(
        _buildQueueEntry(
          entityType: 'task_note',
          entityId: id,
          operation: 'DELETE',
          payload: {'id': id},
        ),
      );
    });
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

  /// Build a JSON-serializable payload map from a [TaskNotesCompanion].
  Map<String, dynamic> _notePayload(TaskNotesCompanion entry) {
    return {
      if (entry.id.present) 'id': entry.id.value,
      if (entry.companyId.present) 'companyId': entry.companyId.value,
      if (entry.taskId.present) 'taskId': entry.taskId.value,
      if (entry.authorId.present) 'authorId': entry.authorId.value,
      if (entry.body.present) 'body': entry.body.value,
      if (entry.version.present) 'version': entry.version.value,
      if (entry.createdAt.present)
        'createdAt': entry.createdAt.value.toIso8601String(),
      if (entry.updatedAt.present)
        'updatedAt': entry.updatedAt.value.toIso8601String(),
    };
  }
}
