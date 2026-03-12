/// Unit tests for NoteDao — Drift in-memory database.
///
/// Tests cover:
/// 1. insertNote creates note with correct fields
/// 2. insertNote also creates sync_queue entry (dual-write outbox pattern)
/// 3. watchNotesForJob returns notes ordered by createdAt DESC (newest first)
/// 4. watchNotesForJob filters by jobId (notes for other jobs not returned)
/// 5. watchNotesForJob excludes soft-deleted notes
/// 6. upsertFromSync inserts new note from sync data
/// 7. upsertFromSync updates existing note (by id) from sync data
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

void main() {
  group('NoteDao', () {
    late AppDatabase db;

    setUp(() async {
      db = _openTestDb();
      await _seedCompany(db, 'co-1');
      await _seedCompany(db, 'co-2');
      await _seedUser(db, id: 'u-1', companyId: 'co-1', email: 'a@test.com');
      await _seedJob(db, id: 'job-1', companyId: 'co-1');
      await _seedJob(db, id: 'job-2', companyId: 'co-1');
    });

    tearDown(() async => await db.close());

    test('insertNote creates note in jobNotes table with correct fields',
        () async {
      final noteId = await db.noteDao.insertNote(
        companyId: 'co-1',
        jobId: 'job-1',
        authorId: 'u-1',
        body: 'Checked the pipes.',
      );

      final notes =
          await db.noteDao.watchNotesForJob('job-1').first;
      expect(notes, hasLength(1));
      expect(notes.first.id, noteId);
      expect(notes.first.companyId, 'co-1');
      expect(notes.first.jobId, 'job-1');
      expect(notes.first.authorId, 'u-1');
      expect(notes.first.body, 'Checked the pipes.');
      expect(notes.first.deletedAt, isNull);
    });

    test(
        'insertNote also creates sync_queue entry with entityType=job_note and operation=CREATE',
        () async {
      final noteId = await db.noteDao.insertNote(
        companyId: 'co-1',
        jobId: 'job-1',
        authorId: 'u-1',
        body: 'Inspection done.',
      );

      final queueItems = await db.syncQueueDao.getAllItems();
      final noteItems = queueItems
          .where((item) =>
              item.entityType == 'job_note' && item.entityId == noteId)
          .toList();
      expect(noteItems, hasLength(1));
      expect(noteItems.first.operation, 'CREATE');
      expect(noteItems.first.status, 'pending');
    });

    test('watchNotesForJob returns notes ordered by createdAt DESC (newest first)',
        () async {
      final now = DateTime.now();
      final older = now.subtract(const Duration(hours: 2));

      // Insert older note first
      await db.noteDao.upsertFromSync({
        'id': 'note-old',
        'company_id': 'co-1',
        'job_id': 'job-1',
        'author_id': 'u-1',
        'body': 'Older note',
        'version': 1,
        'created_at': older.toIso8601String(),
        'updated_at': older.toIso8601String(),
      });

      // Insert newer note second
      await db.noteDao.upsertFromSync({
        'id': 'note-new',
        'company_id': 'co-1',
        'job_id': 'job-1',
        'author_id': 'u-1',
        'body': 'Newer note',
        'version': 1,
        'created_at': now.toIso8601String(),
        'updated_at': now.toIso8601String(),
      });

      final notes = await db.noteDao.watchNotesForJob('job-1').first;
      expect(notes, hasLength(2));
      expect(notes.first.id, 'note-new');
      expect(notes.last.id, 'note-old');
    });

    test('watchNotesForJob filters by jobId (notes for other jobs not returned)',
        () async {
      await db.noteDao.insertNote(
        companyId: 'co-1',
        jobId: 'job-1',
        authorId: 'u-1',
        body: 'Note for job 1',
      );
      await db.noteDao.insertNote(
        companyId: 'co-1',
        jobId: 'job-2',
        authorId: 'u-1',
        body: 'Note for job 2',
      );

      final notesForJob1 =
          await db.noteDao.watchNotesForJob('job-1').first;
      expect(notesForJob1, hasLength(1));
      expect(notesForJob1.first.body, 'Note for job 1');

      final notesForJob2 =
          await db.noteDao.watchNotesForJob('job-2').first;
      expect(notesForJob2, hasLength(1));
      expect(notesForJob2.first.body, 'Note for job 2');
    });

    test('watchNotesForJob excludes soft-deleted notes (deletedAt not null)',
        () async {
      // Insert via insertNote (no deletedAt)
      final aliveId = await db.noteDao.insertNote(
        companyId: 'co-1',
        jobId: 'job-1',
        authorId: 'u-1',
        body: 'Alive note',
      );

      // Upsert a soft-deleted note via sync
      await db.noteDao.upsertFromSync({
        'id': 'note-deleted',
        'company_id': 'co-1',
        'job_id': 'job-1',
        'author_id': 'u-1',
        'body': 'Deleted note',
        'version': 1,
        'created_at': DateTime.now().toIso8601String(),
        'updated_at': DateTime.now().toIso8601String(),
        'deleted_at': DateTime.now().toIso8601String(),
      });

      final notes = await db.noteDao.watchNotesForJob('job-1').first;
      expect(notes, hasLength(1));
      expect(notes.first.id, aliveId);
    });

    test('upsertFromSync inserts new note from sync data', () async {
      await db.noteDao.upsertFromSync({
        'id': 'synced-note-1',
        'company_id': 'co-1',
        'job_id': 'job-1',
        'author_id': 'u-1',
        'body': 'Synced from server',
        'version': 2,
        'created_at': DateTime.now().toIso8601String(),
        'updated_at': DateTime.now().toIso8601String(),
      });

      final notes = await db.noteDao.watchNotesForJob('job-1').first;
      expect(notes, hasLength(1));
      expect(notes.first.id, 'synced-note-1');
      expect(notes.first.body, 'Synced from server');
      expect(notes.first.version, 2);
    });

    test('upsertFromSync updates existing note (by id) from sync data',
        () async {
      final now = DateTime.now();
      // Insert initial note
      await db.noteDao.upsertFromSync({
        'id': 'note-to-update',
        'company_id': 'co-1',
        'job_id': 'job-1',
        'author_id': 'u-1',
        'body': 'Original body',
        'version': 1,
        'created_at': now.toIso8601String(),
        'updated_at': now.toIso8601String(),
      });

      // Upsert with updated body and version
      final later = now.add(const Duration(minutes: 5));
      await db.noteDao.upsertFromSync({
        'id': 'note-to-update',
        'company_id': 'co-1',
        'job_id': 'job-1',
        'author_id': 'u-1',
        'body': 'Updated body',
        'version': 2,
        'created_at': now.toIso8601String(),
        'updated_at': later.toIso8601String(),
      });

      final notes = await db.noteDao.watchNotesForJob('job-1').first;
      expect(notes, hasLength(1));
      expect(notes.first.body, 'Updated body');
      expect(notes.first.version, 2);
    });
  });
}
