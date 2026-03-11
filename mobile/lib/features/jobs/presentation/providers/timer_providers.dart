import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/database/app_database.dart';
import '../../../../core/di/service_locator.dart';
import '../../../../features/auth/domain/auth_state.dart';
import '../../../../features/auth/presentation/providers/auth_provider.dart';
import '../../data/job_dao.dart';
import '../../data/time_entry_dao.dart';

// ─── DAO providers ────────────────────────────────────────────────────────────

/// Provider exposing [TimeEntryDao] from GetIt.
///
/// NOTE: GetIt is used here because [TimeEntryDao] is registered at startup.
/// (CLAUDE.md: document GetIt<->Riverpod tradeoffs)
final timeEntryDaoProvider = Provider<TimeEntryDao>((ref) {
  return getIt<TimeEntryDao>();
});

// ─── Timer state ──────────────────────────────────────────────────────────────

/// Immutable snapshot of the timer state.
///
/// A simple value class (not Freezed) — equality by fields for provider diffing.
///
/// [activeEntry]: the open TimeEntry row from Drift (null if clocked out).
/// [elapsedSeconds]: seconds since [activeEntry.clockedInAt] (live-incrementing).
/// [activeJobId]: convenience copy of activeEntry?.jobId.
class TimerState {
  final TimeEntry? activeEntry;
  final int elapsedSeconds;
  final String? activeJobId;

  const TimerState({
    this.activeEntry,
    this.elapsedSeconds = 0,
    this.activeJobId,
  });

  TimerState copyWith({
    TimeEntry? activeEntry,
    bool clearActiveEntry = false,
    int? elapsedSeconds,
    String? activeJobId,
    bool clearActiveJobId = false,
  }) {
    return TimerState(
      activeEntry: clearActiveEntry ? null : (activeEntry ?? this.activeEntry),
      elapsedSeconds: elapsedSeconds ?? this.elapsedSeconds,
      activeJobId:
          clearActiveJobId ? null : (activeJobId ?? this.activeJobId),
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is TimerState &&
          runtimeType == other.runtimeType &&
          activeEntry?.id == other.activeEntry?.id &&
          elapsedSeconds == other.elapsedSeconds &&
          activeJobId == other.activeJobId;

  @override
  int get hashCode =>
      Object.hash(activeEntry?.id, elapsedSeconds, activeJobId);
}

// ─── Timer notifier ───────────────────────────────────────────────────────────

/// Manages timer state: active clock-in/out session with 1-second tick.
///
/// DESIGN:
/// - [build()] restores active session from Drift on app restart — timer
///   resumes from the elapsed time since [clockedInAt] (not from 0).
/// - [clockIn] calls TimeEntryDao.clockIn (DAO auto-closes previous session),
///   then auto-transitions job from scheduled→in_progress.
/// - [clockOut] calls TimeEntryDao.clockOut, cancels the periodic timer.
/// - [Timer.periodic(1 second)] is owned by the notifier and cancelled on dispose.
///
/// CLAUDE.md: AsyncNotifier used because build() requires async init.
class TimerNotifier extends AsyncNotifier<TimerState> {
  Timer? _ticker;

  @override
  Future<TimerState> build() async {
    ref.onDispose(_cancelTicker);

    final authState = ref.read(authNotifierProvider);
    if (authState is! AuthAuthenticated) {
      return const TimerState();
    }

    final dao = ref.read(timeEntryDaoProvider);
    final contractorId = authState.userId;

    // Restore active session from Drift — handles app restart.
    final activeSession = await dao.watchActiveSession(contractorId).first;

    if (activeSession == null) {
      return const TimerState();
    }

    // Resume elapsed time from the persisted clockedInAt, not from 0.
    final elapsed =
        DateTime.now().difference(activeSession.clockedInAt).inSeconds;
    _startTicker();

    return TimerState(
      activeEntry: activeSession,
      elapsedSeconds: elapsed,
      activeJobId: activeSession.jobId,
    );
  }

  // ─── Public API ─────────────────────────────────────────────────────────────

  /// Clock in to [jobId].
  ///
  /// If already clocked in to the same job, does nothing.
  /// If clocked in to a different job, the DAO auto-clocks out the previous
  /// session before creating the new one (one-active-session invariant).
  ///
  /// If the job's status is 'scheduled', auto-transitions it to 'in_progress'.
  Future<void> clockIn(String jobId, String companyId) async {
    final current = state.value;

    // Already clocked in to this job — no-op.
    if (current?.activeJobId == jobId) return;

    final authState = ref.read(authNotifierProvider);
    if (authState is! AuthAuthenticated) return;

    final contractorId = authState.userId;
    final dao = ref.read(timeEntryDaoProvider);

    try {
      // DAO handles auto-clock-out of previous session in one transaction.
      final newEntryId = await dao.clockIn(
        companyId: companyId,
        jobId: jobId,
        contractorId: contractorId,
      );

      // Auto-transition job from scheduled → in_progress.
      await _maybeTransitionJobToInProgress(
        jobId: jobId,
        companyId: companyId,
        userId: authState.userId,
      );

      // Fetch the newly created entry for the state.
      final newEntry = await dao.watchActiveSession(contractorId).first;

      _cancelTicker();
      _startTicker();

      state = AsyncData(
        TimerState(
          activeEntry: newEntry,
          elapsedSeconds: 0,
          activeJobId: jobId,
        ),
      );

      debugPrint('[TimerNotifier] Clocked in — entryId=$newEntryId');
    } catch (e, st) {
      debugPrint('[TimerNotifier] clockIn failed: $e');
      state = AsyncError(e, st);
    }
  }

  /// Clock out of the current active session.
  ///
  /// Cancels the periodic ticker, writes clock-out to Drift, clears state.
  Future<void> clockOut() async {
    final current = state.value;
    if (current?.activeEntry == null) return;

    final entryId = current!.activeEntry!.id;

    try {
      _cancelTicker();

      final dao = ref.read(timeEntryDaoProvider);
      await dao.clockOut(entryId);

      state = const AsyncData(TimerState());

      debugPrint('[TimerNotifier] Clocked out — entryId=$entryId');
    } catch (e, st) {
      debugPrint('[TimerNotifier] clockOut failed: $e');
      state = AsyncError(e, st);
    }
  }

  // ─── Internals ──────────────────────────────────────────────────────────────

  void _startTicker() {
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) => _tick());
  }

  void _cancelTicker() {
    _ticker?.cancel();
    _ticker = null;
  }

  void _tick() {
    final current = state.value;
    if (current == null) return;

    state = AsyncData(
      current.copyWith(elapsedSeconds: current.elapsedSeconds + 1),
    );
  }

  /// Transitions a job from 'scheduled' → 'in_progress' on first clock-in.
  ///
  /// Reads the current job from Drift. If status is 'scheduled', writes the
  /// transition with an updated statusHistory entry.
  Future<void> _maybeTransitionJobToInProgress({
    required String jobId,
    required String companyId,
    required String userId,
  }) async {
    final jobDao = getIt<JobDao>();
    final now = DateTime.now();

    // Find the current job to read its status and history.
    final jobs = await jobDao
        .watchJobsByCompany(companyId)
        .first
        .then((list) => list.where((j) => j.id == jobId).toList());

    if (jobs.isEmpty) return;
    final job = jobs.first;

    if (job.status != 'scheduled') return;

    // Append transition entry.
    final history = List<Map<String, dynamic>>.from(job.statusHistory)
      ..add({
        'status': 'in_progress',
        'timestamp': now.toIso8601String(),
        'user_id': userId,
      });

    await jobDao.updateJobStatus(
      jobId,
      'in_progress',
      jsonEncode(history),
      job.version + 1,
    );

    debugPrint(
        '[TimerNotifier] Auto-transitioned job $jobId to in_progress on clock-in');
  }
}

/// Provider for [TimerNotifier].
///
/// Lives for the app lifetime — the timer state must persist across screens.
/// Not autoDispose: the timer ticker must keep running when navigating away.
final timerNotifierProvider =
    AsyncNotifierProvider<TimerNotifier, TimerState>(TimerNotifier.new);

// ─── Entries stream provider ──────────────────────────────────────────────────

/// Streams all time entries for a job, newest-first.
///
/// Used in [TimerScreen] session history list and [TimeTrackedSection] admin view.
/// autoDispose.family — one instance per jobId; disposed when screen is popped.
final timeEntriesForJobProvider = StreamProvider.autoDispose
    .family<List<TimeEntry>, String>((ref, jobId) {
  final dao = ref.watch(timeEntryDaoProvider);
  return dao.watchEntriesForJob(jobId);
});
