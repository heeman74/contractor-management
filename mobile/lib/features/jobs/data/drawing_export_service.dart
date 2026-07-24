import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/rendering.dart';
import 'package:path_provider/path_provider.dart';
import 'package:uuid/uuid.dart';

/// Raised when a drawing cannot be exported to a PNG file.
class DrawingExportException implements Exception {
  const DrawingExportException(this.message);
  final String message;

  @override
  String toString() => 'DrawingExportException: $message';
}

/// Captures a [RepaintBoundary] as a PNG and persists it to app storage.
///
/// Extracted from the drawing pad screen so the widget contains no file IO or
/// image-encoding logic.
class DrawingExportService {
  DrawingExportService({Uuid uuid = const Uuid()}) : _uuid = uuid;

  static const double _exportPixelRatio = 2.0;
  static const String _drawingsSubdir = 'drawings';

  final Uuid _uuid;

  /// Renders [boundary] to a PNG under the app support directory and returns
  /// the saved file path. Throws [DrawingExportException] on failure.
  Future<String> exportToPng(RenderRepaintBoundary boundary) async {
    final image = await boundary.toImage(pixelRatio: _exportPixelRatio);
    final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
    if (byteData == null) {
      throw const DrawingExportException('Failed to capture image.');
    }

    final bytes = byteData.buffer.asUint8List();
    final directory = await _ensureDrawingsDirectory();
    final file = File('${directory.path}/${_uuid.v4()}.png');
    await file.writeAsBytes(bytes);
    return file.path;
  }

  Future<Directory> _ensureDrawingsDirectory() async {
    final supportDir = await getApplicationSupportDirectory();
    final drawingsDir = Directory('${supportDir.path}/$_drawingsSubdir');
    if (!drawingsDir.existsSync()) {
      await drawingsDir.create(recursive: true);
    }
    return drawingsDir;
  }
}
