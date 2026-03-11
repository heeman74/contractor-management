import 'package:flutter_test/flutter_test.dart';

void main() {
  group('NoteDao', () {
    test('insertNote creates note with sync queue entry',
        skip: 'Wave 0 stub — implementation in plan 06-02', () {
      // Will test: insertNote writes to notes table and enqueues a sync_queue entry
    });

    test('watchNotesForJob returns newest first',
        skip: 'Wave 0 stub — implementation in plan 06-02', () {
      // Will test: Stream emits notes ordered by created_at DESC for the given job_id
    });

    test('watchNotesForJob excludes soft-deleted',
        skip: 'Wave 0 stub — implementation in plan 06-06', () {
      // Will test: Notes with deleted_at set are filtered out of the stream
    });
  });
}
