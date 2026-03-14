import 'dart:convert';

import '../../../core/database/app_database.dart';
import '../../../core/network/dio_client.dart';
import '../../../core/sync/sync_handler.dart';

/// SyncHandler implementation for the Quote entity.
///
/// Pushes quote mutations to the backend [POST/PATCH /api/v1/quotes] with
/// an [Idempotency-Key] header set to the sync_queue item's UUID.
///
/// Applies pulled entities by upserting into the Drift [quotes] and
/// [quoteLineItems] tables via [QuoteDao.upsertFromSync]. The entire
/// parent+children payload is processed in a single transaction for atomicity.
///
/// Tombstones (non-null [deleted_at] in the response) are propagated by
/// setting the local [deletedAt] column on both the quote and its line items.
class QuoteSyncHandler extends SyncHandler {
  final DioClient _dioClient;
  final AppDatabase _db;

  QuoteSyncHandler(this._dioClient, this._db);

  @override
  String get entityType => 'quote';

  @override
  Future<void> push(SyncQueueData item) async {
    final payload = jsonDecode(item.payload) as Map<String, dynamic>;

    if (item.operation == 'CREATE') {
      await _dioClient.pushWithIdempotency(
        '/quotes',
        payload,
        item.id,
      );
    } else if (item.operation == 'UPDATE') {
      await _dioClient.pushWithIdempotency(
        '/quotes/${item.entityId}',
        payload,
        item.id,
        method: 'PATCH',
      );
    } else if (item.operation == 'DELETE') {
      await _dioClient.pushWithIdempotency(
        '/quotes/${item.entityId}',
        payload,
        item.id,
        method: 'DELETE',
      );
    }
  }

  @override
  Future<void> applyPulled(Map<String, dynamic> data) async {
    await _db.quoteDao.upsertFromSync(data);
  }
}
