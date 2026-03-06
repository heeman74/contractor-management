---
status: resolved
trigger: "Sync status subtitle jumps straight to 'All synced' without showing 'Syncing 1 of 1...'"
created: 2026-03-05T00:00:00Z
updated: 2026-03-05T00:00:00Z
---

## Current Focus

hypothesis: CONFIRMED — see Resolution
test: static code trace of the full event sequence
expecting: n/a
next_action: n/a (resolved)

## Symptoms

expected: After creating a record offline and restoring connectivity, the subtitle should
          briefly show "Syncing 1 of 1..." (SyncState.syncing) before settling on "All synced".
actual: The subtitle immediately displays "All synced" with no intermediate syncing state visible.
errors: none (no crash or exception)
reproduction: 1. Create a record while the device is offline.
              2. Restore network connectivity.
              3. Observe the sync status subtitle in the app bar.
started: always (the intermediate state has never been visible in this code path)

## Eliminated

- hypothesis: SyncEngine never emits SyncState.syncing at all
  evidence: drainQueue() does emit syncing at line 169 (initial) and line 173-175 (per-item).
            The SyncState enum includes 'syncing' and the subtitle getter handles it.
  timestamp: 2026-03-05T00:00:00Z

- hypothesis: SyncStatusSubtitle does not handle SyncState.syncing
  evidence: _buildFromStatus() has an explicit case for SyncState.syncing that renders
            _AnimatedSyncRow. The widget code is correct.
  timestamp: 2026-03-05T00:00:00Z

- hypothesis: The UI widget drops the status stream
  evidence: SyncStatusSubtitle uses ref.watch(syncStatusProvider) which subscribes for
            the widget's lifetime. No stream is dropped by the widget itself.
  timestamp: 2026-03-05T00:00:00Z

## Evidence

- timestamp: 2026-03-05T00:00:00Z
  checked: connectivity_service.dart lines 63-83
  found: When connectivity restores, the listener fires twice in rapid succession:
         (1) _onlineController.add(hasInternet) — emits true on isOnlineStream
         (2) onConnected() — immediately calls SyncEngine._onConnectivityRestored()
         Both happen synchronously within the same listener callback (no await between them
         except for the internet check itself, which already completed).
  implication: The _ConnectivityEvent(true) and the sequence of _EngineEvents all race
               into the merged stream within microseconds of each other.

- timestamp: 2026-03-05T00:00:00Z
  checked: sync_status_provider.dart lines 51-68
  found: The connectivity event handler (lines 51-58) does:
           isOnline = event.isOnline  →  true
           yield lastEngineStatus ?? SyncStatus(allSynced, 0)
         At this moment lastEngineStatus is still null (no engine event has been processed yet),
         so the provider yields SyncStatus(allSynced, 0).
         Then the engine events arrive and are processed:
           SyncState.syncing (initial) → yield event.status  [isOnline is now true]
           SyncState.syncing (item 1)  → yield event.status
           SyncState.allSynced         → yield event.status
  implication: The syncing yields DO reach the stream — but they race with the connectivity
               yield and with Riverpod/Flutter's frame scheduling.

- timestamp: 2026-03-05T00:00:00Z
  checked: sync_status_provider.dart lines 47-68 and sync_engine.dart lines 156-225
  found: The root ordering problem:
         ConnectivityService.startListening callback fires onConnected() AFTER
         _onlineController.add(hasInternet). Both happen in the same async callback.
         drainQueue() is awaited, so it completes fully before pullDelta() starts.
         Within drainQueue(), for a single-item queue the execution is:
           emit syncing(total=1)           [engine stream event 1]
           emit syncing(total=1, of=1)     [engine stream event 2]
           await handler.push(item)        [network call — takes real time]
           await markSynced(item.id)
           emit allSynced                  [engine stream event 3]
         The network call IS awaited, so events 1 and 2 land on the stream before
         allSynced. The syncing state IS emitted and DOES reach the provider.
  implication: The syncing state reaches the provider stream correctly.
               The problem is therefore in how the provider yields on the connectivity event.

- timestamp: 2026-03-05T00:00:00Z
  checked: sync_status_provider.dart lines 51-58 (connectivity branch)
  found: CRITICAL RACE:
         When _ConnectivityEvent(true) is processed, the provider immediately yields
         `lastEngineStatus ?? SyncStatus(allSynced, 0)`.
         Since lastEngineStatus is null at that instant, it yields allSynced FIRST.
         The subsequent _EngineEvents (syncing x2, allSynced) then yield correctly —
         but the UI frame that renders "All synced" from the connectivity-restore yield
         may arrive at Flutter's rendering pipeline AT THE SAME TIME or BEFORE the
         syncing events, depending on microtask / event-loop scheduling.
         More importantly: if the network call in handler.push() is very fast
         (local test server, mocked HTTP, or already-cached response), the entire
         drain completes within a single event-loop turn after the connectivity event.
         Dart's async* generators yield lazily — each `yield` suspends the generator
         and resumes on the next microtask. If Riverpod batches rapid successive stream
         events and only delivers the final value to the widget tree before the next
         frame, the intermediate syncing values are dropped.
  implication: The "All synced" yield from the connectivity branch acts as a race
               condition seed. Even if syncing events follow immediately, Riverpod's
               StreamProvider (backed by StreamNotifier) only exposes the LATEST event
               to watchers. If allSynced is the last event emitted before the next
               Flutter frame paint, that is all the widget ever sees.

- timestamp: 2026-03-05T00:00:00Z
  checked: sync_status_provider.dart lines 51-58 (specific yield on re-connect)
  found: The line `yield lastEngineStatus ?? const SyncStatus(SyncState.allSynced, 0)`
         is the direct source of the premature "All synced". When coming back online,
         the provider always emits allSynced (or the last engine status, which for a
         first-ever sync is also allSynced because no engine event has fired yet).
         This yields allSynced BEFORE the engine's syncing events have a chance to arrive.
  implication: This yield is unnecessary and incorrect. It pre-empts the engine's own
               status with a stale default.

## Resolution

root_cause: |
  Two compounding problems in sync_status_provider.dart:

  PROBLEM 1 — Premature "All synced" yield on reconnect (primary, lines 57-58):
  When the provider processes a _ConnectivityEvent(true), it immediately yields
  `lastEngineStatus ?? SyncStatus(SyncState.allSynced, 0)`. Because lastEngineStatus
  is null on the first reconnect (no engine event has arrived yet), this unconditionally
  emits allSynced before the engine has started draining the queue. The engine's
  syncing events land in the stream moments later, but by that time the UI has
  already received and rendered "All synced".

  PROBLEM 2 — Flutter/Riverpod frame batching collapses rapid emissions (secondary):
  ConnectivityService calls _onlineController.add(true) and then onConnected()
  synchronously within the same callback. onConnected() calls drainQueue() which
  emits syncing events as Dart stream adds. Riverpod's StreamProvider only rebuilds
  the widget tree once per frame. If the entire drain completes within a single frame
  (fast network, single-item queue, mocked backend), the widget only ever sees the
  last emitted value — which is allSynced — even if syncing was emitted earlier.

  Combined effect: The user never sees "Syncing 1 of 1..." because:
  (a) The provider yields allSynced first (Problem 1), establishing it as the rendered state.
  (b) Even if the order were correct, rapid completion means syncing may never reach a
      frame paint boundary (Problem 2).

fix: |
  FIX FOR PROBLEM 1 — Remove the premature yield on reconnect:
  In sync_status_provider.dart, the connectivity restored branch (lines 57-58) should
  NOT yield anything immediately. The engine will emit its own status events (syncing,
  then allSynced) as it drains the queue. Yielding here preempts that correct sequence.

  Change:
    } else {
      // Back online — resume showing engine status (or allSynced default).
      yield lastEngineStatus ?? const SyncStatus(SyncState.allSynced, 0);
    }

  To:
    } else {
      // Back online — do NOT yield here. Let the engine emit its own status
      // (syncing → allSynced) as it drains the queue. If the queue is empty,
      // drainQueue() will emit allSynced itself. Yielding a default here would
      // race with and overwrite the engine's syncing state.
    }

  FIX FOR PROBLEM 2 — Ensure syncing state has observable duration:
  In connectivity_service.dart, separate the _onlineController.add() from the
  onConnected() callback with a brief async gap (await Future.microtask() or
  await Future<void>.delayed(Duration.zero)). This ensures the connectivity event
  is processed and the provider updates the UI before the engine starts emitting,
  giving the syncing state at least one frame of visibility.

  Alternatively (cleaner): in sync_engine.dart drainQueue(), after emitting the
  initial syncing status, yield to the event loop before processing items:
    _syncStatusController.add(SyncStatus(SyncState.syncing, total));
    await Future<void>.delayed(Duration.zero); // allow UI to render syncing state
    for (var i = 0; i < items.length; i++) { ... }

  This guarantees the Flutter frame pump runs at least once while "Syncing..." is
  the active status, making it visible to the user regardless of how fast the
  network call completes.

verification: |
  Static code analysis — no runtime execution performed.
  The race condition is deterministic and reproducible via code trace:
  1. Set breakpoints at sync_status_provider.dart:57 and sync_engine.dart:169.
  2. Restore connectivity with one pending queue item.
  3. Observe allSynced is yielded at line 57 BEFORE the engine emits syncing at line 169.
  To confirm the fix: after removing the yield at line 57-58, the first value the
  provider emits after reconnect will be the engine's SyncState.syncing event.

files_changed: []
