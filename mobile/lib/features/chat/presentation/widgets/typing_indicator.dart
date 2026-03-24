import 'package:flutter/material.dart';

/// Animated typing indicator — shown when another thread participant is typing.
///
/// Displays three animated dots with staggered opacity cycling, plus a
/// "{firstName} is typing..." label.
///
/// Shown at the bottom of the message list (index 0 in reversed ListView)
/// when [typingUserName] is non-null. Auto-hidden by the parent
/// ([ChatThreadScreen]) via a 3-second Timer after the last 'typing' event.
///
/// Semantics: announces to screen reader as a live region.
class TypingIndicator extends StatefulWidget {
  const TypingIndicator({this.typingUserName, super.key});

  /// First name of the typing user, or null to hide.
  final String? typingUserName;

  @override
  State<TypingIndicator> createState() => _TypingIndicatorState();
}

class _TypingIndicatorState extends State<TypingIndicator>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    )..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final userName = widget.typingUserName;
    if (userName == null) return const SizedBox.shrink();

    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return Semantics(
      label: '$userName is typing',
      liveRegion: true,
      child: Padding(
        padding: const EdgeInsets.only(left: 16, right: 16, bottom: 8),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Animated three-dot indicator
            AnimatedBuilder(
              animation: _controller,
              builder: (context, _) {
                return Row(
                  mainAxisSize: MainAxisSize.min,
                  children: List.generate(3, (i) {
                    // Stagger: dot i peaks at i/3 through the cycle
                    final phase = (i / 3.0);
                    final value = _controller.value;
                    // Map to a 0→1→0 pulse shifted by phase
                    final shifted = (value - phase + 1.0) % 1.0;
                    final opacity = (shifted < 0.5
                            ? shifted / 0.5
                            : (1.0 - shifted) / 0.5)
                        .clamp(0.3, 1.0);

                    return Padding(
                      padding: EdgeInsets.only(right: i < 2 ? 4 : 0),
                      child: Opacity(
                        opacity: opacity,
                        child: Container(
                          width: 6,
                          height: 6,
                          decoration: BoxDecoration(
                            color: colorScheme.onSurface
                                .withValues(alpha: 0.6),
                            shape: BoxShape.circle,
                          ),
                        ),
                      ),
                    );
                  }),
                );
              },
            ),
            const SizedBox(width: 8),
            Text(
              '$userName is typing...',
              style: textTheme.bodySmall?.copyWith(
                color: colorScheme.onSurface.withValues(alpha: 0.5),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
