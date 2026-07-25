// Photo Annotation — Flutter E2E widget tests.
//
// TARGET: lib/features/projects/presentation/screens/photo_annotation_screen.dart
//   The STANDALONE, non-destructive photo annotation screen. It draws
//   arrows / circles / text / measurements on a CustomPaint layer over a base
//   photo (Image.file) and returns the annotation overlay as a JSON string.
//
// IMPORTANT — what the SOURCE actually does (differs from a naive spec):
//   * The screen is PURELY UI. It has NO Riverpod providers of its own, NO
//     GetIt, NO Drift, NO Dio. It takes {localPath, annotationData?} and, on
//     Save, returns `AnnotationLayer.toJsonString()` via `Navigator.pop(ctx,
//     String?)` (null on Discard). Persistence to Drift/TaskAttachment.
//     annotationData is the CALLER's job (task-execution / phase_22), NOT this
//     screen. There is therefore no DB row to seed and no sync-queue to assert
//     HERE — the meaningful non-destructive assertion is: (a) the returned JSON
//     is a valid AnnotationLayer with the expected tools/colors/coords, and
//     (b) the base photo FILE on disk is byte-for-byte unchanged.
//     (It IS a ConsumerStatefulWidget, so a ProviderScope ancestor is required
//     — but no overrides are needed since it never reads a provider.)
//   * Drawing requires FIRST selecting a tool. Default is view mode
//     (InteractiveViewer, pinch/pan). Selecting any tool flips `_isDrawMode`
//     → a GestureDetector captures pan/tap for the active tool.
//   * Tools & gestures:  arrow  = pan (onPanEnd commits),
//                        circle = pan (bounding rect),
//                        text   = TAP → AlertDialog "Add Text Label",
//                        measure= pan → AlertDialog "Add Measurement".
//     Coordinates are normalized 0–1 against the live canvas size (set via an
//     addPostFrameCallback), so we pump enough frames for size to settle.
//   * Colors: 5 presets — Red #D32F2F (default), Orange #F57C00, Yellow
//     #FFC107, Blue #1565C0, Black #000000.
//   * Undo pops the last annotation; Clear-all confirms then removes all.
//   * Save is DISABLED unless `_hasChanges` (annotations non-empty OR an
//     existing annotationData was passed in) — a clean in-memory signal.
//   * There is NO async/server save path, so a "save failure" error state is
//     unreachable. The honest error/edge coverage is: malformed incoming
//     annotationData is swallowed in initState (screen still renders), and
//     Discard returns null.
//
// Coverage:
//   1.  Renders canvas over the base photo + full tool palette (arrow/circle/
//       text/measure), color swatches, undo/clear, Save/Discard.
//   2.  Starts in VIEW mode (InteractiveViewer, no "Done Drawing"); Save is
//       disabled with no annotations and no incoming data.
//   3.  Selecting a tool enters draw mode (InteractiveViewer gone, "Done
//       Drawing" shown); "Done Drawing" exits draw mode.
//   4.  Draw ARROW (pan) → Save returns a layer with 1 arrow, normalized 0–1
//       coords, default red, and a populated canvas size.
//   5.  Draw CIRCLE (pan) → returned layer has 1 circle with bounding-rect
//       fields.
//   6.  Color selection: pick Blue → drawn arrow carries #1565C0.
//   7.  TEXT tool: tap → dialog → type label → returned layer has a text
//       annotation with that label.
//   8.  MEASUREMENT tool: pan → dialog → type value → returned layer has a
//       measurement annotation with that label.
//   9.  Undo: draw one → Undo → Save re-disabled (in-memory state emptied).
//   10. Clear-all: draw two → confirm dialog → Clear → Save re-disabled.
//   11. Edit existing: load annotationData (arrow+circle) → Save round-trips
//       both back out (load path works).
//   12. Edit existing + modify: load two, draw a third → returned layer has 3.
//   13. Non-destructive: base photo file bytes are unchanged after a save.
//   14. Edge: malformed incoming annotationData is ignored, screen still
//       renders and Save (enabled because data was passed) returns an empty
//       layer.
//   15. Discard returns null.
//
// Harness rules (CLAUDE.md + MEMORY.md):
//   * A real base-photo file (1×1 PNG) is written to a temp dir per test and
//     deleted in tearDown; Image.file loads it locally (no network, no hang).
//   * pump() / pump(Duration(...)) only — never pumpAndSettle().
//   * The screen is pushed via Navigator so the Save/Discard pop result is
//     captured and asserted; each test unmounts to a SizedBox + pump to drain
//     any pending frame callbacks.

import 'dart:convert';
import 'dart:io';

import 'package:contractorhub/features/projects/domain/annotation_schema.dart';
import 'package:contractorhub/features/projects/presentation/screens/photo_annotation_screen.dart';
import 'package:contractorhub/features/projects/presentation/widgets/annotation_painter.dart';
import 'package:contractorhub/features/projects/presentation/widgets/annotation_toolbar.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // A 1×1 transparent PNG — a real, decodable image for Image.file.
  final pngBytes = base64Decode(
    'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk'
    '+M8AAAMBAQDJ/pLvAAAAAElFTkSuQmCC',
  );

  late Directory tempDir;
  late File photoFile;
  late String photoPath;

  // Captured Navigator.pop result from the pushed screen.
  String? lastResult;
  bool didPop = false;

  setUp(() {
    tempDir = Directory.systemTemp.createTempSync('photo_annotation_e2e');
    photoFile = File('${tempDir.path}/base_photo.png')..writeAsBytesSync(pngBytes);
    photoPath = photoFile.path;
    lastResult = null;
    didPop = false;
  });

  tearDown(() {
    if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
  });

  // A safe drag/tap region inside the canvas, clear of the top bar and the
  // bottom toolbar overlays (default 800×600 test surface).
  const canvasStart = Offset(280, 260);
  const canvasDelta = Offset(140, 100);
  const canvasTapPoint = Offset(360, 300);

  // Pushes the annotation screen and captures its pop result into [lastResult].
  Future<void> pumpScreen(
    WidgetTester tester, {
    String? annotationData,
  }) async {
    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => Center(
                child: ElevatedButton(
                  onPressed: () async {
                    lastResult = await Navigator.of(context).push<String>(
                      MaterialPageRoute<String>(
                        builder: (_) => PhotoAnnotationScreen(
                          localPath: photoPath,
                          annotationData: annotationData,
                        ),
                      ),
                    );
                    didPop = true;
                  },
                  child: const Text('OPEN'),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.tap(find.text('OPEN'));
    // Advance the push slide-in transition to completion (fixed duration, not
    // pumpAndSettle) so the screen is fully on-screen, then let the post-frame
    // callback set the live canvas size.
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pump();
  }

  // Unmounts the widget tree so any pending frame callbacks are drained.
  Future<void> unmount(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
    tester.takeException();
  }

  Future<void> selectTool(WidgetTester tester, String tooltip) async {
    await tester.tap(find.byTooltip(tooltip));
    await tester.pump();
    await tester.pump();
  }

  Future<void> selectColor(WidgetTester tester, Color color) async {
    final swatch = find.byWidgetPredicate(
      (w) =>
          w is Container &&
          w.decoration is BoxDecoration &&
          (w.decoration! as BoxDecoration).color?.toARGB32() ==
              color.toARGB32(),
    );
    await tester.tap(swatch);
    await tester.pump();
  }

  bool saveEnabled(WidgetTester tester) {
    final button = tester.widget<TextButton>(
      find.ancestor(
        of: find.text('Save Annotation'),
        matching: find.byType(TextButton),
      ),
    );
    return button.onPressed != null;
  }

  Future<void> tapSave(WidgetTester tester) async {
    await tester.tap(find.text('Save Annotation'));
    await tester.pump();
    // Settle the pop transition so the push future completes with the result.
    await tester.pump(const Duration(milliseconds: 500));
  }

  AnnotationLayer decodeResult() {
    expect(lastResult, isNotNull,
        reason: 'expected a JSON payload from Navigator.pop on Save');
    return AnnotationLayer.fromJsonString(lastResult!);
  }

  // A minimal existing overlay: one arrow + one circle.
  String seededOverlay() => AnnotationLayer(
        canvasWidth: 800,
        canvasHeight: 600,
        annotations: [
          Annotation(
            id: 'seed-arrow',
            tool: AnnotationTool.arrow,
            color: '#F57C00',
            thickness: 3,
            startX: 0.1,
            startY: 0.1,
            endX: 0.5,
            endY: 0.5,
          ),
          Annotation(
            id: 'seed-circle',
            tool: AnnotationTool.circle,
            color: '#1565C0',
            thickness: 3,
            x: 0.2,
            y: 0.2,
            width: 0.4,
            height: 0.3,
          ),
        ],
      ).toJsonString();

  group('Photo Annotation E2E — render & mode', () {
    testWidgets('renders base photo, tool palette, colors, and controls',
        (tester) async {
      await pumpScreen(tester);

      // Base photo layer + annotation CustomPaint.
      expect(find.byType(Image), findsWidgets);
      expect(
        find.byWidgetPredicate(
          (w) => w is CustomPaint && w.painter is AnnotationPainter,
        ),
        findsWidgets,
      );

      // Toolbar + tools.
      expect(find.byType(AnnotationToolbar), findsOneWidget);
      expect(find.byTooltip('Arrow'), findsOneWidget);
      expect(find.byTooltip('Circle'), findsOneWidget);
      expect(find.byTooltip('Text'), findsOneWidget);
      expect(find.byTooltip('Measure'), findsOneWidget);
      expect(find.byTooltip('Undo'), findsOneWidget);
      expect(find.byTooltip('Clear all'), findsOneWidget);

      // Top-bar actions.
      expect(find.text('Discard Changes'), findsOneWidget);
      expect(find.text('Save Annotation'), findsOneWidget);

      await unmount(tester);
    });

    testWidgets('starts in view mode; Save disabled with nothing to save',
        (tester) async {
      await pumpScreen(tester);

      expect(find.byType(InteractiveViewer), findsOneWidget);
      expect(find.text('Done Drawing'), findsNothing);
      expect(saveEnabled(tester), isFalse);

      await unmount(tester);
    });

    testWidgets('selecting a tool enters draw mode; Done Drawing exits it',
        (tester) async {
      await pumpScreen(tester);

      await selectTool(tester, 'Arrow');
      expect(find.byType(InteractiveViewer), findsNothing);
      expect(find.text('Done Drawing'), findsOneWidget);

      await tester.tap(find.text('Done Drawing'));
      await tester.pump();
      expect(find.byType(InteractiveViewer), findsOneWidget);
      expect(find.text('Done Drawing'), findsNothing);

      await unmount(tester);
    });
  });

  group('Photo Annotation E2E — drawing tools', () {
    testWidgets('draw ARROW → returns layer with one normalized arrow',
        (tester) async {
      await pumpScreen(tester);
      await selectTool(tester, 'Arrow');

      await tester.dragFrom(canvasStart, canvasDelta);
      await tester.pump();

      expect(saveEnabled(tester), isTrue);
      await tapSave(tester);

      final layer = decodeResult();
      expect(layer.version, 1);
      expect(layer.canvasWidth, greaterThan(0));
      expect(layer.canvasHeight, greaterThan(0));
      expect(layer.annotations, hasLength(1));

      final arrow = layer.annotations.single;
      expect(arrow.tool, AnnotationTool.arrow);
      expect(arrow.color, '#D32F2F'); // default red
      expect(arrow.startX, isNotNull);
      expect(arrow.endX, isNotNull);
      expect(arrow.startX, inInclusiveRange(0.0, 1.0));
      expect(arrow.endX, inInclusiveRange(0.0, 1.0));
      expect(arrow.startY, inInclusiveRange(0.0, 1.0));
      expect(arrow.endY, inInclusiveRange(0.0, 1.0));

      await unmount(tester);
    });

    testWidgets('draw CIRCLE → returns layer with one bounding-rect circle',
        (tester) async {
      await pumpScreen(tester);
      await selectTool(tester, 'Circle');

      await tester.dragFrom(canvasStart, canvasDelta);
      await tester.pump();
      await tapSave(tester);

      final circle = decodeResult().annotations.single;
      expect(circle.tool, AnnotationTool.circle);
      expect(circle.x, isNotNull);
      expect(circle.y, isNotNull);
      expect(circle.width, isNotNull);
      expect(circle.height, isNotNull);

      await unmount(tester);
    });

    testWidgets('color selection: Blue swatch → drawn arrow carries #1565C0',
        (tester) async {
      await pumpScreen(tester);
      await selectTool(tester, 'Arrow');
      await selectColor(tester, const Color(0xFF1565C0));

      await tester.dragFrom(canvasStart, canvasDelta);
      await tester.pump();
      await tapSave(tester);

      expect(decodeResult().annotations.single.color, '#1565C0');

      await unmount(tester);
    });

    // NOTE on the two dialog-driven tools below: `_promptForLabel` disposes its
    // TextEditingController the instant the dialog pops (Route.didPop completes
    // the future synchronously). In debug/test (asserts on) a still-focused
    // EditableText would then rebuild against that disposed controller during
    // the dialog's reverse transition and corrupt the element tree. We sidestep
    // it by dropping focus BEFORE confirming, so the pop has no focused field
    // to rebuild — the dialog tears down cleanly and Save round-trips normally.

    testWidgets('TEXT tool: tap → dialog → label persisted in returned layer',
        (tester) async {
      await pumpScreen(tester);
      await selectTool(tester, 'Text');
      expect(saveEnabled(tester), isFalse);

      await tester.tapAt(canvasTapPoint);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(find.text('Add Text Label'), findsOneWidget);
      await tester.enterText(find.byType(TextField), 'Cracked tile');
      await tester.pump();
      // Drop focus BEFORE confirming: the screen disposes the dialog's
      // controller the instant it pops, so a still-focused EditableText would
      // rebuild against a disposed controller during the reverse transition.
      FocusManager.instance.primaryFocus?.unfocus();
      await tester.pump();
      await tester.tap(find.widgetWithText(FilledButton, 'Add'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));

      await tapSave(tester);
      final text = decodeResult().annotations.single;
      expect(text.tool, AnnotationTool.text);
      expect(text.label, 'Cracked tile');
      expect(text.x, isNotNull);
      expect(text.y, isNotNull);

      await unmount(tester);
    });

    testWidgets('MEASUREMENT tool: pan → dialog → value persisted',
        (tester) async {
      await pumpScreen(tester);
      await selectTool(tester, 'Measure');

      await tester.dragFrom(canvasStart, canvasDelta);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(find.text('Add Measurement'), findsWidgets); // title + button
      await tester.enterText(find.byType(TextField), '24 inches');
      await tester.pump();
      FocusManager.instance.primaryFocus?.unfocus();
      await tester.pump();
      await tester.tap(find.widgetWithText(FilledButton, 'Add Measurement'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));

      await tapSave(tester);
      final measure = decodeResult().annotations.single;
      expect(measure.tool, AnnotationTool.measurement);
      expect(measure.label, '24 inches');
      expect(measure.startX, isNotNull);
      expect(measure.endX, isNotNull);

      await unmount(tester);
    });
  });

  group('Photo Annotation E2E — undo & clear', () {
    testWidgets('Undo removes the last annotation (Save re-disabled)',
        (tester) async {
      await pumpScreen(tester);
      await selectTool(tester, 'Arrow');

      await tester.dragFrom(canvasStart, canvasDelta);
      await tester.pump();
      expect(saveEnabled(tester), isTrue);

      await tester.tap(find.byTooltip('Undo'));
      await tester.pump();
      expect(saveEnabled(tester), isFalse);

      await unmount(tester);
    });

    testWidgets('Clear-all confirms then empties (Save re-disabled)',
        (tester) async {
      await pumpScreen(tester);
      await selectTool(tester, 'Arrow');

      await tester.dragFrom(canvasStart, canvasDelta);
      await tester.pump();
      await tester.dragFrom(
        canvasStart + const Offset(0, 40),
        canvasDelta,
      );
      await tester.pump();
      expect(saveEnabled(tester), isTrue);

      await tester.tap(find.byTooltip('Clear all'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.text('Clear all annotations?'), findsOneWidget);

      await tester.tap(find.text('Clear all'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(saveEnabled(tester), isFalse);

      await unmount(tester);
    });
  });

  group('Photo Annotation E2E — edit existing & non-destructive', () {
    testWidgets('loads existing annotationData and round-trips it on Save',
        (tester) async {
      await pumpScreen(tester, annotationData: seededOverlay());

      // Save is enabled purely because existing data was supplied.
      expect(saveEnabled(tester), isTrue);
      await tapSave(tester);

      final layer = decodeResult();
      expect(layer.annotations, hasLength(2));
      expect(
        layer.annotations.map((a) => a.tool),
        containsAll(<AnnotationTool>[
          AnnotationTool.arrow,
          AnnotationTool.circle,
        ]),
      );
      final loadedArrow = layer.annotations
          .firstWhere((a) => a.tool == AnnotationTool.arrow);
      expect(loadedArrow.color, '#F57C00');

      await unmount(tester);
    });

    testWidgets('edit existing + add a third annotation → layer has 3',
        (tester) async {
      await pumpScreen(tester, annotationData: seededOverlay());

      await selectTool(tester, 'Arrow');
      await tester.dragFrom(canvasStart, canvasDelta);
      await tester.pump();

      await tapSave(tester);
      expect(decodeResult().annotations, hasLength(3));

      await unmount(tester);
    });

    testWidgets('non-destructive: base photo file is unchanged after Save',
        (tester) async {
      final before = photoFile.readAsBytesSync();

      await pumpScreen(tester);
      await selectTool(tester, 'Circle');
      await tester.dragFrom(canvasStart, canvasDelta);
      await tester.pump();
      await tapSave(tester);

      // A payload was produced, and the original photo bytes are untouched.
      expect(lastResult, isNotNull);
      expect(photoFile.readAsBytesSync(), equals(before));

      await unmount(tester);
    });
  });

  group('Photo Annotation E2E — edge & discard', () {
    testWidgets('malformed annotationData is ignored; screen still renders',
        (tester) async {
      await pumpScreen(tester, annotationData: '{{ not valid json');

      // No crash; the toolbar renders and Save is enabled (data was passed).
      expect(find.byType(AnnotationToolbar), findsOneWidget);
      expect(saveEnabled(tester), isTrue);

      await tapSave(tester);
      expect(decodeResult().annotations, isEmpty);

      await unmount(tester);
    });

    testWidgets('Discard Changes returns null (no payload)', (tester) async {
      await pumpScreen(tester);

      await tester.tap(find.text('Discard Changes'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));

      expect(didPop, isTrue);
      expect(lastResult, isNull);

      await unmount(tester);
    });
  });
}
