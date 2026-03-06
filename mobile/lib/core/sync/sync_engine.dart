import 'dart:async';

import 'package:dio/dio.dart';

import '../database/app_database.dart';
import '../network/dio_client.dart';
import 'connectivity_service.dart';
import 'sync_cursor_dao.dart';
import 'sync_queue_dao.dart';
import 'sync_registry.dart';

/// The sync state for use in [SyncStatus].
enum SyncState {
  /// Device has no internet connection.
  offline,

  /// All local mutations have been pushed and delta pull is current.
  allSynced,

  /// There are pending items in the sync queue waiting to be pushed.
  pending,

  /// Queue drain or delta pull is actively in progress.
  syncing,
}

/// Status value emitted on [SyncEngine.statusStream] for UI display.
///
/// Used by the app bar sync status indicator to show users the current
/// state of the offline sync system.
class SyncStatus {
  final SyncState state;
  final int pendingCount;
  final int? syncingOf;

  const SyncStatus(this.state, this.pendingCount, {this.syncingOf});

  /// Human-readable subtitle for the sync status indicator.
  ///
  /// Format matches user decision:
  /// - offline → 'Offline'
  /// - allSynced → 'All synced'
  /// - pending → 'N item(s) pending'
  /// - syncing → 'Syncing M of N...'
  String get subtitle => switch (state) {
        SyncState.offline => 'Offline',
        SyncState.allSynced => 'All synced',
        SyncState.pending => '$pendingCount item(s) pending',
        SyncState.syncing => 'Syncing $syncingOf of $pendingCount...',
      };

  @override
  String toString() => 'SyncStatus(state: $state, subtitle: $subtitle)';
}

/// Exponential backoff delays for 5xx/timeout retry attempts.
///
/// Matches user decision: 1s/2s/4s/8s/16s up to 5 attempts.
const _backoffDelays = [
  Duration(seconds: 1),
  Duration(seconds: 2),
  Duration(seconds: 4),
  Duration(seconds: 8),
  Duration(seconds: 16),
];

/// Maximum retry attempts before leaving the item as pending.
///
/// After max retries, item stays in queue with reset attemptCount = 0.
/// It will retry on the next connectivity cycle (next time network restores).
const _maxAttempts = 5;

/// Orchestrates all push/pull operations for the offline-first sync system.
///
/// [SyncEngine] is the heart of the sync engine:
/// - [drainQueue]: processes the outbox (sync_queue) in FIFO order, pushing
///   each item to the backend via its registered [SyncHandler].
/// - [pullDelta]: fetches changes from the backend since the last cursor,
///   upserts results into Drift tables via [SyncHandler.applyPulled].
/// - [ConnectivityService] triggers [_onConnectivityRestored] on real network
///   restore, which calls drain + pull automatically.
///
/// 4xx responses are parked immediately (user error, no retry).
/// 5xx / timeout responses are retried with exponential backoff (1-16s, max 5 attempts).
/// After max retries: item stays pending with attemptCount reset to 0 for the
/// next connectivity cycle.
///
/// Drift table streams auto-update the UI when tables change — no manual
/// notification is needed after [pullDelta] writes to Drift.
class SyncEngine {
  final AppDatabase _db;
  final DioClient _dioClient;
  final SyncRegistry _registry;
  final ConnectivityService _connectivityService;

  late final SyncQueueDao _syncQueueDao;
  late final SyncCursorDao _syncCursorDao;

  /// Guards against re-entrant drain calls.
  ///
  /// If [drainQueue] is already running when connectivity restores again,
  /// the second call returns immediately. This prevents duplicate concurrent
  /// pushes of the same queue items.
  bool _isSyncing = false;

  final _syncStatusController = StreamController<SyncStatus>.broadcast();

  SyncEngine(
    this._db,
    this._dioClient,
    this._registry,
    this._connectivityService,
  ) {
    _syncQueueDao = _db.syncQueueDao;
    _syncCursorDao = _db.syncCursorDao;
  }

  /// Stream of [SyncStatus] updates for the sync status UI indicator.
  ///
  /// Emits on: start of drain, each item processed, completion.
  /// UI should listen to this stream to display sync state in the app bar.
  Stream<SyncStatus> get statusStream => _syncStatusController.stream;

  /// Start the connectivity listener.
  ///
  /// Called once from [setupServiceLocator] after all singletons are
  /// registered. Wires [ConnectivityService] to call [_onConnectivityRestored]
  /// when real internet access is detected.
  void initialize() {
    _connectivityService.startListening(_onConnectivityRestored);
  }

  /// Called by [ConnectivityService] when real internet access is confirmed.
  ///
  /// Runs drain + pull in sequence: pending local mutations are pushed first,
  /// then the delta is pulled from the server. This ordering ensures that
  /// local writes are not overwritten by an out-of-date server response.
  Future<void> _onConnectivityRestored() async {
    await drainQueue();
    await pullDelta();
  }

  /// Drain the sync queue — push all pending items to the backend.
  ///
  /// Processes items in FIFO order ([createdAt] ASC) one at a time. FIFO
  /// ordering preserves causality: a CREATE must reach the server before
  /// a subsequent UPDATE for the same entity.
  ///
  /// Error handling:
  /// - 4xx: [markParked] — permanent failure, will not be retried automatically
  /// - 5xx/timeout: increment [attemptCount], apply exponential backoff delay
  ///   - If [attemptCount] >= [_maxAttempts]: reset to 0, leave as pending
  ///     (will retry on next connectivity cycle)
  ///
  /// Emits [SyncStatus.syncing] updates throughout and final status on completion.
  Future<void> drainQueue() async {
    if (_isSyncing) return;
    _isSyncing = true;

    try {
      final items = await _syncQueueDao.getPendingItems();
      final total = items.length;

      if (total == 0) {
        _syncStatusController.add(const SyncStatus(SyncState.allSynced, 0));
        return;
      }

      _syncStatusController.add(SyncStatus(SyncState.syncing, total));

      // Yield to the event loop so Flutter can paint the "Syncing..." state
      // before we start processing items. Without this, if the queue is small
      // and the network is fast, drainQueue() can complete in a single frame
      // and the UI only ever sees the final allSynced state.
      await Future<void>.delayed(Duration.zero);

      for (var i = 0; i < items.length; i++) {
        final item = items[i];
        _syncStatusController.add(
          SyncStatus(SyncState.syncing, total, syncingOf: i + 1),
        );

        try {
          final handler = _registry.getHandler(item.entityType);
          await handler.push(item);
          await _syncQueueDao.markSynced(item.id);
        } on DioException catch (e) {
          final statusCode = e.response?.statusCode;
          final is4xx =
              statusCode != null && statusCode >= 400 && statusCode < 500;

          if (is4xx) {
            // Client error — park this item, do not retry
            await _syncQueueDao.markParked(
              item.id,
              error: e.message ?? 'HTTP $statusCode',
            );
          } else {
            // Server error or timeout — retry with exponential backoff
            final newCount = item.attemptCount + 1;
            if (newCount >= _maxAttempts) {
              // Max retries exhausted — reset attempt count for next cycle
              // Item stays pending and will be retried when connectivity restores again
              await _syncQueueDao.updateAttemptCount(item.id, 0);
            } else {
              await _syncQueueDao.updateAttemptCount(item.id, newCount);
              // Apply exponential backoff: index is newCount - 1 (0-based)
              final delayIndex = (newCount - 1).clamp(0, _backoffDelays.length - 1);
              await Future<void>.delayed(_backoffDelays[delayIndex]);
            }
          }
        } catch (e) {
          // Unexpected error (e.g., StateError for unregistered entity type)
          // Park to avoid infinite loop
          await _syncQueueDao.markParked(item.id, error: e.toString());
        }
      }

      // After drain, emit status based on remaining pending count
      final remaining = await _syncQueueDao.getPendingItems();
      if (remaining.isEmpty) {
        _syncStatusController.add(const SyncStatus(SyncState.allSynced, 0));
      } else {
        _syncStatusController.add(
          SyncStatus(SyncState.pending, remaining.length),
        );
      }
    } finally {
      _isSyncing = false;
    }
  }

  /// Pull changed entities from the backend since the last cursor timestamp.
  ///
  /// Flow:
  /// 1. Get last pull timestamp from [SyncCursorDao] (null = first launch)
  /// 2. GET /api/v1/sync?cursor=<isoTimestamp> — omit param on first launch
  ///    (server defaults to full download from epoch 2000-01-01)
  /// 3. For each entity type in response: call [SyncHandler.applyPulled] for each entity
  /// 4. Update cursor to server-returned [server_timestamp]
  ///
  /// Drift table writes trigger automatic UI stream updates — no manual
  /// notification is needed after this method completes.
  Future<void> pullDelta() async {
    try {
      final cursor = await _syncCursorDao.getCursor();

      // Build query params — omit cursor on first launch (server handles it)
      final Map<String, dynamic> queryParams = {};
      if (cursor != null) {
        queryParams['cursor'] = cursor.toUtc().toIso8601String();
      }

      final response = await _dioClient.instance.get<Map<String, dynamic>>(
        '/sync',
        queryParameters: queryParams.isNotEmpty ? queryParams : null,
      );

      final data = response.data;
      if (data == null) return;

      // Process each registered entity type from the response
      final List<dynamic>? companies = data['companies'] as List<dynamic>?;
      if (companies != null) {
        final handler = _registry.getHandler('company');
        for (final entity in companies) {
          await handler.applyPulled(entity as Map<String, dynamic>);
        }
      }

      final List<dynamic>? users = data['users'] as List<dynamic>?;
      if (users != null) {
        final handler = _registry.getHandler('user');
        for (final entity in users) {
          await handler.applyPulled(entity as Map<String, dynamic>);
        }
      }

      final List<dynamic>? userRoles = data['user_roles'] as List<dynamic>?;
      if (userRoles != null) {
        final handler = _registry.getHandler('user_role');
        for (final entity in userRoles) {
          await handler.applyPulled(entity as Map<String, dynamic>);
        }
      }

      // Update the cursor to the server's timestamp for the next delta pull
      final serverTimestamp = data['server_timestamp'] as String?;
      if (serverTimestamp != null) {
        await _syncCursorDao.updateCursor(DateTime.parse(serverTimestamp));
      }
    } on DioException {
      // Network failures during pull are non-fatal — next sync cycle will retry
      // The cursor is NOT updated, so the next pull will cover the same range
    }
  }

  /// Public convenience method: drain then pull.
  ///
  /// Called by pull-to-refresh gestures and foreground sync triggers.
  /// Same as [_onConnectivityRestored] but callable externally.
  Future<void> syncNow() async {
    await drainQueue();
    await pullDelta();
  }

  /// Cancel connectivity subscription and close the status stream.
  ///
  /// Must be called when the engine is no longer needed (typically never,
  /// since SyncEngine is a singleton for the app lifetime).
  void dispose() {
    _connectivityService.dispose();
    _syncStatusController.close();
  }
}
