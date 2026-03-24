import 'dart:async';
import 'dart:convert';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';

import '../../../core/database/app_database.dart';
import '../../../core/database/tables/sync_queue.dart';
import 'chat_ws_client.dart';

/// Offline message queue drain service for chat.
///
/// Listens to connectivity changes and drains SyncQueue entries with
/// entityType == 'chat_message' via the active WebSocket client when
/// connectivity is restored.
///
/// Message lifecycle:
///   1. [queueOfflineMessage] — writes ChatMessage (status='pending') and
///      SyncQueue entry atomically when offline.
///   2. On connectivity restore → [drainQueue] sends each pending entry via
///      [ChatWsClient.send] in FIFO order.
///   3. On server ACK (message echoed back with seq assigned) → SyncQueue
///      entry deleted, ChatMessage status updated to 'sent', seq stored.
///   4. On failure after 3 retries → entry parked, ChatMessage status 'failed'.
class ChatSyncService {
  ChatSyncService({
    required AppDatabase db,
    required ChatDao chatDao,
  })  : _db = db,
        _chatDao = chatDao;

  final AppDatabase _db;
  final ChatDao _chatDao;

  ChatWsClient? _wsClient;
  StreamSubscription<List<ConnectivityResult>>? _connectivitySubscription;
  StreamSubscription<Map<String, dynamic>>? _wsSubscription;

  // ---------------------------------------------------------------------------
  // Initialization
  // ---------------------------------------------------------------------------

  /// Attach a WebSocket client and begin listening for connectivity changes.
  ///
  /// Call this once when the chat screen opens with an active [wsClient].
  void attach(ChatWsClient wsClient) {
    _wsClient = wsClient;

    // Listen to WS messages for ACK processing.
    _wsSubscription = wsClient.messages.listen(_onWsMessage);

    // Listen to connectivity changes to drain offline queue on reconnect.
    _connectivitySubscription = Connectivity()
        .onConnectivityChanged
        .listen(_onConnectivityChanged);

    // Attempt an immediate drain in case we're already online.
    drainQueue();
  }

  /// Detach WebSocket client — call when leaving the chat screen.
  void detach() {
    _wsSubscription?.cancel();
    _wsSubscription = null;
    _connectivitySubscription?.cancel();
    _connectivitySubscription = null;
    _wsClient = null;
  }

  // ---------------------------------------------------------------------------
  // Offline message queueing
  // ---------------------------------------------------------------------------

  /// Queue a chat message for offline delivery.
  ///
  /// Writes the [ChatMessagesCompanion] (with status='pending') to Drift and
  /// adds a [SyncQueue] outbox entry in the same transaction.
  ///
  /// The [msg] must have [id], [threadId], [companyId], [senderId], and
  /// [senderName] set as non-absent Values — these are required for the
  /// outbox payload.
  Future<void> queueOfflineMessage(ChatMessagesCompanion msg) async {
    await _db.transaction(() async {
      // Write local message with pending status.
      await _chatDao.insertMessage(
        msg.copyWith(status: const Value('pending')),
      );

      // Build outbox payload from present companion fields.
      // Value<T> fields are always the actual type — no conditional checks needed.
      final msgId = msg.id.value;
      final now = DateTime.now();

      final payload = <String, dynamic>{
        'id': msgId,
        'threadId': msg.threadId.value,
        'companyId': msg.companyId.value,
        'senderId': msg.senderId.value,
        'senderName': msg.senderName.value,
        'content': msg.content.present ? msg.content.value : null,
        'mentions': msg.mentions.present ? msg.mentions.value : '[]',
        'mentionAll': msg.mentionAll.present && msg.mentionAll.value,
        'createdAt': msg.createdAt.present
            ? msg.createdAt.value.toIso8601String()
            : now.toIso8601String(),
      };

      await _db.into(_db.syncQueue).insert(
            SyncQueueCompanion(
              id: Value(const Uuid().v4()),
              entityType: const Value('chat_message'),
              entityId: Value(msgId),
              operation: const Value('CREATE'),
              payload: Value(jsonEncode(payload)),
              status: const Value('pending'),
              createdAt: Value(now),
            ),
          );
    });
  }

  // ---------------------------------------------------------------------------
  // Queue drain
  // ---------------------------------------------------------------------------

  /// Drain all pending 'chat_message' entries from the SyncQueue via WS.
  ///
  /// Called on connectivity restore and after WebSocket reconnect.
  /// Items are processed in FIFO order (createdAt ASC).
  Future<void> drainQueue() async {
    if (_wsClient == null) return;

    final pending = await _getPendingChatItems();
    if (pending.isEmpty) return;

    debugPrint('[ChatSyncService] Draining ${pending.length} offline messages');

    for (final item in pending) {
      if (_wsClient == null) break;

      final attemptCount = item.attemptCount;
      if (attemptCount >= 3) {
        await _parkItem(item.id, 'Max retries exceeded');
        continue;
      }

      await _incrementAttempt(item.id, attemptCount + 1);

      try {
        final payload = jsonDecode(item.payload) as Map<String, dynamic>;
        _wsClient!.send({'type': 'message', ...payload});
        // ACK is handled via _onWsMessage when the server echoes back.
      } catch (e) {
        debugPrint(
            '[ChatSyncService] Failed to send message ${item.entityId}: $e');
        // Will retry on next drain cycle.
      }
    }
  }

  // ---------------------------------------------------------------------------
  // WS message handling (ACK processing)
  // ---------------------------------------------------------------------------

  void _onWsMessage(Map<String, dynamic> msg) {
    final type = msg['type'] as String?;

    if (type == 'message') {
      // Server echoed back a message with assigned seq — treat as ACK.
      final id = msg['id'] as String?;
      final seq = msg['seq'] as int?;
      if (id == null || seq == null) return;

      _acknowledgeMessage(id, seq);
    } else if (type == 'reconnected') {
      // WS client reconnected — drain any queued messages.
      drainQueue();
    }
  }

  Future<void> _acknowledgeMessage(String messageId, int seq) async {
    try {
      // Update ChatMessage: set status='sent' and seq from server.
      await (_db.update(_db.chatMessages)
            ..where((tbl) => tbl.id.equals(messageId)))
          .write(ChatMessagesCompanion(
        status: const Value('sent'),
        seq: Value(seq),
      ));

      // Remove the SyncQueue outbox entry.
      await (_db.delete(_db.syncQueue)
            ..where(
              (tbl) =>
                  tbl.entityId.equals(messageId) &
                  tbl.entityType.equals('chat_message'),
            ))
          .go();

      debugPrint('[ChatSyncService] Acknowledged message $messageId (seq $seq)');
    } catch (e) {
      debugPrint('[ChatSyncService] Error acknowledging message $messageId: $e');
    }
  }

  // ---------------------------------------------------------------------------
  // Connectivity listener
  // ---------------------------------------------------------------------------

  void _onConnectivityChanged(List<ConnectivityResult> results) {
    final isOnline = results.any((r) => r != ConnectivityResult.none);
    if (isOnline) {
      debugPrint('[ChatSyncService] Connectivity restored — draining queue');
      drainQueue();
    }
  }

  // ---------------------------------------------------------------------------
  // SyncQueue helpers
  // ---------------------------------------------------------------------------

  Future<List<SyncQueueData>> _getPendingChatItems() {
    return (_db.select(_db.syncQueue)
          ..where(
            (tbl) =>
                tbl.entityType.equals('chat_message') &
                tbl.status.equals('pending'),
          )
          ..orderBy([(tbl) => OrderingTerm.asc(tbl.createdAt)]))
        .get();
  }

  Future<void> _incrementAttempt(String id, int newCount) async {
    await (_db.update(_db.syncQueue)..where((tbl) => tbl.id.equals(id)))
        .write(SyncQueueCompanion(attemptCount: Value(newCount)));
  }

  Future<void> _parkItem(String id, String error) async {
    await (_db.update(_db.syncQueue)..where((tbl) => tbl.id.equals(id)))
        .write(SyncQueueCompanion(
      status: const Value('parked'),
      errorMessage: Value(error),
    ));

    // Mark the message as failed.
    final item = await (_db.select(_db.syncQueue)
          ..where((tbl) => tbl.id.equals(id)))
        .getSingleOrNull();
    if (item != null) {
      await _chatDao.updateMessageStatus(item.entityId, 'failed');
    }
  }
}
