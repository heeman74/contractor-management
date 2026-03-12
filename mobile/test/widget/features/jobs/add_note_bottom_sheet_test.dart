/// Widget tests for AddNoteBottomSheet.
///
/// Tests cover:
/// 1. renders text field with correct hint text
/// 2. renders Camera, Gallery, PDF, Draw attachment buttons
/// 3. Save button is disabled when body is empty and no attachments
/// 4. Save button is enabled when body has text
/// 5. "Add Field Note" header is present
///
/// Strategy: construct the sheet directly using the private constructor via
/// AddNoteBottomSheet._() — pass mock DAOs.  The sheet has no Riverpod
/// providers, so no ProviderScope override is needed.
library;

import 'package:contractorhub/core/database/app_database.dart';
import 'package:contractorhub/features/jobs/presentation/widgets/add_note_bottom_sheet.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

// ---------------------------------------------------------------------------
// Mocks
// ---------------------------------------------------------------------------

class MockNoteDao extends Mock implements NoteDao {}

class MockAttachmentDao extends Mock implements AttachmentDao {}

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

Widget buildSheet({
  NoteDao? noteDao,
  AttachmentDao? attachmentDao,
}) {
  final mockNoteDao = noteDao ?? MockNoteDao();
  final mockAttachmentDao = attachmentDao ?? MockAttachmentDao();

  return MaterialApp(
    home: Scaffold(
      body: Builder(
        builder: (context) {
          return ElevatedButton(
            onPressed: () {
              AddNoteBottomSheet.show(
                context: context,
                jobId: 'job-1',
                companyId: 'co-1',
                authorId: 'author-1',
                noteDao: mockNoteDao,
                attachmentDao: mockAttachmentDao,
              );
            },
            child: const Text('Open Sheet'),
          );
        },
      ),
    ),
  );
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

void main() {
  group('AddNoteBottomSheet', () {
    testWidgets('opens bottom sheet on button tap', (tester) async {
      await tester.pumpWidget(buildSheet());
      await tester.pump();

      await tester.tap(find.text('Open Sheet'));
      await tester.pump();

      expect(find.text('Add Field Note'), findsOneWidget);
    });

    testWidgets('renders text field with hint text', (tester) async {
      await tester.pumpWidget(buildSheet());
      await tester.pump();
      await tester.tap(find.text('Open Sheet'));
      await tester.pump();

      expect(
        find.byWidgetPredicate(
          (w) =>
              w is TextField ||
              (w is EditableText &&
                  w.controller.text.isEmpty),
        ),
        findsWidgets,
      );
      expect(
        find.text('Describe what you observed or did...'),
        findsOneWidget,
      );
    });

    testWidgets('renders Camera attachment button', (tester) async {
      await tester.pumpWidget(buildSheet());
      await tester.pump();
      await tester.tap(find.text('Open Sheet'));
      await tester.pump();

      expect(find.text('Camera'), findsOneWidget);
    });

    testWidgets('renders Gallery attachment button', (tester) async {
      await tester.pumpWidget(buildSheet());
      await tester.pump();
      await tester.tap(find.text('Open Sheet'));
      await tester.pump();

      expect(find.text('Gallery'), findsOneWidget);
    });

    testWidgets('renders PDF attachment button', (tester) async {
      await tester.pumpWidget(buildSheet());
      await tester.pump();
      await tester.tap(find.text('Open Sheet'));
      await tester.pump();

      expect(find.text('PDF'), findsOneWidget);
    });

    testWidgets('renders Draw attachment button', (tester) async {
      await tester.pumpWidget(buildSheet());
      await tester.pump();
      await tester.tap(find.text('Open Sheet'));
      await tester.pump();

      expect(find.text('Draw'), findsOneWidget);
    });

    testWidgets('Save button is disabled when body is empty', (tester) async {
      await tester.pumpWidget(buildSheet());
      await tester.pump();
      await tester.tap(find.text('Open Sheet'));
      await tester.pump();

      // Find the Save Note button — it should be disabled (onPressed == null)
      final saveButton = find.text('Save Note');
      expect(saveButton, findsOneWidget);

      final filledButton = tester.widget<FilledButton>(
        find.ancestor(of: saveButton, matching: find.byType(FilledButton)),
      );
      expect(filledButton.onPressed, isNull);
    });

    testWidgets('Save button is enabled after entering text', (tester) async {
      await tester.pumpWidget(buildSheet());
      await tester.pump();
      await tester.tap(find.text('Open Sheet'));
      await tester.pump();

      // Type text into the note body
      await tester.enterText(find.byType(TextField).first, 'Found a crack');
      await tester.pump();

      final saveButton = find.text('Save Note');
      expect(saveButton, findsOneWidget);

      final filledButton = tester.widget<FilledButton>(
        find.ancestor(of: saveButton, matching: find.byType(FilledButton)),
      );
      expect(filledButton.onPressed, isNotNull);
    });
  });
}
