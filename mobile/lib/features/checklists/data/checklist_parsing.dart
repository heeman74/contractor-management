import 'package:drift/drift.dart' show Value;

import '../../../core/database/app_database.dart';
import '../../../core/logging/app_logger.dart';

/// Shared parsing utilities for DailyChecklist companion creation.
///
/// Used by both [ChecklistRepository._toCompanion] and
/// [ChecklistSyncHandler.applyPulled] to avoid duplicating the
/// JSON → [DailyChecklistsCompanion] conversion logic.
class ChecklistParsing {
  /// Parse a raw server JSON map into a [DailyChecklistsCompanion].
  ///
  /// Required string fields: id, company_id, contractor_id, project_id,
  /// trade_scope_id, checklist_date, checklist_json, summary_text.
  ///
  /// Optional fields (type-safe with fallbacks):
  /// - is_pushed (bool, default false)
  /// - created_at (ISO 8601 string, default DateTime.now())
  /// - deleted_at (nullable ISO 8601 string)
  ///
  /// Throws [FormatException] if required fields are missing or wrong type.
  static DailyChecklistsCompanion toCompanion(Map<String, dynamic> data) {
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

    final rawIsPushed = data['is_pushed'];
    final isPushed = rawIsPushed is bool && rawIsPushed;

    return DailyChecklistsCompanion(
      id: Value(id),
      companyId: Value(companyId),
      contractorId: Value(contractorId),
      projectId: Value(projectId),
      tradeScopeId: Value(tradeScopeId),
      checklistDate: Value(checklistDate),
      checklistJson: Value(checklistJson),
      summaryText: Value(summaryText),
      isPushed: Value(isPushed),
      createdAt: Value(_parseCreatedAt(data['created_at'])),
      deletedAt: Value(_parseDeletedAt(data['deleted_at'])),
    );
  }

  /// Parse a raw `created_at` value into a [DateTime].
  ///
  /// Returns [DateTime.now] if the value is not a valid ISO 8601 string.
  static DateTime _parseCreatedAt(dynamic raw) {
    if (raw is String) {
      final parsed = DateTime.tryParse(raw);
      if (parsed != null) return parsed;
      AppLogger.warning(
        'ChecklistParsing',
        'Invalid created_at "$raw", using now()',
      );
    }
    return DateTime.now();
  }

  /// Parse a raw `deleted_at` value into a nullable ISO 8601 string.
  ///
  /// Returns null if the value is not a valid date string.
  static String? _parseDeletedAt(dynamic raw) {
    if (raw is String) {
      if (DateTime.tryParse(raw) != null) return raw;
      AppLogger.warning(
        'ChecklistParsing',
        'Invalid deleted_at "$raw", storing null',
      );
    }
    return null;
  }
}
