import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';

import '../../../../core/database/app_database.dart'
    hide UserRole, BookingDao, NoteDao, AttachmentDao, TimeEntryDao,
        QuoteDao, InvoiceDao;
import '../../../../features/auth/domain/auth_state.dart';
import '../../../../features/auth/presentation/providers/auth_provider.dart';
import '../../../../shared/models/user_role.dart';
import '../../data/task_detail_service.dart';
import '../../domain/task_status.dart';
import '../providers/project_providers.dart';
import '../widgets/rejection_bottom_sheet.dart';
import '../widgets/task_detail_sections.dart';
import '../widgets/task_note_item.dart';
import '../widgets/task_photo_grid.dart';

/// Maximum photo attachments allowed per task.
const _maxPhotos = 10;

/// Maximum PDF document attachments allowed per task.
const _maxDocs = 5;

/// Full task detail screen — notes, photos, PDF attachments, and status
/// controls. All data mutations are delegated to [TaskDetailService]; this
/// widget only orchestrates UI state and user interactions.
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
  bool _allChecked = false;
  List<Map<String, dynamic>> _checklistResults = [];

  @override
  void dispose() {
    _noteController.dispose();
    super.dispose();
  }

  TaskDetailService get _service => ref.read(taskDetailServiceProvider);

  TaskActor? _actor() {
    final authState = ref.read(authNotifierProvider);
    if (authState is! AuthAuthenticated) return null;
    return TaskActor(
      companyId: authState.companyId,
      userId: authState.userId,
    );
  }

  @override
  Widget build(BuildContext context) {
    final taskStream = ref.watch(taskByIdProvider(widget.taskId));
    final authState = ref.watch(authNotifierProvider);
    final isGcOrAdmin = authState is AuthAuthenticated &&
        authState.roles.contains(UserRole.admin);

    return taskStream.when(
      loading: () => const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      ),
      error: (error, _) => Scaffold(
        appBar: AppBar(title: const Text('Task Detail')),
        body: Center(child: Text('Error: $error')),
      ),
      data: (task) => task == null
          ? Scaffold(
              appBar: AppBar(title: const Text('Task')),
              body: const Center(child: Text('Task not found.')),
            )
          : _buildScaffold(task, isGcOrAdmin: isGcOrAdmin),
    );
  }

  Widget _buildScaffold(ProjectTask task, {required bool isGcOrAdmin}) {
    final textTheme = Theme.of(context).textTheme;
    final photoCount = ref.watch(taskPhotoCountProvider(widget.taskId)).value ?? 0;
    final docCount = ref.watch(taskDocCountProvider(widget.taskId)).value ?? 0;

    final isCompleted = task.status == TaskStatus.complete;
    final showInspectBar = isCompleted && isGcOrAdmin;
    final showReworkBar = task.status == TaskStatus.rejected && !isGcOrAdmin;

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
          SliverToBoxAdapter(child: _HeaderSection(task: task)),
          SliverToBoxAdapter(child: _DetailsSection(task: task)),
          if (showInspectBar) ...[
            SliverToBoxAdapter(
              child: TaskTotalTimeSummary(taskId: widget.taskId),
            ),
            SliverToBoxAdapter(child: TaskStatusTimeline(task: task)),
            SliverToBoxAdapter(child: _buildInspectionSection(task)),
          ],
          SliverToBoxAdapter(child: _buildNotesSection()),
          SliverToBoxAdapter(
            child: _buildPhotosSection(photoCount),
          ),
          SliverToBoxAdapter(
            child: _buildAttachmentsSection(docCount),
          ),
        ],
      ),
      bottomNavigationBar: BottomAppBar(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: _buildBottomBar(
            task: task,
            showInspectBar: showInspectBar,
            showReworkBar: showReworkBar,
            isCompleted: isCompleted,
            photoCount: photoCount,
          ),
        ),
      ),
    );
  }

  Widget _buildInspectionSection(ProjectTask task) {
    final scope = ref.watch(tradeScopeByIdProvider(task.tradeScopeId)).value;
    return TaskInspectionChecklistSection(
      scope: scope,
      onAllCheckedChanged: (value) => setState(() => _allChecked = value),
      onResultsChanged: (results) =>
          setState(() => _checklistResults = results),
    );
  }

  Widget _buildNotesSection() {
    final textTheme = Theme.of(context).textTheme;
    final colorScheme = Theme.of(context).colorScheme;
    final notesAsync = ref.watch(taskNotesProvider(widget.taskId));

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Divider(),
          Text(
            'Notes',
            style: textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 8),
          _buildNoteInput(),
          const SizedBox(height: 12),
          notesAsync.when(
            loading: () => const CircularProgressIndicator(),
            error: (error, _) => Text('Error: $error'),
            data: (notes) {
              if (notes.isEmpty) {
                return Text(
                  'No notes yet. Tap to add a progress note.',
                  style: textTheme.bodyMedium?.copyWith(
                    color: colorScheme.onSurface.withValues(alpha: 0.5),
                  ),
                );
              }
              return Column(
                children: notes.map((n) => TaskNoteItem(note: n)).toList(),
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _buildNoteInput() {
    return Row(
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
              onPressed: _isSubmittingNote ? null : _submitNote,
              tooltip: 'Add note',
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildPhotosSection(int photoCount) {
    final textTheme = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Divider(),
          Row(
            children: [
              Text(
                'Photos ($photoCount)',
                style: textTheme.titleMedium
                    ?.copyWith(fontWeight: FontWeight.w600),
              ),
              const Spacer(),
              Tooltip(
                message: photoCount >= _maxPhotos
                    ? 'Maximum $_maxPhotos photos per task reached.'
                    : 'Add photo',
                child: TextButton.icon(
                  icon: const Icon(Icons.add_a_photo, size: 18),
                  label: const Text('Add Photo'),
                  onPressed: photoCount >= _maxPhotos ? null : _addPhoto,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          TaskPhotoGrid(taskId: widget.taskId),
        ],
      ),
    );
  }

  Widget _buildAttachmentsSection(int docCount) {
    final textTheme = Theme.of(context).textTheme;
    final colorScheme = Theme.of(context).colorScheme;
    final attachmentsAsync = ref.watch(taskAttachmentsProvider(widget.taskId));

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Divider(),
          Row(
            children: [
              Text(
                'Attachments ($docCount)',
                style: textTheme.titleMedium
                    ?.copyWith(fontWeight: FontWeight.w600),
              ),
              const Spacer(),
              Tooltip(
                message: docCount >= _maxDocs
                    ? 'Maximum $_maxDocs attachments per task reached.'
                    : 'Add PDF attachment',
                child: TextButton.icon(
                  icon: const Icon(Icons.attach_file, size: 18),
                  label: const Text('Add Attachment'),
                  onPressed: docCount >= _maxDocs ? null : _addPdf,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          attachmentsAsync.when(
            loading: () => const CircularProgressIndicator(),
            error: (error, _) => Text('Error: $error'),
            data: (all) {
              final docs = all
                  .where((a) => a.attachmentType == TaskAttachmentType.document)
                  .toList();
              if (docs.isEmpty) {
                return Text(
                  'No attachments yet.',
                  style: textTheme.bodyMedium?.copyWith(
                    color: colorScheme.onSurface.withValues(alpha: 0.5),
                  ),
                );
              }
              return Column(
                children:
                    docs.map((a) => TaskDocListTile(attachment: a)).toList(),
              );
            },
          ),
          const SizedBox(height: 96),
        ],
      ),
    );
  }

  Widget _buildBottomBar({
    required ProjectTask task,
    required bool showInspectBar,
    required bool showReworkBar,
    required bool isCompleted,
    required int photoCount,
  }) {
    if (showInspectBar) return _buildInspectBar(task);
    if (showReworkBar) return _buildReworkBar(task);
    return _buildDefaultBar(task, isCompleted: isCompleted, photoCount: photoCount);
  }

  Widget _buildInspectBar(ProjectTask task) {
    final colorScheme = Theme.of(context).colorScheme;
    return Row(
      children: [
        Expanded(
          child: OutlinedButton(
            style: OutlinedButton.styleFrom(
              foregroundColor: colorScheme.error,
              minimumSize: const Size(0, 48),
            ),
            onPressed: _isSubmitting ? null : () => _handleReject(task),
            child: const Text('Reject'),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: ElevatedButton(
            style: ElevatedButton.styleFrom(minimumSize: const Size(0, 48)),
            onPressed: (_allChecked && !_isSubmitting)
                ? () => _handleApprove(task)
                : null,
            child: const Text('Approve'),
          ),
        ),
      ],
    );
  }

  Widget _buildReworkBar(ProjectTask task) {
    return Row(
      children: [
        Expanded(
          child: ElevatedButton(
            style: ElevatedButton.styleFrom(minimumSize: const Size(0, 48)),
            onPressed: _isSubmitting ? null : () => _handleStartRework(task),
            child: const Text('Start Rework'),
          ),
        ),
      ],
    );
  }

  Widget _buildDefaultBar(
    ProjectTask task, {
    required bool isCompleted,
    required int photoCount,
  }) {
    final colorScheme = Theme.of(context).colorScheme;
    final canMarkDone = !task.photoRequired || photoCount > 0;

    return Row(
      children: [
        Expanded(
          child: Semantics(
            label: 'Add photo to task',
            child: OutlinedButton.icon(
              icon: const Icon(Icons.add_a_photo),
              label: const Text('Add Photo'),
              style: OutlinedButton.styleFrom(minimumSize: const Size(0, 48)),
              onPressed: photoCount >= _maxPhotos ? null : _addPhoto,
            ),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: isCompleted
              ? Semantics(
                  label: 'Mark task as incomplete',
                  child: OutlinedButton(
                    style:
                        OutlinedButton.styleFrom(minimumSize: const Size(0, 48)),
                    onPressed: () => _updateStatus(TaskStatus.inProgress),
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
                          ? () => _updateStatus(TaskStatus.complete)
                          : null,
                      child: Text(canMarkDone ? 'Mark Done' : 'Add photo first'),
                    ),
                  ),
                ),
        ),
      ],
    );
  }

  Future<void> _handleApprove(ProjectTask task) async {
    final actor = _actor();
    if (actor == null) return;

    setState(() => _isSubmitting = true);
    try {
      await _service.approveTask(
        taskId: task.id,
        actor: actor,
        checklistResults: _checklistResults,
      );
      if (!mounted) return;
      _showSnackBar('Task approved.');
      Navigator.of(context).pop();
    } catch (error) {
      debugPrint('[TaskDetailScreen] Approve error: $error');
      if (!mounted) return;
      _showSnackBar('Failed to approve task. Please try again.');
      setState(() => _isSubmitting = false);
    }
  }

  Future<void> _handleReject(ProjectTask task) async {
    final result = await showRejectionSheet(context);
    if (result == null) return;
    final actor = _actor();
    if (actor == null) return;

    setState(() => _isSubmitting = true);
    try {
      await _service.rejectTask(
        taskId: task.id,
        actor: actor,
        checklistResults: _checklistResults,
        reason: result['reason'] as String?,
        comment: result['comment'] as String?,
      );
      if (!mounted) return;
      _showSnackBar('Task rejected. Contractor notified.');
      Navigator.of(context).pop();
    } catch (error) {
      debugPrint('[TaskDetailScreen] Reject error: $error');
      if (!mounted) return;
      _showSnackBar('Failed to submit rejection. Please try again.');
      setState(() => _isSubmitting = false);
    }
  }

  Future<void> _handleStartRework(ProjectTask task) async {
    setState(() => _isSubmitting = true);
    try {
      await _service.updateStatus(task.id, TaskStatus.inProgress);
      if (mounted) _showSnackBar('Rework started.');
    } catch (error) {
      debugPrint('[TaskDetailScreen] Start rework error: $error');
      if (mounted) _showSnackBar('Failed to start rework.');
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  Future<void> _submitNote() async {
    final body = _noteController.text.trim();
    if (body.isEmpty) return;
    final actor = _actor();
    if (actor == null) return;

    setState(() => _isSubmittingNote = true);
    try {
      await _service.addNote(taskId: widget.taskId, actor: actor, body: body);
      _noteController.clear();
    } catch (error) {
      debugPrint('[TaskDetailScreen] Note submission error: $error');
      if (mounted) _showSnackBar('Failed to save note.');
    } finally {
      if (mounted) setState(() => _isSubmittingNote = false);
    }
  }

  Future<void> _updateStatus(String newStatus) async {
    try {
      await _service.updateStatus(widget.taskId, newStatus);
    } catch (error) {
      debugPrint('[TaskDetailScreen] Status update error: $error');
      if (mounted) _showSnackBar('Failed to update task status.');
    }
  }

  Future<void> _addPhoto() async {
    final actor = _actor();
    if (actor == null) return;

    final source = await _pickImageSource();
    if (source == null) return;

    try {
      final picked = await ImagePicker().pickImage(source: source);
      if (picked == null) return;
      await _service.addPhoto(
        taskId: widget.taskId,
        actor: actor,
        source: picked,
      );
    } catch (error) {
      debugPrint('[TaskDetailScreen] Photo add error: $error');
      if (mounted) _showSnackBar('Failed to add photo. Please try again.');
    }
  }

  Future<ImageSource?> _pickImageSource() {
    return showModalBottomSheet<ImageSource>(
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
  }

  Future<void> _addPdf() async {
    final actor = _actor();
    if (actor == null) return;

    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['pdf'],
      );
      final file = result?.files.firstOrNull;
      final sourcePath = file?.path;
      if (file == null || sourcePath == null) return;

      await _service.addDocument(
        taskId: widget.taskId,
        actor: actor,
        sourcePath: sourcePath,
        filename: file.name,
      );
    } catch (error) {
      debugPrint('[TaskDetailScreen] PDF add error: $error');
      if (mounted) _showSnackBar('Failed to add attachment. Please try again.');
    }
  }

  void _showSnackBar(String message) {
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }
}

/// Task title, status badge, priority badge, and photo-required indicator.
class _HeaderSection extends StatelessWidget {
  const _HeaderSection({required this.task});
  final ProjectTask task;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            task.title,
            style: textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            children: [
              TaskStatusBadge(status: task.status),
              TaskPriorityBadge(priority: task.priority),
              if (task.photoRequired) const Chip(label: Text('Photo required')),
            ],
          ),
        ],
      ),
    );
  }
}

/// Task description, estimates, and materials — hidden when all are empty.
class _DetailsSection extends StatelessWidget {
  const _DetailsSection({required this.task});
  final ProjectTask task;

  bool get _hasContent =>
      task.description != null ||
      task.estimatedHours != null ||
      task.estimatedCost != null ||
      task.materialsNeeded.isNotEmpty;

  @override
  Widget build(BuildContext context) {
    if (!_hasContent) return const SizedBox.shrink();
    final textTheme = Theme.of(context).textTheme;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Divider(),
          if (task.description != null) ...[
            Text(task.description!, style: textTheme.bodyMedium),
            const SizedBox(height: 8),
          ],
          if (task.estimatedHours != null)
            Text('Estimated: ${task.estimatedHours}h',
                style: textTheme.bodySmall),
          if (task.estimatedCost != null)
            Text(
              'Cost estimate: \$${task.estimatedCost?.toStringAsFixed(2)}',
              style: textTheme.bodySmall,
            ),
          if (task.materialsNeeded.isNotEmpty)
            TaskMaterialsList(materialsJson: task.materialsNeeded),
        ],
      ),
    );
  }
}
