import 'dart:convert';

import '../../database/app_database.dart';
import '../../network/dio_client.dart';
import '../sync_handler.dart';

/// SyncHandler implementation for the CostEntry entity.
///
/// Pushes cost-entry mutations to the flat `/cost-entries` collection with
/// an [Idempotency-Key] header set to the sync_queue item's UUID:
///   CREATE -> POST   /cost-entries/
///   UPDATE -> PATCH  /cost-entries/{id}
///   DELETE -> DELETE /cost-entries/{id}
///
/// [applyPulled] upserts into the local `CostEntries` table via
/// [CostEntryDao.upsertFromRemote] — used by the ON-DEMAND `FinanceRepository`
/// fetch (fetchCostEntriesForJob/fetchCostEntriesForTradeScope/
/// fetchProjectRollup), NEVER by the company-wide /sync delta
/// (31-RESEARCH.md Pitfall 2 — cost data must not leak to non-finance
/// devices via /sync; this handler is intentionally NOT registered in
/// `sync_engine.dart`'s `pullDelta` entityTypes list).
///
/// [data] passed to [applyPulled] must include an injected `'company_id'`
/// key since `CostEntryResponse` does not carry company_id (see
/// `FinanceRepository`).
class CostEntrySyncHandler extends SyncHandler {
  final DioClient _dioClient;
  final AppDatabase _db;

  CostEntrySyncHandler(this._dioClient, this._db);

  @override
  String get entityType => 'cost_entry';

  @override
  Future<void> push(SyncQueueData item) async {
    final payload = jsonDecode(item.payload) as Map<String, dynamic>;

    if (item.operation == 'CREATE') {
      await _dioClient.pushWithIdempotency(
        '/cost-entries/',
        payload,
        item.id,
      );
    } else if (item.operation == 'UPDATE') {
      await _dioClient.pushWithIdempotency(
        '/cost-entries/${item.entityId}',
        payload,
        item.id,
        method: 'PATCH',
      );
    } else if (item.operation == 'DELETE') {
      await _dioClient.pushWithIdempotency(
        '/cost-entries/${item.entityId}',
        payload,
        item.id,
        method: 'DELETE',
      );
    }
  }

  @override
  Future<void> applyPulled(Map<String, dynamic> data) async {
    await _db.costEntryDao.upsertFromRemote(data);
  }
}
