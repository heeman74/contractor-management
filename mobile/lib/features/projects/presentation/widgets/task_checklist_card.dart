import 'dart:io';

import 'package:drift/drift.dart' show Value;
import 'package:flutter/material.dart';
import 'package:flutter_image_compress/flutter_image_compress.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:uuid/uuid.dart';

import '../../../../core/database/app_database.dart'
    hide UserRole, BookingDao, NoteDao, AttachmentDao, TimeEntryDao,
        QuoteDao, InvoiceDao;
import '../../../../features/auth/domain/auth_state.dart';
import '../../../../features/auth/presentation/providers/auth_provider.dart';
import '../providers/project_providers.dart';

/// A task card for the contractor checklist with priority left border.
///
/// Handles:
/// - Priority left border color (urgent=red, high=orange, medium=blue, low=grey)
/// - Photo gate: if task.photoRequired and no photos → camera icon instead of checkbox
/// - Checkbox toggling task status between 'in_progress' and 'complete'
/// - Overdue amber background when dueDate is in the past
/// - Blocked state with lock icon and disabled checkbox
/// - Completed task strikethrough + reduced opacity
///
/// Camera capture flow: ImagePicker → compressPhoto → localPath → TaskAttachmentDao.insertAttachment
class TaskChecklistCard extends ConsumerWidget {
  const TaskChecklistCard({
    required this.task,
    required this.onTap,
    super.key,
  });

  final ProjectTask task;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final textTheme = Theme.of(context).textTheme;
    final colorScheme = Theme.of(context).colorScheme;
    final priorityColor = _priorityColor(task.priority);

    final isCompleted = task.status == 'complete';
    final isBlocked = task.status == 'blocked';
    final isOverdue = task.dueDate != null &&
        task.dueDate!.isBefore(DateTime.now()) &&
        !isCompleted;

    // Watch photo count if photo is required
    final photoCountAsync = task.photoRequired
        ? ref.watch(taskPhotoCountProvider(task.id))
        : const AsyncData<int>(1); // non-zero so checkbox is shown

    final photoCount = photoCountAsync.value ?? 0;
    final showCameraIcon = task.photoRequired && photoCount == 0;

    return Opacity(
      opacity: isCompleted ? 0.7 : 1.0,
      child: Card(
        margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
        elevation: 1,
        color: isOverdue ? const Color(0xFFFFF8E1) : null,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(10),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(10),
            child: IntrinsicHeight(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // Priority left border — 4px wide
                  Container(
                    width: 4,
                    color: priorityColor,
                  ),
                  // Leading: checkbox or camera icon
                  SizedBox(
                    width: 48,
                    child: Center(
                      child: isBlocked
                          ? Icon(
                              Icons.lock_outline,
                              color:
                                  colorScheme.onSurface.withValues(alpha: 0.4),
                              size: 20,
                            )
                          : showCameraIcon
                              ? Semantics(
                                  label: 'Capture photo for ${task.title}',
                                  child: IconButton(
                                    icon: const Icon(Icons.camera_alt),
                                    color: colorScheme.primary,
                                    onPressed: () =>
                                        _capturePhoto(context, ref),
                                    tooltip: 'Add photo to complete',
                                  ),
                                )
                              : Checkbox(
                                  value: isCompleted,
                                  onChanged: isBlocked
                                      ? null
                                      : (_) => _toggleStatus(ref),
                                ),
                    ),
                  ),
                  // Task content
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 12),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            task.title,
                            style: textTheme.titleMedium?.copyWith(
                              decoration: isCompleted
                                  ? TextDecoration.lineThrough
                                  : null,
                              color: isCompleted
                                  ? colorScheme.onSurface.withValues(alpha: 0.6)
                                  : null,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Wrap(
                            spacing: 6,
                            children: [
                              _PriorityBadge(priority: task.priority),
                              if (task.photoRequired)
                                Chip(
                                  label: const Text('Photo required'),
                                  labelStyle: textTheme.labelSmall,
                                  visualDensity: VisualDensity.compact,
                                  padding: EdgeInsets.zero,
                                ),
                              if (task.estimatedHours != null)
                                Chip(
                                  label: Text(
                                      '${task.estimatedHours}h estimate'),
                                  labelStyle: textTheme.labelSmall,
                                  visualDensity: VisualDensity.compact,
                                  padding: EdgeInsets.zero,
                                ),
                            ],
                          ),
                          if (task.dueDate != null) ...[
                            const SizedBox(height: 2),
                            Text(
                              isOverdue
                                  ? 'Overdue: ${_formatDate(task.dueDate!)}'
                                  : 'Due ${_formatDate(task.dueDate!)}',
                              style: textTheme.bodySmall?.copyWith(
                                color: isOverdue
                                    ? const Color(0xFFE65100)
                                    : colorScheme.onSurface
                                        .withValues(alpha: 0.5),
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),
                  // Trailing chevron
                  Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: Icon(
                      Icons.chevron_right,
                      color: colorScheme.onSurface.withValues(alpha: 0.4),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// Toggle task status between 'complete' and 'in_progress'.
  Future<void> _toggleStatus(WidgetRef ref) async {
    final newStatus = task.status == 'complete' ? 'in_progress' : 'complete';
    await ref.read(taskDaoProvider).updateTask(
          task.id,
          ProjectTasksCompanion(
            status: Value(newStatus),
            updatedAt: Value(DateTime.now()),
          ),
        );
  }

  /// Open camera, compress photo, save to local path, insert attachment.
  Future<void> _capturePhoto(BuildContext context, WidgetRef ref) async {
    final picker = ImagePicker();
    final XFile? picked =
        await picker.pickImage(source: ImageSource.camera, imageQuality: 90);
    if (picked == null) return;

    try {
      final appDir = await getApplicationDocumentsDirectory();
      final attachmentId = const Uuid().v4();
      final localPath =
          '${appDir.path}/task_photos/${task.id}/$attachmentId.jpg';

      // Ensure directory exists
      await Directory('${appDir.path}/task_photos/${task.id}')
          .create(recursive: true);

      // Compress to max 2K dimension
      final XFile? compressed = await FlutterImageCompress.compressAndGetFile(
        picked.path,
        localPath,
        quality: 85,
        minWidth: 1080,
      );

      final finalPath = compressed?.path ?? picked.path;

      // Get auth info for companyId
      final authState = ref.read(authNotifierProvider);
      final companyId =
          authState is AuthAuthenticated ? authState.companyId : '';

      await ref.read(taskAttachmentDaoProvider).insertAttachment(
            TaskAttachmentsCompanion.insert(
              id: Value(attachmentId),
              companyId: companyId,
              taskId: task.id,
              attachmentType: 'photo',
              localPath: Value(finalPath),
              sortOrder: const Value(0),
              createdAt: DateTime.now(),
              updatedAt: DateTime.now(),
            ),
          );
    } catch (e) {
      debugPrint('[TaskChecklistCard] Photo capture error: $e');
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Failed to save photo. Please try again.')),
        );
      }
    }
  }

  static Color _priorityColor(String priority) {
    return switch (priority) {
      'urgent' => const Color(0xFFD32F2F),
      'high' => const Color(0xFFF57C00),
      'medium' => const Color(0xFF1565C0),
      'low' => const Color(0xFF9E9E9E),
      _ => const Color(0xFF9E9E9E),
    };
  }

  static String _formatDate(DateTime dt) {
    return '${dt.day}/${dt.month}/${dt.year}';
  }
}

/// Small colored chip showing task priority.
class _PriorityBadge extends StatelessWidget {
  const _PriorityBadge({required this.priority});

  final String priority;

  @override
  Widget build(BuildContext context) {
    final color = _color(priority);
    return Chip(
      label: Text(
        priority,
        style: Theme.of(context).textTheme.labelSmall?.copyWith(
              color: Colors.white,
            ),
      ),
      backgroundColor: color,
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
