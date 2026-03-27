import 'dart:convert';

import 'package:drift/drift.dart';

import '../../../core/database/app_database.dart';
import '../../../core/network/dio_client.dart';
import '../../../core/sync/sync_handler.dart';

/// SyncHandler implementation for the ClientProfile entity.
///
/// Push: routes both CREATE and UPDATE to the single upsert endpoint.
/// - CREATE → POST /api/v1/clients/{user_id}/profile
/// - UPDATE → POST /api/v1/clients/{user_id}/profile  (upsert semantics)
///
/// The backend exposes only one endpoint for client profile writes:
/// `POST /clients/{user_id}/profile` with upsert semantics. There is no
/// separate PATCH endpoint. Both create and update operations map to the
/// same POST call.
///
/// user_id is extracted from payload['userId'] (camelCase, as enqueued by
/// job_dao.dart:insertClientProfile). Do NOT use item.entityId — that holds
/// the profile UUID, not the user UUID.
///
/// Pull: upserts received entities into the local Drift [clientProfiles] table.
/// Tombstones (non-null [deleted_at]) are propagated as soft deletes.
class ClientProfileSyncHandler extends SyncHandler {
  final DioClient _dioClient;
  final AppDatabase _db;

  ClientProfileSyncHandler(this._dioClient, this._db);

  @override
  String get entityType => 'client_profile';

  @override
  Future<void> push(SyncQueueData item) async {
    final payload = jsonDecode(item.payload) as Map<String, dynamic>;

    // Validate operation — only CREATE and UPDATE are supported.
    // UPDATE uses the same POST upsert endpoint as CREATE (no PATCH exists).
    switch (item.operation.toUpperCase()) {
      case 'CREATE':
      case 'UPDATE':
        // userId is stored camelCase in the enqueued payload by job_dao.dart.
        // item.entityId is the profile UUID — do NOT use it as the user_id path param.
        final userId = payload['userId'];
        if (userId is! String) {
          throw StateError('ClientProfileSyncHandler: userId required in payload');
        }
        await _dioClient.pushWithIdempotency(
          '/clients/$userId/profile',
          payload,
          item.id,
        );
      default:
        throw StateError(
          'ClientProfileSyncHandler: unknown operation "${item.operation}"',
        );
    }
  }

  @override
  Future<void> applyPulled(Map<String, dynamic> data) async {
    final id = data['id'];
    final companyId = data['company_id'];
    final userId = data['user_id'];
    if (id is! String || companyId is! String || userId is! String) {
      throw const FormatException('ClientProfile missing required fields');
    }

    final deletedAt = data['deleted_at'] != null
        ? DateTime.parse(data['deleted_at'].toString())
        : null;

    final companion = ClientProfilesCompanion(
      id: Value(id),
      companyId: Value(companyId),
      userId: Value(userId),
      billingAddress: Value(data['billing_address']?.toString()),
      tags: data['tags'] != null
          ? Value(
              data['tags'] is String
                  ? data['tags'] as String
                  : jsonEncode(data['tags']),
            )
          : const Value.absent(),
      adminNotes: Value(data['admin_notes']?.toString()),
      referralSource: Value(data['referral_source']?.toString()),
      preferredContractorId:
          Value(data['preferred_contractor_id']?.toString()),
      preferredContactMethod:
          Value(data['preferred_contact_method']?.toString()),
      averageRating: data['average_rating'] is num
          ? Value((data['average_rating'] as num).toDouble())
          : const Value.absent(),
      version: data['version'] is int
          ? Value(data['version'] as int)
          : const Value.absent(),
      createdAt: data['created_at'] != null
          ? Value(DateTime.parse(data['created_at'].toString()))
          : const Value.absent(),
      updatedAt: data['updated_at'] != null
          ? Value(DateTime.parse(data['updated_at'].toString()))
          : const Value.absent(),
      deletedAt: Value(deletedAt),
    );

    await _db.into(_db.clientProfiles).insertOnConflictUpdate(companion);
  }
}
