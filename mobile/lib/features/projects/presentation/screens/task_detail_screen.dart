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
import '../providers/project_providers.dart';
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
/// 3. Notes: inline add + list of notes
/// 4. Photos: 3-column grid + "Add Photo" button (max 10)
/// 5. Attachments: PDF list + "Add Attachment" button (max 5)
///
/// Bottom bar:
/// - "Add Photo" OutlinedButton (left)
/// - "Mark Done" / "Mark Incomplete" ElevatedButton (right)
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

  @override
  void dispose() {
    _noteController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final colorScheme = Theme.of(context).colorScheme;

    // Watch task — use tasksProvider for the parent scope... but we only have taskId.
    // We need a single-task lookup. Use a custom approach: watch all tasks from DAO.
    // Simplest: use existing providers to get notes/attachments, and get the task
    // via a helper that reads from the stream. We'll use a StreamProvider inline.
    final taskStream = ref.watch(_taskByIdProvider(widget.taskId));
    final notesAsync = ref.watch(taskNotesProvider(widget.taskId));
    final attachmentsAsync = ref.watch(taskAttachmentsProvider(widget.taskId));
    final photoCountAsync = ref.watch(taskPhotoCountProvider(widget.taskId));
    final docCountAsync = ref.watch(taskDocCountProvider(widget.taskId));
    final authState = ref.watch(authNotifierProvider);

    final companyId =
        authState is AuthAuthenticated ? authState.companyId : '';
    final userId = authState is AuthAuthenticated ? authState.userId : '';

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
        final canMarkDone =
            !task.photoRequired || photoCount > 0;

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

              // ── Section 3: Notes ──────────────────────────────────────────
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

              // ── Section 4: Photos ─────────────────────────────────────────
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

              // ── Section 5: Attachments ────────────────────────────────────
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
              child: Row(
                children: [
                  // Left: Add Photo button
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
                  // Right: Mark Done / Mark Incomplete
                  Expanded(
                    child: isCompleted
                        ? Semantics(
                            label: 'Mark task as incomplete',
                            child: OutlinedButton(
                              style: OutlinedButton.styleFrom(
                                minimumSize: const Size(0, 48),
                              ),
                              onPressed: () =>
                                  _updateStatus('in_progress'),
                              child:
                                  const Text('Mark Incomplete'),
                            ),
                          )
                        : Semantics(
                            label: canMarkDone
                                ? 'Mark task as done'
                                : 'Add photo first to complete task',
                            child: Tooltip(
                              message: canMarkDone
                                  ? ''
                                  : 'Add photo first',
                              child: ElevatedButton(
                                style: ElevatedButton.styleFrom(
                                  minimumSize: const Size(0, 48),
                                  backgroundColor:
                                      colorScheme.primary,
                                  foregroundColor:
                                      colorScheme.onPrimary,
                                ),
                                onPressed: canMarkDone
                                    ? () =>
                                        _updateStatus('complete')
                                    : null,
                                child: Text(
                                  canMarkDone
                                      ? 'Mark Done'
                                      : 'Add photo first',
                                ),
                              ),
                            ),
                          ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
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

/// Provider to watch a single task by ID.
///
/// Returns null if the task is not found (deleted or ID mismatch).
final _taskByIdProvider =
    StreamProvider.autoDispose.family<ProjectTask?, String>((ref, taskId) {
  final dao = ref.watch(taskDaoProvider);
  // Watch all tasks from DAO and filter by ID. This is a lightweight
  // stream operation — no polling.
  return dao.watchTaskById(taskId);
});

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
