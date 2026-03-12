import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:uuid/uuid.dart';

/// Full-screen landscape drawing pad — accessible from the Add Note bottom sheet.
///
/// Opens in landscape orientation and restores portrait on exit.
/// Provides pen, eraser, text, line, rectangle, circle, and arrow tools.
/// 8 preset colors, 3 thickness presets, optional grid overlay, undo/redo.
///
/// On save: exports a PNG to app support directory and pops with the file path.
/// Grid overlay is NOT included in the exported PNG.
///
/// Navigation:
///   Push from anywhere:  context.pushNamed(RouteNames.drawingPad)
///   Result:              Navigator.pop(context, filePath) — String? file path
class DrawingPadScreen extends StatefulWidget {
  const DrawingPadScreen({super.key});

  @override
  State<DrawingPadScreen> createState() => _DrawingPadScreenState();
}

class _DrawingPadScreenState extends State<DrawingPadScreen> {
  // ── Drawing state ──────────────────────────────────────────────────────────
  final List<_Stroke> _strokes = [];
  final List<List<_Stroke>> _undoStack = [];
  _Stroke? _currentStroke;

  // RepaintBoundary key for PNG export (canvas only, no grid)
  final GlobalKey _canvasKey = GlobalKey();

  // ── Toolbar state ──────────────────────────────────────────────────────────
  Color _selectedColor = Colors.black;
  double _selectedThickness = 3.0;
  bool _showGrid = false;
  double _textFontSize = 16.0;

  // Preset values
  static const _colors = [
    Colors.black,
    Colors.red,
    Colors.blue,
    Colors.green,
    Colors.orange,
    Colors.purple,
    Colors.brown,
    Colors.white,
  ];

  static const _thicknessOptions = [1.0, 3.0, 6.0];
  static const _thicknessLabels = ['Thin', 'Med', 'Thick'];

  _Tool _activeTool = _Tool.pen;

  @override
  void initState() {
    super.initState();
    // Lock to landscape on open.
    SystemChrome.setPreferredOrientations([
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight,
    ]);
  }

  @override
  void dispose() {
    // CRITICAL: always restore portrait or the entire app stays in landscape.
    SystemChrome.setPreferredOrientations([
      DeviceOrientation.portraitUp,
    ]);
    super.dispose();
  }

  // ── Persistence ────────────────────────────────────────────────────────────

  Future<void> _saveDrawing() async {
    try {
      final boundary =
          _canvasKey.currentContext?.findRenderObject() as RenderRepaintBoundary?;
      if (boundary == null || _strokes.isEmpty) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Nothing to save.')),
          );
        }
        return;
      }

      final image = await boundary.toImage(pixelRatio: 2.0);
      final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
      if (byteData == null) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Failed to capture image.')),
          );
        }
        return;
      }

      final bytes = byteData.buffer.asUint8List();
      final dir = await getApplicationSupportDirectory();
      final drawingsDir = Directory('${dir.path}/drawings');
      if (!await drawingsDir.exists()) {
        await drawingsDir.create(recursive: true);
      }

      final fileName = '${const Uuid().v4()}.png';
      final file = File('${drawingsDir.path}/$fileName');
      await file.writeAsBytes(bytes);

      if (mounted) {
        Navigator.of(context).pop(file.path);
      }
    } catch (e, st) {
      debugPrint('[DrawingPadScreen._saveDrawing] Error: $e\n$st');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to save: $e')),
        );
      }
    }
  }

  // ── Close / discard guard ──────────────────────────────────────────────────

  Future<void> _handleClose() async {
    if (_strokes.isEmpty) {
      if (mounted) Navigator.of(context).pop();
      return;
    }

    final discard = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Discard drawing?'),
        content: const Text(
          'Your drawing will not be saved.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Discard'),
          ),
        ],
      ),
    );

    if ((discard ?? false) && mounted) {
      Navigator.of(context).pop();
    }
  }

  // ── Undo / Redo ────────────────────────────────────────────────────────────

  void _undo() {
    if (_strokes.isEmpty) return;
    setState(() {
      _undoStack.add(List.from(_strokes));
      _strokes.removeLast();
    });
  }

  void _redo() {
    if (_undoStack.isEmpty) return;
    setState(() {
      final previous = _undoStack.removeLast();
      _strokes.clear();
      _strokes.addAll(previous);
    });
  }

  // ── Drawing gestures ────────────────────────────────────────────────────────

  void _onPanStart(DragStartDetails details) {
    setState(() {
      _currentStroke = _Stroke(
        tool: _activeTool,
        color: _activeTool == _Tool.eraser ? Colors.white : _selectedColor,
        thickness: _selectedThickness,
        points: [details.localPosition],
      );
    });
  }

  void _onPanUpdate(DragUpdateDetails details) {
    if (_currentStroke == null) return;
    setState(() {
      _currentStroke = _Stroke(
        tool: _currentStroke!.tool,
        color: _currentStroke!.color,
        thickness: _currentStroke!.thickness,
        points: [..._currentStroke!.points, details.localPosition],
      );
    });
  }

  void _onPanEnd(DragEndDetails details) {
    if (_currentStroke == null) return;
    setState(() {
      _undoStack.clear();
      _strokes.add(_currentStroke!);
      _currentStroke = null;
    });
  }

  // ── Tool / color / thickness selection ─────────────────────────────────────

  void _selectTool(_Tool tool) {
    setState(() => _activeTool = tool);
  }

  void _selectColor(Color color) {
    setState(() => _selectedColor = color);
  }

  void _selectThickness(double thickness) {
    setState(() => _selectedThickness = thickness);
  }

  // ── Build ──────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.close),
          tooltip: 'Close',
          onPressed: _handleClose,
        ),
        title: const Text('Drawing Pad'),
        actions: [
          IconButton(
            icon: const Icon(Icons.save_outlined),
            tooltip: 'Save',
            onPressed: _saveDrawing,
          ),
        ],
      ),
      body: Row(
        children: [
          // ── Main canvas area ───────────────────────────────────────────────
          Expanded(
            child: Stack(
              children: [
                // Layer a: optional grid overlay (excluded from PNG export)
                if (_showGrid)
                  Positioned.fill(
                    child: IgnorePointer(
                      child: CustomPaint(
                        painter: _GridPainter(),
                      ),
                    ),
                  ),
                // Layer b: Drawing canvas (RepaintBoundary for PNG capture)
                Positioned.fill(
                  child: RepaintBoundary(
                    key: _canvasKey,
                    child: Container(
                      color: Colors.white,
                      child: CustomPaint(
                        painter: _DrawingPainter(
                          strokes: _strokes,
                          currentStroke: _currentStroke,
                        ),
                      ),
                    ),
                  ),
                ),
                // Layer c: Gesture detector (on top)
                Positioned.fill(
                  child: GestureDetector(
                    onPanStart: _onPanStart,
                    onPanUpdate: _onPanUpdate,
                    onPanEnd: _onPanEnd,
                  ),
                ),
              ],
            ),
          ),
          // ── Toolbar panel (right side in landscape) ────────────────────────
          _DrawingToolbar(
            activeTool: _activeTool,
            selectedColor: _selectedColor,
            selectedThickness: _selectedThickness,
            showGrid: _showGrid,
            textFontSize: _textFontSize,
            colors: _colors,
            thicknessOptions: _thicknessOptions,
            thicknessLabels: _thicknessLabels,
            onToolSelected: _selectTool,
            onColorSelected: _selectColor,
            onThicknessSelected: _selectThickness,
            onGridToggled: (value) => setState(() => _showGrid = value),
            onFontSizeChanged: (value) => setState(() => _textFontSize = value),
            onUndo: _undo,
            onRedo: _redo,
          ),
        ],
      ),
    );
  }
}

// ─── Tool enum ─────────────────────────────────────────────────────────────────

enum _Tool { pen, eraser, text, line, rectangle, circle, arrow }

// ─── Stroke model ──────────────────────────────────────────────────────────────

class _Stroke {
  final _Tool tool;
  final Color color;
  final double thickness;
  final List<Offset> points;

  const _Stroke({
    required this.tool,
    required this.color,
    required this.thickness,
    required this.points,
  });
}

// ─── Drawing painter ────────────────────────────────────────────────────────────

class _DrawingPainter extends CustomPainter {
  final List<_Stroke> strokes;
  final _Stroke? currentStroke;

  const _DrawingPainter({
    required this.strokes,
    this.currentStroke,
  });

  @override
  void paint(Canvas canvas, Size size) {
    for (final stroke in strokes) {
      _paintStroke(canvas, stroke);
    }
    if (currentStroke != null) {
      _paintStroke(canvas, currentStroke!);
    }
  }

  void _paintStroke(Canvas canvas, _Stroke stroke) {
    if (stroke.points.isEmpty) return;

    final paint = Paint()
      ..color = stroke.color
      ..strokeWidth = stroke.thickness
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..style = PaintingStyle.stroke;

    if (stroke.tool == _Tool.eraser) {
      paint.blendMode = BlendMode.src;
    }

    if (stroke.points.length == 1) {
      // Single dot
      canvas.drawCircle(stroke.points.first, stroke.thickness / 2, paint..style = PaintingStyle.fill);
      return;
    }

    switch (stroke.tool) {
      case _Tool.rectangle:
        if (stroke.points.length >= 2) {
          final rect = Rect.fromPoints(stroke.points.first, stroke.points.last);
          canvas.drawRect(rect, paint);
        }
      case _Tool.circle:
        if (stroke.points.length >= 2) {
          final rect = Rect.fromPoints(stroke.points.first, stroke.points.last);
          canvas.drawOval(rect, paint);
        }
      case _Tool.line:
      case _Tool.arrow:
        if (stroke.points.length >= 2) {
          canvas.drawLine(stroke.points.first, stroke.points.last, paint);
          if (stroke.tool == _Tool.arrow) {
            _drawArrowHead(canvas, stroke.points.first, stroke.points.last, paint);
          }
        }
      default:
        // Freehand / pen / eraser / text
        final path = Path()..moveTo(stroke.points.first.dx, stroke.points.first.dy);
        for (int i = 1; i < stroke.points.length; i++) {
          path.lineTo(stroke.points[i].dx, stroke.points[i].dy);
        }
        canvas.drawPath(path, paint);
    }
  }

  void _drawArrowHead(Canvas canvas, Offset from, Offset to, Paint paint) {
    const arrowSize = 12.0;
    final angle = (to - from).direction;
    final path = Path()
      ..moveTo(to.dx, to.dy)
      ..lineTo(
        to.dx - arrowSize * math.cos(angle - 0.5),
        to.dy - arrowSize * math.sin(angle - 0.5),
      )
      ..moveTo(to.dx, to.dy)
      ..lineTo(
        to.dx - arrowSize * math.cos(angle + 0.5),
        to.dy - arrowSize * math.sin(angle + 0.5),
      );
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(_DrawingPainter oldDelegate) => true;
}

// ─── Grid painter ──────────────────────────────────────────────────────────────

/// Paints a thin gray grid over the canvas — excluded from PNG export.
class _GridPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    const spacing = 24.0;
    final paint = Paint()
      ..color = Colors.grey.withValues(alpha: 0.3)
      ..strokeWidth = 0.5;

    for (double x = 0; x <= size.width; x += spacing) {
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), paint);
    }
    for (double y = 0; y <= size.height; y += spacing) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), paint);
    }
  }

  @override
  bool shouldRepaint(_GridPainter oldDelegate) => false;
}

// ─── Toolbar widget ────────────────────────────────────────────────────────────

/// Right-side toolbar panel for the landscape drawing pad.
class _DrawingToolbar extends StatelessWidget {
  final _Tool activeTool;
  final Color selectedColor;
  final double selectedThickness;
  final bool showGrid;
  final double textFontSize;
  final List<Color> colors;
  final List<double> thicknessOptions;
  final List<String> thicknessLabels;
  final void Function(_Tool) onToolSelected;
  final void Function(Color) onColorSelected;
  final void Function(double) onThicknessSelected;
  final void Function(bool) onGridToggled;
  final void Function(double) onFontSizeChanged;
  final VoidCallback onUndo;
  final VoidCallback onRedo;

  const _DrawingToolbar({
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
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 200,
      color: Theme.of(context).colorScheme.surfaceContainerHighest,
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── Tool selector ──────────────────────────────────────────────
            Text(
              'Tools',
              style: Theme.of(context).textTheme.labelMedium,
            ),
            const SizedBox(height: 4),
            Wrap(
              spacing: 4,
              runSpacing: 4,
              children: [
                _ToolButton(
                  icon: Icons.edit_outlined,
                  label: 'Pen',
                  tool: _Tool.pen,
                  activeTool: activeTool,
                  onTap: onToolSelected,
                ),
                _ToolButton(
                  icon: Icons.auto_fix_normal_outlined,
                  label: 'Eraser',
                  tool: _Tool.eraser,
                  activeTool: activeTool,
                  onTap: onToolSelected,
                ),
                _ToolButton(
                  icon: Icons.text_fields,
                  label: 'Text',
                  tool: _Tool.text,
                  activeTool: activeTool,
                  onTap: onToolSelected,
                ),
                _ToolButton(
                  icon: Icons.show_chart,
                  label: 'Line',
                  tool: _Tool.line,
                  activeTool: activeTool,
                  onTap: onToolSelected,
                ),
                _ToolButton(
                  icon: Icons.crop_square,
                  label: 'Rect',
                  tool: _Tool.rectangle,
                  activeTool: activeTool,
                  onTap: onToolSelected,
                ),
                _ToolButton(
                  icon: Icons.circle_outlined,
                  label: 'Circle',
                  tool: _Tool.circle,
                  activeTool: activeTool,
                  onTap: onToolSelected,
                ),
                _ToolButton(
                  icon: Icons.arrow_forward,
                  label: 'Arrow',
                  tool: _Tool.arrow,
                  activeTool: activeTool,
                  onTap: onToolSelected,
                ),
              ],
            ),
            const SizedBox(height: 12),

            // ── Color picker ───────────────────────────────────────────────
            Text(
              'Color',
              style: Theme.of(context).textTheme.labelMedium,
            ),
            const SizedBox(height: 4),
            Wrap(
              spacing: 4,
              runSpacing: 4,
              children: colors.map((color) {
                final isSelected = color.value == selectedColor.value;
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
              }).toList(),
            ),
            const SizedBox(height: 12),

            // ── Thickness selector ─────────────────────────────────────────
            Text(
              'Thickness',
              style: Theme.of(context).textTheme.labelMedium,
            ),
            const SizedBox(height: 4),
            Wrap(
              spacing: 4,
              runSpacing: 4,
              children: List.generate(thicknessOptions.length, (i) {
                final thickness = thicknessOptions[i];
                final isSelected = thickness == selectedThickness;
                return ChoiceChip(
                  label: Text(thicknessLabels[i]),
                  selected: isSelected,
                  onSelected: (_) => onThicknessSelected(thickness),
                  visualDensity: VisualDensity.compact,
                );
              }),
            ),
            const SizedBox(height: 12),

            // ── Text tool font size (shown only for Text tool) ─────────────
            if (activeTool == _Tool.text) ...[
              Text(
                'Font Size: ${textFontSize.round()}',
                style: Theme.of(context).textTheme.labelMedium,
              ),
              Slider(
                value: textFontSize,
                min: 8,
                max: 72,
                onChanged: onFontSizeChanged,
              ),
              const SizedBox(height: 12),
            ],

            // ── Grid toggle ────────────────────────────────────────────────
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Grid',
                  style: Theme.of(context).textTheme.labelMedium,
                ),
                IconButton(
                  icon: Icon(showGrid ? Icons.grid_on : Icons.grid_off),
                  tooltip: showGrid ? 'Hide Grid' : 'Show Grid',
                  onPressed: () => onGridToggled(!showGrid),
                ),
              ],
            ),
            const SizedBox(height: 12),

            // ── Undo / Redo ────────────────────────────────────────────────
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    icon: const Icon(Icons.undo, size: 16),
                    label: const Text('Undo'),
                    onPressed: onUndo,
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 4,
                      ),
                      visualDensity: VisualDensity.compact,
                    ),
                  ),
                ),
                const SizedBox(width: 4),
                Expanded(
                  child: OutlinedButton.icon(
                    icon: const Icon(Icons.redo, size: 16),
                    label: const Text('Redo'),
                    onPressed: onRedo,
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 4,
                      ),
                      visualDensity: VisualDensity.compact,
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

// ─── Tool button ───────────────────────────────────────────────────────────────

class _ToolButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final _Tool tool;
  final _Tool activeTool;
  final void Function(_Tool) onTap;

  const _ToolButton({
    required this.icon,
    required this.label,
    required this.tool,
    required this.activeTool,
    required this.onTap,
  });

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

