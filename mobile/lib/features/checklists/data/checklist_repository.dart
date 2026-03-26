import 'package:drift/drift.dart' show Value;
import 'package:flutter/foundation.dart' show debugPrint;

import '../../../core/database/app_database.dart';
import '../../../core/network/dio_client.dart';

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
  /// Delegates to [DailyChecklistDao.watchTodayForContractor] with today's
  /// ISO date string (YYYY-MM-DD).
  Stream<List<DailyChecklist>> watchTodayChecklist(String contractorId) {
    final dateStr = _todayDateStr();
    return _dao.watchTodayForContractor(contractorId, dateStr);
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

      for (final raw in items) {
        if (raw is! Map<String, dynamic>) continue;
        try {
          final companion = _toCompanion(raw);
          await _dao.upsertChecklist(companion);
        } catch (e) {
          final id = raw['id'] ?? 'unknown';
          debugPrint('ChecklistRepository: skip checklist $id — $e');
        }
      }
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

  /// Parse a raw server JSON map into a [DailyChecklistsCompanion].
  DailyChecklistsCompanion _toCompanion(Map<String, dynamic> data) {
    final id = data['id'];
    final companyId = data['company_id'];
    final contractorId = data['contractor_id'];
    final projectId = data['project_id'];
    final tradeScopeId = data['trade_scope_id'];
    final checklistDate = data['checklist_date'];
    final checklistJson = data['checklist_json'];
    final summaryText = data['summary_text'];

    if (id is! String ||
        companyId is! String ||
        contractorId is! String ||
        projectId is! String ||
        tradeScopeId is! String ||
        checklistDate is! String ||
        checklistJson is! String ||
        summaryText is! String) {
      throw FormatException(
        'DailyChecklist missing required fields: '
        'id=${id.runtimeType}, company_id=${companyId.runtimeType}, '
        'contractor_id=${contractorId.runtimeType}',
      );
    }

    return DailyChecklistsCompanion(
      id: Value(id),
      companyId: Value(companyId),
      contractorId: Value(contractorId),
      projectId: Value(projectId),
      tradeScopeId: Value(tradeScopeId),
      checklistDate: Value(checklistDate),
      checklistJson: Value(checklistJson),
      summaryText: Value(summaryText),
      isPushed: data['is_pushed'] != null
          ? Value(data['is_pushed'] as bool)
          : const Value(false),
      createdAt: data['created_at'] != null
          ? Value(DateTime.parse(data['created_at'] as String))
          : Value(DateTime.now()),
      deletedAt: Value(data['deleted_at'] as String?),
    );
  }
}
