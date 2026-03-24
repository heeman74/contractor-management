import 'package:drift/drift.dart' hide isNotNull, isNull;

import '../../../core/database/app_database.dart';
import '../../../core/database/tables/chat_messages.dart';
import '../../../core/database/tables/chat_read_receipts.dart';
import '../../../core/database/tables/chat_threads.dart';

part 'chat_dao.g.dart';

/// Drift DAO for chat persistence operations.
///
/// Provides reactive streams for thread and message lists, batch insert
/// for sync catch-up, and maintenance operations (trim, read status).
///
/// Import pattern uses `hide isNotNull, isNull` to avoid matcher conflicts
/// with test matchers when this file is imported in test contexts.
@DriftAccessor(tables: [ChatThreads, ChatMessages, ChatReadReceipts])
class ChatDao extends DatabaseAccessor<AppDatabase> with _$ChatDaoMixin {
  ChatDao(super.db);

  // ---------------------------------------------------------------------------
  // Thread queries
  // ---------------------------------------------------------------------------

  /// Reactive stream of all active threads for a project, newest first.
  ///
  /// Ordered by [lastMessageAt] DESC (nulls last) so threads with recent
  /// activity surface at the top of the inbox list.
  Stream<List<ChatThread>> watchThreadsByProject(String projectId) {
    return (select(chatThreads)
          ..where(
            (tbl) =>
                tbl.projectId.equals(projectId) &
                tbl.deletedAt.isNull(),
          )
          ..orderBy([
            (tbl) => OrderingTerm(
                  expression: tbl.lastMessageAt,
                  mode: OrderingMode.desc,
                  nulls: NullsOrder.last,
                ),
          ]))
        .watch();
  }

  /// Insert or replace a thread (upserts by primary key).
  Future<void> upsertThread(ChatThreadsCompanion thread) async {
    await into(chatThreads).insertOnConflictUpdate(thread);
  }

  /// Update local-only unread count on a thread after marking as read.
  Future<void> markThreadRead(String threadId, int unreadCount) async {
    await (update(chatThreads)
          ..where((tbl) => tbl.id.equals(threadId)))
        .write(ChatThreadsCompanion(
          unreadCount: Value(unreadCount),
        ));
  }

  // ---------------------------------------------------------------------------
  // Message queries
  // ---------------------------------------------------------------------------

  /// Reactive stream of active messages in a thread, ordered by [seq] ASC.
  ///
  /// Deleted messages (softDeleted) are excluded from the stream.
  Stream<List<ChatMessage>> watchMessages(String threadId) {
    return (select(chatMessages)
          ..where(
            (tbl) =>
                tbl.threadId.equals(threadId) &
                tbl.deletedAt.isNull(),
          )
          ..orderBy([(tbl) => OrderingTerm.asc(tbl.seq)]))
        .watch();
  }

  /// Insert or replace a single message (upserts by primary key).
  Future<void> insertMessage(ChatMessagesCompanion msg) async {
    await into(chatMessages).insertOnConflictUpdate(msg);
  }

  /// Batch insert messages — used for sync catch-up after reconnect.
  Future<void> batchInsertMessages(
      List<ChatMessagesCompanion> messages) async {
    await batch((b) {
      for (final msg in messages) {
        b.insertOnConflictUpdate(chatMessages, msg);
      }
    });
  }

  /// Update the [status] field on a message (pending → sent / failed).
  Future<void> updateMessageStatus(String id, String status) async {
    await (update(chatMessages)..where((tbl) => tbl.id.equals(id)))
        .write(ChatMessagesCompanion(status: Value(status)));
  }

  /// Trim the local cache to the latest [keep] messages for a thread.
  ///
  /// Deletes messages where seq < (max_seq - keep) to prevent unbounded
  /// local storage growth. Implements D-13 local cache ceiling (100 msgs).
  Future<void> trimMessages(String threadId, {int keep = 100}) async {
    // Find the max seq for the thread
    final maxSeqExpr = chatMessages.seq.max();
    final maxQuery = selectOnly(chatMessages)
      ..addColumns([maxSeqExpr])
      ..where(chatMessages.threadId.equals(threadId) &
          chatMessages.deletedAt.isNull());
    final maxResult = await maxQuery.getSingleOrNull();
    final maxSeq = maxResult?.read(maxSeqExpr);

    if (maxSeq == null) return; // no messages yet

    final cutoff = maxSeq - keep;
    if (cutoff <= 0) return; // fewer than keep messages — nothing to trim

    await (delete(chatMessages)
          ..where(
            (tbl) =>
                tbl.threadId.equals(threadId) &
                tbl.seq.isSmallerThanValue(cutoff),
          ))
        .go();
  }

  /// Returns the maximum [seq] for a thread (for cursor-based pagination).
  ///
  /// Returns 0 if the thread has no messages cached locally.
  Future<int> getLastSeq(String threadId) async {
    final maxSeqExpr = chatMessages.seq.max();
    final query = selectOnly(chatMessages)
      ..addColumns([maxSeqExpr])
      ..where(
        chatMessages.threadId.equals(threadId) &
            chatMessages.deletedAt.isNull(),
      );
    final result = await query.getSingleOrNull();
    return result?.read(maxSeqExpr) ?? 0;
  }

  // ---------------------------------------------------------------------------
  // Read receipt queries
  // ---------------------------------------------------------------------------

  /// Insert or replace a read receipt (upserts by primary key).
  Future<void> upsertReadReceipt(ChatReadReceiptsCompanion receipt) async {
    await into(chatReadReceipts).insertOnConflictUpdate(receipt);
  }
}
