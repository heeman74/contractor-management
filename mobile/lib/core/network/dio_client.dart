import 'package:dio/dio.dart';
import 'package:dio_smart_retry/dio_smart_retry.dart';

/// Base URL for Android emulator accessing host machine.
/// In production, this would be set via environment config.
const _baseUrl = 'http://10.0.2.2:8000/api/v1';

/// Exponential backoff delays for 5xx / timeout retries.
///
/// Matches user decision: 1s/2s/4s/8s/16s up to 5 attempts.
/// 4xx responses are NOT retried (parked immediately by SyncEngine).
const _retryDelays = [
  Duration(seconds: 1),
  Duration(seconds: 2),
  Duration(seconds: 4),
  Duration(seconds: 8),
  Duration(seconds: 16),
];

class DioClient {
  late final Dio _dio;

  DioClient() {
    _dio = Dio(
      BaseOptions(
        baseUrl: _baseUrl,
        connectTimeout: const Duration(seconds: 30),
        receiveTimeout: const Duration(seconds: 30),
        headers: {
          'Content-Type': 'application/json',
          'Accept': 'application/json',
        },
      ),
    );

    // RetryInterceptor must be added BEFORE LogInterceptor so that retries
    // are logged individually — helps debug exponential backoff in practice.
    _dio.interceptors.add(
      RetryInterceptor(
        dio: _dio,
        retries: 5,
        retryDelays: _retryDelays,
        retryEvaluator: (error, attempt) async {
          // 4xx errors: park immediately, never retry
          // 5xx errors or no response (timeout/network): retry with backoff
          final statusCode = error.response?.statusCode;
          if (statusCode != null && statusCode >= 400 && statusCode < 500) {
            return false; // 4xx — park, don't retry
          }
          return true; // 5xx / timeout / no response — retry
        },
      ),
    );

    _dio.interceptors.add(
      LogInterceptor(
        requestBody: true,
        responseBody: true,
        logPrint: (obj) => print('[DIO] $obj'), // ignore: avoid_print
      ),
    );
  }

  Dio get instance => _dio;

  /// POST [data] to [path] with an [Idempotency-Key] header.
  ///
  /// Used by [SyncHandler] implementations to push outbox items to the backend.
  /// The [idempotencyKey] is the sync_queue item's UUID — the backend uses it
  /// to deduplicate retried requests transparently.
  ///
  /// The [X-Company-Id] tenant header is passed through the existing Dio
  /// instance interceptors (TenantInterceptor added in later phases).
  Future<Response<dynamic>> pushWithIdempotency(
    String path,
    Map<String, dynamic> data,
    String idempotencyKey,
  ) {
    return _dio.post<dynamic>(
      path,
      data: data,
      options: Options(
        headers: {
          'Idempotency-Key': idempotencyKey,
        },
      ),
    );
  }
}
