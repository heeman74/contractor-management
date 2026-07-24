import 'dart:convert';
import 'dart:io';

import 'package:drift/drift.dart' show Value;
import 'package:flutter_image_compress/flutter_image_compress.dart';
import 'package:path_provider/path_provider.dart';
import 'package:uuid/uuid.dart';

import '../../../core/database/app_database.dart'
    hide UserRole, BookingDao, NoteDao, AttachmentDao, TimeEntryDao, QuoteDao, InvoiceDao;
import '../domain/task_status.dart';

/// Immutable identity of the acting user for task detail write operations.
class TaskActor {
  const TaskActor({required this.companyId, required this.userId});
  final String companyId;
  final String userId;
}

/// Encapsulates all task-detail write operations (status changes, notes,
/// inspections, photo/document capture) behind a single testable surface.
///
/// This keeps [TaskDetailScreen] free of database access, file IO, and image
/// compression — the View only orchestrates UI and delegates to this service.
class TaskDetailService {
  TaskDetailService({
    required TaskDao taskDao,
    required TaskNoteDao noteDao,
    required TaskAttachmentDao attachmentDao,
    required TaskInspectionDao inspectionDao,
    Uuid uuid = const Uuid(),
  })  : _taskDao = taskDao,
        _noteDao = noteDao,
        _attachmentDao = attachmentDao,
        _inspectionDao = inspectionDao,
        _uuid = uuid;

  static const int _photoQuality = 85;
  static const int _photoMinWidth = 1080;
  static const int _captionMaxLength = 40;

  final TaskDao _taskDao;
  final TaskNoteDao _noteDao;
  final TaskAttachmentDao _attachmentDao;
  final TaskInspectionDao _inspectionDao;
  final Uuid _uuid;

  Future<void> updateStatus(String taskId, String newStatus) {
    return _taskDao.updateTask(
      taskId,
      ProjectTasksCompanion(
        status: Value(newStatus),
        updatedAt: Value(DateTime.now()),
      ),
    );
  }

  Future<void> addNote({
    required String taskId,
    required TaskActor actor,
    required String body,
  }) {
    final now = DateTime.now();
    return _noteDao.insertNote(
      TaskNotesCompanion.insert(
        id: Value(_uuid.v4()),
        companyId: actor.companyId,
        taskId: taskId,
        authorId: actor.userId,
        body: body,
        createdAt: now,
        updatedAt: now,
      ),
    );
  }

  Future<void> approveTask({
    required String taskId,
    required TaskActor actor,
    required List<Map<String, dynamic>> checklistResults,
  }) {
    final now = DateTime.now();
    return _inspectionDao.createInspection(
      TaskInspectionsCompanion.insert(
        id: Value(_uuid.v4()),
        companyId: actor.companyId,
        taskId: taskId,
        inspectorId: actor.userId,
        decision: InspectionDecision.approved,
        checklistResults: Value(jsonEncode(checklistResults)),
        createdAt: now,
        updatedAt: now,
      ),
    );
  }

  Future<void> rejectTask({
    required String taskId,
    required TaskActor actor,
    required List<Map<String, dynamic>> checklistResults,
    String? reason,
    String? comment,
  }) async {
    final now = DateTime.now();
    await _inspectionDao.createInspection(
      TaskInspectionsCompanion.insert(
        id: Value(_uuid.v4()),
        companyId: actor.companyId,
        taskId: taskId,
        inspectorId: actor.userId,
        decision: InspectionDecision.rejected,
        checklistResults: Value(jsonEncode(checklistResults)),
        rejectionReason: Value(reason),
        rejectionComment: Value(comment),
        createdAt: now,
        updatedAt: now,
      ),
    );
    await updateStatus(taskId, TaskStatus.rejected);
  }

  /// Compresses [source] into the app documents dir and stores it as a photo
  /// attachment. Returns the stored local path.
  Future<String> addPhoto({
    required String taskId,
    required TaskActor actor,
    required XFile source,
  }) async {
    final attachmentId = _uuid.v4();
    final photoDir = await _ensureDirectory('task_photos', taskId);
    final destPath = '$photoDir/$attachmentId.jpg';

    final compressed = await FlutterImageCompress.compressAndGetFile(
      source.path,
      destPath,
      quality: _photoQuality,
      minWidth: _photoMinWidth,
    );
    final finalPath = compressed?.path ?? source.path;

    final now = DateTime.now();
    await _attachmentDao.insertAttachment(
      TaskAttachmentsCompanion.insert(
        id: Value(attachmentId),
        companyId: actor.companyId,
        taskId: taskId,
        attachmentType: TaskAttachmentType.photo,
        localPath: Value(finalPath),
        sortOrder: const Value(0),
        createdAt: now,
        updatedAt: now,
      ),
    );
    return finalPath;
  }

  /// Copies a picked PDF into the app documents dir and stores it as a
  /// document attachment. Returns the stored local path.
  Future<String> addDocument({
    required String taskId,
    required TaskActor actor,
    required String sourcePath,
    required String filename,
  }) async {
    final attachmentId = _uuid.v4();
    final docDir = await _ensureDirectory('task_docs', taskId);
    final destPath = '$docDir/$attachmentId-$filename';
    await File(sourcePath).copy(destPath);

    final now = DateTime.now();
    await _attachmentDao.insertAttachment(
      TaskAttachmentsCompanion.insert(
        id: Value(attachmentId),
        companyId: actor.companyId,
        taskId: taskId,
        attachmentType: TaskAttachmentType.document,
        localPath: Value(destPath),
        caption: Value(_truncateCaption(filename)),
        sortOrder: const Value(0),
        createdAt: now,
        updatedAt: now,
      ),
    );
    return destPath;
  }

  Future<String> _ensureDirectory(String category, String taskId) async {
    final appDir = await getApplicationDocumentsDirectory();
    final dirPath = '${appDir.path}/$category/$taskId';
    await Directory(dirPath).create(recursive: true);
    return dirPath;
  }

  String _truncateCaption(String filename) {
    return filename.length > _captionMaxLength
        ? '${filename.substring(0, _captionMaxLength)}...'
        : filename;
  }
}
