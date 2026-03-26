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

    // is_pushed: type-safe bool check with default false
    final rawIsPushed = data['is_pushed'];
    final isPushed = rawIsPushed is bool && rawIsPushed;

    // created_at: type-safe string check with DateTime.tryParse
    final rawCreatedAt = data['created_at'];
    DateTime createdAt;
    if (rawCreatedAt is String) {
      final parsed = DateTime.tryParse(rawCreatedAt);
      if (parsed != null) {
        createdAt = parsed;
      } else {
        createdAt = DateTime.now();
        AppLogger.warning(
          'ChecklistParsing',
          'Invalid created_at "$rawCreatedAt", using now()',
        );
      }
    } else {
      createdAt = DateTime.now();
    }

    // deleted_at: type-safe nullable string check with DateTime validation
    final rawDeletedAt = data['deleted_at'];
    String? deletedAt;
    if (rawDeletedAt is String) {
      if (DateTime.tryParse(rawDeletedAt) != null) {
        deletedAt = rawDeletedAt;
      } else {
        AppLogger.warning(
          'ChecklistParsing',
          'Invalid deleted_at "$rawDeletedAt", storing null',
        );
      }
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
      isPushed: Value(isPushed),
      createdAt: Value(createdAt),
      deletedAt: Value(deletedAt),
    );
  }
}
