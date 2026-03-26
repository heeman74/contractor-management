import 'package:drift/drift.dart' show Value;

import '../../database/app_database.dart';
import '../../network/dio_client.dart';
import '../sync_handler.dart';

/// SyncHandler implementation for the DailyChecklist entity.
///
/// Daily checklists are server-generated (AI-produced) — they flow
/// server → client only. This handler has no [push] implementation.
///
/// [applyPulled] upserts pulled checklist records into the local
/// [DailyChecklists] Drift table via [DailyChecklistDao.upsertChecklist].
///
/// The entity type 'daily_checklist' must be added to the sync engine's
/// [entityTypes] list in [SyncEngine.pullDelta] to receive pulled data.
class ChecklistSyncHandler extends SyncHandler {
  // ignore: unused_field — DioClient is passed for API consistency but
  // daily checklists are pull-only (server-generated, no push path).
  // ignore: unused_field
  final DioClient _dioClient;
  final AppDatabase _db;

  ChecklistSyncHandler(this._dioClient, this._db);

  @override
  String get entityType => 'daily_checklist';

  @override
  Future<void> push(SyncQueueData item) async {
    // Daily checklists are server-generated — no push path.
    // This method is a no-op; checklists cannot be locally mutated.
    throw UnsupportedError(
      'ChecklistSyncHandler: push is not supported — '
      'daily checklists are server-generated and read-only on the client.',
    );
  }

  @override
  Future<void> applyPulled(Map<String, dynamic> data) async {
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

    final companion = DailyChecklistsCompanion(
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

    await _db.dailyChecklistDao.upsertChecklist(companion);
  }
}
