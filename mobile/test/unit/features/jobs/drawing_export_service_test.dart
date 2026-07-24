/// Unit tests for the drawing-pad refactor extractions.
///
/// [DrawingStroke.addPoint] is covered here. The PNG capture in
/// [DrawingExportService.exportToPng] is not unit-tested: RepaintBoundary
/// .toImage requires a real rendering surface and hangs under `flutter test`.
/// Its screen-level behaviour (empty canvas → "Nothing to save") is covered by
/// drawing_save_test.dart.
library;

import 'package:contractorhub/features/jobs/domain/drawing_models.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('DrawingStroke.addPoint', () {
    test('returns a new stroke with the point appended', () {
      const original = DrawingStroke(
        tool: DrawingTool.pen,
        color: Colors.black,
        thickness: 3,
        points: [Offset.zero],
      );

      final updated = original.addPoint(const Offset(5, 5));

      expect(original.points, hasLength(1),
          reason: 'original must remain unmutated');
      expect(updated.points, [Offset.zero, const Offset(5, 5)]);
      expect(updated.tool, DrawingTool.pen);
      expect(updated.color, Colors.black);
      expect(updated.thickness, 3);
    });

    test('preserves tool and style across multiple appends', () {
      var stroke = const DrawingStroke(
        tool: DrawingTool.arrow,
        color: Colors.red,
        thickness: 6,
        points: [Offset.zero],
      );

      stroke = stroke.addPoint(const Offset(1, 1)).addPoint(const Offset(2, 2));

      expect(stroke.points, hasLength(3));
      expect(stroke.tool, DrawingTool.arrow);
      expect(stroke.color, Colors.red);
      expect(stroke.thickness, 6);
    });
  });
}
