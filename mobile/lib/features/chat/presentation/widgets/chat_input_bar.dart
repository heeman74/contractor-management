import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../data/chat_ws_client.dart';

/// Chat message input bar — text field + attachment button + send button.
///
/// Layout (16px horizontal padding):
///   [Attachment 48px] [TextField min 48px, max 5 lines] [Send 48px]
///
/// Behaviors:
/// - Send button enabled (colorScheme.primary) when text non-empty or
///   attachment staged. Disabled (muted) when empty.
/// - Attachment button opens [_showAttachmentPicker] bottom sheet with
///   Photo / Document / Annotated Photo options.
/// - Typing indicator emission: text changes → debounce 500ms →
///   [ChatWsClient.sendTyping].
/// - Staged attachment preview shown above the input bar as a removable chip.
/// - @mention autocomplete overlay shown when "@" is typed (stub — full
///   implementation requires thread member list from backend).
class ChatInputBar extends StatefulWidget {
  const ChatInputBar({
    required this.threadName,
    required this.threadId,
    this.wsClient,
    this.onSend,
    super.key,
  });

  /// Display name for the input placeholder ("Message {threadName}...").
  final String threadName;

  /// Thread ID used for offline queue operations.
  final String threadId;

  /// Active WebSocket client for sending messages and typing events.
  final ChatWsClient? wsClient;

  /// Optional callback when a message is sent (text, attachmentPath, type).
  final void Function(String text, String? attachmentPath, String? attachmentType)? onSend;

  @override
  State<ChatInputBar> createState() => _ChatInputBarState();
}

class _ChatInputBarState extends State<ChatInputBar> {
  final TextEditingController _controller = TextEditingController();
  final FocusNode _focusNode = FocusNode();

  Timer? _typingDebounce;

  // Staged attachment state
  String? _stagedAttachmentPath;
  String? _stagedAttachmentType; // 'photo', 'pdf', 'annotated_photo'
  String? _stagedAttachmentName;

  // @mention autocomplete overlay state
  bool _showMentionOverlay = false;
  String _mentionQuery = '';

  @override
  void initState() {
    super.initState();
    _controller.addListener(_onTextChanged);
  }

  @override
  void dispose() {
    _controller.removeListener(_onTextChanged);
    _controller.dispose();
    _focusNode.dispose();
    _typingDebounce?.cancel();
    super.dispose();
  }

  void _onTextChanged() {
    setState(() {}); // Rebuild to update send button state

    // Debounce typing indicator
    _typingDebounce?.cancel();
    if (_controller.text.isNotEmpty) {
      _typingDebounce = Timer(const Duration(milliseconds: 500), () {
        widget.wsClient?.sendTyping();
      });
    }

    // Check for @mention trigger
    final text = _controller.text;
    final selection = _controller.selection;
    if (selection.isValid && selection.baseOffset > 0) {
      final textBeforeCursor = text.substring(0, selection.baseOffset);
      final atIndex = textBeforeCursor.lastIndexOf('@');
      if (atIndex >= 0) {
        final query = textBeforeCursor.substring(atIndex + 1);
        if (!query.contains(' ')) {
          setState(() {
            _showMentionOverlay = true;
            _mentionQuery = query;
          });
          return;
        }
      }
    }
    setState(() {
      _showMentionOverlay = false;
      _mentionQuery = '';
    });
  }

  bool get _canSend {
    return _controller.text.trim().isNotEmpty ||
        _stagedAttachmentPath != null;
  }

  void _sendMessage() {
    if (!_canSend) return;

    final text = _controller.text.trim();

    // Notify parent
    widget.onSend?.call(text, _stagedAttachmentPath, _stagedAttachmentType);

    // Send via WebSocket if connected
    if (widget.wsClient != null) {
      widget.wsClient!.send({
        'type': 'message',
        'content': text,
        'attachment_path': _stagedAttachmentPath,
        'attachment_type': _stagedAttachmentType,
      });
    }

    // Clear state
    _controller.clear();
    setState(() {
      _stagedAttachmentPath = null;
      _stagedAttachmentType = null;
      _stagedAttachmentName = null;
      _showMentionOverlay = false;
    });
  }

  void _showAttachmentPicker() {
    showModalBottomSheet<void>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Semantics(
              label: 'Add attachment',
              child: ListTile(
                leading: const Icon(Icons.photo_library),
                title: const Text('Photo'),
                onTap: () {
                  Navigator.of(ctx).pop();
                  _pickPhoto();
                },
              ),
            ),
            ListTile(
              leading: const Icon(Icons.picture_as_pdf),
              title: const Text('Document'),
              onTap: () {
                Navigator.of(ctx).pop();
                _pickDocument();
              },
            ),
            ListTile(
              leading: const Icon(Icons.draw),
              title: const Text('Annotated Photo'),
              onTap: () {
                Navigator.of(ctx).pop();
                _pickAnnotatedPhoto();
              },
            ),
          ],
        ),
      ),
    );
  }

  void _pickPhoto() {
    // ImagePicker integration — stub for now.
    // Full implementation: image_picker.pickImage(ImageSource.gallery)
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Photo picker — coming soon')),
    );
  }

  void _pickDocument() {
    // FilePicker integration — stub for now.
    // Full implementation: FilePicker.platform.pickFiles(type: FileType.custom, allowedExtensions: ['pdf'])
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Document picker — coming soon')),
    );
  }

  void _pickAnnotatedPhoto() {
    // Navigate to task photo picker showing only annotated photos.
    // Full implementation requires task attachment query from Drift.
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Annotated photo picker — coming soon')),
    );
  }

  void _clearAttachment() {
    setState(() {
      _stagedAttachmentPath = null;
      _stagedAttachmentType = null;
      _stagedAttachmentName = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Container(
      decoration: BoxDecoration(
        color: colorScheme.surface,
        border: Border(
          top: BorderSide(
            color: colorScheme.outline.withValues(alpha: 0.2),
          ),
        ),
      ),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Staged attachment preview
            if (_stagedAttachmentPath != null)
              _AttachmentPreview(
                path: _stagedAttachmentPath!,
                name: _stagedAttachmentName ?? 'Attachment',
                type: _stagedAttachmentType ?? 'photo',
                onRemove: _clearAttachment,
              ),

            // @mention autocomplete overlay (above input)
            if (_showMentionOverlay)
              _MentionAutocomplete(
                query: _mentionQuery,
                onSelect: (name, userId) {
                  // Insert mention into text field
                  final text = _controller.text;
                  final pos = _controller.selection.baseOffset;
                  final atIndex = text.substring(0, pos).lastIndexOf('@');
                  if (atIndex >= 0) {
                    final newText =
                        '${text.substring(0, atIndex)}@$name ${text.substring(pos)}';
                    _controller.value = TextEditingValue(
                      text: newText,
                      selection: TextSelection.collapsed(
                        offset: atIndex + name.length + 2,
                      ),
                    );
                  }
                  setState(() {
                    _showMentionOverlay = false;
                  });
                },
              ),

            // Input row
            Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: 16,
                vertical: 8,
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  // Attachment button (48px touch target)
                  Semantics(
                    label: 'Add attachment',
                    button: true,
                    child: SizedBox(
                      width: 48,
                      height: 48,
                      child: IconButton(
                        icon: const Icon(Icons.attach_file),
                        onPressed: _showAttachmentPicker,
                        tooltip: 'Add attachment',
                        padding: EdgeInsets.zero,
                      ),
                    ),
                  ),
                  const SizedBox(width: 4),

                  // Text field (Expanded, min 48px, max 5 lines)
                  Expanded(
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(minHeight: 48),
                      child: TextField(
                        controller: _controller,
                        focusNode: _focusNode,
                        minLines: 1,
                        maxLines: 5,
                        textInputAction: TextInputAction.newline,
                        keyboardType: TextInputType.multiline,
                        decoration: InputDecoration(
                          hintText: 'Message ${widget.threadName}...',
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(24),
                            borderSide: BorderSide.none,
                          ),
                          filled: true,
                          fillColor:
                              colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 12,
                          ),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 4),

                  // Send button (48px touch target)
                  Semantics(
                    label: 'Send message',
                    button: true,
                    enabled: _canSend,
                    child: SizedBox(
                      width: 48,
                      height: 48,
                      child: IconButton(
                        icon: Icon(
                          Icons.send,
                          color: _canSend
                              ? colorScheme.primary
                              : colorScheme.onSurface.withValues(alpha: 0.3),
                        ),
                        onPressed: _canSend ? _sendMessage : null,
                        tooltip: 'Send message',
                        padding: EdgeInsets.zero,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Staged attachment preview
// ---------------------------------------------------------------------------

class _AttachmentPreview extends StatelessWidget {
  const _AttachmentPreview({
    required this.path,
    required this.name,
    required this.type,
    required this.onRemove,
  });

  final String path;
  final String name;
  final String type;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Container(
      height: 60,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Row(
        children: [
          if (type == 'photo' || type == 'annotated_photo')
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: File(path).existsSync()
                  ? Image.file(
                      File(path),
                      width: 44,
                      height: 44,
                      fit: BoxFit.cover,
                    )
                  : Container(
                      width: 44,
                      height: 44,
                      color: colorScheme.surfaceContainerHighest,
                      child: const Icon(Icons.image, size: 24),
                    ),
            )
          else
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: colorScheme.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(4),
              ),
              child: const Icon(Icons.picture_as_pdf, size: 24),
            ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              name,
              style: Theme.of(context).textTheme.bodySmall,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          IconButton(
            icon: const Icon(Icons.close, size: 18),
            onPressed: onRemove,
            tooltip: 'Remove attachment',
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// @mention autocomplete overlay (stub — member list wired in later plan)
// ---------------------------------------------------------------------------

class _MentionAutocomplete extends StatelessWidget {
  const _MentionAutocomplete({
    required this.query,
    required this.onSelect,
  });

  final String query;
  final void Function(String name, String userId) onSelect;

  @override
  Widget build(BuildContext context) {
    // Placeholder members — real data comes from thread member list provider.
    final members = [
      ('Alex Johnson', 'user-1'),
      ('Sam Rivera', 'user-2'),
      ('Jordan Lee', 'user-3'),
    ]
        .where((m) =>
            query.isEmpty ||
            m.$1.toLowerCase().contains(query.toLowerCase()))
        .toList();

    if (members.isEmpty) return const SizedBox.shrink();

    final colorScheme = Theme.of(context).colorScheme;

    return Container(
      constraints: const BoxConstraints(maxHeight: 160),
      decoration: BoxDecoration(
        color: colorScheme.surface,
        border: Border(
          bottom: BorderSide(
            color: colorScheme.outline.withValues(alpha: 0.2),
          ),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.08),
            blurRadius: 4,
            offset: const Offset(0, -2),
          ),
        ],
      ),
      child: ListView.builder(
        shrinkWrap: true,
        padding: EdgeInsets.zero,
        itemCount: members.length,
        itemBuilder: (ctx, i) {
          final (name, userId) = members[i];
          return ListTile(
            dense: true,
            title: Text(
              '@$name',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            onTap: () => onSelect(name, userId),
          );
        },
      ),
    );
  }
}
