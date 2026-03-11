import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../di/service_locator.dart';
import '../../features/jobs/presentation/services/attachment_upload_service.dart';
import 'connectivity_service.dart';
import 'sync_engine.dart';

/// Reactive provider combining SyncEngine status + connectivity state + upload progress.
///
/// The provider listens to three streams:
/// 1. [SyncEngine.statusStream] — emits [SyncStatus] for allSynced / pending / syncing states
/// 2. [ConnectivityService.isOnlineStream] — emits bool for connectivity changes
/// 3. [AttachmentUploadService.progressStream] — emits upload progress (total, completed)
///
/// When offline: emits [SyncStatus(SyncState.offline, 0)] regardless of queue count.
/// When online: emits status from [SyncEngine.statusStream].
/// When uploads are in progress: augments status subtitle with upload counts per
/// user decision: "3 items synced, 5 photos uploading (2/5)".
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
  final attachmentUploadService = getIt<AttachmentUploadService>();

  // Track the current online state and last known sync status.
  bool isOnline = true;
  SyncStatus lastStatus = const SyncStatus(SyncState.allSynced, 0);

  // Emit initial "all synced" so the app bar shows something immediately.
  yield lastStatus;

  // Merge three streams: connectivity, engine status, and upload progress.
  // StreamController used for merging without external dependencies (RxDart).
  await for (final event in _mergeThreeStreams(
    connectivityService.isOnlineStream.map(_ConnectivityEvent.new),
    syncEngine.statusStream.map(_EngineEvent.new),
    attachmentUploadService.progressStream.map(
      (progress) => _UploadEvent(progress.total, progress.completed),
    ),
  )) {
    if (event is _ConnectivityEvent) {
      isOnline = event.isOnline;
      if (!isOnline) {
        // Device went offline — immediately emit offline status.
        lastStatus = const SyncStatus(SyncState.offline, 0);
        yield lastStatus;
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
        lastStatus = event.status;
        yield lastStatus;
      }
      // When offline, engine status updates are silently swallowed —
      // we always show the offline status while connectivity is down.
    } else if (event is _UploadEvent) {
      if (isOnline) {
        // Merge upload progress into the current status.
        lastStatus = lastStatus.withUploadProgress(
          uploadTotal: event.uploadTotal,
          uploadCompleted: event.uploadCompleted,
        );
        yield lastStatus;
      }
    }
  }
});

/// Merge three streams into a single stream of a common supertype [_StreamEvent].
Stream<_StreamEvent> _mergeThreeStreams(
  Stream<_ConnectivityEvent> connectivity,
  Stream<_EngineEvent> engine,
  Stream<_UploadEvent> upload,
) async* {
  // Use async* with StreamController to merge without external packages.
  final controller = StreamController<_StreamEvent>.broadcast();
  var activeSubs = 3;

  void onDone() {
    activeSubs--;
    if (activeSubs == 0) controller.close();
  }

  connectivity.listen(
    controller.add,
    onError: controller.addError,
    onDone: onDone,
  );

  engine.listen(
    controller.add,
    onError: controller.addError,
    onDone: onDone,
  );

  upload.listen(
    controller.add,
    onError: controller.addError,
    onDone: onDone,
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

/// Upload progress event from [AttachmentUploadService.progressStream].
final class _UploadEvent extends _StreamEvent {
  _UploadEvent(this.uploadTotal, this.uploadCompleted);
  final int uploadTotal;
  final int uploadCompleted;
}
