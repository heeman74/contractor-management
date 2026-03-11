import 'dart:io';

import 'package:flutter/material.dart';

import '../../domain/attachment_entity.dart';

/// Compact 60x60 thumbnail widget for a single [AttachmentEntity].
///
/// Displays:
/// - Photos: local file image (or remote URL if localPath is missing)
/// - PDFs: PDF icon with filename
/// - Drawings: local PNG file
///
/// Upload status overlay in the bottom-right corner:
/// - pending_upload: clock icon
/// - uploading: circular progress
/// - uploaded: checkmark
/// - failed: retry icon
///
/// On tap: shows a full-size dialog for photos/drawings. For PDFs, shows
/// caption text only (no PDF viewer in v1).
class AttachmentThumbnail extends StatelessWidget {
  final AttachmentEntity attachment;

  /// If true, shows a remove button (X) for pre-save selection. Used in
  /// [AddNoteBottomSheet] before the note is saved.
  final VoidCallback? onRemove;

  const AttachmentThumbnail({
    required this.attachment,
    this.onRemove,
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => _onTap(context),
      child: Stack(
        children: [
          _ThumbnailBody(attachment: attachment),
          // Upload status overlay
          Positioned(
            bottom: 2,
            right: 2,
            child: _UploadStatusBadge(status: attachment.uploadStatus),
          ),
          // Remove button (shown before save, in the bottom sheet)
          if (onRemove != null)
            Positioned(
              top: 0,
              right: 0,
              child: GestureDetector(
                onTap: onRemove,
                child: Container(
                  width: 18,
                  height: 18,
                  decoration: BoxDecoration(
                    color: Colors.black54,
                    borderRadius: BorderRadius.circular(9),
                  ),
                  child: const Icon(
                    Icons.close,
                    size: 12,
                    color: Colors.white,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  void _onTap(BuildContext context) {
    if (attachment.attachmentType == 'pdf') {
      _showPdfDialog(context);
    } else {
      _showImageDialog(context);
    }
  }

  void _showImageDialog(BuildContext context) {
    final hasLocal = attachment.localPath.isNotEmpty &&
        File(attachment.localPath).existsSync();
    final hasRemote = attachment.remoteUrl != null;

    if (!hasLocal && !hasRemote) return;

    showDialog<void>(
      context: context,
      builder: (context) => Dialog(
        insetPadding: const EdgeInsets.all(16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Flexible(
              child: hasLocal
                  ? Image.file(
                      File(attachment.localPath),
                      fit: BoxFit.contain,
                    )
                  : Image.network(
                      attachment.remoteUrl!,
                      fit: BoxFit.contain,
                      loadingBuilder: (context, child, loadingProgress) {
                        if (loadingProgress == null) return child;
                        return const Center(
                          child: CircularProgressIndicator(),
                        );
                      },
                    ),
            ),
            if (attachment.caption != null && attachment.caption!.isNotEmpty)
              Padding(
                padding: const EdgeInsets.all(8),
                child: Text(
                  attachment.caption!,
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ),
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Close'),
            ),
          ],
        ),
      ),
    );
  }

  void _showPdfDialog(BuildContext context) {
    final filename = attachment.localPath.isNotEmpty
        ? attachment.localPath.split('/').last
        : 'PDF attachment';

    showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.picture_as_pdf, color: Colors.red),
            SizedBox(width: 8),
            Text('PDF Attachment'),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(filename),
            if (attachment.caption != null && attachment.caption!.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(
                  attachment.caption!,
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }
}

// ─── Thumbnail body ────────────────────────────────────────────────────────────

class _ThumbnailBody extends StatelessWidget {
  final AttachmentEntity attachment;

  const _ThumbnailBody({required this.attachment});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 60,
      height: 60,
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(8),
      ),
      clipBehavior: Clip.hardEdge,
      child: _buildContent(context),
    );
  }

  Widget _buildContent(BuildContext context) {
    if (attachment.attachmentType == 'pdf') {
      return _PdfThumbnailContent(localPath: attachment.localPath);
    }

    // Photo or drawing — try local file first, fall back to remote URL
    final hasLocal = attachment.localPath.isNotEmpty &&
        File(attachment.localPath).existsSync();

    if (hasLocal) {
      return Image.file(
        File(attachment.localPath),
        fit: BoxFit.cover,
        width: 60,
        height: 60,
        errorBuilder: (context, error, stackTrace) {
          debugPrint('[AttachmentThumbnail] Failed to load local image: $error');
          return _PlaceholderIcon(type: attachment.attachmentType);
        },
      );
    }

    if (attachment.remoteUrl != null) {
      return Image.network(
        attachment.remoteUrl!,
        fit: BoxFit.cover,
        width: 60,
        height: 60,
        loadingBuilder: (context, child, loadingProgress) {
          if (loadingProgress == null) return child;
          return const Center(
            child: SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
          );
        },
        errorBuilder: (context, error, stackTrace) {
          debugPrint('[AttachmentThumbnail] Failed to load remote image: $error');
          return _PlaceholderIcon(type: attachment.attachmentType);
        },
      );
    }

    return _PlaceholderIcon(type: attachment.attachmentType);
  }
}

class _PdfThumbnailContent extends StatelessWidget {
  final String localPath;

  const _PdfThumbnailContent({required this.localPath});

  @override
  Widget build(BuildContext context) {
    final filename = localPath.isNotEmpty ? localPath.split('/').last : 'PDF';
    return Padding(
      padding: const EdgeInsets.all(4),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.picture_as_pdf, size: 24, color: Colors.red),
          const SizedBox(height: 2),
          Text(
            filename,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.labelSmall,
          ),
        ],
      ),
    );
  }
}

class _PlaceholderIcon extends StatelessWidget {
  final String type;

  const _PlaceholderIcon({required this.type});

  @override
  Widget build(BuildContext context) {
    final icon = switch (type) {
      'pdf' => Icons.picture_as_pdf,
      'drawing' => Icons.draw_outlined,
      _ => Icons.image_not_supported_outlined,
    };
    return Icon(
      icon,
      size: 28,
      color: Theme.of(context).colorScheme.onSurfaceVariant,
    );
  }
}

// ─── Upload status badge ───────────────────────────────────────────────────────

class _UploadStatusBadge extends StatelessWidget {
  final String status;

  const _UploadStatusBadge({required this.status});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 16,
      height: 16,
      decoration: BoxDecoration(
        color: Colors.black54,
        borderRadius: BorderRadius.circular(8),
      ),
      child: _buildIcon(),
    );
  }

  Widget _buildIcon() {
    return switch (status) {
      'uploaded' => const Icon(Icons.check, size: 10, color: Colors.green),
      'uploading' => const SizedBox(
          width: 10,
          height: 10,
          child: CircularProgressIndicator(
            strokeWidth: 1.5,
            color: Colors.white,
          ),
        ),
      'failed' => const Icon(Icons.refresh, size: 10, color: Colors.orange),
      _ => // pending_upload
        const Icon(Icons.schedule, size: 10, color: Colors.white),
    };
  }
}
