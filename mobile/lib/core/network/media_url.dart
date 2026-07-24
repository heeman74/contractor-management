/// Resolves a possibly-relative media URL to an absolute one.
///
/// Attachment `remote_url` values from the backend are relative (e.g.
/// `/files/attachments/{note}/x.png`). `Image.network` uses Flutter's own
/// HttpClient — it does NOT prepend Dio's base URL — so relative URLs (including
/// everything created by the web app) fail to load. This resolves them against
/// the same host DioClient uses. The `/files` mount is not auth-gated, so no
/// bearer token is needed.
library;

const _baseUrl = String.fromEnvironment(
  'BASE_URL',
  defaultValue: 'http://10.0.2.2:8000/api/v1',
);

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
