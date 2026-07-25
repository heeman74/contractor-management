/// Resolves a possibly-relative media URL to an absolute one, plus the auth
/// headers needed to fetch it.
///
/// Attachment `remote_url` values from the backend are relative (e.g.
/// `/files/attachments/{note}/x.png`). `Image.network` uses Flutter's own
/// HttpClient — it does NOT prepend Dio's base URL — so relative URLs (including
/// everything created by the web app) fail to load. This resolves them against
/// the same host DioClient uses.
///
/// The `/files` and `/uploads/chat` endpoints are now AUTHENTICATED (tenant/thread
/// scoped) — pass [mediaAuthHeaders] to `Image.network(url, headers: ...)` so the
/// Bearer token rides along. Because `Image.network` can't refresh a 401 like Dio
/// does, an expired token means the image simply fails to load until the next
/// authenticated request re-warms the cached token (acceptable for a 15-min token).
library;

import 'package:contractorhub/core/auth/token_storage.dart';

const _baseUrl = String.fromEnvironment(
  'BASE_URL',
  defaultValue: 'http://10.0.2.2:8000/api/v1',
);

/// Bearer auth headers for fetching authenticated media, or an empty map when no
/// token is cached. Spread into `Image.network(url, headers: mediaAuthHeaders())`.
Map<String, String> mediaAuthHeaders() {
  final token = TokenStorage.cachedAccessToken;
  return token == null ? const {} : {'Authorization': 'Bearer $token'};
}

/// The API host without the `/api/v1` suffix (e.g. `http://10.0.2.2:8000`).
String mediaHost() => _baseUrl.replaceAll('/api/v1', '');

/// Return an absolute URL. Absolute inputs pass through unchanged; relative
/// paths are joined onto [mediaHost]. Null/empty inputs are returned as-is.
String? resolveMediaUrl(String? url) {
  if (url == null || url.isEmpty) return url;
  if (url.startsWith('http://') || url.startsWith('https://')) return url;
  final path = url.startsWith('/') ? url : '/$url';
  return '${mediaHost()}$path';
}
