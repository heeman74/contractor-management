/// Unit tests for TaskAttachmentDao — Drift in-memory database.
///
/// Tests cover:
/// 1. insertAttachment creates record and sync queue entry (entityType=task_attachment)
/// 2. watchByTask returns attachments ordered by sortOrder ASC
/// 3. updateAnnotation stores JSON and creates UPDATE sync queue entry
/// 4. watchPhotoCountByTask counts only photo-type attachments
/// 5. deleteAttachment soft-deletes the record and creates DELETE sync queue entry
library;

import 'package:contractorhub/core/database/app_database.dart';
import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

AppDatabase _openTestDb() => AppDatabase(NativeDatabase.memory());

Future<void> _seedCompany(AppDatabase db, String id) async {
  await db.companyDao.insertCompany(CompaniesCompanion.insert(
    id: Value(id),
    name: 'Company $id',
    version: const Value(1),
    createdAt: DateTime.now(),
    updatedAt: DateTime.now(),
  ));
}

Future<void> _seedProject(AppDatabase db,
    {required String id, required String companyId}) async {
  final now = DateTime.now();
  await db.projectDao.insertProject(ProjectsCompanion.insert(
    id: Value(id),
    companyId: companyId,
    name: 'Project $id',
    status: const Value('planning'),
    version: const Value(1),
    createdAt: now,
    updatedAt: now,
  ));
}

Future<void> _seedScope(AppDatabase db,
    {required String id,
    required String companyId,
    required String projectId}) async {
  final now = DateTime.now();
  await db.tradeScopeDao.insertScope(TradeScopesCompanion.insert(
    id: Value(id),
    companyId: companyId,
    projectId: projectId,
    tradeName: 'Electrical',
    version: const Value(1),
    createdAt: now,
    updatedAt: now,
  ));
}

Future<void> _seedTask(AppDatabase db,
    {required String id,
    required String companyId,
    required String tradeScopeId}) async {
  final now = DateTime.now();
  await db.taskDao.insertTask(ProjectTasksCompanion.insert(
    id: Value(id),
    companyId: companyId,
    tradeScopeId: tradeScopeId,
    title: 'Task $id',
    version: const Value(1),
    createdAt: now,
    updatedAt: now,
  ));
}

void main() {
  group('TaskAttachmentDao', () {
    late AppDatabase db;

    setUp(() async {
      db = _openTestDb();
      await _seedCompany(db, 'co-1');
      await _seedProject(db, id: 'proj-1', companyId: 'co-1');
      await _seedScope(db,
          id: 'scope-1', companyId: 'co-1', projectId: 'proj-1');
      await _seedTask(db,
          id: 'task-1', companyId: 'co-1', tradeScopeId: 'scope-1');
      await _seedTask(db,
          id: 'task-2', companyId: 'co-1', tradeScopeId: 'scope-1');
    });

    tearDown(() async => db.close());

    test(
        'insertAttachment creates record and sync queue entry with entityType=task_attachment',
        () async {
      final now = DateTime.now();
      await db.taskAttachmentDao.insertAttachment(
        TaskAttachmentsCompanion.insert(
          id: const Value('att-1'),
          companyId: 'co-1',
          taskId: 'task-1',
          attachmentType: 'photo',
          sortOrder: const Value(0),
          createdAt: now,
          updatedAt: now,
        ),
      );

      // Verify attachment was created
      final attachments =
          await db.taskAttachmentDao.watchByTask('task-1').first;
      expect(attachments, hasLength(1));
      expect(attachments.first.id, 'att-1');
      expect(attachments.first.taskId, 'task-1');
      expect(attachments.first.attachmentType, 'photo');
      expect(attachments.first.deletedAt, isNull);

      // Verify sync queue entry was created
      final queueItems = await db.syncQueueDao.getAllItems();
      final attItems = queueItems
          .where((item) =>
              item.entityType == 'task_attachment' &&
              item.entityId == 'att-1')
          .toList();
      expect(attItems, hasLength(1));
      expect(attItems.first.operation, 'CREATE');
      expect(attItems.first.status, 'pending');
    });

    test('watchByTask returns attachments ordered by sortOrder ASC', () async {
      final now = DateTime.now();

      // Insert higher sortOrder first
      await db.taskAttachmentDao.insertAttachment(
        TaskAttachmentsCompanion.insert(
          id: const Value('att-second'),
          companyId: 'co-1',
          taskId: 'task-1',
          attachmentType: 'photo',
          sortOrder: const Value(5),
          createdAt: now,
          updatedAt: now,
        ),
      );

      // Insert lower sortOrder second
      await db.taskAttachmentDao.insertAttachment(
        TaskAttachmentsCompanion.insert(
          id: const Value('att-first'),
          companyId: 'co-1',
          taskId: 'task-1',
          attachmentType: 'photo',
          sortOrder: const Value(1),
          createdAt: now,
          updatedAt: now,
        ),
      );

      final attachments =
          await db.taskAttachmentDao.watchByTask('task-1').first;
      expect(attachments, hasLength(2));
      expect(attachments.first.id, 'att-first'); // sortOrder=1 comes first
      expect(attachments.last.id, 'att-second'); // sortOrder=5 comes last
    });

    test('updateAnnotation stores JSON and creates UPDATE sync queue entry',
        () async {
      final now = DateTime.now();
      await db.taskAttachmentDao.insertAttachment(
        TaskAttachmentsCompanion.insert(
          id: const Value('att-annotate'),
          companyId: 'co-1',
          taskId: 'task-1',
          attachmentType: 'photo',
          sortOrder: const Value(0),
          createdAt: now,
          updatedAt: now,
        ),
      );

      // Verify no annotation initially
      final before =
          await db.taskAttachmentDao.watchByTask('task-1').first;
      expect(before.first.annotationData, isNull);

      // Apply annotation
      const annotationJson =
          '{"strokes":[{"type":"arrow","x1":10,"y1":20,"x2":100,"y2":80}]}';
      await db.taskAttachmentDao.updateAnnotation('att-annotate', annotationJson);

      // Verify annotation was stored
      final after = await db.taskAttachmentDao.watchByTask('task-1').first;
      expect(after.first.annotationData, annotationJson);

      // Verify UPDATE sync queue entry was created
      final queueItems = await db.syncQueueDao.getAllItems();
      final updateItems = queueItems
          .where((item) =>
              item.entityType == 'task_attachment' &&
              item.entityId == 'att-annotate' &&
              item.operation == 'UPDATE')
          .toList();
      expect(updateItems, hasLength(1));
    });

    test('watchPhotoCountByTask counts only photo-type attachments', () async {
      final now = DateTime.now();

      // Insert 1 photo
      await db.taskAttachmentDao.insertAttachment(
        TaskAttachmentsCompanion.insert(
          id: const Value('att-photo'),
          companyId: 'co-1',
          taskId: 'task-1',
          attachmentType: 'photo',
          sortOrder: const Value(0),
          createdAt: now,
          updatedAt: now,
        ),
      );

      // Insert 1 document
      await db.taskAttachmentDao.insertAttachment(
        TaskAttachmentsCompanion.insert(
          id: const Value('att-doc'),
          companyId: 'co-1',
          taskId: 'task-1',
          attachmentType: 'document',
          sortOrder: const Value(1),
          createdAt: now,
          updatedAt: now,
        ),
      );

      // Photo count should be 1 (not 2)
      final photoCount =
          await db.taskAttachmentDao.watchPhotoCountByTask('task-1').first;
      expect(photoCount, 1);

      // Doc count should also be 1
      final docCount =
          await db.taskAttachmentDao.watchDocCountByTask('task-1').first;
      expect(docCount, 1);

      // Total count should be 2
      final totalCount =
          await db.taskAttachmentDao.watchCountByTask('task-1').first;
      expect(totalCount, 2);
    });

    test('deleteAttachment soft-deletes and creates DELETE sync queue entry',
        () async {
      final now = DateTime.now();
      await db.taskAttachmentDao.insertAttachment(
        TaskAttachmentsCompanion.insert(
          id: const Value('att-to-delete'),
          companyId: 'co-1',
          taskId: 'task-1',
          attachmentType: 'photo',
          sortOrder: const Value(0),
          createdAt: now,
          updatedAt: now,
        ),
      );

      // Verify attachment exists
      final before =
          await db.taskAttachmentDao.watchByTask('task-1').first;
      expect(before, hasLength(1));

      // Delete the attachment
      await db.taskAttachmentDao.deleteAttachment('att-to-delete');

      // Verify it is soft-deleted (excluded from active stream)
      final after = await db.taskAttachmentDao.watchByTask('task-1').first;
      expect(after, isEmpty);

      // Verify DELETE sync queue entry was created
      final queueItems = await db.syncQueueDao.getAllItems();
      final deleteItems = queueItems
          .where((item) =>
              item.entityType == 'task_attachment' &&
              item.entityId == 'att-to-delete' &&
              item.operation == 'DELETE')
          .toList();
      expect(deleteItems, hasLength(1));
    });
  });
}
