/// Unit tests for TimerState value class and TimerNotifier logic.
///
/// Tests cover:
/// 1. TimerState defaults to no active entry and 0 elapsed seconds
/// 2. TimerState.copyWith preserves unchanged fields
/// 3. TimerState.copyWith(clearActiveEntry: true) sets activeEntry to null
/// 4. TimerState.copyWith(clearActiveJobId: true) sets activeJobId to null
/// 5. TimerState equality: equal when same activeEntry id, elapsedSeconds, activeJobId
/// 6. TimerState equality: not equal when elapsedSeconds differ
/// 7. TimerState hashCode: consistent with equality
///
/// Note: TimerNotifier.build/clockIn/clockOut require Riverpod ref + GetIt + Drift DAO.
/// Those are tested in timer_screen_test.dart with stub notifiers.
/// These tests verify the TimerState value class logic in isolation.
library;

import 'package:contractorhub/core/database/app_database.dart' hide UserRole;
import 'package:contractorhub/features/jobs/presentation/providers/timer_providers.dart';
import 'package:flutter_test/flutter_test.dart';

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

TimeEntry _makeTimeEntry({
  String id = 'entry-1',
  String jobId = 'job-1',
  String sessionStatus = 'active',
  DateTime? clockedInAt,
  DateTime? clockedOutAt,
  int? durationSeconds,
}) {
  final now = DateTime.now();
  return TimeEntry(
    id: id,
    companyId: 'co-1',
    jobId: jobId,
    contractorId: 'contractor-1',
    clockedInAt: clockedInAt ?? now.subtract(const Duration(minutes: 30)),
    clockedOutAt: clockedOutAt,
    durationSeconds: durationSeconds,
    sessionStatus: sessionStatus,
    adjustmentLog: '[]',
    version: 1,
    createdAt: now,
    updatedAt: now,
  );
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

void main() {
  group('TimerState', () {
    test('defaults to no active entry and 0 elapsed seconds', () {
      const state = TimerState();
      expect(state.activeEntry, isNull);
      expect(state.elapsedSeconds, 0);
      expect(state.activeJobId, isNull);
    });

    test('copyWith preserves unchanged fields', () {
      final entry = _makeTimeEntry();
      final state = TimerState(
        activeEntry: entry,
        elapsedSeconds: 120,
        activeJobId: 'job-1',
      );

      final updated = state.copyWith(elapsedSeconds: 121);
      expect(updated.activeEntry?.id, entry.id);
      expect(updated.elapsedSeconds, 121);
      expect(updated.activeJobId, 'job-1');
    });

    test('copyWith(clearActiveEntry: true) sets activeEntry to null', () {
      final entry = _makeTimeEntry();
      final state = TimerState(
        activeEntry: entry,
        elapsedSeconds: 60,
        activeJobId: 'job-1',
      );

      final cleared = state.copyWith(clearActiveEntry: true);
      expect(cleared.activeEntry, isNull);
      expect(cleared.elapsedSeconds, 60);
    });

    test('copyWith(clearActiveJobId: true) sets activeJobId to null', () {
      final state = TimerState(
        activeEntry: _makeTimeEntry(),
        elapsedSeconds: 300,
        activeJobId: 'job-1',
      );

      final cleared = state.copyWith(clearActiveJobId: true);
      expect(cleared.activeJobId, isNull);
      expect(cleared.activeEntry, isNotNull);
    });

    test('equality: equal when same activeEntry id, elapsedSeconds, activeJobId',
        () {
      final entry = _makeTimeEntry(id: 'same-id');

      final state1 = TimerState(
        activeEntry: entry,
        elapsedSeconds: 42,
        activeJobId: 'job-1',
      );

      // Create a different TimeEntry instance with same id
      final entry2 = _makeTimeEntry(id: 'same-id');
      final state2 = TimerState(
        activeEntry: entry2,
        elapsedSeconds: 42,
        activeJobId: 'job-1',
      );

      expect(state1, equals(state2));
    });

    test('equality: not equal when elapsedSeconds differ', () {
      final entry = _makeTimeEntry();

      final state1 = TimerState(
        activeEntry: entry,
        elapsedSeconds: 10,
        activeJobId: 'job-1',
      );

      final state2 = TimerState(
        activeEntry: entry,
        elapsedSeconds: 11,
        activeJobId: 'job-1',
      );

      expect(state1, isNot(equals(state2)));
    });

    test('hashCode: consistent with equality', () {
      final entry = _makeTimeEntry(id: 'hash-test');

      final state1 = TimerState(
        activeEntry: entry,
        elapsedSeconds: 99,
        activeJobId: 'job-1',
      );

      final entry2 = _makeTimeEntry(id: 'hash-test');
      final state2 = TimerState(
        activeEntry: entry2,
        elapsedSeconds: 99,
        activeJobId: 'job-1',
      );

      expect(state1.hashCode, equals(state2.hashCode));
    });

    test('default state has correct hashCode', () {
      const s1 = TimerState();
      const s2 = TimerState();
      expect(s1.hashCode, equals(s2.hashCode));
      expect(s1, equals(s2));
    });
  });
}
