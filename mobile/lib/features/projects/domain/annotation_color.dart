import 'package:flutter/painting.dart';

/// Converts between [Color] and the CSS hex strings stored on annotations.
///
/// Consolidates the color conversion that was previously duplicated as
/// `_colorHex` (screen) and `_parseColor` (painter).
class AnnotationColor {
  AnnotationColor._();

  static const Color fallback = Color(0xFFD32F2F); // Red
  static const int _rgbHexLength = 6;

  /// Serializes [color] to an uppercase `#RRGGBB` string (alpha dropped).
  static String toHex(Color color) {
    final argb = color.toARGB32();
    return '#${argb.toRadixString(16).substring(2).toUpperCase()}';
  }

  /// Parses a `#RRGGBB` (or `RRGGBB`) string into an opaque [Color].
  ///
  /// Returns [fallback] when the input is malformed.
  static Color fromHex(String hex) {
    try {
      final clean = hex.replaceAll('#', '');
      if (clean.length == _rgbHexLength) {
        return Color(int.parse('FF$clean', radix: 16));
      }
      return fallback;
    } catch (_) {
      return fallback;
    }
  }
}
