import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../di/service_locator.dart';
import 'connectivity_service.dart';
import 'sync_engine.dart';

/// Reactive provider combining SyncEngine status + connectivity state.
///
/// The provider listens to two streams:
/// 1. [SyncEngine.statusStream] — emits [SyncStatus] for allSynced / pending / syncing states
/// 2. [ConnectivityService.isOnlineStream] — emits bool for connectivity changes
///
/// When offline: emits [SyncStatus(SyncState.offline, 0)] regardless of queue count.
/// When online: emits status from [SyncEngine.statusStream].
///
/// This is a stream provider so the UI reactively updates without polling.
/// ConsumerWidgets watch this via `ref.watch(syncStatusProvider)` which returns
/// AsyncValue<SyncStatus> that should be handled with `.when()` or `.value`.
///
/// The initial value emitted is [SyncStatus(SyncState.allSynced, 0)] until
/// the first real status update arrives — this avoids showing a loading spinner
/// on app open (user decision: show cached data immediately, no loading spinner).
final syncStatusProvider =
    StreamProvider.autoDispose<SyncStatus>((ref) async* {
  final syncEngine = getIt<SyncEngine>();
  final connectivityService = getIt<ConnectivityService>();

  // Track the current online state. We start by emitting allSynced so the
  // UI can display immediately with cached data and no loading spinner.
  bool isOnline = true;

  // Emit initial "all synced" so the app bar shows something immediately.
  yield const SyncStatus(SyncState.allSynced, 0);

  // Merge the two streams. Because Dart doesn't have built-in stream
  // merging for async generators, we use a simple approach: listen to
  // connectivity stream changes and yield accordingly, and listen to
  // engine status stream changes.
  //
  // We use StreamController to merge both streams into one.
  await for (final event in _mergeStreams(
    connectivityService.isOnlineStream.map(_ConnectivityEvent.new),
    syncEngine.statusStream.map(_EngineEvent.new),
  )) {
    if (event is _ConnectivityEvent) {
      isOnline = event.isOnline;
      if (!isOnline) {
        // Device went offline — immediately emit offline status.
        yield const SyncStatus(SyncState.offline, 0);
      } else {
        // Back online — do NOT yield here. The SyncEngine will emit its own
        // status (syncing -> allSynced) as it drains the queue via
        // _onConnectivityRestored(). Yielding a default here would race with
        // and overwrite the engine's syncing state, causing the UI to never
        // show "Syncing 1 of 1...".
        //
        // If the queue is empty, drainQueue() emits allSynced itself.
        // If the queue has items, drainQueue() emits syncing first.
        // Either way, the engine's own emission is the correct source of truth.
      }
    } else if (event is _EngineEvent) {
      if (isOnline) {
        yield event.status;
      }
      // When offline, engine status updates are silently swallowed —
      // we always show the offline status while connectivity is down.
    }
  }
});

/// Merge two streams into a single stream of a common supertype [_StreamEvent].
Stream<_StreamEvent> _mergeStreams(
  Stream<_ConnectivityEvent> connectivity,
  Stream<_EngineEvent> engine,
) async* {
  // Use async* with StreamController to merge without external packages.
  final controller = StreamController<_StreamEvent>.broadcast();

  StreamSubscription<_ConnectivityEvent>? connectivitySub;
  StreamSubscription<_EngineEvent>? engineSub;

  connectivitySub = connectivity.listen(
    controller.add,
    onError: controller.addError,
    onDone: () {
      connectivitySub?.cancel();
      if (engineSub == null) controller.close();
    },
  );

  engineSub = engine.listen(
    controller.add,
    onError: controller.addError,
    onDone: () {
      engineSub?.cancel();
      if (connectivitySub == null) controller.close();
    },
  );

  yield* controller.stream;
}

// ---------------------------------------------------------------------------
// Internal tagged-union types for stream merging
// ---------------------------------------------------------------------------

sealed class _StreamEvent {}

final class _ConnectivityEvent extends _StreamEvent {
  _ConnectivityEvent(this.isOnline);
  final bool isOnline;
}

final class _EngineEvent extends _StreamEvent {
  _EngineEvent(this.status);
  final SyncStatus status;
}
