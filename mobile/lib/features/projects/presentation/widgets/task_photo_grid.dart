import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/database/app_database.dart'
    hide UserRole, BookingDao, NoteDao, AttachmentDao, TimeEntryDao,
        QuoteDao, InvoiceDao;
import '../../../../core/routing/route_names.dart';
import '../providers/project_providers.dart';

/// 3-column photo grid for a task's photo attachments.
///
/// Features:
/// - 3-column grid with square aspect ratio cells
/// - Photo thumbnails from localPath or remoteUrl
/// - Pencil badge overlay when annotationData is set (non-destructive)
/// - Tap opens full-screen viewer with "Annotate" action
/// - Empty state when no photos exist
///
/// Uses [taskAttachmentsProvider] filtered to attachmentType == 'photo'.
class TaskPhotoGrid extends ConsumerWidget {
  const TaskPhotoGrid({required this.taskId, super.key});

  final String taskId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final attachmentsAsync = ref.watch(taskAttachmentsProvider(taskId));

    return attachmentsAsync.when(
      loading: () => const SizedBox(
        height: 80,
        child: Center(child: CircularProgressIndicator()),
      ),
      error: (error, _) => Text(
        'Error loading photos: $error',
        style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: Theme.of(context).colorScheme.error,
            ),
      ),
      data: (allAttachments) {
        final photos = allAttachments
            .where((a) => a.attachmentType == 'photo')
            .toList();

        if (photos.isEmpty) {
          return Padding(
            padding: const EdgeInsets.symmetric(vertical: 16),
            child: Center(
              child: Text(
                "No photos yet. Tap 'Add Photo' to document your progress.",
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: Theme.of(context)
                          .colorScheme
                          .onSurface
                          .withValues(alpha: 0.5),
                    ),
              ),
            ),
          );
        }

        return GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 3,
            mainAxisSpacing: 8,
            crossAxisSpacing: 8,
          ),
          itemCount: photos.length,
          itemBuilder: (context, index) {
            final attachment = photos[index];
            return _PhotoCell(
              attachment: attachment,
              taskId: taskId,
              onTap: () => _openPhoto(context, photos, index),
            );
          },
        );
      },
    );
  }

  void _openPhoto(
      BuildContext context, List<TaskAttachment> photos, int index) {
    // Navigate to a simple full-screen photo viewer.
    // Pass the photo and taskId via extra for the annotate action.
    final attachment = photos[index];
    context.push(
      RouteNames.taskPhotoViewerPath(taskId, attachment.id),
      extra: {
        'attachment': attachment,
        'allPhotos': photos,
        'initialIndex': index,
      },
    );
  }
}

/// A single photo cell in the grid.
class _PhotoCell extends StatelessWidget {
  const _PhotoCell({
    required this.attachment,
    required this.taskId,
    required this.onTap,
  });

  final TaskAttachment attachment;
  final String taskId;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(8),
        child: Stack(
          fit: StackFit.expand,
          children: [
            // Photo thumbnail
            _buildThumbnail(),
            // Annotation badge — pencil icon in bottom-right when annotated
            if (attachment.annotationData != null)
              Positioned(
                bottom: 4,
                right: 4,
                child: CircleAvatar(
                  radius: 12,
                  backgroundColor:
                      Theme.of(context).colorScheme.primaryContainer,
                  child: Icon(
                    Icons.edit,
                    size: 14,
                    color: Theme.of(context).colorScheme.onPrimaryContainer,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildThumbnail() {
    // Try local path first, fall back to network image
    if (attachment.localPath != null &&
        File(attachment.localPath!).existsSync()) {
      return Image.file(
        File(attachment.localPath!),
        fit: BoxFit.cover,
        errorBuilder: (context, error, _) => _errorPlaceholder(context),
      );
    }
    if (attachment.remoteUrl != null) {
      return Image.network(
        attachment.remoteUrl!,
        fit: BoxFit.cover,
        loadingBuilder: (context, child, progress) {
          if (progress == null) return child;
          return const Center(child: CircularProgressIndicator(strokeWidth: 2));
        },
        errorBuilder: (context, error, _) => _errorPlaceholder(context),
      );
    }
    return _errorPlaceholder(null);
  }

  Widget _errorPlaceholder(BuildContext? context) {
    return Container(
      color: Colors.grey[200],
      child: const Icon(Icons.broken_image, color: Colors.grey),
    );
  }
}
