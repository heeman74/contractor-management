import 'package:flutter/foundation.dart' show debugPrint;

import '../../../core/database/app_database.dart';
import '../../../core/network/dio_client.dart';
import 'checklist_parsing.dart';

/// Repository for daily checklist data.
///
/// Wraps [DailyChecklistDao] for local reads and [DioClient] for API fetches.
///
/// Flow:
/// - [watchTodayChecklist] streams data from the local Drift DB (reactive).
/// - [fetchTodayChecklist] hits GET /api/v1/checklists/today, parses each
///   checklist, and upserts into the local Drift DB via [DailyChecklistDao].
///
/// No sync_queue writes — checklists flow server → client only.
class ChecklistRepository {
  final DailyChecklistDao _dao;
  final DioClient _dioClient;

  ChecklistRepository(this._dao, this._dioClient);

  // ────────────────────────────────────────────────────────────────────────
  // Read
  // ────────────────────────────────────────────────────────────────────────

  /// Reactive stream of today's checklists for [contractorId].
  ///
  /// [companyId] — optional tenant filter. When provided, only checklists
  /// for the given company are returned (multi-tenant safety).
  ///
  /// Delegates to [DailyChecklistDao.watchTodayForContractor] with today's
  /// ISO date string (YYYY-MM-DD).
  Stream<List<DailyChecklist>> watchTodayChecklist(
    String contractorId, {
    String? companyId,
  }) {
    final dateStr = _todayDateStr();
    return _dao.watchTodayForContractor(contractorId, dateStr,
        companyId: companyId);
  }

  // ────────────────────────────────────────────────────────────────────────
  // Fetch from API
  // ────────────────────────────────────────────────────────────────────────

  /// Fetch today's checklist from the backend and upsert into local Drift DB.
  ///
  /// GET /api/v1/checklists/today — returns a list of checklist objects.
  /// Each object is upserted into [DailyChecklists] via [DailyChecklistDao].
  ///
  /// Non-fatal: network errors are caught and logged. The local cache
  /// (from a previous sync pull) remains available for offline use.
  Future<void> fetchTodayChecklist() async {
    try {
      final response =
          await _dioClient.instance.get<dynamic>('/checklists/today');

      final data = response.data;
      if (data == null) return;

      final List<dynamic> items;
      if (data is List) {
        items = data;
      } else if (data is Map<String, dynamic> && data['items'] is List) {
        items = data['items'] as List<dynamic>;
      } else {
        debugPrint('ChecklistRepository: unexpected response shape — $data');
        return;
      }

      await _dao.attachedDatabase.transaction(() async {
        for (final raw in items) {
          if (raw is! Map<String, dynamic>) continue;
          try {
            final companion = ChecklistParsing.toCompanion(raw);
            await _dao.upsertChecklist(companion);
          } catch (e) {
            final id = raw['id'] ?? 'unknown';
            debugPrint('ChecklistRepository: skip checklist $id — $e');
          }
        }
      });
    } catch (e) {
      // Non-fatal: offline or backend unavailable.
      // Local Drift cache is still available to the UI stream.
      debugPrint('ChecklistRepository.fetchTodayChecklist error: $e');
    }
  }

  // ────────────────────────────────────────────────────────────────────────
  // Helpers
  // ────────────────────────────────────────────────────────────────────────

  /// Returns today's date as an ISO date string (YYYY-MM-DD).
  String _todayDateStr() {
    final now = DateTime.now();
    return '${now.year.toString().padLeft(4, '0')}'
        '-${now.month.toString().padLeft(2, '0')}'
        '-${now.day.toString().padLeft(2, '0')}';
  }

}
