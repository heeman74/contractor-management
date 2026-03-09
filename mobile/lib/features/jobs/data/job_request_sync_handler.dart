import 'dart:convert';

import 'package:drift/drift.dart';

import '../../../core/database/app_database.dart';
import '../../../core/network/dio_client.dart';
import '../../../core/sync/sync_handler.dart';
import '../../../core/sync/sync_queue_dao.dart';

/// SyncHandler implementation for the JobRequest entity.
///
/// Push: routes CREATE to the job requests REST endpoint.
/// - CREATE → POST /api/v1/jobs/requests
///
/// Status transitions on the backend (Accept/Decline) are admin actions via
/// the backend API and flow back to mobile via pull sync — not pushed from mobile.
///
/// Pull: upserts received entities into the local Drift [jobRequests] table.
/// Tombstones (non-null [deleted_at]) are propagated as soft deletes.
class JobRequestSyncHandler extends SyncHandler {
  final DioClient _dioClient;
  final AppDatabase _db;

  JobRequestSyncHandler(this._dioClient, this._db);

  @override
  String get entityType => 'job_request';

  @override
  Future<void> push(SyncQueueData item) async {
    final payload = jsonDecode(item.payload) as Map<String, dynamic>;

    switch (item.operation.toUpperCase()) {
      case 'CREATE':
        await _dioClient.pushWithIdempotency(
          '/jobs/requests',
          payload,
          item.id,
        );
      default:
        throw StateError(
          'JobRequestSyncHandler: unknown operation "${item.operation}"',
        );
    }
  }

  @override
  Future<void> applyPulled(Map<String, dynamic> data) async {
    final deletedAt = data['deleted_at'] != null
        ? DateTime.parse(data['deleted_at'] as String)
        : null;

    final companion = JobRequestsCompanion(
      id: Value(data['id'] as String),
      companyId: Value(data['company_id'] as String),
      clientId: Value(data['client_id'] as String?),
      description: Value(data['description'] as String),
      tradeType: Value(data['trade_type'] as String?),
      urgency: data['urgency'] != null
          ? Value(data['urgency'] as String)
          : const Value.absent(),
      preferredDateStart: data['preferred_date_start'] != null
          ? Value(DateTime.parse(data['preferred_date_start'] as String))
          : const Value.absent(),
      preferredDateEnd: data['preferred_date_end'] != null
          ? Value(DateTime.parse(data['preferred_date_end'] as String))
          : const Value.absent(),
      budgetMin: data['budget_min'] != null
          ? Value((data['budget_min'] as num).toDouble())
          : const Value.absent(),
      budgetMax: data['budget_max'] != null
          ? Value((data['budget_max'] as num).toDouble())
          : const Value.absent(),
      photos: data['photos'] != null
          ? Value(
              data['photos'] is String
                  ? data['photos'] as String
                  : jsonEncode(data['photos']),
            )
          : const Value.absent(),
      requestStatus: data['status'] != null
          ? Value(data['status'] as String)
          : const Value.absent(),
      declineReason: Value(data['decline_reason'] as String?),
      declineMessage: Value(data['decline_message'] as String?),
      convertedJobId: Value(data['converted_job_id'] as String?),
      submittedName: Value(data['submitted_name'] as String?),
      submittedEmail: Value(data['submitted_email'] as String?),
      submittedPhone: Value(data['submitted_phone'] as String?),
      version: data['version'] != null
          ? Value(data['version'] as int)
          : const Value.absent(),
      createdAt: data['created_at'] != null
          ? Value(DateTime.parse(data['created_at'] as String))
          : const Value.absent(),
      updatedAt: data['updated_at'] != null
          ? Value(DateTime.parse(data['updated_at'] as String))
          : const Value.absent(),
      deletedAt: Value(deletedAt),
    );

    await _db.into(_db.jobRequests).insertOnConflictUpdate(companion);
  }
}
