import 'package:dio/dio.dart';

/// Job data returned by the backend when a request is accepted.
///
/// The backend atomically creates the job and updates the request; the client
/// never creates the job itself (locked project decision).
class AcceptedRequestJob {
  const AcceptedRequestJob({
    this.jobId,
    this.description,
    this.tradeType,
    this.clientId,
  });

  final String? jobId;
  final String? description;
  final String? tradeType;
  final String? clientId;

  factory AcceptedRequestJob.fromResponse(Object? responseData) {
    if (responseData is! Map<String, dynamic>) return const AcceptedRequestJob();
    final job = responseData['job'];
    if (job is! Map<String, dynamic>) return const AcceptedRequestJob();
    return AcceptedRequestJob(
      jobId: _asString(job['id']),
      description: _asString(job['description']),
      tradeType: _asString(job['trade_type']),
      clientId: _asString(job['client_id']),
    );
  }

  static String? _asString(Object? value) => value is String ? value : null;
}

/// Sends admin review decisions for incoming job requests to the backend.
///
/// Extracted from the review screen so the widget performs no HTTP. All three
/// actions POST to `/jobs/requests/{id}/review` with an `action` discriminator.
class JobRequestReviewService {
  JobRequestReviewService({required Dio dio}) : _dio = dio;

  final Dio _dio;

  Future<AcceptedRequestJob> accept(String requestId) async {
    final response = await _post(requestId, {'action': 'accepted'});
    return AcceptedRequestJob.fromResponse(response.data);
  }

  Future<void> decline(
    String requestId, {
    required String reason,
    String? message,
  }) {
    return _post(requestId, {
      'action': 'declined',
      'decline_reason': reason,
      if (message != null) 'decline_message': message,
    });
  }

  Future<void> requestInfo(String requestId, {String? message}) {
    return _post(requestId, {
      'action': 'info_requested',
      if (message != null) 'message': message,
    });
  }

  Future<Response<dynamic>> _post(
    String requestId,
    Map<String, dynamic> body,
  ) {
    return _dio.post<dynamic>('/jobs/requests/$requestId/review', data: body);
  }

  /// Maps a [DioException] to a user-facing message. Centralizes the
  /// status-code handling previously duplicated across each action.
  static String errorMessage(DioException exception) {
    final statusCode = exception.response?.statusCode;
    return switch (statusCode) {
      401 => 'Not authorised. Please log in again.',
      403 => 'You do not have permission to review requests.',
      404 => 'Request not found — it may have already been reviewed.',
      422 => 'Invalid request data. Please contact support.',
      final code when code != null && code >= 500 =>
        'Server error. Please try again.',
      _ => 'Failed to submit review. Please try again.',
    };
  }
}
