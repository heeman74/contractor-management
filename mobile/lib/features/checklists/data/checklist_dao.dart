import 'package:drift/drift.dart' hide isNotNull, isNull;

import '../../../core/database/app_database.dart';
import '../../../core/database/tables/daily_checklists.dart';

part 'checklist_dao.g.dart';

/// Drift DAO for DailyChecklist read operations.
///
/// Checklists are pulled from the backend via [ChecklistSyncHandler] /
/// [ChecklistRepository.fetchTodayChecklist] — they are never created locally.
///
/// All read methods return reactive [Stream]s for offline-first updates.
///
/// [upsertChecklist] is used by the sync pull path and the repository's
/// fetch-and-store method. It does NOT write to sync_queue — checklists are
/// server-generated, not client-initiated.
@DriftAccessor(tables: [DailyChecklists])
class DailyChecklistDao extends DatabaseAccessor<AppDatabase>
    with _$DailyChecklistDaoMixin {
  DailyChecklistDao(super.db);

  // ────────────────────────────────────────────────────────────────────────
  // Reactive streams
  // ────────────────────────────────────────────────────────────────────────

  /// Reactive stream of today's non-deleted checklists for a contractor.
  ///
  /// [contractorId] — the contractor's user ID.
  /// [dateStr] — ISO date string (YYYY-MM-DD) for today's date.
  ///
  /// Ordered by [createdAt] DESC (most recent first).
  Stream<List<DailyChecklist>> watchTodayForContractor(
    String contractorId,
    String dateStr,
  ) {
    return (select(dailyChecklists)
          ..where(
            (tbl) =>
                tbl.contractorId.equals(contractorId) &
                tbl.checklistDate.equals(dateStr) &
                tbl.deletedAt.isNull(),
          )
          ..orderBy([(tbl) => OrderingTerm.desc(tbl.createdAt)]))
        .watch();
  }

  // ────────────────────────────────────────────────────────────────────────
  // One-shot queries
  // ────────────────────────────────────────────────────────────────────────

  /// One-shot query for today's non-deleted checklists for a contractor.
  ///
  /// Same filter as [watchTodayForContractor] but returns a Future.
  Future<List<DailyChecklist>> getTodayForContractor(
    String contractorId,
    String dateStr,
  ) {
    return (select(dailyChecklists)
          ..where(
            (tbl) =>
                tbl.contractorId.equals(contractorId) &
                tbl.checklistDate.equals(dateStr) &
                tbl.deletedAt.isNull(),
          )
          ..orderBy([(tbl) => OrderingTerm.desc(tbl.createdAt)]))
        .get();
  }

  // ────────────────────────────────────────────────────────────────────────
  // Upsert (sync pull path)
  // ────────────────────────────────────────────────────────────────────────

  /// Upsert a checklist from a sync pull or direct API fetch.
  ///
  /// Uses [insertOnConflictUpdate] to handle both insert and update in one call.
  /// No sync_queue entry — checklists flow server → client only.
  Future<void> upsertChecklist(DailyChecklistsCompanion companion) async {
    await into(dailyChecklists).insertOnConflictUpdate(companion);
  }
}
