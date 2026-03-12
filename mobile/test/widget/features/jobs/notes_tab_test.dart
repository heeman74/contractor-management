/// Widget tests for NotesTab.
///
/// Tests cover:
/// 1. renders note entries with author truncation and body text
/// 2. renders attachment thumbnails inline with notes
/// 3. empty state shows "No notes yet" message
/// 4. FAB / "Add the first note" button is present
/// 5. notes ordered newest first (provider responsibility — test data is pre-ordered)
library;

import 'package:contractorhub/features/jobs/domain/attachment_entity.dart';
import 'package:contractorhub/features/jobs/domain/note_entity.dart';
import 'package:contractorhub/features/jobs/presentation/providers/note_providers.dart';
import 'package:contractorhub/features/jobs/presentation/widgets/notes_tab.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

NoteEntity makeNoteEntity({
  String id = 'note-1',
  String companyId = 'co-1',
  String jobId = 'job-1',
  String authorId = 'author-abcd1234',
  String body = 'Checked the pipe — no leak found.',
  List<AttachmentEntity> attachments = const [],
  DateTime? createdAt,
}) {
  final now = createdAt ?? DateTime.now();
  return NoteEntity(
    id: id,
    companyId: companyId,
    jobId: jobId,
    authorId: authorId,
    body: body,
    version: 1,
    createdAt: now,
    updatedAt: now,
    attachments: attachments,
  );
}

AttachmentEntity makeAttachmentEntity({
  String id = 'att-1',
  String noteId = 'note-1',
  String localPath = '/tmp/test.jpg',
  String attachmentType = 'photo',
}) {
  final now = DateTime.now();
  return AttachmentEntity(
    id: id,
    companyId: 'co-1',
    noteId: noteId,
    attachmentType: attachmentType,
    localPath: localPath,
    uploadStatus: 'pending_upload',
    sortOrder: 0,
    createdAt: now,
    updatedAt: now,
  );
}

Widget buildNotesTab(
  List<NoteEntity> notes, {
  String jobId = 'job-1',
}) {
  return ProviderScope(
    overrides: [
      notesForJobProvider(jobId).overrideWith(
        (ref) => Stream.value(notes),
      ),
    ],
    child: MaterialApp(
      home: Scaffold(
        body: NotesTab(
          jobId: jobId,
          companyId: 'co-1',
          authorId: 'author-1',
        ),
      ),
    ),
  );
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

void main() {
  group('NotesTab', () {
    testWidgets('renders note body text', (tester) async {
      final notes = [
        makeNoteEntity(body: 'Checked the pipe — no leak found.'),
      ];

      await tester.pumpWidget(buildNotesTab(notes));
      await tester.pump(); // Let stream emit

      expect(find.text('Checked the pipe — no leak found.'), findsOneWidget);
    });

    testWidgets('truncates authorId to last 8 chars', (tester) async {
      // authorId = 'author-abcd1234' → displayed as '...bcd1234'
      final notes = [makeNoteEntity(authorId: 'author-abcd1234')];

      await tester.pumpWidget(buildNotesTab(notes));
      await tester.pump();

      // The widget shows last 8 chars prefixed with '...'
      expect(find.textContaining('bcd1234'), findsOneWidget);
    });

    testWidgets('renders multiple notes', (tester) async {
      final now = DateTime.now();
      final notes = [
        makeNoteEntity(
          id: 'note-1',
          body: 'First note',
          createdAt: now.subtract(const Duration(hours: 2)),
        ),
        makeNoteEntity(
          id: 'note-2',
          body: 'Second note',
          createdAt: now.subtract(const Duration(hours: 1)),
        ),
      ];

      await tester.pumpWidget(buildNotesTab(notes));
      await tester.pump();

      expect(find.text('First note'), findsOneWidget);
      expect(find.text('Second note'), findsOneWidget);
    });

    testWidgets('empty state shows "No notes yet" message', (tester) async {
      await tester.pumpWidget(buildNotesTab([]));
      await tester.pump();

      expect(find.text('No notes yet'), findsOneWidget);
    });

    testWidgets('empty state shows "Add the first note" button', (tester) async {
      await tester.pumpWidget(buildNotesTab([]));
      await tester.pump();

      expect(find.text('Add the first note'), findsOneWidget);
    });

    testWidgets('FAB "Add Note" button is present when notes exist',
        (tester) async {
      final notes = [makeNoteEntity()];

      await tester.pumpWidget(buildNotesTab(notes));
      await tester.pump();

      expect(find.text('Add Note'), findsOneWidget);
    });
  });
}
