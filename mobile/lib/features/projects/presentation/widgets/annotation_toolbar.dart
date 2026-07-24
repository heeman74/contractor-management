import 'package:flutter/material.dart';

import '../../domain/annotation_schema.dart';

/// Bottom toolbar for the photo annotation screen: tool selector, color
/// swatches, undo, and clear-all.
class AnnotationToolbar extends StatelessWidget {
  const AnnotationToolbar({
    required this.activeTool,
    required this.activeColor,
    required this.colorPresets,
    required this.isDrawMode,
    required this.onToolSelected,
    required this.onColorSelected,
    required this.onUndo,
    required this.onClearAll,
    super.key,
  });

  final AnnotationTool activeTool;
  final Color activeColor;
  final List<(Color, String)> colorPresets;
  final bool isDrawMode;
  final ValueChanged<AnnotationTool> onToolSelected;
  final ValueChanged<Color> onColorSelected;
  final VoidCallback onUndo;
  final VoidCallback onClearAll;

  static const _tools = <(IconData, String, AnnotationTool)>[
    (Icons.arrow_forward, 'Arrow', AnnotationTool.arrow),
    (Icons.circle_outlined, 'Circle', AnnotationTool.circle),
    (Icons.text_fields, 'Text', AnnotationTool.text),
    (Icons.straighten, 'Measure', AnnotationTool.measurement),
  ];

  @override
  Widget build(BuildContext context) {
    return Container(
      color: Colors.black.withValues(alpha: 0.75),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: [
            ..._buildToolButtons(),
            const SizedBox(width: 12),
            ..._buildColorSwatches(),
            const SizedBox(width: 12),
            IconButton(
              icon: const Icon(Icons.undo, color: Colors.white),
              tooltip: 'Undo',
              onPressed: onUndo,
            ),
            IconButton(
              icon: const Icon(Icons.delete_outline, color: Colors.white70),
              tooltip: 'Clear all',
              onPressed: onClearAll,
            ),
          ],
        ),
      ),
    );
  }

  List<Widget> _buildToolButtons() {
    final buttons = <Widget>[];
    for (final (icon, label, tool) in _tools) {
      if (buttons.isNotEmpty) buttons.add(const SizedBox(width: 4));
      buttons.add(_ToolButton(
        icon: icon,
        label: label,
        tool: tool,
        activeTool: activeTool,
        onTap: onToolSelected,
      ));
    }
    return buttons;
  }

  List<Widget> _buildColorSwatches() {
    return colorPresets.map((preset) {
      final isSelected = preset.$1.toARGB32() == activeColor.toARGB32();
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 3),
        child: GestureDetector(
          onTap: () => onColorSelected(preset.$1),
          child: Container(
            width: 28,
            height: 28,
            decoration: BoxDecoration(
              color: preset.$1,
              shape: BoxShape.circle,
              border: Border.all(
                color: isSelected ? Colors.white : Colors.white30,
                width: isSelected ? 3 : 1,
              ),
            ),
          ),
        ),
      );
    }).toList();
  }
}

class _ToolButton extends StatelessWidget {
  const _ToolButton({
    required this.icon,
    required this.label,
    required this.tool,
    required this.activeTool,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final AnnotationTool tool;
  final AnnotationTool activeTool;
  final ValueChanged<AnnotationTool> onTap;

  @override
  Widget build(BuildContext context) {
    final isActive = tool == activeTool;
    return Tooltip(
      message: label,
      child: InkWell(
        onTap: () => onTap(tool),
        borderRadius: BorderRadius.circular(8),
        child: Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: isActive
                ? Theme.of(context).colorScheme.primary.withValues(alpha: 0.85)
                : Colors.white.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(icon, color: Colors.white, size: 22),
        ),
      ),
    );
  }
}
