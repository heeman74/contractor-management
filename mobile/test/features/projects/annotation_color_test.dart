/// Unit tests for [AnnotationColor] — the shared hex<->Color converter that
/// replaced the duplicated `_colorHex` / `_parseColor` helpers.
library;

import 'dart:ui';

import 'package:contractorhub/features/projects/domain/annotation_color.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('AnnotationColor.toHex', () {
    test('serializes an opaque color to #RRGGBB (alpha dropped)', () {
      expect(AnnotationColor.toHex(const Color(0xFFD32F2F)), '#D32F2F');
    });

    test('serializes black correctly', () {
      expect(AnnotationColor.toHex(const Color(0xFF000000)), '#000000');
    });
  });

  group('AnnotationColor.fromHex', () {
    test('parses a #RRGGBB string into an opaque color', () {
      expect(AnnotationColor.fromHex('#1565C0'), const Color(0xFF1565C0));
    });

    test('parses a bare RRGGBB string (no leading #)', () {
      expect(AnnotationColor.fromHex('F57C00'), const Color(0xFFF57C00));
    });

    test('returns fallback for malformed input', () {
      expect(AnnotationColor.fromHex('not-a-color'), AnnotationColor.fallback);
    });

    test('returns fallback for wrong-length input', () {
      expect(AnnotationColor.fromHex('#FFF'), AnnotationColor.fallback);
    });
  });

  group('round-trip', () {
    test('toHex then fromHex preserves the color', () {
      for (final color in const [
        Color(0xFFD32F2F),
        Color(0xFFF57C00),
        Color(0xFFFFC107),
        Color(0xFF1565C0),
        Color(0xFF000000),
      ]) {
        expect(AnnotationColor.fromHex(AnnotationColor.toHex(color)), color);
      }
    });
  });
}
