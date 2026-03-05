import 'package:drift/drift.dart';

/// Delta sync cursor table — tracks the high-water mark for pull-based sync.
///
/// Single-row pattern: only one row with key='main' ever exists. The cursor
/// stores the timestamp of the last successful delta pull from the backend.
///
/// [lastPulledAt] is null when the app has never synced (first launch). The
/// SyncEngine uses null to detect first-launch and trigger a full data download
/// instead of a delta pull.
///
/// Cursor-based delta sync: GET /sync?cursor=<lastPulledAt> returns all entities
/// changed since that timestamp. On success, the cursor is updated to the
/// server-returned timestamp for the next delta pull.
class SyncCursor extends Table {
  /// Row key — always 'main' (single-row pattern).
  TextColumn get key => text().withDefault(const Constant('main'))();

  /// Timestamp of last successful delta pull. Null means never synced (first launch).
  DateTimeColumn get lastPulledAt => dateTime().nullable()();

  @override
  Set<Column> get primaryKey => {key};
}
