/// Widget tests for DrawingPadScreen.
///
/// Tests cover:
/// 1. renders drawing tools toolbar (pen, eraser, etc.)
/// 2. renders 8 color swatches in the color picker
/// 3. renders 3 thickness options (Thin, Med, Thick)
/// 4. grid toggle button is present
/// 5. Save button is present in the app bar
///
/// Note: landscape lock testing is limited in widget tests — only UI element
/// presence is verified. The actual SystemChrome orientation call is not tested.
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
  group('DrawingPadScreen', () {
    testWidgets('renders pen tool icon in toolbar', (tester) async {
      await tester.pumpWidget(buildDrawingPad());
      await tester.pump();

      // DrawingPadScreen shows an edit/draw icon for pen tool
      expect(find.byIcon(Icons.edit_outlined), findsWidgets);
    });

    testWidgets('renders eraser tool icon in toolbar', (tester) async {
      await tester.pumpWidget(buildDrawingPad());
      await tester.pump();

      expect(
        find.byWidgetPredicate(
          (w) =>
              w is Icon &&
              (w.icon == Icons.auto_fix_normal_outlined ||
                  w.icon == Icons.highlight_off_outlined ||
                  w.icon == Icons.cleaning_services_outlined),
        ),
        findsWidgets,
      );
    });

    testWidgets('renders 8 color swatches', (tester) async {
      await tester.pumpWidget(buildDrawingPad());
      await tester.pump();

      // The color picker uses GestureDetector-wrapped Container for each swatch
      // 8 colors: black, red, blue, green, orange, purple, brown, white
      // They're rendered as circular Container widgets in a Row
      final colorSwatches = find.byWidgetPredicate(
        (w) =>
            w is Container &&
            w.decoration is BoxDecoration &&
            (w.decoration as BoxDecoration).shape == BoxShape.circle,
      );
      expect(colorSwatches.evaluate().length, greaterThanOrEqualTo(8));
    });

    testWidgets('renders 3 thickness options', (tester) async {
      await tester.pumpWidget(buildDrawingPad());
      await tester.pump();

      expect(find.text('Thin'), findsOneWidget);
      expect(find.text('Med'), findsOneWidget);
      expect(find.text('Thick'), findsOneWidget);
    });

    testWidgets('grid toggle button is present', (tester) async {
      await tester.pumpWidget(buildDrawingPad());
      await tester.pump();

      // Grid button uses grid_on icon
      expect(
        find.byWidgetPredicate(
          (w) =>
              w is Icon &&
              (w.icon == Icons.grid_on ||
                  w.icon == Icons.grid_off ||
                  w.icon == Icons.grid_4x4 ||
                  w.icon == Icons.grid_3x3),
        ),
        findsWidgets,
      );
    });

    testWidgets('Save button is present in app bar area', (tester) async {
      await tester.pumpWidget(buildDrawingPad());
      await tester.pump();

      // Save button uses save icon or 'Save' text
      final saveIcon = find.byWidgetPredicate(
        (w) => w is Icon && w.icon == Icons.save_outlined,
      );
      final saveText = find.text('Save');
      expect(saveIcon.evaluate().isNotEmpty || saveText.evaluate().isNotEmpty,
          isTrue);
    });

    testWidgets('undo button is present', (tester) async {
      await tester.pumpWidget(buildDrawingPad());
      await tester.pump();

      expect(
        find.byWidgetPredicate(
          (w) => w is Icon && w.icon == Icons.undo,
        ),
        findsWidgets,
      );
    });
  });
}
