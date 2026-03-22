import 'package:flutter/material.dart';

import '../../../../core/database/app_database.dart'
    show TradeScope, ProjectTask, TaskDependency;
import 'dependency_arrow_painter.dart';
import 'gantt_painter.dart';

/// Interactive Gantt chart widget with pinch-to-zoom, pan, and
/// long-press drag-to-connect for creating task dependencies.
///
/// Uses two stacked [CustomPaint] layers:
/// 1. [GanttPainter] — swim lanes, task bars, today line
/// 2. [DependencyArrowPainter] — bezier arrows between connected bars
///
/// Zoom: [InteractiveViewer] controls scale (0.5x to 3.0x).
/// Drag-to-connect: long-press on the right edge of a task bar (rightmost 44px)
/// to begin drawing a ghost arrow. Release on another task bar to create a
/// dependency edge.
class GanttChartWidget extends StatefulWidget {
  final List<TradeScope> scopes;
  final Map<String, List<ProjectTask>> tasksByScope;
  final List<TaskDependency> dependencies;
  final Set<String> conflictTaskIds;
  final void Function(String predecessorId, String successorId)?
      onDependencyCreated;
  final void Function(String taskId)? onTaskTapped;

  const GanttChartWidget({
    super.key,
    required this.scopes,
    required this.tasksByScope,
    required this.dependencies,
    this.conflictTaskIds = const {},
    this.onDependencyCreated,
    this.onTaskTapped,
  });

  @override
  State<GanttChartWidget> createState() => _GanttChartWidgetState();
}

class _GanttChartWidgetState extends State<GanttChartWidget> {
  static const double _baseDayWidth = 28.0;
  static const double _laneHeight = 48.0;
  static const double _headerWidth = GanttPainter.headerWidth;
  static const double _timeAxisHeight = GanttPainter.timeAxisHeight;

  /// Task bar rects populated by GanttPainter during paint.
  /// Used for hit testing taps and arrow endpoint positioning.
  final Map<String, Rect> _taskBarRects = {};

  /// The task ID that the user started a drag-to-connect from.
  String? _dragSourceTaskId;

  /// Ghost arrow start position (right edge of source task bar).
  Offset? _dragStartOffset;

  /// Current drag cursor position for ghost arrow.
  Offset? _dragPosition;

  /// The earliest date visible on the chart (left edge of time axis).
  late DateTime _chartStartDate;

  @override
  void initState() {
    super.initState();
    _chartStartDate = _computeChartStartDate();
  }

  @override
  void didUpdateWidget(GanttChartWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.tasksByScope != widget.tasksByScope ||
        oldWidget.scopes != widget.scopes) {
      _chartStartDate = _computeChartStartDate();
    }
  }

  /// Find the earliest start date in all tasks, defaulting to 7 days ago.
  DateTime _computeChartStartDate() {
    DateTime earliest = DateTime.now().subtract(const Duration(days: 7));
    for (final tasks in widget.tasksByScope.values) {
      for (final task in tasks) {
        final d = task.startDate ?? task.dueDate;
        if (d != null && d.isBefore(earliest)) {
          earliest = d;
        }
      }
    }
    // Start 3 days before the earliest task for visual breathing room
    return earliest.subtract(const Duration(days: 3));
  }

  /// Compute canvas width to fit all tasks with padding.
  double _computeCanvasWidth() {
    // Find latest due date
    DateTime latest = DateTime.now().add(const Duration(days: 30));
    for (final tasks in widget.tasksByScope.values) {
      for (final task in tasks) {
        final d = task.dueDate;
        if (d != null && d.isAfter(latest)) {
          latest = d;
        }
      }
    }
    final totalDays = latest.difference(_chartStartDate).inDays + 14;
    return _headerWidth + totalDays * _baseDayWidth;
  }

  double get _canvasHeight =>
      widget.scopes.length * _laneHeight + _timeAxisHeight;

  /// Check whether [point] is on the right-edge handle (last 44px) of a task bar.
  String? _taskAtRightEdge(Offset point) {
    const handleWidth = 44.0;
    for (final entry in _taskBarRects.entries) {
      final rect = entry.value;
      if (rect.contains(point) && point.dx >= rect.right - handleWidth) {
        return entry.key;
      }
    }
    return null;
  }

  /// Find which task bar contains [point].
  String? _taskAtPoint(Offset point) {
    for (final entry in _taskBarRects.entries) {
      if (entry.value.contains(point)) return entry.key;
    }
    return null;
  }

  void _handleTap(TapUpDetails details) {
    final taskId = _taskAtPoint(details.localPosition);
    if (taskId != null) {
      widget.onTaskTapped?.call(taskId);
    }
  }

  void _handleLongPressStart(LongPressStartDetails details) {
    final taskId = _taskAtRightEdge(details.localPosition);
    if (taskId != null) {
      final rect = _taskBarRects[taskId]!;
      setState(() {
        _dragSourceTaskId = taskId;
        _dragStartOffset = Offset(rect.right, rect.center.dy);
        _dragPosition = details.localPosition;
      });
    }
  }

  void _handleLongPressMove(LongPressMoveUpdateDetails details) {
    if (_dragSourceTaskId != null) {
      setState(() {
        _dragPosition = details.localPosition;
      });
    }
  }

  void _handleLongPressEnd(LongPressEndDetails details) {
    if (_dragSourceTaskId != null) {
      final targetId = _taskAtPoint(details.localPosition);
      if (targetId != null && targetId != _dragSourceTaskId) {
        widget.onDependencyCreated?.call(_dragSourceTaskId!, targetId);
      }
    }
    setState(() {
      _dragSourceTaskId = null;
      _dragStartOffset = null;
      _dragPosition = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    final canvasWidth = _computeCanvasWidth();
    final canvasHeight = _canvasHeight;

    return InteractiveViewer(
      minScale: 0.5,
      maxScale: 3.0,
      constrained: false,
      child: GestureDetector(
        onTapUp: _handleTap,
        onLongPressStart: _handleLongPressStart,
        onLongPressMoveUpdate: _handleLongPressMove,
        onLongPressEnd: _handleLongPressEnd,
        child: SizedBox(
          width: canvasWidth,
          height: canvasHeight,
          child: RepaintBoundary(
            child: Stack(
              children: [
                CustomPaint(
                  painter: GanttPainter(
                    scopes: widget.scopes,
                    tasksByScope: widget.tasksByScope,
                    startDate: _chartStartDate,
                    dayWidth: _baseDayWidth,
                    laneHeight: _laneHeight,
                    conflictTaskIds: widget.conflictTaskIds,
                    taskBarRectsOut: _taskBarRects,
                  ),
                  size: Size(canvasWidth, canvasHeight),
                ),
                CustomPaint(
                  painter: DependencyArrowPainter(
                    dependencies: widget.dependencies,
                    taskBarRects: _taskBarRects,
                    cycleInvolvedIds: const {},
                    dragStart: _dragStartOffset,
                    dragEnd: _dragPosition,
                  ),
                  size: Size(canvasWidth, canvasHeight),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
