import 'package:dio/dio.dart';
import 'package:dio_smart_retry/dio_smart_retry.dart';
import 'package:flutter/foundation.dart';

import '../auth/auth_repository.dart';
import '../auth/token_storage.dart';

/// Base URL — configurable via --dart-define=BASE_URL=...
/// Defaults to Android emulator accessing host machine.
const _baseUrl = String.fromEnvironment(
  'BASE_URL',
  defaultValue: 'http://10.0.2.2:8000/api/v1',
);

/// Exponential backoff delays for 5xx / timeout retries.
const _retryDelays = [
  Duration(seconds: 1),
  Duration(seconds: 2),
  Duration(seconds: 4),
  Duration(seconds: 8),
  Duration(seconds: 16),
];

class DioClient {
  late final Dio _dio;
  TokenStorage? _tokenStorage;
  AuthRepository? _authRepository;

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

    // AuthInterceptor runs FIRST — injects Bearer token and handles 401 refresh.
    // Must be before RetryInterceptor so 401s are refreshed before retry logic.
    _dio.interceptors.add(_AuthInterceptor(this));

    // RetryInterceptor must be added BEFORE LogInterceptor so that retries
    // are logged individually — helps debug exponential backoff in practice.
    _dio.interceptors.add(
      RetryInterceptor(
        dio: _dio,
        retries: 5,
        retryDelays: _retryDelays,
        retryEvaluator: (error, attempt) async {
          final statusCode = error.response?.statusCode;
          if (statusCode != null && statusCode >= 400 && statusCode < 500) {
            return false; // 4xx — park, don't retry
          }
          return true; // 5xx / timeout / no response — retry
        },
      ),
    );

    // Conditional logging: no LogInterceptor in release builds.
    // In debug: log headers only (no request/response body to avoid leaking tokens).
    if (kDebugMode) {
      _dio.interceptors.add(
        LogInterceptor(
          requestBody: false,
          responseBody: false,
          logPrint: (obj) => debugPrint('[DIO] $obj'),
        ),
      );
    }
  }

  /// Wire up auth dependencies after service locator setup.
  void setAuthDependencies(TokenStorage tokenStorage, AuthRepository authRepository) {
    _tokenStorage = tokenStorage;
    _authRepository = authRepository;
  }

  Dio get instance => _dio;

  /// POST [data] to [path] with an [Idempotency-Key] header.
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

/// Auth interceptor — injects Bearer token on every request, handles 401 refresh.
/// Uses QueuedInterceptor so async onRequest/onError are properly awaited
/// and requests are serialized (prevents race conditions during refresh).
class _AuthInterceptor extends QueuedInterceptor {
  final DioClient _client;
  bool _isRefreshing = false;

  _AuthInterceptor(this._client);

  @override
  void onRequest(RequestOptions options, RequestInterceptorHandler handler) async {
    final tokenStorage = _client._tokenStorage;
    if (tokenStorage == null) {
      handler.next(options);
      return;
    }

    // Skip auth header for auth endpoints (login, register, refresh)
    final path = options.path;
    if (path.contains('/auth/login') ||
        path.contains('/auth/register') ||
        path.contains('/auth/refresh')) {
      handler.next(options);
      return;
    }

    final accessToken = await tokenStorage.readAccessToken();
    if (accessToken != null) {
      options.headers['Authorization'] = 'Bearer $accessToken';
    }
    handler.next(options);
  }

  @override
  void onError(DioException err, ErrorInterceptorHandler handler) async {
    if (err.response?.statusCode != 401) {
      handler.next(err);
      return;
    }

    final authRepository = _client._authRepository;
    final tokenStorage = _client._tokenStorage;
    if (authRepository == null || tokenStorage == null) {
      handler.next(err);
      return;
    }

    // Skip refresh for auth endpoints
    final path = err.requestOptions.path;
    if (path.contains('/auth/')) {
      handler.next(err);
      return;
    }

    // Prevent concurrent refresh attempts
    if (_isRefreshing) {
      handler.next(err);
      return;
    }

    _isRefreshing = true;
    try {
      final result = await authRepository.refreshToken();
      if (result != null) {
        // Retry original request with new token
        final newToken = await tokenStorage.readAccessToken();
        final options = err.requestOptions;
        options.headers['Authorization'] = 'Bearer $newToken';

        final response = await _client._dio.fetch(options);
        handler.resolve(response);
      } else {
        handler.next(err);
      }
    } catch (_) {
      handler.next(err);
    } finally {
      _isRefreshing = false;
    }
  }
}
