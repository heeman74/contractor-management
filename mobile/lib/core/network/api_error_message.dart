import 'package:dio/dio.dart';

/// Fallback shown when the backend gave no usable explanation.
const String kGenericApiErrorMessage =
    'Something went wrong. Please try again.';

/// The human-readable reason behind a failed API call.
///
/// The backend refuses some actions on purpose and explains why in `detail` —
/// sending a quote with no client, deleting one an invoice depends on. Those
/// sentences are the only thing that tells a user what to do next, so they are
/// shown rather than replaced by a stringified [DioException], which surfaces
/// a stack-trace-shaped message no contractor can act on.
///
/// Validation errors arrive as a list of objects rather than a string; the
/// first message is taken, since showing one actionable line beats showing
/// none. Response shapes are checked rather than cast, so a payload that does
/// not match cannot throw on top of the error being reported.
String apiErrorMessage(Object error) {
  if (error is! DioException) return kGenericApiErrorMessage;

  final data = error.response?.data;
  if (data is! Map) return kGenericApiErrorMessage;

  final detail = data['detail'];
  if (detail is String && detail.trim().isNotEmpty) return detail;

  // FastAPI validation errors: [{"loc": [...], "msg": "..."}]
  if (detail is List) {
    for (final entry in detail) {
      if (entry is Map) {
        final message = entry['msg'];
        if (message is String && message.trim().isNotEmpty) return message;
      }
    }
  }

  return kGenericApiErrorMessage;
}
