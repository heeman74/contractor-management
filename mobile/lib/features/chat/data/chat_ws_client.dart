import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:web_socket_channel/io.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

/// WebSocket client for real-time chat messaging.
///
/// Manages a single WebSocket connection to the backend chat endpoint for
/// one thread. Handles JWT authentication via query parameter, reconnection
/// with exponential backoff (1s → 2s → 4s → 8s → 16s → 32s → 64s cap),
/// and a 30-second heartbeat with 10-second pong timeout.
///
/// Message types received from the server:
/// - 'message'       — new chat message
/// - 'typing'        — another user is typing
/// - 'read_receipt'  — a user read up to a given seq
/// - 'pong'          — heartbeat response
/// - 'reconnected'   — emitted locally after a successful reconnect so
///                     consumers know to fetch missed messages
///
/// Registration in GetIt / Riverpod:
///   Created per-thread via [chatWsClientProvider].
class ChatWsClient {
  ChatWsClient({
    required this.baseWsUrl,
    required this.tokenProvider,
  });

  /// Base WebSocket URL, e.g. 'ws://10.0.2.2:8000'.
  final String baseWsUrl;

  /// Async function that returns a fresh JWT access token.
  final Future<String> Function() tokenProvider;

  WebSocketChannel? _channel;
  StreamSubscription<dynamic>? _subscription;
  Timer? _heartbeatTimer;
  Timer? _pongTimeoutTimer;
  Timer? _reconnectTimer;

  bool _disposed = false;
  bool _isConnecting = false;
  String? _currentThreadId;
  int _reconnectAttempt = 0;

  final _messageController =
      StreamController<Map<String, dynamic>>.broadcast();

  /// Broadcast stream of incoming server messages (decoded JSON maps).
  Stream<Map<String, dynamic>> get messages => _messageController.stream;

  // ---------------------------------------------------------------------------
  // Connection management
  // ---------------------------------------------------------------------------

  /// Connect to the WebSocket endpoint for [threadId].
  ///
  /// Fetches a fresh JWT and opens `$baseWsUrl/ws/chat/$threadId?token=$token`.
  /// On connection drop or error, reconnects with exponential backoff.
  Future<void> connect(String threadId) async {
    if (_disposed) return;
    _currentThreadId = threadId;
    await _openConnection(threadId);
  }

  Future<void> _openConnection(String threadId) async {
    if (_disposed || _isConnecting) return;
    _isConnecting = true;

    try {
      final token = await tokenProvider();
      final uri = Uri.parse('$baseWsUrl/ws/chat/$threadId?token=$token');

      _channel = IOWebSocketChannel.connect(uri);
      _subscription = _channel!.stream.listen(
        _onData,
        onError: _onError,
        onDone: _onDone,
      );

      // Successful connection — reset backoff and start heartbeat.
      _reconnectAttempt = 0;
      _startHeartbeat();

      debugPrint('[ChatWsClient] Connected to thread $threadId');
    } catch (e) {
      debugPrint('[ChatWsClient] Connection error: $e');
      _scheduleReconnect();
    } finally {
      _isConnecting = false;
    }
  }

  void _onData(dynamic raw) {
    try {
      if (raw is! String) {
        debugPrint('[ChatWsClient] Unexpected WS data type: ${raw.runtimeType}');
        return;
      }
      final decoded = jsonDecode(raw);
      if (decoded is! Map<String, dynamic>) return;

      final type = decoded['type'] as String?;

      // Handle heartbeat pong — cancel pong timeout timer.
      if (type == 'pong') {
        _pongTimeoutTimer?.cancel();
        _pongTimeoutTimer = null;
        return;
      }

      _messageController.add(decoded);
    } catch (e) {
      debugPrint('[ChatWsClient] Failed to parse message: $e');
    }
  }

  void _onError(Object error) {
    debugPrint('[ChatWsClient] WebSocket error: $error');
    _cleanup();
    _scheduleReconnect();
  }

  void _onDone() {
    debugPrint('[ChatWsClient] WebSocket closed');
    _cleanup();
    if (!_disposed) {
      _scheduleReconnect();
    }
  }

  // ---------------------------------------------------------------------------
  // Sending
  // ---------------------------------------------------------------------------

  /// Send a JSON payload over the active WebSocket connection.
  ///
  /// Silently drops the message if the channel is not connected.
  void send(Map<String, dynamic> payload) {
    if (_channel == null) {
      debugPrint('[ChatWsClient] send called but channel is null');
      return;
    }
    try {
      _channel!.sink.add(jsonEncode(payload));
    } catch (e) {
      debugPrint('[ChatWsClient] send error: $e');
    }
  }

  /// Broadcast a typing indicator to other thread participants.
  void sendTyping() => send({'type': 'typing'});

  /// Notify the server that the current user has read up to [seq].
  void sendRead(int seq) => send({'type': 'read', 'seq': seq});

  // ---------------------------------------------------------------------------
  // Heartbeat
  // ---------------------------------------------------------------------------

  void _startHeartbeat() {
    _heartbeatTimer?.cancel();
    _heartbeatTimer = Timer.periodic(
      const Duration(seconds: 30),
      (_) => _sendPing(),
    );
  }

  void _sendPing() {
    send({'type': 'ping'});
    // If no pong arrives within 10 seconds, force reconnect.
    _pongTimeoutTimer?.cancel();
    _pongTimeoutTimer = Timer(
      const Duration(seconds: 10),
      () {
        debugPrint('[ChatWsClient] Pong timeout — reconnecting');
        _cleanup();
        _scheduleReconnect();
      },
    );
  }

  // ---------------------------------------------------------------------------
  // Reconnection with exponential backoff
  // ---------------------------------------------------------------------------

  /// Exponential backoff delays: 1s, 2s, 4s, 8s, 16s, 32s, 64s (capped).
  Duration get _reconnectDelay {
    final seconds =
        (1 << _reconnectAttempt.clamp(0, 6)); // 2^0=1 to 2^6=64
    return Duration(seconds: seconds);
  }

  void _scheduleReconnect() {
    if (_disposed || _currentThreadId == null) return;
    _reconnectTimer?.cancel();

    final delay = _reconnectDelay;
    _reconnectAttempt++;
    debugPrint(
        '[ChatWsClient] Reconnecting in ${delay.inSeconds}s (attempt $_reconnectAttempt)');

    _reconnectTimer = Timer(delay, () async {
      if (_disposed) return;
      await _openConnection(_currentThreadId!);

      // Emit reconnected event so consumers know to fetch missed messages.
      if (!_disposed) {
        _messageController.add({'type': 'reconnected'});
      }
    });
  }

  // ---------------------------------------------------------------------------
  // Cleanup
  // ---------------------------------------------------------------------------

  void _cleanup() {
    _heartbeatTimer?.cancel();
    _heartbeatTimer = null;
    _pongTimeoutTimer?.cancel();
    _pongTimeoutTimer = null;
    _subscription?.cancel();
    _subscription = null;
    _channel?.sink.close();
    _channel = null;
  }

  /// Release all resources. Call when the thread screen is closed.
  void dispose() {
    _disposed = true;
    _reconnectTimer?.cancel();
    _cleanup();
    _messageController.close();
  }
}
