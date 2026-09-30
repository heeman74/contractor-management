import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

import '../../../core/network/api_error_message.dart';
import '../domain/quote_client.dart';

/// Thrown when a client lookup, creation, or assignment fails.
///
/// [message] is the backend's own explanation where it gave one, so a refusal
/// such as an email already belonging to another account reaches the user in
/// words they can act on.
class QuoteClientException implements Exception {
  const QuoteClientException(this.message, {this.cause});

  final String message;
  final Object? cause;

  @override
  String toString() => 'QuoteClientException: $message';
}

/// Client roster access for the quote flow.
///
/// Endpoints (base `/api/v1`, Bearer attached by AuthInterceptor):
/// - `GET  /crm/clients`   → the roster, optionally searched
/// - `POST /crm/clients`   → add one, no password (this is not an invitation
///                            to sign in; the account cannot authenticate)
/// - `PATCH /quotes/{id}`  → attach the chosen client to the quote
///
/// The quote send transition refuses a quote with no client, so without this
/// a quote raised on mobile against a job with no client assigned could not be
/// sent at all — the app could report the refusal but never resolve it.
class QuoteClientRepository {
  QuoteClientRepository({required Dio dio}) : _dio = dio;

  final Dio _dio;

  /// The roster, newest search first. [search] matches name or email.
  Future<List<QuoteClient>> listClients({String? search}) async {
    try {
      final response = await _dio.get<dynamic>(
        '/crm/clients',
        queryParameters: <String, dynamic>{
          if (search != null && search.trim().isNotEmpty) 'search': search.trim(),
        },
      );

      final data = response.data;
      if (data is! List) {
        throw const FormatException('Expected a JSON list of clients');
      }
      return data.map(QuoteClient.fromJson).toList(growable: false);
    } on DioException catch (error) {
      debugPrint('[QuoteClientRepository] listClients failed: ${error.message}');
      throw QuoteClientException(apiErrorMessage(error), cause: error);
    }
  }

  /// Add a client to the roster and return it.
  ///
  /// The backend is idempotent for an address already on this roster, so a
  /// repeat add returns the existing client rather than failing.
  Future<QuoteClient> createClient({
    required String email,
    String? firstName,
    String? lastName,
  }) async {
    try {
      final response = await _dio.post<dynamic>(
        '/crm/clients',
        data: <String, dynamic>{
          'email': email.trim(),
          if (firstName != null && firstName.trim().isNotEmpty)
            'first_name': firstName.trim(),
          if (lastName != null && lastName.trim().isNotEmpty)
            'last_name': lastName.trim(),
        },
      );
      return QuoteClient.fromJson(response.data);
    } on DioException catch (error) {
      debugPrint('[QuoteClientRepository] createClient failed: ${error.message}');
      throw QuoteClientException(apiErrorMessage(error), cause: error);
    }
  }

  /// Point a draft quote at [clientId] so it can be sent.
  Future<void> assignClient({
    required String quoteId,
    required String clientId,
  }) async {
    try {
      await _dio.patch<dynamic>(
        '/quotes/$quoteId',
        data: <String, dynamic>{'client_id': clientId},
      );
    } on DioException catch (error) {
      debugPrint('[QuoteClientRepository] assignClient failed: ${error.message}');
      throw QuoteClientException(apiErrorMessage(error), cause: error);
    }
  }
}
