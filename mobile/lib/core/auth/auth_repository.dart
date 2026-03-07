import 'package:dio/dio.dart';

import '../network/dio_client.dart';
import 'token_storage.dart';

/// Auth repository — handles login, register, refresh, logout, and session restore.
///
/// Communicates with the backend auth endpoints and manages token persistence.
/// Used by AuthNotifier (Riverpod) to drive auth state transitions.
class AuthRepository {
  final DioClient _dioClient;
  final TokenStorage _tokenStorage;

  AuthRepository(this._dioClient, this._tokenStorage);

  /// Register a new company + admin user. Stores tokens on success.
  Future<AuthResult> register({
    required String email,
    required String password,
    required String companyName,
    String? firstName,
    String? lastName,
  }) async {
    final response = await _dioClient.instance.post<Map<String, dynamic>>(
      '/auth/register',
      data: {
        'email': email,
        'password': password,
        'company_name': companyName,
        if (firstName != null) 'first_name': firstName,
        if (lastName != null) 'last_name': lastName,
      },
    );

    return _handleTokenResponse(response.data!);
  }

  /// Login with email + password. Stores tokens on success.
  Future<AuthResult> login({
    required String email,
    required String password,
  }) async {
    final response = await _dioClient.instance.post<Map<String, dynamic>>(
      '/auth/login',
      data: {
        'email': email,
        'password': password,
      },
    );

    return _handleTokenResponse(response.data!);
  }

  /// Refresh the token pair using the stored refresh token.
  /// Returns new AuthResult or null if refresh fails.
  Future<AuthResult?> refreshToken() async {
    final refreshToken = await _tokenStorage.readRefreshToken();
    if (refreshToken == null) return null;

    try {
      final response = await _dioClient.instance.post<Map<String, dynamic>>(
        '/auth/refresh',
        data: {'refresh_token': refreshToken},
      );
      return _handleTokenResponse(response.data!);
    } on DioException {
      // Refresh failed — clear tokens and return null
      await _tokenStorage.clearTokens();
      return null;
    }
  }

  /// Logout — revoke refresh token family on backend, clear local tokens.
  Future<void> logout() async {
    final refreshToken = await _tokenStorage.readRefreshToken();
    final accessToken = await _tokenStorage.readAccessToken();

    if (refreshToken != null && accessToken != null) {
      try {
        await _dioClient.instance.post<void>(
          '/auth/logout',
          data: {'refresh_token': refreshToken},
          options: Options(
            headers: {'Authorization': 'Bearer $accessToken'},
          ),
        );
      } on DioException {
        // Best-effort logout — clear tokens regardless
      }
    }

    await _tokenStorage.clearTokens();
  }

  /// Restore session from stored tokens (app cold start).
  /// Returns AuthResult if valid tokens exist, null otherwise.
  Future<AuthResult?> restoreSession() async {
    final accessToken = await _tokenStorage.readAccessToken();
    if (accessToken == null) return null;

    // Decode JWT payload locally (offline-compatible)
    final payload = TokenStorage.decodeJwtPayload(accessToken);
    if (payload == null) {
      await _tokenStorage.clearTokens();
      return null;
    }

    // Check if token is expired
    final exp = payload['exp'] as int?;
    if (exp != null) {
      final expiry = DateTime.fromMillisecondsSinceEpoch(exp * 1000);
      if (expiry.isBefore(DateTime.now())) {
        // Token expired — try refresh
        return refreshToken();
      }
    }

    return AuthResult(
      userId: payload['sub'] as String,
      companyId: payload['company_id'] as String,
      roles: (payload['roles'] as List<dynamic>?)
              ?.map((r) => r as String)
              .toList() ??
          [],
    );
  }

  Future<AuthResult> _handleTokenResponse(Map<String, dynamic> data) async {
    final accessToken = data['access_token'];
    final refreshToken = data['refresh_token'];
    if (accessToken is! String || refreshToken is! String) {
      throw FormatException('Invalid token response: missing access_token or refresh_token');
    }

    await _tokenStorage.saveTokens(
      accessToken: accessToken,
      refreshToken: refreshToken,
    );

    final userId = data['user_id'];
    final companyId = data['company_id'];
    final rawRoles = data['roles'];
    if (userId is! String || companyId is! String || rawRoles is! List) {
      throw FormatException('Invalid token response: missing user_id, company_id, or roles');
    }

    return AuthResult(
      userId: userId,
      companyId: companyId,
      roles: rawRoles.whereType<String>().toList(),
    );
  }
}

/// Result of a successful auth operation (login/register/refresh/restore).
class AuthResult {
  final String userId;
  final String companyId;
  final List<String> roles;

  AuthResult({
    required this.userId,
    required this.companyId,
    required this.roles,
  });
}
