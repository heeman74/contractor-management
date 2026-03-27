import 'package:dio/dio.dart';

import '../../../core/logging/app_logger.dart';
import '../../../core/network/dio_client.dart';

/// Repository for foreman-specific API operations.
///
/// Wraps [DioClient] for foreman endpoints: project assignments,
/// daily status updates, and status history retrieval.
///
/// All methods use `is` type checks on response data (never bare `as` casts)
/// and log errors via [AppLogger] per CLAUDE.md rules.
class ForemanRepository {
  final DioClient _dioClient;

  static const _tag = 'ForemanRepository';

  ForemanRepository(this._dioClient);

  /// Fetch projects assigned to the current authenticated foreman.
  ///
  /// Returns a list of assignment maps, or empty list on failure.
  /// GET /foreman/assignments/me
  Future<List<Map<String, dynamic>>> fetchAssignedProjects() async {
    try {
      final response = await _dioClient.instance.get<dynamic>(
        '/foreman/assignments/me',
      );

      final data = response.data;
      if (data is List) {
        return data
            .whereType<Map<String, dynamic>>()
            .toList();
      }

      AppLogger.warning(_tag, 'Unexpected response type: ${data.runtimeType}');
      return [];
    } on DioException catch (e, st) {
      AppLogger.error(
        _tag,
        'Failed to fetch assigned projects',
        error: e,
        stackTrace: st,
      );
      rethrow;
    }
  }

  /// Submit a daily status update for a project.
  ///
  /// POST /foreman/status-updates
  /// Returns the created status update map, or throws on failure.
  Future<Map<String, dynamic>> createStatusUpdate(
    Map<String, dynamic> data,
  ) async {
    try {
      final response = await _dioClient.instance.post<dynamic>(
        '/foreman/status-updates',
        data: data,
      );

      final responseData = response.data;
      if (responseData is Map<String, dynamic>) {
        return responseData;
      }

      throw FormatException(
        'Expected Map<String, dynamic> but got ${responseData.runtimeType}',
      );
    } on DioException catch (e, st) {
      AppLogger.error(
        _tag,
        'Failed to create status update',
        error: e,
        stackTrace: st,
      );
      rethrow;
    }
  }

  /// Fetch status update history for a project.
  ///
  /// GET /foreman/status-updates/{projectId}
  /// Optional [limit] and [offset] for pagination.
  Future<List<Map<String, dynamic>>> fetchStatusUpdates(
    String projectId, {
    int limit = 20,
    int offset = 0,
  }) async {
    try {
      final response = await _dioClient.instance.get<dynamic>(
        '/foreman/status-updates/$projectId',
        queryParameters: {
          'limit': limit,
          'offset': offset,
        },
      );

      final data = response.data;
      if (data is List) {
        return data
            .whereType<Map<String, dynamic>>()
            .toList();
      }

      AppLogger.warning(_tag, 'Unexpected response type: ${data.runtimeType}');
      return [];
    } on DioException catch (e, st) {
      AppLogger.error(
        _tag,
        'Failed to fetch status updates for project $projectId',
        error: e,
        stackTrace: st,
      );
      rethrow;
    }
  }

  /// Fetch the latest status update for a project.
  ///
  /// GET /foreman/status-updates/{projectId}/latest
  /// Returns null if no status updates exist.
  Future<Map<String, dynamic>?> fetchLatestStatus(String projectId) async {
    try {
      final response = await _dioClient.instance.get<dynamic>(
        '/foreman/status-updates/$projectId/latest',
      );

      final data = response.data;
      if (data is Map<String, dynamic>) {
        return data;
      }

      // Null or empty response means no status updates yet.
      if (data == null) return null;

      AppLogger.warning(_tag, 'Unexpected response type: ${data.runtimeType}');
      return null;
    } on DioException catch (e, st) {
      // 404 means no status updates exist — not an error.
      if (e.response?.statusCode == 404) {
        return null;
      }
      AppLogger.error(
        _tag,
        'Failed to fetch latest status for project $projectId',
        error: e,
        stackTrace: st,
      );
      rethrow;
    }
  }
}
