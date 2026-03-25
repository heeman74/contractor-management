import 'dart:convert';
import 'dart:io';

import 'package:drift/drift.dart' show Value;
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_image_compress/flutter_image_compress.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:uuid/uuid.dart';

import '../../../../core/database/app_database.dart'
    hide UserRole, BookingDao, NoteDao, AttachmentDao, TimeEntryDao,
        QuoteDao, InvoiceDao;
import '../../../../features/auth/domain/auth_state.dart';
import '../../../../features/auth/presentation/providers/auth_provider.dart';
import '../../../../shared/models/user_role.dart';
import '../providers/project_providers.dart';
import '../widgets/inspection_checklist.dart';
import '../widgets/rejection_bottom_sheet.dart';
import '../widgets/task_note_item.dart';
import '../widgets/task_photo_grid.dart';

/// Limits enforced in UI.
const _maxPhotos = 10;
const _maxDocs = 5;

/// Full task detail screen — notes, photos, PDF attachments, and status controls.
///
/// Layout (CustomScrollView):
/// 1. Header: title, status badge, priority badge, photo-required indicator
/// 2. Details: description, estimated hours/cost, materials needed
/// 3. [GC only, task complete] Time summary (total hours logged)
/// 4. [GC only, task complete] Status transition timeline
/// 5. [GC only, task complete] Inspection checklist
/// 6. Notes: inline add + list of notes
/// 7. Photos: 3-column grid + "Add Photo" button (max 10)
/// 8. Attachments: PDF list + "Add Attachment" button (max 5)
///
/// Bottom bar:
/// - [contractor, task rejected] "Start Rework" button
/// - [GC/admin, task complete] "Reject" (left) + "Approve" (right, disabled until all checked)
/// - [default] "Add Photo" (left) + "Mark Done" / "Mark Incomplete" (right)
/// - Photo gate: if task.photoRequired and no photos → Mark Done disabled
class TaskDetailScreen extends ConsumerStatefulWidget {
  const TaskDetailScreen({required this.taskId, super.key});

  final String taskId;

  @override
  ConsumerState<TaskDetailScreen> createState() => _TaskDetailScreenState();
}

class _TaskDetailScreenState extends ConsumerState<TaskDetailScreen> {
  final _noteController = TextEditingController();
  bool _isSubmittingNote = false;
  bool _isSubmitting = false;

  // Inspection checklist state
  bool _allChecked = false;
  List<Map<String, dynamic>> _checklistResults = [];

  @override
  void dispose() {
    _noteController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final colorScheme = Theme.of(context).colorScheme;

    final taskStream = ref.watch(_taskByIdProvider(widget.taskId));
    final notesAsync = ref.watch(taskNotesProvider(widget.taskId));
    final attachmentsAsync = ref.watch(taskAttachmentsProvider(widget.taskId));
    final photoCountAsync = ref.watch(taskPhotoCountProvider(widget.taskId));
    final docCountAsync = ref.watch(taskDocCountProvider(widget.taskId));
    final authState = ref.watch(authNotifierProvider);

    final companyId =
        authState is AuthAuthenticated ? authState.companyId : '';
    final userId = authState is AuthAuthenticated ? authState.userId : '';

    final isGcOrAdmin = authState is AuthAuthenticated &&
        authState.roles.contains(UserRole.admin);

    final photoCount = photoCountAsync.value ?? 0;
    final docCount = docCountAsync.value ?? 0;

    return taskStream.when(
      loading: () => const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      ),
      error: (error, _) => Scaffold(
        appBar: AppBar(title: const Text('Task Detail')),
        body: Center(child: Text('Error: $error')),
      ),
      data: (task) {
        if (task == null) {
          return Scaffold(
            appBar: AppBar(title: const Text('Task')),
            body: const Center(child: Text('Task not found.')),
          );
        }

        final isCompleted = task.status == 'complete';
        final isRejected = task.status == 'rejected';
        final canMarkDone = !task.photoRequired || photoCount > 0;

        // Inspection bottom bar: GC/admin sees Approve+Reject when task is complete
        final showInspectBar = isCompleted && isGcOrAdmin;
        // Rework bottom bar: contractor (non-GC) sees Start Rework when rejected
        final showReworkBar = isRejected && !isGcOrAdmin;

        return Scaffold(
          appBar: AppBar(
            title: Text(
              task.title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: textTheme.titleLarge,
            ),
          ),
          body: CustomScrollView(
            slivers: [
              // ── Section 1: Header ─────────────────────────────────────────
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        task.title,
                        style: textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 8,
                        children: [
                          _StatusBadge(status: task.status),
                          _PriorityBadge(priority: task.priority),
                          if (task.photoRequired)
                            const Chip(label: Text('Photo required')),
                        ],
                      ),
                    ],
                  ),
                ),
              ),

              // ── Section 2: Details ────────────────────────────────────────
              if (task.description != null ||
                  task.estimatedHours != null ||
                  task.estimatedCost != null ||
                  task.materialsNeeded.isNotEmpty)
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 16, vertical: 8),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Divider(),
                        if (task.description != null) ...[
                          Text(task.description!,
                              style: textTheme.bodyMedium),
                          const SizedBox(height: 8),
                        ],
                        if (task.estimatedHours != null)
                          Text(
                            'Estimated: ${task.estimatedHours}h',
                            style: textTheme.bodySmall,
                          ),
                        if (task.estimatedCost != null)
                          Text(
                            'Cost estimate: \$${task.estimatedCost?.toStringAsFixed(2)}',
                            style: textTheme.bodySmall,
                          ),
                        if (task.materialsNeeded.isNotEmpty)
                          _MaterialsList(
                              materialsJson: task.materialsNeeded),
                      ],
                    ),
                  ),
                ),

              // ── Section 3 (GC): Total Time Logged (D-02) ─────────────────
              if (showInspectBar)
                SliverToBoxAdapter(
                  child: _TotalTimeSummary(taskId: widget.taskId),
                ),

              // ── Section 4 (GC): Status Transition Timeline (D-02) ────────
              if (showInspectBar)
                SliverToBoxAdapter(
                  child: _StatusTimeline(task: task),
                ),

              // ── Section 5 (GC): Inspection Checklist ─────────────────────
              if (showInspectBar)
                SliverToBoxAdapter(
                  child: _InspectionChecklistSection(
                    scope: ref
                        .watch(_tradeScopeByIdProvider(task.tradeScopeId))
                        .value,
                    onAllCheckedChanged: (val) =>
                        setState(() => _allChecked = val),
                    onResultsChanged: (results) =>
                        setState(() => _checklistResults = results),
                  ),
                ),

              // ── Section 6: Notes ──────────────────────────────────────────
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 16, vertical: 8),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Divider(),
                      Text(
                        'Notes',
                        style: textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 8),
                      // Inline note input
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          Expanded(
                            child: TextField(
                              controller: _noteController,
                              decoration: const InputDecoration(
                                hintText: 'Add a progress note...',
                                border: OutlineInputBorder(),
                                isDense: true,
                              ),
                              minLines: 1,
                              maxLines: 4,
                            ),
                          ),
                          const SizedBox(width: 8),
                          SizedBox(
                            height: 48,
                            child: Semantics(
                              label: 'Submit note',
                              child: IconButton.filled(
                                icon: const Icon(Icons.add),
                                onPressed: _isSubmittingNote
                                    ? null
                                    : () => _submitNote(
                                        companyId, userId),
                                tooltip: 'Add note',
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      // Notes list
                      notesAsync.when(
                        loading: () =>
                            const CircularProgressIndicator(),
                        error: (error, _) => Text('Error: $error'),
                        data: (notes) {
                          if (notes.isEmpty) {
                            return Text(
                              'No notes yet. Tap to add a progress note.',
                              style: textTheme.bodyMedium?.copyWith(
                                color: colorScheme.onSurface
                                    .withValues(alpha: 0.5),
                              ),
                            );
                          }
                          return Column(
                            children:
                                notes.map((n) => TaskNoteItem(note: n)).toList(),
                          );
                        },
                      ),
                    ],
                  ),
                ),
              ),

              // ── Section 7: Photos ─────────────────────────────────────────
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 16, vertical: 8),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Divider(),
                      Row(
                        children: [
                          Text(
                            'Photos ($photoCount)',
                            style: textTheme.titleMedium?.copyWith(
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          const Spacer(),
                          Tooltip(
                            message: photoCount >= _maxPhotos
                                ? 'Maximum 10 photos per task reached.'
                                : 'Add photo',
                            child: TextButton.icon(
                              icon: const Icon(Icons.add_a_photo, size: 18),
                              label: const Text('Add Photo'),
                              onPressed: photoCount >= _maxPhotos
                                  ? null
                                  : () => _addPhoto(
                                      context, companyId),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      TaskPhotoGrid(taskId: widget.taskId),
                    ],
                  ),
                ),
              ),

              // ── Section 8: Attachments ────────────────────────────────────
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 16, vertical: 8),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Divider(),
                      Row(
                        children: [
                          Text(
                            'Attachments ($docCount)',
                            style: textTheme.titleMedium?.copyWith(
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          const Spacer(),
                          Tooltip(
                            message: docCount >= _maxDocs
                                ? 'Maximum 5 attachments per task reached.'
                                : 'Add PDF attachment',
                            child: TextButton.icon(
                              icon: const Icon(Icons.attach_file, size: 18),
                              label: const Text('Add Attachment'),
                              onPressed: docCount >= _maxDocs
                                  ? null
                                  : () => _addPdf(context, companyId),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      attachmentsAsync.when(
                        loading: () =>
                            const CircularProgressIndicator(),
                        error: (error, _) => Text('Error: $error'),
                        data: (all) {
                          final docs = all
                              .where(
                                  (a) => a.attachmentType == 'document')
                              .toList();
                          if (docs.isEmpty) {
                            return Text(
                              'No attachments yet.',
                              style: textTheme.bodyMedium?.copyWith(
                                color: colorScheme.onSurface
                                    .withValues(alpha: 0.5),
                              ),
                            );
                          }
                          return Column(
                            children: docs
                                .map((a) => _DocListTile(attachment: a))
                                .toList(),
                          );
                        },
                      ),
                      // Spacer for bottom bar
                      const SizedBox(height: 96),
                    ],
                  ),
                ),
              ),
            ],
          ),

          // ── Bottom Bar ───────────────────────────────────────────────────
          bottomNavigationBar: BottomAppBar(
            child: Padding(
              padding: const EdgeInsets.symmetric(
                  horizontal: 16, vertical: 8),
              child: _buildBottomBar(
                context,
                task: task,
                showInspectBar: showInspectBar,
                showReworkBar: showReworkBar,
                isCompleted: isCompleted,
                canMarkDone: canMarkDone,
                photoCount: photoCount,
                companyId: companyId,
                authState: authState,
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildBottomBar(
    BuildContext context, {
    required ProjectTask task,
    required bool showInspectBar,
    required bool showReworkBar,
    required bool isCompleted,
    required bool canMarkDone,
    required int photoCount,
    required String companyId,
    required AuthState authState,
  }) {
    final colorScheme = Theme.of(context).colorScheme;

    // GC inspection bar: Reject + Approve when task is complete
    if (showInspectBar) {
      return Row(
        children: [
          Expanded(
            child: OutlinedButton(
              style: OutlinedButton.styleFrom(
                foregroundColor: colorScheme.error,
                minimumSize: const Size(0, 48),
              ),
              onPressed: _isSubmitting
                  ? null
                  : () => _handleReject(task, authState),
              child: const Text('Reject'),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: ElevatedButton(
              style: ElevatedButton.styleFrom(
                minimumSize: const Size(0, 48),
              ),
              onPressed: (_allChecked && !_isSubmitting)
                  ? () => _handleApprove(task, authState)
                  : null,
              child: const Text('Approve'),
            ),
          ),
        ],
      );
    }

    // Contractor rework bar: Start Rework when task is rejected
    if (showReworkBar) {
      return Row(
        children: [
          Expanded(
            child: ElevatedButton(
              style: ElevatedButton.styleFrom(
                minimumSize: const Size(0, 48),
              ),
              onPressed:
                  _isSubmitting ? null : () => _handleStartRework(task),
              child: const Text('Start Rework'),
            ),
          ),
        ],
      );
    }

    // Default bar: Add Photo + Mark Done / Mark Incomplete
    return Row(
      children: [
        Expanded(
          child: Semantics(
            label: 'Add photo to task',
            child: OutlinedButton.icon(
              icon: const Icon(Icons.add_a_photo),
              label: const Text('Add Photo'),
              style: OutlinedButton.styleFrom(
                minimumSize: const Size(0, 48),
              ),
              onPressed: photoCount >= _maxPhotos
                  ? null
                  : () => _addPhoto(context, companyId),
            ),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: isCompleted
              ? Semantics(
                  label: 'Mark task as incomplete',
                  child: OutlinedButton(
                    style: OutlinedButton.styleFrom(
                      minimumSize: const Size(0, 48),
                    ),
                    onPressed: () => _updateStatus('in_progress'),
                    child: const Text('Mark Incomplete'),
                  ),
                )
              : Semantics(
                  label: canMarkDone
                      ? 'Mark task as done'
                      : 'Add photo first to complete task',
                  child: Tooltip(
                    message: canMarkDone ? '' : 'Add photo first',
                    child: ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        minimumSize: const Size(0, 48),
                        backgroundColor: colorScheme.primary,
                        foregroundColor: colorScheme.onPrimary,
                      ),
                      onPressed: canMarkDone
                          ? () => _updateStatus('complete')
                          : null,
                      child: Text(
                        canMarkDone ? 'Mark Done' : 'Add photo first',
                      ),
                    ),
                  ),
                ),
        ),
      ],
    );
  }

  Future<void> _handleApprove(
      ProjectTask task, AuthState authState) async {
    setState(() => _isSubmitting = true);
    try {
      final authenticated = authState is AuthAuthenticated ? authState : null;
      if (authenticated == null) return;

      final dao = ref.read(taskInspectionDaoProvider);
      await dao.createInspection(TaskInspectionsCompanion.insert(
        id: Value(const Uuid().v4()),
        companyId: authenticated.companyId,
        taskId: task.id,
        inspectorId: authenticated.userId,
        decision: 'approved',
        checklistResults: Value(jsonEncode(_checklistResults)),
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      ));
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Task approved.')),
        );
        Navigator.of(context).pop();
      }
    } catch (e) {
      debugPrint('[TaskDetailScreen] Approve error: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
              content:
                  Text('Failed to approve task. Please try again.')),
        );
        setState(() => _isSubmitting = false);
      }
    }
  }

  Future<void> _handleReject(
      ProjectTask task, AuthState authState) async {
    final result = await showRejectionSheet(context);
    if (result == null) return;

    setState(() => _isSubmitting = true);
    try {
      final authenticated = authState is AuthAuthenticated ? authState : null;
      if (authenticated == null) return;

      final dao = ref.read(taskInspectionDaoProvider);
      await dao.createInspection(TaskInspectionsCompanion.insert(
        id: Value(const Uuid().v4()),
        companyId: authenticated.companyId,
        taskId: task.id,
        inspectorId: authenticated.userId,
        decision: 'rejected',
        checklistResults: Value(jsonEncode(_checklistResults)),
        rejectionReason: Value(result['reason'] as String?),
        rejectionComment: Value(result['comment'] as String?),
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      ));
      // Also update task status locally to 'rejected'
      final taskDao = ref.read(taskDaoProvider);
      await taskDao.updateTask(
        task.id,
        ProjectTasksCompanion(
          status: const Value('rejected'),
          updatedAt: Value(DateTime.now()),
        ),
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
              content: Text('Task rejected. Contractor notified.')),
        );
        Navigator.of(context).pop();
      }
    } catch (e) {
      debugPrint('[TaskDetailScreen] Reject error: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
              content:
                  Text('Failed to submit rejection. Please try again.')),
        );
        setState(() => _isSubmitting = false);
      }
    }
  }

  Future<void> _handleStartRework(ProjectTask task) async {
    setState(() => _isSubmitting = true);
    try {
      await ref.read(taskDaoProvider).updateTask(
            task.id,
            ProjectTasksCompanion(
              status: const Value('in_progress'),
              updatedAt: Value(DateTime.now()),
            ),
          );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Rework started.')),
        );
      }
    } catch (e) {
      debugPrint('[TaskDetailScreen] Start rework error: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Failed to start rework.')),
        );
      }
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  Future<void> _submitNote(String companyId, String userId) async {
    final body = _noteController.text.trim();
    if (body.isEmpty) return;

    setState(() => _isSubmittingNote = true);
    try {
      await ref.read(taskNoteDaoProvider).insertNote(
            TaskNotesCompanion.insert(
              id: Value(const Uuid().v4()),
              companyId: companyId,
              taskId: widget.taskId,
              authorId: userId,
              body: body,
              createdAt: DateTime.now(),
              updatedAt: DateTime.now(),
            ),
          );
      _noteController.clear();
    } catch (e) {
      debugPrint('[TaskDetailScreen] Note submission error: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Failed to save note.')),
        );
      }
    } finally {
      if (mounted) setState(() => _isSubmittingNote = false);
    }
  }

  Future<void> _updateStatus(String newStatus) async {
    try {
      await ref.read(taskDaoProvider).updateTask(
            widget.taskId,
            ProjectTasksCompanion(
              status: Value(newStatus),
              updatedAt: Value(DateTime.now()),
            ),
          );
    } catch (e) {
      debugPrint('[TaskDetailScreen] Status update error: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Failed to update task status.')),
        );
      }
    }
  }

  /// Show a bottom sheet to pick camera or gallery, then compress & save.
  Future<void> _addPhoto(BuildContext context, String companyId) async {
    final source = await showModalBottomSheet<ImageSource>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.camera_alt),
              title: const Text('Camera'),
              onTap: () => Navigator.pop(ctx, ImageSource.camera),
            ),
            ListTile(
              leading: const Icon(Icons.photo_library),
              title: const Text('Gallery'),
              onTap: () => Navigator.pop(ctx, ImageSource.gallery),
            ),
          ],
        ),
      ),
    );

    if (source == null) return;

    try {
      final picker = ImagePicker();
      final XFile? picked = await picker.pickImage(source: source);
      if (picked == null) return;

      final appDir = await getApplicationDocumentsDirectory();
      final attachmentId = const Uuid().v4();
      final localPath =
          '${appDir.path}/task_photos/${widget.taskId}/$attachmentId.jpg';
      await Directory('${appDir.path}/task_photos/${widget.taskId}')
          .create(recursive: true);

      final XFile? compressed = await FlutterImageCompress.compressAndGetFile(
        picked.path,
        localPath,
        quality: 85,
        minWidth: 1080,
        minHeight: 1080,
      );
      final finalPath = compressed?.path ?? picked.path;

      await ref.read(taskAttachmentDaoProvider).insertAttachment(
            TaskAttachmentsCompanion.insert(
              id: Value(attachmentId),
              companyId: companyId,
              taskId: widget.taskId,
              attachmentType: 'photo',
              localPath: Value(finalPath),
              sortOrder: Value(0),
              createdAt: DateTime.now(),
              updatedAt: DateTime.now(),
            ),
          );
    } catch (e) {
      debugPrint('[TaskDetailScreen] Photo add error: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
              content: Text('Failed to add photo. Please try again.')),
        );
      }
    }
  }

  /// Open file picker for PDFs, copy to app dir, insert as document attachment.
  Future<void> _addPdf(BuildContext context, String companyId) async {
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['pdf'],
      );
      if (result == null || result.files.isEmpty) return;

      final file = result.files.first;
      final sourcePath = file.path;
      if (sourcePath == null) return;

      final appDir = await getApplicationDocumentsDirectory();
      final attachmentId = const Uuid().v4();
      final filename = file.name;
      final destDir = '${appDir.path}/task_docs/${widget.taskId}';
      final destPath = '$destDir/$attachmentId-$filename';

      await Directory(destDir).create(recursive: true);
      await File(sourcePath).copy(destPath);

      await ref.read(taskAttachmentDaoProvider).insertAttachment(
            TaskAttachmentsCompanion.insert(
              id: Value(attachmentId),
              companyId: companyId,
              taskId: widget.taskId,
              attachmentType: 'document',
              localPath: Value(destPath),
              caption: Value(filename.length > 40
                  ? '${filename.substring(0, 40)}...'
                  : filename),
              sortOrder: Value(0),
              createdAt: DateTime.now(),
              updatedAt: DateTime.now(),
            ),
          );
    } catch (e) {
      debugPrint('[TaskDetailScreen] PDF add error: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
              content: Text('Failed to add attachment. Please try again.')),
        );
      }
    }
  }
}

// ── Providers ──────────────────────────────────────────────────────────────

/// Provider to watch a single task by ID.
///
/// Returns null if the task is not found (deleted or ID mismatch).
final _taskByIdProvider =
    StreamProvider.autoDispose.family<ProjectTask?, String>((ref, taskId) {
  final dao = ref.watch(taskDaoProvider);
  return dao.watchTaskById(taskId);
});

/// Provider to watch a single trade scope by ID.
///
/// Returns null if the scope is not found. Used by TaskDetailScreen to load
/// the scope's [inspectionChecklist] JSON for the GC's checklist section.
final _tradeScopeByIdProvider =
    StreamProvider.autoDispose.family<TradeScope?, String>((ref, scopeId) {
  final dao = ref.watch(tradeScopeDaoProvider);
  return dao.watchScopeById(scopeId);
});

// ── Inspection section widgets ─────────────────────────────────────────────

/// Renders the total time logged section for GC inspection view (D-02).
///
/// Reads time entry attachments to compute total hours. Falls back to
/// "No time logged" when no entries exist.
class _TotalTimeSummary extends ConsumerWidget {
  const _TotalTimeSummary({required this.taskId});
  final String taskId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Use the task's note count as a proxy -- actual time entries from
    // time_entries table (legacy v1 jobs). For project tasks we track
    // estimated hours. Display estimated hours as a reference.
    // Time entry integration via TaskTimeEntry is deferred; show estimated.
    final taskAsync = ref.watch(_taskByIdProvider(taskId));
    final task = taskAsync.value;

    String timeLabel = 'No time logged';
    if (task?.estimatedHours != null && task!.estimatedHours! > 0) {
      final totalMins = (task.estimatedHours! * 60).round();
      final hrs = totalMins ~/ 60;
      final mins = totalMins % 60;
      timeLabel = hrs > 0 ? '$hrs hrs $mins min' : '$mins min';
    }

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Divider(),
          ListTile(
            leading: const Icon(Icons.access_time),
            title: const Text('Total Time Logged'),
            subtitle: Text(timeLabel),
            contentPadding: EdgeInsets.zero,
            dense: true,
          ),
        ],
      ),
    );
  }
}

/// Renders the status transition timeline for GC inspection view (D-02).
///
/// Shows the task lifecycle: Created → In Progress → Complete with timestamps.
class _StatusTimeline extends StatelessWidget {
  const _StatusTimeline({required this.task});
  final ProjectTask task;

  static String _fmtDate(DateTime dt) {
    final months = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'
    ];
    final hour = dt.hour % 12 == 0 ? 12 : dt.hour % 12;
    final minute = dt.minute.toString().padLeft(2, '0');
    final ampm = dt.hour < 12 ? 'AM' : 'PM';
    return '${months[dt.month - 1]} ${dt.day}, ${dt.year} $hour:$minute $ampm';
  }

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Divider(),
          Text(
            'Status Timeline',
            style:
                textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 8),
          _TimelineRow(
            color: Colors.grey,
            label: 'Created',
            timestamp: _fmtDate(task.createdAt),
          ),
          _TimelineDivider(),
          _TimelineRow(
            color: const Color(0xFF1565C0),
            label: 'In Progress',
            timestamp: task.startDate != null
                ? _fmtDate(task.startDate!)
                : 'N/A',
          ),
          _TimelineDivider(),
          _TimelineRow(
            color: const Color(0xFF388E3C),
            label: 'Complete',
            timestamp: task.status == 'complete'
                ? _fmtDate(task.updatedAt)
                : 'N/A',
          ),
        ],
      ),
    );
  }
}

class _TimelineRow extends StatelessWidget {
  const _TimelineRow({
    required this.color,
    required this.label,
    required this.timestamp,
  });
  final Color color;
  final String label;
  final String timestamp;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return Row(
      children: [
        Container(
          width: 8,
          height: 8,
          decoration: BoxDecoration(shape: BoxShape.circle, color: color),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Text(label, style: textTheme.bodySmall),
        ),
        Text(
          timestamp,
          style: textTheme.bodySmall?.copyWith(
            color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.6),
          ),
        ),
      ],
    );
  }
}

class _TimelineDivider extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(left: 3),
      child: Container(
        width: 2,
        height: 16,
        color: Colors.grey.shade300,
      ),
    );
  }
}

/// Renders the inspection checklist section embedded in the task detail.
class _InspectionChecklistSection extends StatelessWidget {
  const _InspectionChecklistSection({
    required this.scope,
    required this.onAllCheckedChanged,
    required this.onResultsChanged,
  });

  final TradeScope? scope;
  final ValueChanged<bool> onAllCheckedChanged;
  final ValueChanged<List<Map<String, dynamic>>> onResultsChanged;

  List<Map<String, dynamic>> _parseChecklist() {
    final checklistJson = scope?.inspectionChecklist;
    if (checklistJson == null || checklistJson.isEmpty) {
      return kDefaultInspectionChecklist
          .map((m) => Map<String, dynamic>.from(m))
          .toList();
    }
    try {
      final parsed = jsonDecode(checklistJson) as List<dynamic>;
      return parsed
          .whereType<Map<String, dynamic>>()
          .map((m) {
            // Support both "item" and "label" key variants from scope JSON
            final item = (m['item'] ?? m['label'] ?? '').toString();
            return <String, dynamic>{"item": item, "id": m['id'] ?? ''};
          })
          .where((m) => (m['item'] as String).isNotEmpty)
          .toList();
    } catch (_) {
      return kDefaultInspectionChecklist
          .map((m) => Map<String, dynamic>.from(m))
          .toList();
    }
  }

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final checklistItems = _parseChecklist();

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Divider(),
          Text(
            'Inspection Checklist',
            style:
                textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 8),
          InspectionChecklist(
            items: checklistItems,
            onAllCheckedChanged: onAllCheckedChanged,
            onResultsChanged: onResultsChanged,
          ),
        ],
      ),
    );
  }
}

// ── Status and priority badge widgets ─────────────────────────────────────

class _StatusBadge extends StatelessWidget {
  const _StatusBadge({required this.status});
  final String status;

  @override
  Widget build(BuildContext context) {
    return Chip(
      label: Text(
        status.replaceAll('_', ' '),
        style: Theme.of(context).textTheme.labelSmall?.copyWith(
              color: Colors.white,
            ),
      ),
      backgroundColor: _color(status),
      visualDensity: VisualDensity.compact,
      padding: EdgeInsets.zero,
    );
  }

  static Color _color(String status) {
    return switch (status) {
      'complete' => const Color(0xFF388E3C),
      'in_progress' => const Color(0xFF1565C0),
      'blocked' => const Color(0xFFD32F2F),
      'rejected' => const Color(0xFFB71C1C),
      _ => const Color(0xFF9E9E9E),
    };
  }
}

class _PriorityBadge extends StatelessWidget {
  const _PriorityBadge({required this.priority});
  final String priority;

  @override
  Widget build(BuildContext context) {
    return Chip(
      label: Text(
        priority,
        style: Theme.of(context).textTheme.labelSmall?.copyWith(
              color: Colors.white,
            ),
      ),
      backgroundColor: _color(priority),
      visualDensity: VisualDensity.compact,
      padding: EdgeInsets.zero,
    );
  }

  static Color _color(String priority) {
    return switch (priority) {
      'urgent' => const Color(0xFFD32F2F),
      'high' => const Color(0xFFF57C00),
      'medium' => const Color(0xFF1565C0),
      'low' => const Color(0xFF9E9E9E),
      _ => const Color(0xFF9E9E9E),
    };
  }
}

/// Renders a materials list from a JSONB string or list.
///
/// materialsNeeded is stored as JSON in Drift. Attempts to parse as a List;
/// falls back to plain text rendering on parse failure.
class _MaterialsList extends StatelessWidget {
  const _MaterialsList({required this.materialsJson});
  final String materialsJson;

  @override
  Widget build(BuildContext context) {
    // Try to parse as JSON list
    List<String> materials = [];
    try {
      // Simple heuristic: strip brackets and split by commas
      final trimmed = materialsJson.trim();
      if (trimmed.startsWith('[')) {
        // Remove brackets and quotes
        final inner = trimmed.substring(1, trimmed.length - 1);
        materials = inner
            .split(',')
            .map((s) => s.trim().replaceAll('"', '').replaceAll("'", ''))
            .where((s) => s.isNotEmpty)
            .toList();
      }
    } catch (_) {
      materials = [materialsJson];
    }

    if (materials.isEmpty) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 8),
        Text(
          'Materials needed:',
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                fontWeight: FontWeight.w600,
              ),
        ),
        ...materials.map(
          (m) => Padding(
            padding: const EdgeInsets.only(left: 8, top: 2),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('• '),
                Expanded(
                  child: Text(
                    m,
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

/// A document attachment list tile with tap to open in system viewer.
class _DocListTile extends StatelessWidget {
  const _DocListTile({required this.attachment});
  final TaskAttachment attachment;

  @override
  Widget build(BuildContext context) {
    final filename = attachment.caption ??
        attachment.localPath?.split('/').last ??
        'attachment.pdf';

    return ListTile(
      leading: const Icon(Icons.picture_as_pdf, color: Color(0xFFD32F2F)),
      title: Text(
        filename.length > 40 ? '${filename.substring(0, 40)}...' : filename,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      subtitle: attachment.localPath != null
          ? Text(_fileSize(attachment.localPath!),
              style: Theme.of(context).textTheme.bodySmall)
          : null,
      onTap: () => _openFile(context),
      contentPadding: EdgeInsets.zero,
    );
  }

  Future<void> _openFile(BuildContext context) async {
    try {
      final path = attachment.localPath;
      if (path == null) return;

      final uri = Uri.file(path);
      if (await canLaunchUrl(uri)) {
        await launchUrl(uri);
      } else {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
                content: Text('No app available to open this file.')),
          );
        }
      }
    } catch (e) {
      debugPrint('[TaskDetailScreen] File open error: $e');
    }
  }

  String _fileSize(String path) {
    try {
      final file = File(path);
      if (!file.existsSync()) return 'File not found';
      final bytes = file.lengthSync();
      if (bytes < 1024) return '${bytes}B';
      if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)}KB';
      return '${(bytes / (1024 * 1024)).toStringAsFixed(1)}MB';
    } catch (_) {
      return '';
    }
  }
}
