import 'package:flutter/material.dart';

/// Chat input bar with offline detection and accessibility semantics.
///
/// Features:
/// - Multi-line expandable TextField (1-4 lines)
/// - Send button: disabled when empty, streaming, or offline
/// - Attach button for image attachment
/// - Offline banner: "AI features require an internet connection." above input
/// - Minimum 48px touch targets on all interactive elements (Material spec)
class ChatInputBar extends StatefulWidget {
  const ChatInputBar({
    required this.onSend,
    this.isStreaming = false,
    this.isOffline = false,
    this.placeholder = 'Type your message...',
    this.onAttach,
    super.key,
  });

  /// Called when the user taps Send or submits the text field.
  final Function(String) onSend;

  /// True while the AI is streaming a response — disables sending.
  final bool isStreaming;

  /// True when no internet connection is detected — shows banner, disables input.
  final bool isOffline;

  /// Placeholder text for the input field.
  final String placeholder;

  /// Called when the user taps the attach button. Null hides the button.
  final Function()? onAttach;

  @override
  State<ChatInputBar> createState() => _ChatInputBarState();
}

class _ChatInputBarState extends State<ChatInputBar> {
  final TextEditingController _controller = TextEditingController();
  bool _hasText = false;

  @override
  void initState() {
    super.initState();
    _controller.addListener(_onTextChanged);
  }

  @override
  void dispose() {
    _controller.removeListener(_onTextChanged);
    _controller.dispose();
    super.dispose();
  }

  void _onTextChanged() {
    final hasText = _controller.text.trim().isNotEmpty;
    if (hasText != _hasText) {
      setState(() => _hasText = hasText);
    }
  }

  void _handleSend() {
    final text = _controller.text.trim();
    if (text.isEmpty || widget.isStreaming || widget.isOffline) return;
    _controller.clear();
    widget.onSend(text);
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // Offline banner
        if (widget.isOffline)
          Semantics(
            liveRegion: true,
            child: Container(
              width: double.infinity,
              color: colorScheme.errorContainer,
              padding:
                  const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Row(
                children: [
                  Icon(
                    Icons.wifi_off,
                    size: 16,
                    color: colorScheme.onErrorContainer,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'AI features require an internet connection.',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: colorScheme.onErrorContainer,
                          ),
                    ),
                  ),
                ],
              ),
            ),
          ),

        // Input row
        Container(
          decoration: BoxDecoration(
            border: Border(
              top: BorderSide(
                color: colorScheme.outlineVariant,
              ),
            ),
          ),
          padding: const EdgeInsets.all(8),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              // Attach button
              if (widget.onAttach != null)
                SizedBox(
                  width: 48,
                  height: 48,
                  child: Semantics(
                    label: 'Attach image',
                    button: true,
                    child: IconButton(
                      onPressed: widget.isOffline ? null : widget.onAttach,
                      icon: const Icon(Icons.attach_file),
                      tooltip: 'Attach image',
                    ),
                  ),
                ),

              // Text input
              Expanded(
                child: TextField(
                  controller: _controller,
                  maxLines: 4,
                  minLines: 1,
                  enabled: !widget.isOffline,
                  textInputAction: TextInputAction.newline,
                  onSubmitted: (value) {
                    // Mobile: newline is fine; submission handled by send button
                  },
                  decoration: InputDecoration(
                    hintText: widget.isOffline
                        ? 'Connect to internet to use AI chat'
                        : widget.placeholder,
                    hintStyle: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: colorScheme.onSurfaceVariant,
                        ),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(24),
                      borderSide: BorderSide(color: colorScheme.outline),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(24),
                      borderSide: BorderSide(color: colorScheme.outline),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(24),
                      borderSide: BorderSide(
                        color: colorScheme.primary,
                        width: 2,
                      ),
                    ),
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 10,
                    ),
                    isDense: true,
                  ),
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
              ),

              const SizedBox(width: 4),

              // Send button
              SizedBox(
                width: 48,
                height: 48,
                child: Semantics(
                  label: 'Send message',
                  button: true,
                  child: IconButton(
                    onPressed: (_hasText && !widget.isStreaming && !widget.isOffline)
                        ? _handleSend
                        : null,
                    icon: Icon(
                      widget.isStreaming
                          ? Icons.hourglass_empty
                          : Icons.send,
                    ),
                    tooltip: 'Send message',
                    style: IconButton.styleFrom(
                      foregroundColor: colorScheme.primary,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
