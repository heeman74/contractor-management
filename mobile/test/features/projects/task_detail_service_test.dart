/// Unit tests for [TaskDetailService] using a real in-memory Drift database.
///
/// Covers the business logic extracted out of TaskDetailScreen:
/// 1. updateStatus writes the new status to the task
/// 2. addNote persists a note authored by the acting user
/// 3. approveTask records an 'approved' inspection with checklist results
/// 4. rejectTask records a 'rejected' inspection AND flips task status
/// 5. addDocument copies the source file and stores a document attachment
library;

import 'dart:convert';
import 'dart:io';

import 'package:contractorhub/core/database/app_database.dart';
import 'package:contractorhub/features/projects/data/task_detail_service.dart';
import 'package:contractorhub/features/projects/domain/task_status.dart';
import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';

AppDatabase _openTestDb() => AppDatabase(NativeDatabase.memory());

const _companyId = 'co-1';
const _userId = 'user-1';
const _taskId = 'task-1';
const _actor = TaskActor(companyId: _companyId, userId: _userId);

class _FakePathProvider extends PathProviderPlatform
    with MockPlatformInterfaceMixin {
  _FakePathProvider(this.root);
  final String root;

  @override
  Future<String?> getApplicationDocumentsPath() async => root;
}

Future<void> _seedTaskGraph(AppDatabase db) async {
  final now = DateTime.now();
  await db.companyDao.insertCompany(CompaniesCompanion.insert(
    id: const Value(_companyId),
    name: 'Company',
    version: const Value(1),
    createdAt: now,
    updatedAt: now,
  ));
  await db.projectDao.insertProject(ProjectsCompanion.insert(
    id: const Value('proj-1'),
    companyId: _companyId,
    name: 'Project',
    status: const Value('planning'),
    version: const Value(1),
    createdAt: now,
    updatedAt: now,
  ));
  await db.tradeScopeDao.insertScope(TradeScopesCompanion.insert(
    id: const Value('scope-1'),
    companyId: _companyId,
    projectId: 'proj-1',
    tradeName: 'Plumbing',
    version: const Value(1),
    createdAt: now,
    updatedAt: now,
  ));
  await db.taskDao.insertTask(ProjectTasksCompanion.insert(
    id: const Value(_taskId),
    companyId: _companyId,
    tradeScopeId: 'scope-1',
    title: 'Task',
    version: const Value(1),
    createdAt: now,
    updatedAt: now,
  ));
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late AppDatabase db;
  late TaskDetailService service;

  setUp(() async {
    db = _openTestDb();
    await _seedTaskGraph(db);
    service = TaskDetailService(
      taskDao: db.taskDao,
      noteDao: db.taskNoteDao,
      attachmentDao: db.taskAttachmentDao,
      inspectionDao: db.taskInspectionDao,
    );
  });

  tearDown(() async => db.close());

  group('updateStatus', () {
    test('writes the new status to the task', () async {
      await service.updateStatus(_taskId, TaskStatus.complete);

      final task = await db.taskDao.watchTaskById(_taskId).first;
      expect(task?.status, TaskStatus.complete);
    });
  });

  group('addNote', () {
    test('persists a note authored by the acting user', () async {
      await service.addNote(
        taskId: _taskId,
        actor: _actor,
        body: 'Installed shutoff valve.',
      );

      final notes = await db.taskNoteDao.watchByTask(_taskId).first;
      expect(notes, hasLength(1));
      expect(notes.first.authorId, _userId);
      expect(notes.first.body, 'Installed shutoff valve.');
    });
  });

  group('approveTask', () {
    test('records an approved inspection with checklist results', () async {
      final checklist = [
        {'item': 'Sealed joints', 'checked': true},
      ];

      await service.approveTask(
        taskId: _taskId,
        actor: _actor,
        checklistResults: checklist,
      );

      final inspections = await db.taskInspectionDao.watchByTaskId(_taskId).first;
      expect(inspections, hasLength(1));
      expect(inspections.first.decision, InspectionDecision.approved);
      expect(inspections.first.inspectorId, _userId);
      expect(
        jsonDecode(inspections.first.checklistResults),
        checklist,
      );
    });
  });

  group('rejectTask', () {
    test('records a rejected inspection and flips task status', () async {
      await service.rejectTask(
        taskId: _taskId,
        actor: _actor,
        checklistResults: const [],
        reason: 'incomplete',
        comment: 'Missing sealant',
      );

      final inspections =
          await db.taskInspectionDao.watchByTaskId(_taskId).first;
      expect(inspections, hasLength(1));
      expect(inspections.first.decision, InspectionDecision.rejected);
      expect(inspections.first.rejectionReason, 'incomplete');
      expect(inspections.first.rejectionComment, 'Missing sealant');

      final task = await db.taskDao.watchTaskById(_taskId).first;
      expect(task?.status, TaskStatus.rejected);
    });
  });

  group('addDocument', () {
    test('copies the source file and stores a document attachment', () async {
      final tempRoot = await Directory.systemTemp.createTemp('task_docs_test');
      PathProviderPlatform.instance = _FakePathProvider(tempRoot.path);

      final source = File('${tempRoot.path}/spec.pdf');
      await source.writeAsString('pdf-bytes');

      final destPath = await service.addDocument(
        taskId: _taskId,
        actor: _actor,
        sourcePath: source.path,
        filename: 'spec.pdf',
      );

      expect(File(destPath).existsSync(), isTrue);

      final attachments = await db.taskAttachmentDao.watchByTask(_taskId).first;
      expect(attachments, hasLength(1));
      expect(attachments.first.attachmentType, TaskAttachmentType.document);
      expect(attachments.first.caption, 'spec.pdf');

      await tempRoot.delete(recursive: true);
    });
  });
}
