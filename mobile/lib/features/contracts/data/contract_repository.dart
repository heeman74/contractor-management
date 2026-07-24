import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

import '../../../core/network/media_url.dart';
import '../domain/contract.dart';

/// Thrown when a contract API call fails, carrying a user-friendly [message].
///
/// The screen layer shows [message] directly; the original [DioException] is
/// kept for logging/debugging but never surfaced to the client.
class ContractException implements Exception {
  const ContractException(this.message, {this.cause});

  final String message;
  final Object? cause;

  @override
  String toString() => 'ContractException: $message';
}

/// Data-layer access to client contracts over the authenticated Dio client.
///
/// Endpoints (base `/api/v1`, Bearer attached by AuthInterceptor):
/// - `GET /contracts/{id}`            → contract JSON
/// - `GET /contracts/{id}/sign-url`   → `{ sign_url }` fresh embedded URL
///
/// Type-safe parsing only (no bare `as` on wire data); [DioException]s are
/// mapped to [ContractException] with status-code-specific messages.
class ContractRepository {
  ContractRepository({required Dio dio}) : _dio = dio;

  final Dio _dio;

  static const _signUrlKey = 'sign_url';

  /// Fetch a single contract by [contractId].
  ///
  /// Throws [ContractException] on network/HTTP failure and [FormatException]
  /// when the payload shape is invalid (propagated from [Contract.fromJson]).
  Future<Contract> getContract(String contractId) async {
    try {
      final response = await _dio.get<dynamic>('/contracts/$contractId');
      return Contract.fromJson(response.data);
    } on DioException catch (error) {
      debugPrint('[ContractRepository] getContract failed: ${error.message}');
      throw ContractException(_messageFor(error), cause: error);
    }
  }

  /// Fetch a fresh embedded signing URL for [contractId].
  ///
  /// GET `/contracts/{id}/sign-url` → `{ sign_url: string }`. Throws
  /// [ContractException] on HTTP failure and [FormatException] when the
  /// response lacks a string `sign_url`.
  Future<String> getSignUrl(String contractId) async {
    try {
      final response =
          await _dio.get<dynamic>('/contracts/$contractId/sign-url');
      final data = response.data;
      if (data is! Map<String, dynamic>) {
        throw FormatException(
          'Expected a JSON object from sign-url, got ${data.runtimeType}',
        );
      }
      final signUrl = data[_signUrlKey];
      if (signUrl is! String || signUrl.isEmpty) {
        throw FormatException(
          'sign-url response missing a valid "$_signUrlKey" '
          '(got ${signUrl.runtimeType})',
        );
      }
      return signUrl;
    } on DioException catch (error) {
      debugPrint('[ContractRepository] getSignUrl failed: ${error.message}');
      throw ContractException(_messageFor(error), cause: error);
    }
  }

  /// Resolve the absolute URL of the signed PDF for [contract], or `null` when
  /// no signed PDF has been stored yet.
  ///
  /// Uses the `signed_pdf_url` (`/files/...`) path resolved against the API
  /// host via [resolveMediaUrl]; the `/files` mount is not auth-gated.
  String? signedPdfUrl(Contract contract) =>
      resolveMediaUrl(contract.signedPdfUrl);

  /// Map a [DioException] to a user-facing message. Never leaks backend detail.
  String _messageFor(DioException error) {
    final statusCode = error.response?.statusCode;
    return switch (statusCode) {
      401 => 'Your session has expired. Please log in again.',
      403 => 'You do not have permission to view this contract.',
      404 => 'This contract could not be found.',
      final code when code != null && code >= 500 =>
        'The server is having trouble. Please try again shortly.',
      _ => 'Could not load the contract. Please check your connection.',
    };
  }
}
