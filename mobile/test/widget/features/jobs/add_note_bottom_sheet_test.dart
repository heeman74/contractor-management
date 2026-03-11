import 'package:flutter_test/flutter_test.dart';

void main() {
  group('AddNoteBottomSheet', () {
    test('renders text field and attachment buttons',
        skip: 'Wave 0 stub — implementation in plan 06-03', () {
      // Will test: bottom sheet contains a TextField for body and buttons for camera/gallery
    });

    test('save disabled when body empty and no attachments',
        skip: 'Wave 0 stub — implementation in plan 06-03', () {
      // Will test: Save/Submit button is disabled when text is empty and no attachments selected
    });

    test('save calls NoteDao.insertNote',
        skip: 'Wave 0 stub — implementation in plan 06-03', () {
      // Will test: tapping Save calls NoteDao.insertNote with the entered body text
    });
  });
}
