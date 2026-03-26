import 'package:dio/dio.dart';
import 'package:uuid/uuid.dart';

import 'app_logger.dart';

const _uuid = Uuid();

/// Key used to store the request start time in [RequestOptions.extra].
const _kStartTimeKey = '__trace_start_ms';

/// Dio interceptor that adds X-Request-ID headers and logs request/response timing.
///
/// - Generates a UUID4 request ID for each outgoing request
/// - Adds X-Request-ID header for backend correlation
/// - Logs request start (method, path) at debug level
/// - Logs response completion (status, duration_ms) at info level
/// - Logs errors (status, duration_ms, error message) at error level
/// - NEVER logs request/response bodies (token leakage risk per CLAUDE.md)
///
/// Must be added AFTER AuthInterceptor and BEFORE RetryInterceptor.
class TraceInterceptor extends Interceptor {
  static const _tag = 'HTTP';

  @override
  void onRequest(RequestOptions options, RequestInterceptorHandler handler) {
    // Generate and attach a unique request ID for backend correlation.
    final requestId = _uuid.v4();
    options.headers['X-Request-ID'] = requestId;

    // Store start time for duration calculation.
    options.extra[_kStartTimeKey] = DateTime.now().millisecondsSinceEpoch;

    AppLogger.debug(_tag, '${options.method} ${options.path}');

    handler.next(options);
  }

  @override
  void onResponse(Response response, ResponseInterceptorHandler handler) {
    final durationMs = _durationMs(response.requestOptions);
    final status = response.statusCode ?? 0;

    AppLogger.info(
      _tag,
      '${response.requestOptions.method} ${response.requestOptions.path} '
      '→ $status (${durationMs}ms)',
    );

    handler.next(response);
  }

  @override
  void onError(DioException err, ErrorInterceptorHandler handler) {
    final durationMs = _durationMs(err.requestOptions);
    final status = err.response?.statusCode;
    final method = err.requestOptions.method;
    final path = err.requestOptions.path;

    final statusLabel = status != null ? '$status' : 'no response';
    final errorDetail = _classifyError(status, err);

    AppLogger.error(
      _tag,
      '$method $path → $statusLabel (${durationMs}ms) — $errorDetail',
    );

    handler.next(err);
  }

  /// Calculate request duration from the stored start time.
  int _durationMs(RequestOptions options) {
    final startMs = options.extra[_kStartTimeKey];
    if (startMs is int) {
      return DateTime.now().millisecondsSinceEpoch - startMs;
    }
    return -1;
  }

  /// Classify the error by status code for structured logging.
  /// Does NOT include response body details (token leakage risk).
  String _classifyError(int? status, DioException err) {
    if (status == null) {
      return 'network error: ${err.type.name}';
    }
    switch (status) {
      case 401:
        return 'unauthorized';
      case 403:
        return 'forbidden';
      case 409:
        return 'conflict';
      case 422:
        return 'validation error';
      default:
        if (status >= 500) {
          return 'server error ($status)';
        }
        return 'client error ($status)';
    }
  }
}
