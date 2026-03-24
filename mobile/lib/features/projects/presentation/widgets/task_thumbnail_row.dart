import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers/project_providers.dart';

/// Displays 2–3 small photo thumbnails for a task row in the GC read-only view.
///
/// Per D-15: GC can see quick visual progress by looking at photo thumbnails
/// directly on each task row without opening individual tasks.
///
/// Layout:
/// - Row of up to 3 ClipRRect thumbnails (32×32 rounded-md)
/// - If more than 3 photos: the 3rd slot shows a "+N more" overlay
/// - If no photos: SizedBox.shrink() (empty, no space taken)
/// - Spacing: SizedBox(width: 4) between thumbnails
///
/// Parameters:
///   [taskId] — task ID used to watch photo attachments via [taskAttachmentsProvider].
class TaskThumbnailRow extends ConsumerWidget {
  const TaskThumbnailRow({required this.taskId, super.key});

  final String taskId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final attachmentsAsync = ref.watch(taskAttachmentsProvider(taskId));

    return attachmentsAsync.when(
      loading: () => const SizedBox.shrink(),
      error: (_, __) => const SizedBox.shrink(),
      data: (attachments) {
        // Filter to photo-type attachments only.
        final photos = attachments
            .where((a) => a.attachmentType == 'photo')
            .toList();

        if (photos.isEmpty) {
          return const SizedBox.shrink();
        }

        // Show at most 3 thumbnails; last one may show "+N" overflow badge.
        final displayCount = photos.length > 3 ? 3 : photos.length;
        final extraCount = photos.length - 2; // visible overflow on slot 3

        return Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (int i = 0; i < displayCount; i++) ...[
              if (i > 0) const SizedBox(width: 4),
              _buildThumbnail(
                photos[i].localPath,
                photos[i].remoteUrl,
                // Show overflow badge on slot 3 when there are >3 photos.
                overflowCount:
                    (i == 2 && photos.length > 3) ? extraCount : null,
              ),
            ],
          ],
        );
      },
    );
  }

  /// Builds a single 32×32 rounded thumbnail with optional overflow badge.
  Widget _buildThumbnail(
    String? localPath,
    String? remoteUrl, {
    int? overflowCount,
  }) {
    Widget imageWidget;

    if (localPath != null && localPath.isNotEmpty) {
      imageWidget = Image.file(
        File(localPath),
        width: 32,
        height: 32,
        fit: BoxFit.cover,
        errorBuilder: (context, error, stackTrace) =>
            _fallbackThumbnail(remoteUrl),
      );
    } else if (remoteUrl != null && remoteUrl.isNotEmpty) {
      imageWidget = Image.network(
        remoteUrl,
        width: 32,
        height: 32,
        fit: BoxFit.cover,
        errorBuilder: (context, error, stackTrace) =>
            _placeholderThumbnail(),
      );
    } else {
      imageWidget = _placeholderThumbnail();
    }

    Widget thumbnail = ClipRRect(
      borderRadius: BorderRadius.circular(4),
      child: SizedBox(width: 32, height: 32, child: imageWidget),
    );

    // Overlay "+N" badge for overflow slot
    if (overflowCount != null && overflowCount > 0) {
      thumbnail = Stack(
        children: [
          thumbnail,
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: Container(
              width: 32,
              height: 32,
              color: Colors.black54,
              alignment: Alignment.center,
              child: Text(
                '+$overflowCount',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 10,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ),
        ],
      );
    }

    return thumbnail;
  }

  /// Returns a network fallback or placeholder if local file fails.
  Widget _fallbackThumbnail(String? remoteUrl) {
    if (remoteUrl != null && remoteUrl.isNotEmpty) {
      return Image.network(
        remoteUrl,
        width: 32,
        height: 32,
        fit: BoxFit.cover,
        errorBuilder: (context, error, stackTrace) => _placeholderThumbnail(),
      );
    }
    return _placeholderThumbnail();
  }

  /// Grey placeholder shown when both localPath and remoteUrl are unavailable.
  Widget _placeholderThumbnail() {
    return Container(
      width: 32,
      height: 32,
      color: const Color(0xFFE0E0E0),
      child: const Icon(
        Icons.image_outlined,
        size: 16,
        color: Color(0xFF9E9E9E),
      ),
    );
  }
}
