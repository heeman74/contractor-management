import 'dart:convert';

import 'package:uuid/uuid.dart';

/// The 4 annotation tools available for photo annotation.
///
/// - [arrow]: Directional arrow from start point to end point.
/// - [circle]: Ellipse drawn inside a bounding rectangle.
/// - [text]: Text label placed at a point.
/// - [measurement]: Ruler line with tick marks and a dimension label.
enum AnnotationTool { arrow, circle, text, measurement }

/// A single annotation on a photo.
///
/// Coordinates are **normalized to 0.0–1.0** relative to the canvas/photo
/// dimensions. This ensures annotations render correctly at any resolution on
/// both mobile (CustomPainter) and web (HTML5 Canvas).
///
/// Field usage by tool:
/// - [arrow]: [startX], [startY], [endX], [endY]
/// - [circle]: [x], [y], [width], [height] (bounding rect top-left + size)
/// - [text]: [x], [y], [label], [fontSize]
/// - [measurement]: [startX], [startY], [endX], [endY], [label]
class Annotation {
  /// Unique ID for this annotation (UUID v4).
  final String id;

  /// The drawing tool that produced this annotation.
  final AnnotationTool tool;

  /// Stroke/fill color as a CSS hex string, e.g. "#FF0000".
  final String color;

  /// Stroke width in logical pixels.
  final double thickness;

  // ── Arrow / Measurement fields (normalized 0-1) ──────────────────────────

  /// Start X coordinate (normalized 0–1). Used by [arrow] and [measurement].
  final double? startX;

  /// Start Y coordinate (normalized 0–1). Used by [arrow] and [measurement].
  final double? startY;

  /// End X coordinate (normalized 0–1). Used by [arrow] and [measurement].
  final double? endX;

  /// End Y coordinate (normalized 0–1). Used by [arrow] and [measurement].
  final double? endY;

  // ── Circle fields (normalized 0-1) ───────────────────────────────────────

  /// Bounding rect top-left X (normalized 0–1). Used by [circle] and [text].
  final double? x;

  /// Bounding rect top-left Y (normalized 0–1). Used by [circle] and [text].
  final double? y;

  /// Bounding rect width (normalized 0–1). Used by [circle].
  final double? width;

  /// Bounding rect height (normalized 0–1). Used by [circle].
  final double? height;

  // ── Text / Measurement label fields ──────────────────────────────────────

  /// Text content for [text] tool, or measurement value for [measurement] tool
  /// (e.g., "24 inches").
  final String? label;

  /// Font size in logical pixels. Used by [text] tool. Defaults to 16.
  final double? fontSize;

  Annotation({
    String? id,
    required this.tool,
    required this.color,
    required this.thickness,
    this.startX,
    this.startY,
    this.endX,
    this.endY,
    this.x,
    this.y,
    this.width,
    this.height,
    this.label,
    this.fontSize,
  }) : id = id ?? const Uuid().v4();

  /// Serialize to a JSON-compatible map.
  ///
  /// Only non-null optional fields are included — compact JSON on the wire.
  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'tool': tool.name,
      'color': color,
      'thickness': thickness,
      if (startX != null) 'startX': startX,
      if (startY != null) 'startY': startY,
      if (endX != null) 'endX': endX,
      if (endY != null) 'endY': endY,
      if (x != null) 'x': x,
      if (y != null) 'y': y,
      if (width != null) 'width': width,
      if (height != null) 'height': height,
      if (label != null) 'label': label,
      if (fontSize != null) 'fontSize': fontSize,
    };
  }

  /// Deserialize from a JSON map.
  ///
  /// Returns `null` if the [tool] field is missing or contains an unknown value.
  /// Callers should filter out null entries when building an [AnnotationLayer].
  factory Annotation.fromJson(Map<String, dynamic> json) {
    final toolString = json['tool'] as String?;
    if (toolString == null) {
      throw const FormatException('Annotation.fromJson: missing tool field');
    }

    // Map tool name to enum — unknown names throw, caller catches and skips.
    final tool = AnnotationTool.values.firstWhere(
      (t) => t.name == toolString,
      orElse: () => throw FormatException(
        'Annotation.fromJson: unknown tool "$toolString"',
      ),
    );

    return Annotation(
      id: json['id'] as String? ?? const Uuid().v4(),
      tool: tool,
      color: json['color'] as String? ?? '#000000',
      thickness: (json['thickness'] as num?)?.toDouble() ?? 2.0,
      startX: (json['startX'] as num?)?.toDouble(),
      startY: (json['startY'] as num?)?.toDouble(),
      endX: (json['endX'] as num?)?.toDouble(),
      endY: (json['endY'] as num?)?.toDouble(),
      x: (json['x'] as num?)?.toDouble(),
      y: (json['y'] as num?)?.toDouble(),
      width: (json['width'] as num?)?.toDouble(),
      height: (json['height'] as num?)?.toDouble(),
      label: json['label'] as String?,
      fontSize: (json['fontSize'] as num?)?.toDouble(),
    );
  }
}

/// The complete annotation overlay for a photo.
///
/// Stores all [annotations] in a flat list with the original photo dimensions
/// ([canvasWidth], [canvasHeight]) for coordinate denormalization.
///
/// **Non-destructive**: the base photo is never modified. The annotation layer
/// is a separate JSON string stored in [TaskAttachment.annotationData].
///
/// JSON schema:
/// ```json
/// {
///   "version": 1,
///   "canvasWidth": 1920.0,
///   "canvasHeight": 1080.0,
///   "annotations": [...]
/// }
/// ```
class AnnotationLayer {
  /// Schema version — currently always 1.
  final int version;

  /// Original photo width in logical pixels (used for denormalization).
  final double canvasWidth;

  /// Original photo height in logical pixels (used for denormalization).
  final double canvasHeight;

  /// Ordered list of annotations to render on top of the photo.
  final List<Annotation> annotations;

  AnnotationLayer({
    this.version = 1,
    required this.canvasWidth,
    required this.canvasHeight,
    required this.annotations,
  });

  /// Serialize the layer to a JSON-compatible map.
  Map<String, dynamic> toJson() {
    return {
      'version': version,
      'canvasWidth': canvasWidth,
      'canvasHeight': canvasHeight,
      'annotations': annotations.map((a) => a.toJson()).toList(),
    };
  }

  /// Encode the layer to a JSON string for storage in [TaskAttachment.annotationData].
  String toJsonString() => jsonEncode(toJson());

  /// Deserialize from a JSON map.
  ///
  /// Unknown annotation tools are silently skipped — forward-compatible
  /// deserialization so future tool types don't break old clients.
  factory AnnotationLayer.fromJson(Map<String, dynamic> json) {
    final rawAnnotations = json['annotations'] as List<dynamic>? ?? [];

    final annotations = <Annotation>[];
    for (final item in rawAnnotations) {
      if (item is! Map<String, dynamic>) continue;
      try {
        annotations.add(Annotation.fromJson(item));
      } on FormatException {
        // Skip unknown tool types — forward compatibility.
        continue;
      }
    }

    return AnnotationLayer(
      version: (json['version'] as num?)?.toInt() ?? 1,
      canvasWidth: (json['canvasWidth'] as num?)?.toDouble() ?? 0.0,
      canvasHeight: (json['canvasHeight'] as num?)?.toDouble() ?? 0.0,
      annotations: annotations,
    );
  }

  /// Decode an annotation layer from a JSON string.
  factory AnnotationLayer.fromJsonString(String s) =>
      AnnotationLayer.fromJson(jsonDecode(s) as Map<String, dynamic>);
}
