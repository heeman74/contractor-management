import 'dart:convert';

import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:uuid/uuid.dart';

import '../../../core/database/app_database.dart';
import '../../../core/database/tables/sync_queue.dart';
import '../../../core/database/tables/task_attachments.dart';

part 'task_attachment_dao.g.dart';

/// Drift DAO for TaskAttachment CRUD with transactional outbox dual-write.
///
/// All read methods return [Stream] — offline-first, reactive to local DB changes.
///
/// Every mutating method uses [db.transaction] to atomically write to BOTH
/// the task_attachments table AND sync_queue outbox. If either write fails,
/// both are rolled back — no orphaned queue items, no untracked mutations.
///
/// Annotation storage is non-destructive: base photo (localPath/remoteUrl)
/// is never modified; annotation JSON is stored in [annotationData] column.
@DriftAccessor(tables: [TaskAttachments, SyncQueue])
class TaskAttachmentDao extends DatabaseAccessor<AppDatabase>
    with _$TaskAttachmentDaoMixin {
  TaskAttachmentDao(super.db);

  // ────────────────────────────────────────────────────────────────────────
  // Attachment streams
  // ────────────────────────────────────────────────────────────────────────

  /// Reactive stream of active (non-deleted) attachments for a task.
  ///
  /// Ordered by [sortOrder] for consistent display in the attachment viewer.
  Stream<List<TaskAttachment>> watchByTask(String taskId) {
    return (select(taskAttachments)
          ..where(
            (tbl) =>
                tbl.taskId.equals(taskId) & tbl.deletedAt.isNull(),
          )
          ..orderBy([(tbl) => OrderingTerm.asc(tbl.sortOrder)]))
        .watch();
  }

  /// Reactive count stream of all active attachments for a task.
  ///
  /// Used for photo gate checking (e.g., require at least 1 photo to complete).
  Stream<int> watchCountByTask(String taskId) {
    final countExpr = taskAttachments.id.count();
    final query = selectOnly(taskAttachments)
      ..addColumns([countExpr])
      ..where(
        taskAttachments.taskId.equals(taskId) &
            taskAttachments.deletedAt.isNull(),
      );
    return query.watchSingleOrNull().map((row) => row?.read(countExpr) ?? 0);
  }

  /// Reactive count stream of photo-type attachments for a task.
  ///
  /// Used to enforce photo limits and track completion requirements.
  Stream<int> watchPhotoCountByTask(String taskId) {
    final countExpr = taskAttachments.id.count();
    final query = selectOnly(taskAttachments)
      ..addColumns([countExpr])
      ..where(
        taskAttachments.taskId.equals(taskId) &
            taskAttachments.attachmentType.equals('photo') &
            taskAttachments.deletedAt.isNull(),
      );
    return query.watchSingleOrNull().map((row) => row?.read(countExpr) ?? 0);
  }

  /// Reactive count stream of document-type attachments for a task.
  ///
  /// Used to enforce document limits and display badge counts.
  Stream<int> watchDocCountByTask(String taskId) {
    final countExpr = taskAttachments.id.count();
    final query = selectOnly(taskAttachments)
      ..addColumns([countExpr])
      ..where(
        taskAttachments.taskId.equals(taskId) &
            taskAttachments.attachmentType.equals('document') &
            taskAttachments.deletedAt.isNull(),
      );
    return query.watchSingleOrNull().map((row) => row?.read(countExpr) ?? 0);
  }

  // ────────────────────────────────────────────────────────────────────────
  // Attachment mutations (transactional outbox pattern)
  // ────────────────────────────────────────────────────────────────────────

  /// Insert a new task attachment and atomically enqueue a CREATE sync item.
  ///
  /// Both the entity write and sync_queue insert happen in a single
  /// transaction — if either fails, both are rolled back.
  Future<void> insertAttachment(TaskAttachmentsCompanion entry) async {
    await db.transaction(() async {
      await into(taskAttachments).insert(entry);
      await into(syncQueue).insert(
        _buildQueueEntry(
          entityType: 'task_attachment',
          entityId: entry.id.present ? entry.id.value : '',
          operation: 'CREATE',
          payload: _attachmentPayload(entry),
        ),
      );
    });
  }

  /// Update the annotation JSON for an attachment and enqueue an UPDATE sync item.
  ///
  /// Non-destructive: only [annotationData] and [updatedAt] are modified.
  /// The base photo file is never touched.
  Future<void> updateAnnotation(String id, String annotationJson) async {
    final now = DateTime.now();
    await db.transaction(() async {
      await (update(taskAttachments)..where((tbl) => tbl.id.equals(id))).write(
        TaskAttachmentsCompanion(
          annotationData: Value(annotationJson),
          updatedAt: Value(now),
        ),
      );
      await into(syncQueue).insert(
        _buildQueueEntry(
          entityType: 'task_attachment',
          entityId: id,
          operation: 'UPDATE',
          payload: {
            'id': id,
            'annotationData': annotationJson,
            'updatedAt': now.toIso8601String(),
          },
        ),
      );
    });
  }

  /// Soft-delete a task attachment and atomically enqueue a DELETE sync item.
  ///
  /// Sets [deletedAt] to the current timestamp — the record is retained
  /// for sync tombstone propagation and excluded from all live queries.
  Future<void> deleteAttachment(String id) async {
    await db.transaction(() async {
      await (update(taskAttachments)..where((tbl) => tbl.id.equals(id))).write(
        TaskAttachmentsCompanion(deletedAt: Value(DateTime.now())),
      );
      await into(syncQueue).insert(
        _buildQueueEntry(
          entityType: 'task_attachment',
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

  /// Build a JSON-serializable payload map from a [TaskAttachmentsCompanion].
  Map<String, dynamic> _attachmentPayload(TaskAttachmentsCompanion entry) {
    return {
      if (entry.id.present) 'id': entry.id.value,
      if (entry.companyId.present) 'companyId': entry.companyId.value,
      if (entry.taskId.present) 'taskId': entry.taskId.value,
      if (entry.attachmentType.present)
        'attachmentType': entry.attachmentType.value,
      if (entry.remoteUrl.present) 'remoteUrl': entry.remoteUrl.value,
      if (entry.localPath.present) 'localPath': entry.localPath.value,
      if (entry.caption.present) 'caption': entry.caption.value,
      if (entry.annotationData.present)
        'annotationData': entry.annotationData.value,
      if (entry.sortOrder.present) 'sortOrder': entry.sortOrder.value,
      if (entry.version.present) 'version': entry.version.value,
      if (entry.createdAt.present)
        'createdAt': entry.createdAt.value.toIso8601String(),
      if (entry.updatedAt.present)
        'updatedAt': entry.updatedAt.value.toIso8601String(),
    };
  }
}
