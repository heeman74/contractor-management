import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Secure token storage using platform-encrypted storage (Keychain/Keystore).
///
/// Stores access and refresh tokens separately for independent access.
/// All values are encrypted at rest by the platform's secure storage.
class TokenStorage {
  static const _accessTokenKey = 'access_token';
  static const _refreshTokenKey = 'refresh_token';

  /// In-memory copy of the current access token, kept in sync with secure
  /// storage. Needed because `Image.network(headers: ...)` requires the header
  /// synchronously at widget-build time (it can't await secure storage). The
  /// authoritative store is still the encrypted [FlutterSecureStorage]; this is
  /// only a read cache for synchronous callers (see media_url.dart).
  static String? _cachedAccessToken;

  /// The last-known access token, or null if none is cached (logged out, or the
  /// cache hasn't been warmed yet by a save/read). May lag secure storage until
  /// the next save/read, which is acceptable for image auth headers.
  static String? get cachedAccessToken => _cachedAccessToken;

  final FlutterSecureStorage _storage;

  TokenStorage({FlutterSecureStorage? storage})
      : _storage = storage ??
            const FlutterSecureStorage(
              aOptions: AndroidOptions(encryptedSharedPreferences: true),
            );

  Future<void> saveTokens({
    required String accessToken,
    required String refreshToken,
  }) async {
    _cachedAccessToken = accessToken;
    await Future.wait([
      _storage.write(key: _accessTokenKey, value: accessToken),
      _storage.write(key: _refreshTokenKey, value: refreshToken),
    ]);
  }

  Future<String?> readAccessToken() async {
    final token = await _storage.read(key: _accessTokenKey);
    _cachedAccessToken = token;
    return token;
  }

  Future<String?> readRefreshToken() async {
    return _storage.read(key: _refreshTokenKey);
  }

  Future<void> clearTokens() async {
    _cachedAccessToken = null;
    await Future.wait([
      _storage.delete(key: _accessTokenKey),
      _storage.delete(key: _refreshTokenKey),
    ]);
  }

  /// Decode a JWT payload without verification (for offline use).
  ///
  /// The client decodes the JWT locally to extract user/company/roles
  /// without calling the backend. This supports offline-first auth:
  /// users stay "authenticated" offline based on cached token data.
  static Map<String, dynamic>? decodeJwtPayload(String token) {
    try {
      final parts = token.split('.');
      if (parts.length != 3) return null;

      final payload = parts[1];
      // JWT base64url encoding — add padding if needed
      final normalized = base64Url.normalize(payload);
      final decoded = utf8.decode(base64Url.decode(normalized));
      return jsonDecode(decoded) as Map<String, dynamic>;
    } catch (_) {
      return null;
    }
  }
}
