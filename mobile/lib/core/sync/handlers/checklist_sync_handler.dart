import '../../../features/checklists/data/checklist_parsing.dart';
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
  // DioClient is accepted for constructor-signature consistency with other
  // SyncHandler subclasses (e.g., CompanySyncHandler, ProjectSyncHandler),
  // but daily checklists are pull-only so it is intentionally unused.
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
    final companion = ChecklistParsing.toCompanion(data);
    await _db.dailyChecklistDao.upsertChecklist(companion);
  }
}
