import 'dart:convert';

import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:uuid/uuid.dart';

import '../../../core/database/app_database.dart';
import '../../../core/database/tables/job_notes.dart';
import '../../../core/database/tables/attachments.dart';
import '../../../core/database/tables/sync_queue.dart';

part 'note_dao.g.dart';

/// Drift DAO for JobNote CRUD with transactional outbox dual-write.
///
/// All read methods return [Stream] — offline-first, reactive to local DB changes.
///
/// Every mutating method uses [db.transaction] to atomically write to BOTH
/// the job_notes table AND sync_queue outbox. If either write fails, both are
/// rolled back — no orphaned queue items, no untracked mutations.
///
/// [upsertFromSync] is the sync-pull path and does NOT write to the
/// sync_queue — this IS the sync; writing to the queue would create an infinite loop.
@DriftAccessor(
  tables: [JobNotes, Attachments, SyncQueue],
)
class NoteDao extends DatabaseAccessor<AppDatabase> with _$NoteDaoMixin {
  NoteDao(super.db);

  // ────────────────────────────────────────────────────────────────────────
  // Note streams
  // ────────────────────────────────────────────────────────────────────────

  /// Reactive stream of active (non-deleted) notes for a job.
  ///
  /// Ordered newest-first for the field notes list view.
  /// Does NOT include attachments — use [watchNotesWithAttachmentsForJob]
  /// for the full NoteEntity graph.
  Stream<List<JobNote>> watchNotesForJob(String jobId) {
    return (select(jobNotes)
          ..where(
            (tbl) =>
                tbl.jobId.equals(jobId) & tbl.deletedAt.isNull(),
          )
          ..orderBy([(tbl) => OrderingTerm.desc(tbl.createdAt)]))
        .watch();
  }

  // ────────────────────────────────────────────────────────────────────────
  // Note mutations (transactional outbox pattern)
  // ────────────────────────────────────────────────────────────────────────

  /// Insert a new job note and atomically enqueue a CREATE sync item.
  ///
  /// Both the entity write and sync_queue insert happen in a single
  /// transaction — if either fails, both are rolled back.
  ///
  /// Returns the generated note UUID.
  Future<String> insertNote({
    required String companyId,
    required String jobId,
    required String authorId,
    required String body,
  }) async {
    final now = DateTime.now();
    final noteId = const Uuid().v4();

    await db.transaction(() async {
      await into(jobNotes).insert(
        JobNotesCompanion.insert(
          id: Value(noteId),
          companyId: companyId,
          jobId: jobId,
          authorId: authorId,
          body: body,
          createdAt: now,
          updatedAt: now,
        ),
      );
      await into(syncQueue).insert(
        _buildQueueEntry(
          entityType: 'job_note',
          entityId: noteId,
          operation: 'CREATE',
          payload: {
            'id': noteId,
            'company_id': companyId,
            'job_id': jobId,
            'author_id': authorId,
            'body': body,
            'version': 1,
            'created_at': now.toIso8601String(),
            'updated_at': now.toIso8601String(),
          },
        ),
      );
    });

    return noteId;
  }

  // ────────────────────────────────────────────────────────────────────────
  // Sync pull upsert
  // ────────────────────────────────────────────────────────────────────────

  /// Upsert a job note from a sync pull response (server-wins on conflict).
  ///
  /// No sync_queue entry — this IS the sync; writing to the queue would
  /// cause an infinite sync loop.
  Future<void> upsertFromSync(Map<String, dynamic> data) async {
    final deletedAt = data['deleted_at'] != null
        ? DateTime.parse(data['deleted_at'] as String)
        : null;

    final companion = JobNotesCompanion(
      id: Value(data['id'] as String),
      companyId: Value(data['company_id'] as String),
      jobId: Value(data['job_id'] as String),
      authorId: Value(data['author_id'] as String),
      body: Value(data['body'] as String),
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

    await into(jobNotes).insertOnConflictUpdate(companion);
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
