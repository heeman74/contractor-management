import 'package:flutter/material.dart';

import '../../domain/drawing_models.dart';

/// Right-side toolbar panel for the landscape drawing pad.
class DrawingToolbar extends StatelessWidget {
  const DrawingToolbar({
    required this.activeTool,
    required this.selectedColor,
    required this.selectedThickness,
    required this.showGrid,
    required this.textFontSize,
    required this.colors,
    required this.thicknessOptions,
    required this.thicknessLabels,
    required this.onToolSelected,
    required this.onColorSelected,
    required this.onThicknessSelected,
    required this.onGridToggled,
    required this.onFontSizeChanged,
    required this.onUndo,
    required this.onRedo,
    super.key,
  });

  final DrawingTool activeTool;
  final Color selectedColor;
  final double selectedThickness;
  final bool showGrid;
  final double textFontSize;
  final List<Color> colors;
  final List<double> thicknessOptions;
  final List<String> thicknessLabels;
  final ValueChanged<DrawingTool> onToolSelected;
  final ValueChanged<Color> onColorSelected;
  final ValueChanged<double> onThicknessSelected;
  final ValueChanged<bool> onGridToggled;
  final ValueChanged<double> onFontSizeChanged;
  final VoidCallback onUndo;
  final VoidCallback onRedo;

  static const double _panelWidth = 200;
  static const double _minFontSize = 8;
  static const double _maxFontSize = 72;

  static const _tools = <(IconData, String, DrawingTool)>[
    (Icons.edit_outlined, 'Pen', DrawingTool.pen),
    (Icons.auto_fix_normal_outlined, 'Eraser', DrawingTool.eraser),
    (Icons.text_fields, 'Text', DrawingTool.text),
    (Icons.show_chart, 'Line', DrawingTool.line),
    (Icons.crop_square, 'Rect', DrawingTool.rectangle),
    (Icons.circle_outlined, 'Circle', DrawingTool.circle),
    (Icons.arrow_forward, 'Arrow', DrawingTool.arrow),
  ];

  @override
  Widget build(BuildContext context) {
    return Container(
      width: _panelWidth,
      color: Theme.of(context).colorScheme.surfaceContainerHighest,
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _sectionLabel(context, 'Tools'),
            const SizedBox(height: 4),
            Wrap(spacing: 4, runSpacing: 4, children: _buildToolButtons()),
            const SizedBox(height: 12),
            _sectionLabel(context, 'Color'),
            const SizedBox(height: 4),
            Wrap(spacing: 4, runSpacing: 4, children: _buildColorSwatches(context)),
            const SizedBox(height: 12),
            _sectionLabel(context, 'Thickness'),
            const SizedBox(height: 4),
            Wrap(spacing: 4, runSpacing: 4, children: _buildThicknessChips()),
            const SizedBox(height: 12),
            if (activeTool == DrawingTool.text) ...[
              _sectionLabel(context, 'Font Size: ${textFontSize.round()}'),
              Slider(
                value: textFontSize,
                min: _minFontSize,
                max: _maxFontSize,
                onChanged: onFontSizeChanged,
              ),
              const SizedBox(height: 12),
            ],
            _buildGridToggle(context),
            const SizedBox(height: 12),
            _buildUndoRedo(),
          ],
        ),
      ),
    );
  }

  Widget _sectionLabel(BuildContext context, String text) =>
      Text(text, style: Theme.of(context).textTheme.labelMedium);

  List<Widget> _buildToolButtons() {
    return _tools
        .map((entry) => _ToolButton(
              icon: entry.$1,
              label: entry.$2,
              tool: entry.$3,
              activeTool: activeTool,
              onTap: onToolSelected,
            ))
        .toList();
  }

  List<Widget> _buildColorSwatches(BuildContext context) {
    return colors.map((color) {
      final isSelected = color.toARGB32() == selectedColor.toARGB32();
      return GestureDetector(
        onTap: () => onColorSelected(color),
        child: Container(
          width: 28,
          height: 28,
          decoration: BoxDecoration(
            color: color,
            shape: BoxShape.circle,
            border: Border.all(
              color: isSelected
                  ? Theme.of(context).colorScheme.primary
                  : Colors.grey.shade400,
              width: isSelected ? 3 : 1,
            ),
          ),
        ),
      );
    }).toList();
  }

  List<Widget> _buildThicknessChips() {
    return List.generate(thicknessOptions.length, (i) {
      final thickness = thicknessOptions[i];
      return ChoiceChip(
        label: Text(thicknessLabels[i]),
        selected: thickness == selectedThickness,
        onSelected: (_) => onThicknessSelected(thickness),
        visualDensity: VisualDensity.compact,
      );
    });
  }

  Widget _buildGridToggle(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        _sectionLabel(context, 'Grid'),
        IconButton(
          icon: Icon(showGrid ? Icons.grid_on : Icons.grid_off),
          tooltip: showGrid ? 'Hide Grid' : 'Show Grid',
          onPressed: () => onGridToggled(!showGrid),
        ),
      ],
    );
  }

  Widget _buildUndoRedo() {
    return Row(
      children: [
        Expanded(child: _undoRedoButton(Icons.undo, 'Undo', onUndo)),
        const SizedBox(width: 4),
        Expanded(child: _undoRedoButton(Icons.redo, 'Redo', onRedo)),
      ],
    );
  }

  Widget _undoRedoButton(IconData icon, String label, VoidCallback onPressed) {
    return OutlinedButton.icon(
      icon: Icon(icon, size: 16),
      label: Text(label),
      onPressed: onPressed,
      style: OutlinedButton.styleFrom(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        visualDensity: VisualDensity.compact,
      ),
    );
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
  final DrawingTool tool;
  final DrawingTool activeTool;
  final ValueChanged<DrawingTool> onTap;

  @override
  Widget build(BuildContext context) {
    final isActive = tool == activeTool;
    return Tooltip(
      message: label,
      child: InkWell(
        onTap: () => onTap(tool),
        borderRadius: BorderRadius.circular(6),
        child: Container(
          padding: const EdgeInsets.all(6),
          decoration: BoxDecoration(
            color: isActive
                ? Theme.of(context).colorScheme.primaryContainer
                : null,
            borderRadius: BorderRadius.circular(6),
          ),
          child: Icon(
            icon,
            size: 20,
            color: isActive
                ? Theme.of(context).colorScheme.onPrimaryContainer
                : Theme.of(context).colorScheme.onSurface,
          ),
        ),
      ),
    );
  }
}
