import 'dart:io';

import 'package:dio/dio.dart';
import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:flutter/foundation.dart';

import '../../../core/database/app_database.dart';

/// Repository bridging the backend chat REST API and the local Drift cache.
///
/// Fetches threads and messages from the backend, upserts them into Drift
/// for offline-first reactive access, and provides REST fallbacks for
/// operations that complement the WebSocket channel.
///
/// Uses the Dio instance from GetIt for all HTTP calls. The Dio instance is
/// pre-configured with auth interceptors and retry logic.
class ChatRepository {
  ChatRepository({
    required Dio dio,
    required ChatDao chatDao,
  })  : _dio = dio,
        _chatDao = chatDao;

  final Dio _dio;
  final ChatDao _chatDao;

  // ---------------------------------------------------------------------------
  // Threads
  // ---------------------------------------------------------------------------

  /// Fetch threads for a project and upsert into local Drift cache.
  ///
  /// GET /chat/threads?project_id={projectId}
  Future<void> fetchThreads(String projectId) async {
    try {
      final response = await _dio.get<Map<String, dynamic>>(
        '/chat/threads',
        queryParameters: {'project_id': projectId},
      );

      final data = response.data;
      if (data == null) return;

      final items = data['items'];
      if (items is! List) return;

      for (final item in items) {
        if (item is! Map<String, dynamic>) continue;
        await _chatDao.upsertThread(_threadFromJson(item));
      }
    } on DioException catch (e) {
      debugPrint('[ChatRepository] fetchThreads error: ${e.message}');
      rethrow;
    }
  }

  // ---------------------------------------------------------------------------
  // Messages
  // ---------------------------------------------------------------------------

  /// Fetch messages for a thread and insert into local Drift cache.
  ///
  /// GET /chat/threads/{threadId}/messages?before_seq={seq}&limit={limit}
  Future<void> fetchMessages(
    String threadId, {
    int? beforeSeq,
    int limit = 50,
  }) async {
    try {
      final queryParams = <String, dynamic>{'limit': limit};
      if (beforeSeq != null) queryParams['before_seq'] = beforeSeq;

      final response = await _dio.get<Map<String, dynamic>>(
        '/chat/threads/$threadId/messages',
        queryParameters: queryParams,
      );

      final data = response.data;
      if (data == null) return;

      final items = data['items'];
      if (items is! List) return;

      final companions = <ChatMessagesCompanion>[];
      for (final item in items) {
        if (item is! Map<String, dynamic>) continue;
        companions.add(_messageFromJson(item));
      }

      if (companions.isNotEmpty) {
        await _chatDao.batchInsertMessages(companions);
      }
    } on DioException catch (e) {
      debugPrint('[ChatRepository] fetchMessages error: ${e.message}');
      rethrow;
    }
  }

  /// Fetch messages received after [sinceSeq] — used after WebSocket reconnect.
  ///
  /// GET /chat/threads/{threadId}/messages?since_seq={seq}
  Future<void> fetchMissedMessages(String threadId, int sinceSeq) async {
    try {
      final response = await _dio.get<Map<String, dynamic>>(
        '/chat/threads/$threadId/messages',
        queryParameters: {'since_seq': sinceSeq},
      );

      final data = response.data;
      if (data == null) return;

      final items = data['items'];
      if (items is! List) return;

      final companions = <ChatMessagesCompanion>[];
      for (final item in items) {
        if (item is! Map<String, dynamic>) continue;
        companions.add(_messageFromJson(item));
      }

      if (companions.isNotEmpty) {
        await _chatDao.batchInsertMessages(companions);
      }
    } on DioException catch (e) {
      debugPrint('[ChatRepository] fetchMissedMessages error: ${e.message}');
      rethrow;
    }
  }

  // ---------------------------------------------------------------------------
  // Attachments
  // ---------------------------------------------------------------------------

  /// Upload an attachment for a message.
  ///
  /// POST /chat/messages/{messageId}/attachment (multipart/form-data)
  /// Returns the URL of the uploaded file.
  Future<String> uploadAttachment(
    String messageId,
    File file,
    String type,
  ) async {
    try {
      final formData = FormData.fromMap({
        'file': await MultipartFile.fromFile(
          file.path,
          filename: file.path.split('/').last,
        ),
        'type': type,
      });

      final response = await _dio.post<Map<String, dynamic>>(
        '/chat/messages/$messageId/attachment',
        data: formData,
      );

      final data = response.data;
      if (data == null) {
        throw const FormatException(
          'Expected JSON response from attachment upload, got null',
        );
      }

      final url = data['url'];
      if (url is! String) {
        throw FormatException(
          'Expected string URL in attachment response, got: ${url.runtimeType}',
        );
      }

      return url;
    } on DioException catch (e) {
      debugPrint('[ChatRepository] uploadAttachment error: ${e.message}');
      rethrow;
    }
  }

  // ---------------------------------------------------------------------------
  // Read receipts
  // ---------------------------------------------------------------------------

  /// Send a read receipt for a thread (REST fallback when WS is unavailable).
  ///
  /// POST /chat/threads/{threadId}/read
  Future<void> sendReadReceipt(String threadId, int seq) async {
    try {
      await _dio.post<void>(
        '/chat/threads/$threadId/read',
        data: {'seq': seq},
      );
    } on DioException catch (e) {
      debugPrint('[ChatRepository] sendReadReceipt error: ${e.message}');
      rethrow;
    }
  }

  // ---------------------------------------------------------------------------
  // JSON deserialization helpers
  // ---------------------------------------------------------------------------

  ChatThreadsCompanion _threadFromJson(Map<String, dynamic> json) {
    DateTime? parseNullable(dynamic val) {
      if (val == null) return null;
      if (val is! String) return null;
      return DateTime.tryParse(val);
    }

    return ChatThreadsCompanion(
      id: Value(json['id'] as String),
      companyId: Value(json['company_id'] as String),
      projectId: Value(json['project_id'] as String),
      threadType: Value(json['thread_type'] as String),
      tradeScopeId: Value(json['trade_scope_id'] as String?),
      name: Value(json['name'] as String),
      createdAt: Value(
        DateTime.parse(json['created_at'] as String),
      ),
      updatedAt: Value(
        DateTime.parse(json['updated_at'] as String),
      ),
      deletedAt: Value(parseNullable(json['deleted_at'])),
    );
  }

  ChatMessagesCompanion _messageFromJson(Map<String, dynamic> json) {
    DateTime? parseNullable(dynamic val) {
      if (val == null) return null;
      if (val is! String) return null;
      return DateTime.tryParse(val);
    }

    return ChatMessagesCompanion(
      id: Value(json['id'] as String),
      companyId: Value(json['company_id'] as String),
      threadId: Value(json['thread_id'] as String),
      senderId: Value(json['sender_id'] as String),
      senderName: Value(json['sender_name'] as String),
      content: Value(json['content'] as String?),
      seq: Value(json['seq'] as int),
      attachmentUrl: Value(json['attachment_url'] as String?),
      attachmentType: Value(json['attachment_type'] as String?),
      annotationData: Value(json['annotation_data'] as String?),
      mentions: Value((json['mentions'] as String?) ?? '[]'),
      mentionAll: Value((json['mention_all'] as bool?) ?? false),
      status: const Value('sent'),
      createdAt: Value(
        DateTime.parse(json['created_at'] as String),
      ),
      deletedAt: Value(parseNullable(json['deleted_at'])),
    );
  }
}
