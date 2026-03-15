/// Unit tests for AttachmentDao — Drift in-memory database.
///
/// Tests cover:
/// 1. insertAttachment creates attachment with uploadStatus = pending_upload
/// 2. insertAttachment stores correct companyId, noteId, attachmentType, localPath
/// 3. getPendingUploads returns attachments with pending_upload status
/// 4. getPendingUploads returns attachments with failed status
/// 5. getPendingUploads excludes uploaded attachments
/// 6. getPendingUploads excludes soft-deleted attachments
/// 7. markUploaded sets remoteUrl and uploadStatus to uploaded
/// 8. watchAttachmentsForNote returns only attachments for given noteId
/// 9. watchAttachmentsForNote excludes soft-deleted attachments
/// 10. watchAttachmentsForNote orders by sortOrder ascending
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

Future<void> _seedUser(AppDatabase db,
    {required String id,
    required String companyId,
    String email = 'user@test.com'}) async {
  final now = DateTime.now();
  await db.userDao.insertUser(UsersCompanion.insert(
    id: Value(id),
    companyId: companyId,
    email: email,
    version: const Value(1),
    createdAt: now,
    updatedAt: now,
  ));
}

Future<void> _seedJob(AppDatabase db,
    {required String id, required String companyId}) async {
  final now = DateTime.now();
  await db.jobDao.insertJob(JobsCompanion.insert(
    id: Value(id),
    companyId: companyId,
    description: 'Test Job $id',
    tradeType: 'plumbing',
    status: const Value('quote'),
    priority: const Value('medium'),
    statusHistory: const Value('[]'),
    tags: const Value('[]'),
    version: const Value(1),
    createdAt: now,
    updatedAt: now,
  ));
}

Future<String> _seedNote(AppDatabase db,
    {required String companyId,
    required String jobId,
    required String authorId}) async {
  return db.noteDao.insertNote(
    companyId: companyId,
    jobId: jobId,
    authorId: authorId,
    body: 'Test note',
  );
}

void main() {
  group('AttachmentDao', () {
    late AppDatabase db;
    late String noteId;

    setUp(() async {
      db = _openTestDb();
      await _seedCompany(db, 'co-1');
      await _seedUser(db, id: 'u-1', companyId: 'co-1');
      await _seedJob(db, id: 'job-1', companyId: 'co-1');
      noteId = await _seedNote(db,
          companyId: 'co-1', jobId: 'job-1', authorId: 'u-1');
    });

    tearDown(() async => await db.close());

    test('insertAttachment creates attachment with uploadStatus pending_upload',
        () async {
      final attachmentId = await db.attachmentDao.insertAttachment(
        companyId: 'co-1',
        noteId: noteId,
        attachmentType: 'photo',
        localPath: '/tmp/photo1.jpg',
      );

      final attachments =
          await db.attachmentDao.watchAttachmentsForNote(noteId).first;
      expect(attachments, hasLength(1));
      expect(attachments.first.id, attachmentId);
      expect(attachments.first.uploadStatus, 'pending_upload');
    });

    test('insertAttachment stores correct companyId, noteId, attachmentType, localPath',
        () async {
      await db.attachmentDao.insertAttachment(
        companyId: 'co-1',
        noteId: noteId,
        attachmentType: 'drawing',
        localPath: '/tmp/drawing1.png',
        caption: 'Floor plan',
        sortOrder: 2,
      );

      final attachments =
          await db.attachmentDao.watchAttachmentsForNote(noteId).first;
      expect(attachments, hasLength(1));
      expect(attachments.first.companyId, 'co-1');
      expect(attachments.first.noteId, noteId);
      expect(attachments.first.attachmentType, 'drawing');
      expect(attachments.first.localPath, '/tmp/drawing1.png');
      expect(attachments.first.caption, 'Floor plan');
      expect(attachments.first.sortOrder, 2);
    });

    test('getPendingUploads returns attachments with pending_upload status',
        () async {
      await db.attachmentDao.insertAttachment(
        companyId: 'co-1',
        noteId: noteId,
        attachmentType: 'photo',
        localPath: '/tmp/photo1.jpg',
      );

      final pending = await db.attachmentDao.getPendingUploads();
      expect(pending, hasLength(1));
      expect(pending.first.uploadStatus, 'pending_upload');
    });

    test('getPendingUploads returns attachments with failed status', () async {
      final id = await db.attachmentDao.insertAttachment(
        companyId: 'co-1',
        noteId: noteId,
        attachmentType: 'photo',
        localPath: '/tmp/photo1.jpg',
      );

      // Mark as failed
      await db.attachmentDao.incrementRetry(id);

      final pending = await db.attachmentDao.getPendingUploads();
      expect(pending, hasLength(1));
      expect(pending.first.uploadStatus, 'failed');
    });

    test('getPendingUploads excludes uploaded attachments', () async {
      final id = await db.attachmentDao.insertAttachment(
        companyId: 'co-1',
        noteId: noteId,
        attachmentType: 'photo',
        localPath: '/tmp/photo1.jpg',
      );

      await db.attachmentDao.markUploaded(id, 'https://cdn.example.com/photo1.jpg');

      final pending = await db.attachmentDao.getPendingUploads();
      expect(pending, isEmpty);
    });

    test('getPendingUploads excludes soft-deleted attachments', () async {
      // Insert via upsertFromSync with deletedAt set
      final now = DateTime.now();
      await db.attachmentDao.upsertFromSync({
        'id': 'att-deleted',
        'company_id': 'co-1',
        'note_id': noteId,
        'attachment_type': 'photo',
        'local_path': '/tmp/deleted.jpg',
        'upload_status': 'pending_upload',
        'created_at': now.toIso8601String(),
        'updated_at': now.toIso8601String(),
        'deleted_at': now.toIso8601String(),
      });

      final pending = await db.attachmentDao.getPendingUploads();
      expect(pending, isEmpty);
    });

    test('markUploaded sets remoteUrl and uploadStatus to uploaded', () async {
      final id = await db.attachmentDao.insertAttachment(
        companyId: 'co-1',
        noteId: noteId,
        attachmentType: 'photo',
        localPath: '/tmp/photo1.jpg',
      );

      await db.attachmentDao.markUploaded(id, 'https://cdn.example.com/photo1.jpg');

      final attachments =
          await db.attachmentDao.watchAttachmentsForNote(noteId).first;
      expect(attachments, hasLength(1));
      expect(attachments.first.uploadStatus, 'uploaded');
      expect(attachments.first.remoteUrl, 'https://cdn.example.com/photo1.jpg');
    });

    test('watchAttachmentsForNote returns only attachments for given noteId',
        () async {
      // Create a second note
      final noteId2 = await _seedNote(db,
          companyId: 'co-1', jobId: 'job-1', authorId: 'u-1');

      await db.attachmentDao.insertAttachment(
        companyId: 'co-1',
        noteId: noteId,
        attachmentType: 'photo',
        localPath: '/tmp/note1_photo.jpg',
      );

      await db.attachmentDao.insertAttachment(
        companyId: 'co-1',
        noteId: noteId2,
        attachmentType: 'photo',
        localPath: '/tmp/note2_photo.jpg',
      );

      final attachmentsNote1 =
          await db.attachmentDao.watchAttachmentsForNote(noteId).first;
      expect(attachmentsNote1, hasLength(1));
      expect(attachmentsNote1.first.localPath, '/tmp/note1_photo.jpg');

      final attachmentsNote2 =
          await db.attachmentDao.watchAttachmentsForNote(noteId2).first;
      expect(attachmentsNote2, hasLength(1));
      expect(attachmentsNote2.first.localPath, '/tmp/note2_photo.jpg');
    });

    test('watchAttachmentsForNote excludes soft-deleted attachments', () async {
      await db.attachmentDao.insertAttachment(
        companyId: 'co-1',
        noteId: noteId,
        attachmentType: 'photo',
        localPath: '/tmp/alive.jpg',
      );

      final now = DateTime.now();
      await db.attachmentDao.upsertFromSync({
        'id': 'att-soft-deleted',
        'company_id': 'co-1',
        'note_id': noteId,
        'attachment_type': 'photo',
        'local_path': '/tmp/deleted.jpg',
        'upload_status': 'pending_upload',
        'created_at': now.toIso8601String(),
        'updated_at': now.toIso8601String(),
        'deleted_at': now.toIso8601String(),
      });

      final attachments =
          await db.attachmentDao.watchAttachmentsForNote(noteId).first;
      expect(attachments, hasLength(1));
      expect(attachments.first.localPath, '/tmp/alive.jpg');
    });

    test('watchAttachmentsForNote orders by sortOrder ascending', () async {
      final now = DateTime.now();

      // Insert with sortOrder 2 first
      await db.attachmentDao.upsertFromSync({
        'id': 'att-second',
        'company_id': 'co-1',
        'note_id': noteId,
        'attachment_type': 'photo',
        'local_path': '/tmp/second.jpg',
        'upload_status': 'pending_upload',
        'sort_order': 2,
        'created_at': now.toIso8601String(),
        'updated_at': now.toIso8601String(),
      });

      // Insert with sortOrder 0 second
      await db.attachmentDao.upsertFromSync({
        'id': 'att-first',
        'company_id': 'co-1',
        'note_id': noteId,
        'attachment_type': 'photo',
        'local_path': '/tmp/first.jpg',
        'upload_status': 'pending_upload',
        'sort_order': 0,
        'created_at': now.toIso8601String(),
        'updated_at': now.toIso8601String(),
      });

      final attachments =
          await db.attachmentDao.watchAttachmentsForNote(noteId).first;
      expect(attachments, hasLength(2));
      expect(attachments.first.id, 'att-first');
      expect(attachments.last.id, 'att-second');
    });
  });
}
