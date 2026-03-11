import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_image_compress/flutter_image_compress.dart';
import 'package:image_picker/image_picker.dart';
import 'package:file_picker/file_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:uuid/uuid.dart';

// app_database.dart re-exports NoteDao and AttachmentDao.
import '../../../../core/database/app_database.dart';
import '../../domain/attachment_entity.dart';
import 'attachment_thumbnail.dart';

/// Maximum attachments allowed per note (per user decision).
const _maxAttachments = 10;

/// Bottom sheet for adding a field note with optional attachments.
///
/// Captures:
/// - Text body (required to enable Save, unless attachments are present)
/// - Camera photos (compressed to 2K max / 90% quality, GPS EXIF preserved)
/// - Gallery photos (same compression)
/// - PDF documents (file_picker)
/// - Drawings (route result from DrawingPadScreen)
///
/// On save:
/// 1. [NoteDao.insertNote] creates the note and enqueues a sync item
/// 2. [AttachmentDao.insertAttachment] creates each attachment (pending_upload)
/// 3. Shows "Note saved" snackbar — attachments upload on next sync
///
/// Notes are immutable after save — no edit or delete.
///
/// Usage:
/// ```dart
/// AddNoteBottomSheet.show(
///   context: context,
///   jobId: job.id,
///   companyId: companyId,
///   authorId: currentUserId,
///   noteDao: noteDao,
///   attachmentDao: attachmentDao,
/// );
/// ```
class AddNoteBottomSheet extends StatefulWidget {
  const AddNoteBottomSheet._({
    required this.jobId,
    required this.companyId,
    required this.authorId,
    required this.noteDao,
    required this.attachmentDao,
  });

  final String jobId;
  final String companyId;
  final String authorId;
  final NoteDao noteDao;
  final AttachmentDao attachmentDao;

  /// Shows the bottom sheet for adding a note.
  ///
  /// DAOs are passed in to avoid mixing GetIt inside provider widgets.
  static Future<void> show({
    required BuildContext context,
    required String jobId,
    required String companyId,
    required String authorId,
    required NoteDao noteDao,
    required AttachmentDao attachmentDao,
  }) {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => AddNoteBottomSheet._(
        jobId: jobId,
        companyId: companyId,
        authorId: authorId,
        noteDao: noteDao,
        attachmentDao: attachmentDao,
      ),
    );
  }

  @override
  State<AddNoteBottomSheet> createState() => _AddNoteBottomSheetState();
}

/// Internal model for a pending attachment before saving to the DAO.
class _PendingAttachment {
  final String id;
  final String type; // 'photo', 'pdf', 'drawing'
  final String localPath;
  final String? thumbnailPath;
  String? caption;

  _PendingAttachment({
    required this.id,
    required this.type,
    required this.localPath,
    this.thumbnailPath,
    this.caption,
  });
}

class _AddNoteBottomSheetState extends State<AddNoteBottomSheet> {
  final _bodyController = TextEditingController();
  final _imagePicker = ImagePicker();
  final List<_PendingAttachment> _attachments = [];
  bool _isSaving = false;

  @override
  void dispose() {
    _bodyController.dispose();
    super.dispose();
  }

  bool get _canSave {
    final hasText = _bodyController.text.trim().isNotEmpty;
    final hasAttachments = _attachments.isNotEmpty;
    return hasText || hasAttachments;
  }

  bool get _atLimit => _attachments.length >= _maxAttachments;

  @override
  Widget build(BuildContext context) {
    final viewInsets = MediaQuery.of(context).viewInsets;

    return Padding(
      padding: EdgeInsets.only(bottom: viewInsets.bottom),
      child: DraggableScrollableSheet(
        initialChildSize: 0.6,
        minChildSize: 0.4,
        maxChildSize: 0.95,
        expand: false,
        builder: (context, scrollController) {
          return Column(
            children: [
              // Drag handle
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.outlineVariant,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              // Header
              Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                child: Row(
                  children: [
                    Text(
                      'Add Field Note',
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.bold,
                          ),
                    ),
                    const Spacer(),
                    TextButton(
                      onPressed: _isSaving
                          ? null
                          : () => Navigator.of(context).pop(),
                      child: const Text('Cancel'),
                    ),
                  ],
                ),
              ),
              const Divider(height: 1),
              // Scrollable body
              Expanded(
                child: SingleChildScrollView(
                  controller: scrollController,
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Body text field
                      TextField(
                        controller: _bodyController,
                        maxLength: 2000,
                        maxLines: 5,
                        autofocus: true,
                        decoration: const InputDecoration(
                          hintText: 'Describe what you observed or did...',
                          border: OutlineInputBorder(),
                          alignLabelWithHint: true,
                        ),
                        onChanged: (_) => setState(() {}),
                      ),
                      const SizedBox(height: 12),
                      // Attachment action buttons
                      Row(
                        children: [
                          _AttachButton(
                            icon: Icons.camera_alt_outlined,
                            label: 'Camera',
                            onPressed: _atLimit ? null : _pickFromCamera,
                          ),
                          const SizedBox(width: 8),
                          _AttachButton(
                            icon: Icons.photo_library_outlined,
                            label: 'Gallery',
                            onPressed: _atLimit ? null : _pickFromGallery,
                          ),
                          const SizedBox(width: 8),
                          _AttachButton(
                            icon: Icons.picture_as_pdf,
                            label: 'PDF',
                            onPressed: _atLimit ? null : _pickPdf,
                          ),
                          const SizedBox(width: 8),
                          _AttachButton(
                            icon: Icons.draw_outlined,
                            label: 'Draw',
                            onPressed: _atLimit ? null : _openDrawingPad,
                          ),
                        ],
                      ),
                      // Attachment count warning
                      if (_atLimit)
                        Padding(
                          padding: const EdgeInsets.only(top: 8),
                          child: Text(
                            'Maximum $_maxAttachments attachments per note',
                            style: TextStyle(
                              color: Theme.of(context).colorScheme.error,
                              fontSize: 12,
                            ),
                          ),
                        ),
                      // Attachment preview row
                      if (_attachments.isNotEmpty) ...[
                        const SizedBox(height: 12),
                        SingleChildScrollView(
                          scrollDirection: Axis.horizontal,
                          child: Row(
                            children: _attachments.map((pending) {
                              // Build a transient AttachmentEntity for preview
                              final entity = AttachmentEntity(
                                id: pending.id,
                                companyId: widget.companyId,
                                noteId: '',
                                attachmentType: pending.type,
                                localPath: pending.localPath,
                                thumbnailPath: pending.thumbnailPath,
                                caption: pending.caption,
                                uploadStatus: 'pending_upload',
                                sortOrder: 0,
                                createdAt: DateTime.now(),
                                updatedAt: DateTime.now(),
                              );
                              return Padding(
                                padding: const EdgeInsets.only(right: 8),
                                child: Column(
                                  children: [
                                    AttachmentThumbnail(
                                      attachment: entity,
                                      onRemove: () => _removeAttachment(pending),
                                    ),
                                    // Caption tap
                                    GestureDetector(
                                      onTap: () =>
                                          _editCaption(context, pending),
                                      child: Container(
                                        width: 60,
                                        padding: const EdgeInsets.symmetric(
                                          vertical: 2,
                                        ),
                                        child: Text(
                                          pending.caption?.isNotEmpty == true
                                              ? pending.caption!
                                              : 'Add caption',
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          textAlign: TextAlign.center,
                                          style: Theme.of(context)
                                              .textTheme
                                              .labelSmall
                                              ?.copyWith(
                                                color: Theme.of(context)
                                                    .colorScheme
                                                    .onSurfaceVariant,
                                              ),
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              );
                            }).toList(),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
              // Save button
              SafeArea(
                child: Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  child: FilledButton(
                    onPressed: _canSave && !_isSaving ? _save : null,
                    style: FilledButton.styleFrom(
                      minimumSize: const Size.fromHeight(48),
                    ),
                    child: _isSaving
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Text('Save Note'),
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  // ─── Attachment pickers ──────────────────────────────────────────────────────

  Future<void> _pickFromCamera() async {
    final xFile = await _imagePicker.pickImage(source: ImageSource.camera);
    if (xFile == null) return;
    await _processPhoto(xFile.path);
  }

  Future<void> _pickFromGallery() async {
    final xFile = await _imagePicker.pickImage(source: ImageSource.gallery);
    if (xFile == null) return;
    await _processPhoto(xFile.path);
  }

  Future<void> _processPhoto(String sourcePath) async {
    try {
      final (compressedPath, thumbnailPath) = await compressPhoto(sourcePath);
      final pending = _PendingAttachment(
        id: const Uuid().v4(),
        type: 'photo',
        localPath: compressedPath,
        thumbnailPath: thumbnailPath,
      );
      setState(() => _attachments.add(pending));
    } catch (e) {
      debugPrint('[AddNoteBottomSheet] Photo processing failed: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to process photo: $e'),
            backgroundColor: Theme.of(context).colorScheme.error,
          ),
        );
      }
    }
  }

  Future<void> _pickPdf() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['pdf'],
    );
    if (result == null || result.files.isEmpty) return;

    final sourceFile = result.files.first;
    if (sourceFile.path == null) return;

    try {
      final dir = await getApplicationSupportDirectory();
      final destDir = Directory('${dir.path}/attachments');
      await destDir.create(recursive: true);
      final destPath = '${destDir.path}/${const Uuid().v4()}.pdf';
      await File(sourceFile.path!).copy(destPath);

      final pending = _PendingAttachment(
        id: const Uuid().v4(),
        type: 'pdf',
        localPath: destPath,
      );
      setState(() => _attachments.add(pending));
    } catch (e) {
      debugPrint('[AddNoteBottomSheet] PDF copy failed: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to attach PDF: $e'),
            backgroundColor: Theme.of(context).colorScheme.error,
          ),
        );
      }
    }
  }

  Future<void> _openDrawingPad() async {
    // Navigate to DrawingPadScreen (Plan 04). Receives PNG file path back via
    // Navigator.pop result. If Plan 04 not yet in place, gracefully no-ops.
    final result = await Navigator.of(context).pushNamed<String?>('/drawing-pad');
    if (result == null) return;

    final pending = _PendingAttachment(
      id: const Uuid().v4(),
      type: 'drawing',
      localPath: result,
    );
    setState(() => _attachments.add(pending));
  }

  void _removeAttachment(_PendingAttachment pending) {
    setState(() => _attachments.remove(pending));
  }

  Future<void> _editCaption(
    BuildContext context,
    _PendingAttachment pending,
  ) async {
    final controller = TextEditingController(text: pending.caption ?? '');
    final result = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Add Caption'),
        content: TextField(
          controller: controller,
          maxLength: 200,
          autofocus: true,
          decoration: const InputDecoration(
            hintText: 'Optional caption for this attachment',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(null),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(controller.text.trim()),
            child: const Text('Save'),
          ),
        ],
      ),
    );
    controller.dispose();

    if (result != null) {
      setState(() => pending.caption = result.isEmpty ? null : result);
    }
  }

  // ─── Save handler ────────────────────────────────────────────────────────────

  Future<void> _save() async {
    setState(() => _isSaving = true);

    try {
      final body = _bodyController.text.trim();

      // 1. Insert note and enqueue sync item
      final noteId = await widget.noteDao.insertNote(
        companyId: widget.companyId,
        jobId: widget.jobId,
        authorId: widget.authorId,
        body: body,
      );

      // 2. Insert each attachment (pending_upload; binary upload handled by AttachmentUploadService)
      for (var i = 0; i < _attachments.length; i++) {
        final pending = _attachments[i];
        await widget.attachmentDao.insertAttachment(
          companyId: widget.companyId,
          noteId: noteId,
          attachmentType: pending.type,
          localPath: pending.localPath,
          thumbnailPath: pending.thumbnailPath,
          caption: pending.caption,
          sortOrder: i,
        );
      }

      // 3. Close and show confirmation
      if (mounted) {
        Navigator.of(context).pop();
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Note saved — attachments will upload on next sync'),
          ),
        );
      }
    } catch (e) {
      debugPrint('[AddNoteBottomSheet] Save failed: $e');
      if (mounted) {
        setState(() => _isSaving = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to save note: $e'),
            backgroundColor: Theme.of(context).colorScheme.error,
          ),
        );
      }
    }
  }
}

// ─── Attachment button ─────────────────────────────────────────────────────────

class _AttachButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback? onPressed;

  const _AttachButton({
    required this.icon,
    required this.label,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: OutlinedButton(
        onPressed: onPressed,
        style: OutlinedButton.styleFrom(
          padding: const EdgeInsets.symmetric(vertical: 10),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(8),
          ),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 20),
            const SizedBox(height: 2),
            Text(label, style: const TextStyle(fontSize: 10)),
          ],
        ),
      ),
    );
  }
}

// ─── Photo compression utility ────────────────────────────────────────────────

/// Compress a source photo and generate a thumbnail.
///
/// - Compressed: maxWidth 2048, quality 90, keepExif true (preserves GPS)
/// - Thumbnail: maxWidth 200, quality 70
/// - Both saved to app support dir under attachments/
///
/// Returns (compressedPath, thumbnailPath).
Future<(String compressedPath, String thumbnailPath)> compressPhoto(
  String sourcePath,
) async {
  final dir = await getApplicationSupportDirectory();
  final attachmentsDir = Directory('${dir.path}/attachments');
  await attachmentsDir.create(recursive: true);

  final id = const Uuid().v4();
  final compressedPath = '${attachmentsDir.path}/$id.jpg';
  final thumbnailPath = '${attachmentsDir.path}/${id}_thumb.jpg';

  // Compress to 2K max / 90% quality with GPS EXIF preserved
  final compressedResult = await FlutterImageCompress.compressAndGetFile(
    sourcePath,
    compressedPath,
    minWidth: 1,
    minHeight: 1,
    quality: 90,
    keepExif: true,
  );

  if (compressedResult == null) {
    throw Exception('Image compression failed for $sourcePath');
  }

  // Generate thumbnail: 200x200 max / 70% quality
  final thumbnailResult = await FlutterImageCompress.compressAndGetFile(
    sourcePath,
    thumbnailPath,
    minWidth: 1,
    minHeight: 1,
    quality: 70,
  );

  if (thumbnailResult == null) {
    // Non-fatal: thumbnail generation failed, use compressed as fallback
    debugPrint('[compressPhoto] Thumbnail generation failed, using compressed');
    return (compressedPath, compressedPath);
  }

  return (compressedPath, thumbnailPath);
}
