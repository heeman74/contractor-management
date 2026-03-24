/// Unit tests for TaskNoteDao — Drift in-memory database.
///
/// Tests cover:
/// 1. insertNote creates note and sync queue entry (entityType=task_note, operation=CREATE)
/// 2. watchByTask returns notes ordered by createdAt DESC (newest first)
/// 3. deleteNote soft-deletes note and creates DELETE sync queue entry
/// 4. watchByTask filters by taskId (notes for other tasks not returned)
/// 5. watchByTask excludes soft-deleted notes
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
    tradeName: 'Plumbing',
    version: const Value(1),
    createdAt: now,
    updatedAt: now,
  ));
}

Future<void> _seedTask(AppDatabase db,
    {required String id,
    required String companyId,
    required String tradeScopeId,
    String? assignedTo}) async {
  final now = DateTime.now();
  await db.taskDao.insertTask(ProjectTasksCompanion.insert(
    id: Value(id),
    companyId: companyId,
    tradeScopeId: tradeScopeId,
    title: 'Task $id',
    version: const Value(1),
    createdAt: now,
    updatedAt: now,
    assignedTo: Value(assignedTo),
  ));
}

void main() {
  group('TaskNoteDao', () {
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

    test('insertNote creates note and sync queue entry with entityType=task_note',
        () async {
      final now = DateTime.now();
      final noteId = const String.fromEnvironment('', defaultValue: 'note-1');
      await db.taskNoteDao.insertNote(TaskNotesCompanion.insert(
        id: const Value('note-1'),
        companyId: 'co-1',
        taskId: 'task-1',
        authorId: 'user-1',
        body: 'Installed main shutoff valve.',
        createdAt: now,
        updatedAt: now,
      ));

      // Verify the note was created
      final notes = await db.taskNoteDao.watchByTask('task-1').first;
      expect(notes, hasLength(1));
      expect(notes.first.id, 'note-1');
      expect(notes.first.taskId, 'task-1');
      expect(notes.first.authorId, 'user-1');
      expect(notes.first.body, 'Installed main shutoff valve.');
      expect(notes.first.deletedAt, isNull);

      // Verify sync queue entry was created
      final queueItems = await db.syncQueueDao.getAllItems();
      final noteItems = queueItems
          .where((item) =>
              item.entityType == 'task_note' && item.entityId == 'note-1')
          .toList();
      expect(noteItems, hasLength(1));
      expect(noteItems.first.operation, 'CREATE');
      expect(noteItems.first.status, 'pending');
    });

    test('watchByTask returns notes ordered by createdAt DESC (newest first)',
        () async {
      final now = DateTime.now();
      final older = now.subtract(const Duration(hours: 3));

      // Insert older note first
      await db.taskNoteDao.insertNote(TaskNotesCompanion.insert(
        id: const Value('note-old'),
        companyId: 'co-1',
        taskId: 'task-1',
        authorId: 'user-1',
        body: 'Older progress update.',
        createdAt: older,
        updatedAt: older,
      ));

      // Insert newer note second
      await db.taskNoteDao.insertNote(TaskNotesCompanion.insert(
        id: const Value('note-new'),
        companyId: 'co-1',
        taskId: 'task-1',
        authorId: 'user-1',
        body: 'Newer progress update.',
        createdAt: now,
        updatedAt: now,
      ));

      final notes = await db.taskNoteDao.watchByTask('task-1').first;
      expect(notes, hasLength(2));
      expect(notes.first.id, 'note-new'); // Newest first
      expect(notes.last.id, 'note-old');
    });

    test('deleteNote soft-deletes note and creates DELETE sync queue entry',
        () async {
      final now = DateTime.now();
      await db.taskNoteDao.insertNote(TaskNotesCompanion.insert(
        id: const Value('note-to-delete'),
        companyId: 'co-1',
        taskId: 'task-1',
        authorId: 'user-1',
        body: 'This note will be deleted.',
        createdAt: now,
        updatedAt: now,
      ));

      // Verify note exists
      final before = await db.taskNoteDao.watchByTask('task-1').first;
      expect(before, hasLength(1));

      // Delete the note
      await db.taskNoteDao.deleteNote('note-to-delete');

      // Verify note is soft-deleted (excluded from active stream)
      final after = await db.taskNoteDao.watchByTask('task-1').first;
      expect(after, isEmpty);

      // Verify DELETE sync queue entry was created
      final queueItems = await db.syncQueueDao.getAllItems();
      final deleteItems = queueItems
          .where((item) =>
              item.entityType == 'task_note' &&
              item.entityId == 'note-to-delete' &&
              item.operation == 'DELETE')
          .toList();
      expect(deleteItems, hasLength(1));
    });

    test('watchByTask filters by taskId (notes for other tasks not returned)',
        () async {
      final now = DateTime.now();
      await db.taskNoteDao.insertNote(TaskNotesCompanion.insert(
        id: const Value('note-task1'),
        companyId: 'co-1',
        taskId: 'task-1',
        authorId: 'user-1',
        body: 'Note for task 1',
        createdAt: now,
        updatedAt: now,
      ));
      await db.taskNoteDao.insertNote(TaskNotesCompanion.insert(
        id: const Value('note-task2'),
        companyId: 'co-1',
        taskId: 'task-2',
        authorId: 'user-1',
        body: 'Note for task 2',
        createdAt: now,
        updatedAt: now,
      ));

      final notesForTask1 = await db.taskNoteDao.watchByTask('task-1').first;
      expect(notesForTask1, hasLength(1));
      expect(notesForTask1.first.body, 'Note for task 1');

      final notesForTask2 = await db.taskNoteDao.watchByTask('task-2').first;
      expect(notesForTask2, hasLength(1));
      expect(notesForTask2.first.body, 'Note for task 2');
    });

    test('watchByTask excludes soft-deleted notes (deletedAt not null)',
        () async {
      final now = DateTime.now();
      // Insert active note
      await db.taskNoteDao.insertNote(TaskNotesCompanion.insert(
        id: const Value('note-alive'),
        companyId: 'co-1',
        taskId: 'task-1',
        authorId: 'user-1',
        body: 'Active note',
        createdAt: now,
        updatedAt: now,
      ));

      // Insert and delete another note
      await db.taskNoteDao.insertNote(TaskNotesCompanion.insert(
        id: const Value('note-deleted'),
        companyId: 'co-1',
        taskId: 'task-1',
        authorId: 'user-1',
        body: 'Deleted note',
        createdAt: now,
        updatedAt: now,
      ));
      await db.taskNoteDao.deleteNote('note-deleted');

      final notes = await db.taskNoteDao.watchByTask('task-1').first;
      expect(notes, hasLength(1));
      expect(notes.first.id, 'note-alive');
    });
  });
}
