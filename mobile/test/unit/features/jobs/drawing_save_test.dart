/// Unit tests for DrawingPadScreen save logic.
///
/// Tests cover:
/// 1. Save button shows snackbar "Nothing to save." when canvas is empty (no strokes)
/// 2. Discard dialog appears when closing with strokes present
/// 3. Cancel in discard dialog keeps drawing pad open
///
/// Note: The actual PNG export to getApplicationSupportDirectory() cannot be
/// tested in widget tests because RenderRepaintBoundary.toImage() requires a
/// live rendering pipeline. These tests verify the UI-level save flow behavior.
library;

import 'package:contractorhub/features/jobs/presentation/screens/drawing_pad_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

Widget buildDrawingPad() {
  return const MaterialApp(
    home: DrawingPadScreen(),
  );
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

void main() {
  group('DrawingSave', () {
    testWidgets('save button shows nothing-to-save snackbar when canvas is empty',
        (tester) async {
      await tester.pumpWidget(buildDrawingPad());
      await tester.pump();

      // Find and tap the Save button (FilledButton.icon with save_outlined icon)
      final saveButton = find.byWidgetPredicate(
        (w) =>
            w is FilledButton &&
            w.child != null,
      );
      // Try text-based finder instead
      final saveText = find.text('Save');
      expect(saveText, findsOneWidget);
      await tester.tap(saveText);
      await tester.pump();

      // Should show "Nothing to save." snackbar
      expect(find.text('Nothing to save.'), findsOneWidget);
    });

    testWidgets('close button shows discard dialog when strokes are present',
        (tester) async {
      await tester.pumpWidget(buildDrawingPad());
      await tester.pump();

      // Draw a stroke on the canvas by simulating a drag gesture
      // The GestureDetector is on top of the canvas in the Stack
      final canvasArea = find.byType(GestureDetector).first;
      await tester.drag(canvasArea, const Offset(100, 100));
      await tester.pump();

      // Tap the close button (leading icon in app bar)
      final closeButton = find.byIcon(Icons.close);
      expect(closeButton, findsOneWidget);
      await tester.tap(closeButton);
      await tester.pump();

      // Discard dialog should appear
      expect(find.text('Discard drawing?'), findsOneWidget);
      expect(find.text('Your drawing will not be saved.'), findsOneWidget);
    });

    testWidgets('cancel in discard dialog keeps drawing pad open',
        (tester) async {
      await tester.pumpWidget(buildDrawingPad());
      await tester.pump();

      // Draw a stroke
      final canvasArea = find.byType(GestureDetector).first;
      await tester.drag(canvasArea, const Offset(100, 100));
      await tester.pump();

      // Tap close
      await tester.tap(find.byIcon(Icons.close));
      await tester.pump();

      // Tap Cancel in the dialog
      await tester.tap(find.text('Cancel'));
      await tester.pump();

      // Drawing pad should still be visible
      expect(find.text('Drawing Pad'), findsOneWidget);
    });
  });
}
