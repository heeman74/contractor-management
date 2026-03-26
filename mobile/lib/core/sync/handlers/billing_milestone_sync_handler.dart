import 'dart:convert';

import '../../database/app_database.dart';
import '../../network/dio_client.dart';
import '../sync_handler.dart';

/// SyncHandler implementation for the BillingMilestone entity.
///
/// Pushes milestone mutations to [POST /api/v1/scopes/{trade_scope_id}/milestones]
/// and [PATCH /api/v1/milestones/{milestone_id}] with an [Idempotency-Key]
/// header set to the sync_queue item's UUID.
///
/// Applies pulled entities by upserting into the Drift [billingMilestones] table
/// via [BillingMilestoneDao.upsertFromSync].
class BillingMilestoneSyncHandler extends SyncHandler {
  final DioClient _dioClient;
  final AppDatabase _db;

  BillingMilestoneSyncHandler(this._dioClient, this._db);

  @override
  String get entityType => 'billing_milestone';

  @override
  Future<void> push(SyncQueueData item) async {
    final payload = jsonDecode(item.payload) as Map<String, dynamic>;
    final tradeScopeId = payload['trade_scope_id'] as String?;

    if (item.operation == 'CREATE') {
      if (tradeScopeId == null) {
        throw StateError(
            'BillingMilestoneSyncHandler: trade_scope_id is required in CREATE payload');
      }
      await _dioClient.pushWithIdempotency(
        '/scopes/$tradeScopeId/milestones',
        payload,
        item.id,
      );
    } else if (item.operation == 'UPDATE') {
      await _dioClient.pushWithIdempotency(
        '/milestones/${item.entityId}',
        payload,
        item.id,
        method: 'PATCH',
      );
    } else if (item.operation == 'DELETE') {
      await _dioClient.pushWithIdempotency(
        '/milestones/${item.entityId}',
        payload,
        item.id,
        method: 'DELETE',
      );
    }
  }

  @override
  Future<void> applyPulled(Map<String, dynamic> data) async {
    await _db.billingMilestoneDao.upsertFromSync(data);
  }
}
