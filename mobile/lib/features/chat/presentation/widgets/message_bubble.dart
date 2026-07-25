import 'dart:io';

import 'package:contractorhub/core/network/media_url.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/database/app_database.dart' show ChatMessage;
import '../../../../core/routing/route_names.dart';

/// Adaptive chat message bubble.
///
/// Own messages (isOwn: true) are right-aligned with [colorScheme.primary]
/// background and [colorScheme.onPrimary] text.
///
/// Incoming messages (isOwn: false) are left-aligned with
/// [colorScheme.surfaceVariant] background and [colorScheme.onSurface] text.
///
/// Supports four content variants:
///   - text-only: bodyMedium text
///   - photo: ClipRRect thumbnail (max 200px wide), tap → full-screen view
///   - pdf: PDF icon + filename tile, tap → url_launcher
///   - annotated_photo: thumbnail + "Annotated photo" chip, tap → annotation view
///
/// Status icons (own messages only):
///   - 'pending': [Icons.schedule] clock icon (opacity 0.7 on bubble)
///   - 'sent': [Icons.check] single check
///   - read receipt present: [Icons.done_all] double check (accent color)
class MessageBubble extends StatelessWidget {
  const MessageBubble({
    required this.message,
    required this.isOwn,
    this.readByText,
    super.key,
  });

  final ChatMessage message;
  final bool isOwn;

  /// Read receipt display text (e.g. "Read by Alex" or "Read by Alex and 2 others").
  final String? readByText;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    final isPending = message.status == 'pending';
    final isRead = readByText != null;

    final backgroundColor =
        isOwn ? colorScheme.primary : colorScheme.surfaceContainerHighest;
    final textColor =
        isOwn ? colorScheme.onPrimary : colorScheme.onSurface;

    // Sharp corner on the sender side
    final borderRadius = isOwn
        ? const BorderRadius.only(
            topLeft: Radius.circular(16),
            topRight: Radius.circular(4), // sharp top-right for own
            bottomLeft: Radius.circular(16),
            bottomRight: Radius.circular(16),
          )
        : const BorderRadius.only(
            topLeft: Radius.circular(4), // sharp top-left for incoming
            topRight: Radius.circular(16),
            bottomLeft: Radius.circular(16),
            bottomRight: Radius.circular(16),
          );

    return Align(
      alignment: isOwn ? Alignment.centerRight : Alignment.centerLeft,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        child: Column(
          crossAxisAlignment:
              isOwn ? CrossAxisAlignment.end : CrossAxisAlignment.start,
          children: [
            // Sender name label for incoming messages
            if (!isOwn)
              Padding(
                padding: const EdgeInsets.only(left: 4, bottom: 2),
                child: Text(
                  message.senderName,
                  style: textTheme.bodySmall?.copyWith(
                    fontWeight: FontWeight.w600,
                    color: colorScheme.onSurface.withValues(alpha: 0.6),
                  ),
                ),
              ),

            // Message bubble
            Semantics(
              label:
                  '${message.senderName}: $_semanticsContent, ${_formatTimestamp(message.createdAt)}',
              liveRegion: !isOwn, // announce incoming messages to screen readers
              child: GestureDetector(
                onLongPress: () => _showOptions(context, message),
                child: Opacity(
                  opacity: isPending ? 0.7 : 1.0,
                  child: Container(
                    constraints: BoxConstraints(
                      maxWidth: MediaQuery.of(context).size.width * 0.72,
                    ),
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: backgroundColor,
                      borderRadius: borderRadius,
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        // Content area
                        _buildContent(context, textColor),

                        // Bottom row: timestamp + status icon
                        const SizedBox(height: 4),
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          mainAxisAlignment: MainAxisAlignment.end,
                          children: [
                            Text(
                              _formatTimestamp(message.createdAt),
                              style: textTheme.bodySmall?.copyWith(
                                color: textColor.withValues(alpha: 0.7),
                                fontSize: 11,
                              ),
                            ),
                            if (isOwn) ...[
                              const SizedBox(width: 4),
                              _StatusIcon(
                                status: message.status,
                                isRead: isRead,
                                color: textColor,
                                accentColor: colorScheme.secondary,
                              ),
                            ],
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),

            // Read receipt row below own messages
            if (isOwn && readByText != null)
              Padding(
                padding: const EdgeInsets.only(top: 2, right: 4),
                child: Semantics(
                  label: 'Read by $readByText',
                  child: Text(
                    'Read by $readByText',
                    style: textTheme.bodySmall?.copyWith(
                      color: colorScheme.onSurface.withValues(alpha: 0.5),
                      fontSize: 11,
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildContent(BuildContext context, Color textColor) {
    final textTheme = Theme.of(context).textTheme;
    final attachmentType = message.attachmentType;
    final attachmentUrl = message.attachmentUrl;

    if (attachmentType == 'photo' && attachmentUrl != null) {
      return _PhotoContent(
        url: attachmentUrl,
        textColor: textColor,
        context: context,
        isAnnotated: false,
      );
    }

    if (attachmentType == 'annotated_photo' && attachmentUrl != null) {
      return _PhotoContent(
        url: attachmentUrl,
        textColor: textColor,
        context: context,
        isAnnotated: true,
        annotationData: message.annotationData,
      );
    }

    if (attachmentType == 'pdf' && attachmentUrl != null) {
      return Semantics(
        label: 'PDF: ${_pdfFilename(attachmentUrl)}',
        button: true,
        child: GestureDetector(
          onTap: () => _openPdf(context, attachmentUrl),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.picture_as_pdf,
                color: textColor,
                size: 24,
              ),
              const SizedBox(width: 8),
              Flexible(
                child: Text(
                  _pdfFilename(attachmentUrl),
                  style: textTheme.bodyMedium?.copyWith(
                    color: textColor,
                    decoration: TextDecoration.underline,
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
        ),
      );
    }

    // Default: text content
    final content = message.content ?? '';
    return Text(
      content,
      style: textTheme.bodyMedium?.copyWith(color: textColor),
    );
  }

  String get _semanticsContent {
    if (message.attachmentType == 'photo') return 'shared a photo';
    if (message.attachmentType == 'pdf') return 'shared a PDF';
    if (message.attachmentType == 'annotated_photo') {
      return 'shared an annotated photo';
    }
    return message.content ?? '';
  }

  String _pdfFilename(String url) {
    final parts = url.split('/');
    return parts.isNotEmpty ? parts.last : 'document.pdf';
  }

  void _openPdf(BuildContext context, String url) {
    // url_launcher approach — same pattern as Phase 22 task attachments.
    // If url_launcher is not yet wired, show a snackbar placeholder.
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Opening: $url')),
    );
  }

  void _showOptions(BuildContext context, ChatMessage msg) {
    final content = msg.content;
    showModalBottomSheet<void>(
      context: context,
      builder: (_) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (content != null && content.isNotEmpty)
              ListTile(
                leading: const Icon(Icons.copy),
                title: const Text('Copy Text'),
                onTap: () {
                  Clipboard.setData(ClipboardData(text: content));
                  Navigator.of(context).pop();
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Copied to clipboard')),
                  );
                },
              ),
            if (isOwn)
              ListTile(
                leading: const Icon(Icons.info_outline),
                title: const Text('Queued — will send when online'),
                enabled: msg.status == 'pending',
                onTap: () => Navigator.of(context).pop(),
              ),
          ],
        ),
      ),
    );
  }

  String _formatTimestamp(DateTime dt) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final msgDay = DateTime(dt.year, dt.month, dt.day);
    final diff = today.difference(msgDay).inDays;

    final hour = dt.hour;
    final minute = dt.minute.toString().padLeft(2, '0');
    final period = hour < 12 ? 'AM' : 'PM';
    final displayHour = hour == 0 ? 12 : (hour > 12 ? hour - 12 : hour);
    final timeStr = '$displayHour:$minute $period';

    if (diff == 0) return timeStr;

    const days = ['Sun', 'Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat'];
    if (diff <= 6) return '${days[dt.weekday % 7]} $timeStr';

    const months = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
    ];
    return '${months[dt.month - 1]} ${dt.day}';
  }
}

// ---------------------------------------------------------------------------
// Photo content widget
// ---------------------------------------------------------------------------

class _PhotoContent extends StatelessWidget {
  const _PhotoContent({
    required this.url,
    required this.textColor,
    required this.context,
    required this.isAnnotated,
    this.annotationData,
  });

  final String url;
  final Color textColor;
  final BuildContext context;
  final bool isAnnotated;
  final String? annotationData;

  @override
  Widget build(BuildContext bContext) {
    final textTheme = Theme.of(bContext).textTheme;
    final colorScheme = Theme.of(bContext).colorScheme;

    return GestureDetector(
      onTap: () {
        if (isAnnotated && annotationData != null) {
          // Open photo annotation screen in read-only mode
          bContext.push(
            RouteNames.photoAnnotation,
            extra: {
              'localPath': url,
              'annotationData': annotationData,
              'readOnly': true,
            },
          );
        } else {
          // Open full-screen photo viewer
          // For now show a placeholder; wired fully when photo viewer
          // accepts URL (Phase 22 viewer expects local file paths)
          ScaffoldMessenger.of(bContext).showSnackBar(
            const SnackBar(content: Text('Opening photo...')),
          );
        }
      },
      child: Semantics(
        label: isAnnotated ? 'Shared photo, annotated' : 'Shared photo',
        image: true,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: _buildImage(url),
            ),
            if (isAnnotated) ...[
              const SizedBox(height: 4),
              Chip(
                label: const Text('Annotated photo'),
                labelStyle: textTheme.bodySmall?.copyWith(
                  color: colorScheme.onSecondaryContainer,
                ),
                backgroundColor: colorScheme.secondaryContainer,
                padding: EdgeInsets.zero,
                materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildImage(String imageUrl) {
    // Local file paths render directly; everything else is a backend media URL
    // (possibly server-relative) fetched over the authenticated /uploads/chat
    // endpoint with a Bearer header.
    final file = File(imageUrl);
    if (!imageUrl.startsWith('/') && file.existsSync()) {
      return Image.file(
        file,
        width: 200,
        fit: BoxFit.cover,
        errorBuilder: (_, __, ___) => _imagePlaceholder(),
      );
    }
    final resolved = resolveMediaUrl(imageUrl);
    if (resolved != null &&
        (resolved.startsWith('http://') || resolved.startsWith('https://'))) {
      return Image.network(
        resolved,
        headers: mediaAuthHeaders(),
        width: 200,
        fit: BoxFit.cover,
        errorBuilder: (_, __, ___) => _imagePlaceholder(),
      );
    }
    return _imagePlaceholder();
  }

  Widget _imagePlaceholder() {
    return Container(
      width: 200,
      height: 120,
      color: Colors.grey.withValues(alpha: 0.2),
      child: const Center(child: Icon(Icons.image, size: 40)),
    );
  }
}

// ---------------------------------------------------------------------------
// Status icon widget
// ---------------------------------------------------------------------------

class _StatusIcon extends StatelessWidget {
  const _StatusIcon({
    required this.status,
    required this.isRead,
    required this.color,
    required this.accentColor,
  });

  final String status;
  final bool isRead;
  final Color color;
  final Color accentColor;

  @override
  Widget build(BuildContext context) {
    if (status == 'pending') {
      return Icon(Icons.schedule, size: 14, color: color.withValues(alpha: 0.7));
    }
    if (isRead) {
      return Icon(Icons.done_all, size: 14, color: accentColor);
    }
    return Icon(Icons.check, size: 14, color: color.withValues(alpha: 0.7));
  }
}
