import 'package:drift/drift.dart';

import '../database/app_database.dart';
import '../database/tables/sync_queue.dart';

part 'sync_queue_dao.g.dart';

/// DAO for the sync_queue outbox table.
///
/// The sync_queue is the transactional outbox for offline-first sync. Every local
/// mutation writes a row here atomically. The SyncEngine calls [getPendingItems]
/// to drain the queue in FIFO order when connectivity is available.
///
/// Lifecycle:
/// - [insertQueueItem]: called by CompanyDao/UserDao inside their transactions
/// - [getPendingItems]: called by SyncEngine to drain the queue
/// - [markSynced]: called after successful upload (deletes the row)
/// - [markParked]: called after 4xx error (won't be retried automatically)
/// - [updateAttemptCount]: called before each retry attempt
/// - [watchPendingCount]: drives the sync status indicator in the app bar
@DriftAccessor(tables: [SyncQueue])
class SyncQueueDao extends DatabaseAccessor<AppDatabase>
    with _$SyncQueueDaoMixin {
  SyncQueueDao(super.db);

  /// Insert a new outbox entry. Called within a Drift transaction alongside
  /// the entity write to guarantee atomicity.
  Future<void> insertQueueItem(SyncQueueCompanion item) async {
    await into(syncQueue).insert(item);
  }

  /// Returns all pending items ordered by [createdAt] ASC (FIFO).
  ///
  /// FIFO ordering preserves causality: a CREATE must reach the server before
  /// a subsequent UPDATE for the same entity.
  Future<List<SyncQueueData>> getPendingItems() {
    return (select(syncQueue)
          ..where((tbl) => tbl.status.equals('pending'))
          ..orderBy([(tbl) => OrderingTerm.asc(tbl.createdAt)]))
        .get();
  }

  /// Mark an item as successfully synced by deleting its row.
  ///
  /// Synced items are removed rather than kept — the entity table is the
  /// source of truth. Keeping synced rows would just grow the table.
  Future<int> markSynced(String id) {
    return (delete(syncQueue)..where((tbl) => tbl.id.equals(id))).go();
  }

  /// Mark an item as parked (permanent failure — 4xx errors).
  ///
  /// Parked items are excluded from [getPendingItems] and will not be retried
  /// automatically. They require manual intervention or a future retry cycle.
  Future<void> markParked(String id, {String? error}) async {
    await (update(syncQueue)..where((tbl) => tbl.id.equals(id))).write(
      SyncQueueCompanion(
        status: const Value('parked'),
        errorMessage: Value(error),
      ),
    );
  }

  /// Update the attempt count for an item before each retry.
  Future<void> updateAttemptCount(String id, int count) async {
    await (update(syncQueue)..where((tbl) => tbl.id.equals(id))).write(
      SyncQueueCompanion(attemptCount: Value(count)),
    );
  }

  /// Reactive stream of the count of pending items.
  ///
  /// Used by the sync status indicator in the app bar:
  /// - 0 → "All synced"
  /// - >0 → "N items pending" or "Syncing N of M..."
  Stream<int> watchPendingCount() {
    return (select(syncQueue)..where((tbl) => tbl.status.equals('pending')))
        .watch()
        .map((rows) => rows.length);
  }
}
