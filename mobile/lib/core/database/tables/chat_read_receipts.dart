import 'package:drift/drift.dart';

/// Drift table definition for ChatReadReceipt entities.
///
/// Tracks the last-read sequence number per user per thread. Used to
/// compute unread counts and show "seen by" indicators in the chat UI.
///
/// Receipt rows are upserted (not appended) — one row per (threadId, userId)
/// pair representing the current read position for that user.
///
/// [id] is a composite key string "{threadId}:{userId}" assigned by the
/// backend for stable upserting; alternatively the backend may use a UUID.
class ChatReadReceipts extends Table {
  /// Unique receipt ID — backend-assigned UUID or composite key.
  TextColumn get id => text()();

  /// Tenant scope — matches JWT companyId.
  TextColumn get companyId => text()();

  /// FK to chat_threads.id — soft reference.
  TextColumn get threadId => text()();

  /// FK to users.id — the user whose read position this tracks.
  TextColumn get userId => text()();

  /// Display name of the user at time of receipt (denormalized).
  TextColumn get userName => text()();

  /// The highest [seq] number this user has read in the thread.
  IntColumn get lastReadSeq => integer()();

  /// Timestamp when the user last read up to [lastReadSeq].
  DateTimeColumn get readAt => dateTime()();

  @override
  Set<Column> get primaryKey => {id};
}
