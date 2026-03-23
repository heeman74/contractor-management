import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';

/// A single parsed SSE event from the AI streaming endpoint.
///
/// Fields:
/// - [event]: the event type ('token' | 'tool_call' | 'done' | 'error')
/// - [data]: the raw JSON data string for this event
class SseEvent {
  const SseEvent({required this.event, required this.data});

  final String event;
  final String data;

  /// Parse the data field as a JSON map.
  ///
  /// Returns an empty map on parse failure — callers should check for required keys.
  Map<String, dynamic> get dataJson {
    try {
      final decoded = jsonDecode(data);
      if (decoded is Map<String, dynamic>) return decoded;
      return {};
    } catch (e) {
      debugPrint('[AiSseClient] dataJson parse error: $e for data: $data');
      return {};
    }
  }

  @override
  String toString() => 'SseEvent(event: $event, data: $data)';
}

/// Parse a raw SSE event from its component lines.
///
/// This is a top-level function (not a class method) to enable independent unit testing.
///
/// Parameters:
/// - [eventLine]: the value after the 'event: ' prefix, or '' if no event line
/// - [dataLine]: the value after the 'data: ' prefix
///
/// Returns a [SseEvent] if [dataLine] is non-empty, or null otherwise.
/// An empty [eventLine] defaults to the standard 'message' event type.
SseEvent? parseSseEvent(String eventLine, String dataLine) {
  if (dataLine.isEmpty) return null;
  final eventType = eventLine.isEmpty ? 'message' : eventLine;
  return SseEvent(event: eventType, data: dataLine);
}

/// HTTP client for AI SSE streaming endpoints.
///
/// IMPORTANT: Bypasses Dio entirely because Dio cannot handle text/event-stream
/// responses. Uses dart:io HttpClient directly for streaming HTTP POST requests.
/// Standard (non-streaming) endpoints use HttpClient as well for consistency.
///
/// Registration in GetIt:
///   getIt.registerLazySingleton<AiSseClient>(() => AiSseClient(
///     baseUrl: ...,
///     getAccessToken: () => getIt<TokenStorage>().readAccessToken(),
///   ));
class AiSseClient {
  const AiSseClient({
    required this.baseUrl,
    required this.getAccessToken,
  });

  final String baseUrl;

  /// Async function that returns the current Bearer token, or null if not authed.
  final Future<String?> Function() getAccessToken;

  /// Stream chat turn events from an AI endpoint via SSE.
  ///
  /// Posts [body] as JSON to [path] with Accept: text/event-stream.
  /// Yields parsed [SseEvent] objects as they arrive.
  ///
  /// Event types the backend emits:
  /// - 'token': streaming text delta — data: {"delta": "..."}
  /// - 'tool_call': AI tool invocation — data: {"tool": "...", "input": {...}, "id": "..."}
  /// - 'done': conversation turn complete — data: {"stop_reason": "end_turn"}
  /// - 'error': backend error — data: {"message": "..."}
  Stream<SseEvent> streamChatTurn({
    required String path,
    required Map<String, dynamic> body,
  }) async* {
    final token = await getAccessToken();
    final url = '$baseUrl$path';

    final client = HttpClient();
    try {
      final request = await client.postUrl(Uri.parse(url));
      if (token != null) {
        request.headers.set(HttpHeaders.authorizationHeader, 'Bearer $token');
      }
      request.headers.set(HttpHeaders.contentTypeHeader, 'application/json');
      request.headers.set(HttpHeaders.acceptHeader, 'text/event-stream');
      request.headers.set('Cache-Control', 'no-cache');
      request.write(jsonEncode(body));

      final response = await request.close();

      if (response.statusCode != 200) {
        final errorBody = await response.transform(utf8.decoder).join();
        throw HttpException(
          'SSE request failed with ${response.statusCode}: $errorBody',
          uri: Uri.parse(url),
        );
      }

      String currentEvent = '';
      String currentData = '';

      // Process incoming chunks line by line
      await for (final chunk in response.transform(utf8.decoder)) {
        // Split chunk on newlines — SSE uses CRLF or LF between lines, blank line ends event
        final lines = chunk.split('\n');

        for (final rawLine in lines) {
          final line = rawLine.trimRight(); // remove trailing \r

          if (line.startsWith('event:')) {
            currentEvent = line.substring(6).trim();
          } else if (line.startsWith('data:')) {
            currentData = line.substring(5).trim();
          } else if (line.isEmpty) {
            // Blank line = event boundary
            if (currentData.isNotEmpty) {
              final parsed = parseSseEvent(currentEvent, currentData);
              if (parsed != null) yield parsed;
            }
            // Reset for next event
            currentEvent = '';
            currentData = '';
          }
        }
      }

      // Flush last event if stream ended without a final blank line
      if (currentData.isNotEmpty) {
        final parsed = parseSseEvent(currentEvent, currentData);
        if (parsed != null) yield parsed;
      }
    } catch (e) {
      debugPrint('[AiSseClient] streamChatTurn error: $e');
      rethrow;
    } finally {
      client.close(force: false);
    }
  }

  /// Standard JSON POST for non-streaming AI endpoints (start, complete).
  ///
  /// Returns the decoded JSON response body as a map.
  /// Throws [HttpException] on non-2xx status codes.
  Future<Map<String, dynamic>> post(String path, Map<String, dynamic> body) async {
    final token = await getAccessToken();
    final url = '$baseUrl$path';

    final client = HttpClient();
    try {
      final request = await client.postUrl(Uri.parse(url));
      if (token != null) {
        request.headers.set(HttpHeaders.authorizationHeader, 'Bearer $token');
      }
      request.headers.set(HttpHeaders.contentTypeHeader, 'application/json');
      request.write(jsonEncode(body));

      final response = await request.close();
      final responseBody = await response.transform(utf8.decoder).join();

      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw HttpException(
          'POST $path failed with ${response.statusCode}: $responseBody',
          uri: Uri.parse(url),
        );
      }

      final decoded = jsonDecode(responseBody);
      if (decoded is Map<String, dynamic>) return decoded;
      throw FormatException(
        'Expected JSON object from POST $path, got: ${decoded.runtimeType}',
      );
    } finally {
      client.close(force: false);
    }
  }

  /// Standard JSON GET for conversation fetch endpoint.
  ///
  /// Returns the decoded JSON response body as a map.
  /// Throws [HttpException] on non-2xx status codes.
  Future<Map<String, dynamic>> get(String path) async {
    final token = await getAccessToken();
    final url = '$baseUrl$path';

    final client = HttpClient();
    try {
      final request = await client.getUrl(Uri.parse(url));
      if (token != null) {
        request.headers.set(HttpHeaders.authorizationHeader, 'Bearer $token');
      }
      request.headers.set(HttpHeaders.acceptHeader, 'application/json');

      final response = await request.close();
      final responseBody = await response.transform(utf8.decoder).join();

      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw HttpException(
          'GET $path failed with ${response.statusCode}: $responseBody',
          uri: Uri.parse(url),
        );
      }

      final decoded = jsonDecode(responseBody);
      if (decoded is Map<String, dynamic>) return decoded;
      throw FormatException(
        'Expected JSON object from GET $path, got: ${decoded.runtimeType}',
      );
    } finally {
      client.close(force: false);
    }
  }
}
