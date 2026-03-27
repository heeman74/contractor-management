import 'dart:convert';

import 'package:contractorhub/features/projects/domain/annotation_schema.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('AnnotationLayer JSON serialization', () {
    // ─── Test 1: toJson produces valid JSON with required top-level fields ───

    test('toJson produces version=1, canvasWidth, canvasHeight, annotations', () {
      final layer = AnnotationLayer(
        canvasWidth: 1920,
        canvasHeight: 1080,
        annotations: [],
      );

      final json = layer.toJson();

      expect(json['version'], equals(1));
      expect(json['canvasWidth'], equals(1920.0));
      expect(json['canvasHeight'], equals(1080.0));
      expect(json['annotations'], isA<List>());
    });

    // ─── Test 2: round-trip serialization ─────────────────────────────────

    test('fromJson round-trips — create, serialize, deserialize, compare', () {
      final original = AnnotationLayer(
        canvasWidth: 1920,
        canvasHeight: 1080,
        annotations: [
          Annotation(
            id: 'abc-123',
            tool: AnnotationTool.arrow,
            color: '#FF0000',
            thickness: 2.0,
            startX: 0.1,
            startY: 0.2,
            endX: 0.8,
            endY: 0.9,
          ),
        ],
      );

      final jsonString = original.toJsonString();
      final restored = AnnotationLayer.fromJsonString(jsonString);

      expect(restored.version, equals(original.version));
      expect(restored.canvasWidth, equals(original.canvasWidth));
      expect(restored.canvasHeight, equals(original.canvasHeight));
      expect(restored.annotations.length, equals(1));
      expect(restored.annotations.first.id, equals('abc-123'));
      expect(restored.annotations.first.tool, equals(AnnotationTool.arrow));
      expect(restored.annotations.first.color, equals('#FF0000'));
    });

    // ─── Test 3: Arrow annotation normalized coordinates ─────────────────

    test('Arrow annotation serializes with startX, startY, endX, endY as 0-1', () {
      final ann = Annotation(
        id: 'arrow-1',
        tool: AnnotationTool.arrow,
        color: '#0000FF',
        thickness: 3.0,
        startX: 0.05,
        startY: 0.15,
        endX: 0.95,
        endY: 0.85,
      );

      final json = ann.toJson();

      expect(json['tool'], equals('arrow'));
      expect(json['startX'], closeTo(0.05, 1e-9));
      expect(json['startY'], closeTo(0.15, 1e-9));
      expect(json['endX'], closeTo(0.95, 1e-9));
      expect(json['endY'], closeTo(0.85, 1e-9));

      // Verify all coordinates are in normalized 0-1 range
      expect(json['startX'] as double, lessThanOrEqualTo(1.0));
      expect(json['startX'] as double, greaterThanOrEqualTo(0.0));
      expect(json['endX'] as double, lessThanOrEqualTo(1.0));
    });

    // ─── Test 4: Circle annotation normalized ────────────────────────────

    test('Circle annotation serializes with x, y, width, height as 0-1', () {
      final ann = Annotation(
        id: 'circle-1',
        tool: AnnotationTool.circle,
        color: '#00FF00',
        thickness: 2.0,
        x: 0.3,
        y: 0.4,
        width: 0.2,
        height: 0.15,
      );

      final json = ann.toJson();

      expect(json['tool'], equals('circle'));
      expect(json['x'], closeTo(0.3, 1e-9));
      expect(json['y'], closeTo(0.4, 1e-9));
      expect(json['width'], closeTo(0.2, 1e-9));
      expect(json['height'], closeTo(0.15, 1e-9));

      // Arrow-specific fields should not be present
      expect(json.containsKey('startX'), isFalse);
    });

    // ─── Test 5: Text annotation ─────────────────────────────────────────

    test('Text annotation serializes with x, y, label, fontSize', () {
      final ann = Annotation(
        id: 'text-1',
        tool: AnnotationTool.text,
        color: '#000000',
        thickness: 1.0,
        x: 0.5,
        y: 0.5,
        label: 'Crack in wall',
        fontSize: 16.0,
      );

      final json = ann.toJson();

      expect(json['tool'], equals('text'));
      expect(json['x'], closeTo(0.5, 1e-9));
      expect(json['y'], closeTo(0.5, 1e-9));
      expect(json['label'], equals('Crack in wall'));
      expect(json['fontSize'], equals(16.0));
    });

    // ─── Test 6: Measurement annotation ──────────────────────────────────

    test('Measurement annotation serializes with startX/Y, endX/Y, and label', () {
      final ann = Annotation(
        id: 'meas-1',
        tool: AnnotationTool.measurement,
        color: '#FFC107',
        thickness: 2.0,
        startX: 0.1,
        startY: 0.5,
        endX: 0.9,
        endY: 0.5,
        label: '24 inches',
      );

      final json = ann.toJson();

      expect(json['tool'], equals('measurement'));
      expect(json['startX'], closeTo(0.1, 1e-9));
      expect(json['startY'], closeTo(0.5, 1e-9));
      expect(json['endX'], closeTo(0.9, 1e-9));
      expect(json['endY'], closeTo(0.5, 1e-9));
      expect(json['label'], equals('24 inches'));
    });

    // ─── Test 7: Empty annotations list ──────────────────────────────────

    test('Empty annotations list serializes and deserializes correctly', () {
      final layer = AnnotationLayer(
        canvasWidth: 800,
        canvasHeight: 600,
        annotations: [],
      );

      final jsonString = layer.toJsonString();
      final restored = AnnotationLayer.fromJsonString(jsonString);

      expect(restored.annotations, isEmpty);

      // Verify valid JSON was produced
      final decoded = jsonDecode(jsonString) as Map<String, dynamic>;
      expect(decoded['annotations'], isA<List>());
      expect((decoded['annotations'] as List).isEmpty, isTrue);
    });

    // ─── Test 8: Unknown tool types are gracefully skipped ────────────────

    test('Unknown tool type in JSON is gracefully skipped during deserialization', () {
      final jsonString = jsonEncode({
        'version': 1,
        'canvasWidth': 1920.0,
        'canvasHeight': 1080.0,
        'annotations': [
          {
            'id': 'known-1',
            'tool': 'arrow',
            'color': '#FF0000',
            'thickness': 2.0,
            'startX': 0.1,
            'startY': 0.1,
            'endX': 0.9,
            'endY': 0.9,
          },
          {
            'id': 'unknown-1',
            'tool': 'futuristic_laser',
            'color': '#00FF00',
            'thickness': 1.0,
          },
          {
            'id': 'known-2',
            'tool': 'circle',
            'color': '#0000FF',
            'thickness': 3.0,
            'x': 0.3,
            'y': 0.3,
            'width': 0.2,
            'height': 0.2,
          },
        ],
      });

      final layer = AnnotationLayer.fromJsonString(jsonString);

      // Unknown tool should be skipped — only 2 known annotations remain
      expect(layer.annotations.length, equals(2));
      expect(layer.annotations[0].tool, equals(AnnotationTool.arrow));
      expect(layer.annotations[1].tool, equals(AnnotationTool.circle));
    });

    // ─── Additional: toJsonString produces valid parseable JSON ──────────

    test('toJsonString produces a valid JSON string that can be re-parsed', () {
      final layer = AnnotationLayer(
        canvasWidth: 1280,
        canvasHeight: 720,
        annotations: [
          Annotation(
            id: 'test-1',
            tool: AnnotationTool.measurement,
            color: '#FFFFFF',
            thickness: 2.5,
            startX: 0.0,
            startY: 0.0,
            endX: 1.0,
            endY: 1.0,
            label: '10 feet',
          ),
        ],
      );

      final jsonString = layer.toJsonString();

      // Must not throw
      final decoded = jsonDecode(jsonString);
      expect(decoded, isA<Map<String, dynamic>>());
    });
  });
}
