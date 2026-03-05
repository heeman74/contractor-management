import 'package:drift/drift.dart';

import '../database/app_database.dart';
import '../database/tables/sync_cursor.dart';

part 'sync_cursor_dao.g.dart';

/// DAO for the sync_cursor table — tracks the delta pull high-water mark.
///
/// Single-row pattern: only the 'main' row ever exists. The cursor stores
/// the timestamp of the last successful delta pull from the backend.
///
/// First-launch detection: [getCursor] returns null when no row exists or
/// [lastPulledAt] is null. The SyncEngine uses this to trigger a full data
/// download on first sync instead of a delta pull.
///
/// Cursor-based delta sync flow:
/// 1. Call [getCursor] to get the last pull timestamp (null = first launch)
/// 2. GET /sync?cursor=<timestamp> (or full download if null)
/// 3. Process server response
/// 4. Call [updateCursor] with server-returned timestamp
@DriftAccessor(tables: [SyncCursor])
class SyncCursorDao extends DatabaseAccessor<AppDatabase>
    with _$SyncCursorDaoMixin {
  SyncCursorDao(super.db);

  /// Returns the last successful pull timestamp, or null if never synced.
  ///
  /// Null indicates first launch — the SyncEngine should perform a full
  /// data download rather than a delta pull.
  Future<DateTime?> getCursor() async {
    final row = await (select(syncCursor)
          ..where((tbl) => tbl.key.equals('main')))
        .getSingleOrNull();
    return row?.lastPulledAt;
  }

  /// Upsert the 'main' cursor row with the new pull timestamp.
  ///
  /// Called after every successful delta pull from the backend.
  /// Uses insertOnConflictUpdate to handle both first-time insert and
  /// subsequent updates.
  Future<void> updateCursor(DateTime timestamp) async {
    await into(syncCursor).insertOnConflictUpdate(
      SyncCursorCompanion.insert(
        key: const Value('main'),
        lastPulledAt: Value(timestamp),
      ),
    );
  }
}
