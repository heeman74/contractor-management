import 'dart:convert';

import 'package:drift/drift.dart';

import '../../../core/database/app_database.dart';
import '../../../core/network/dio_client.dart';
import '../../../core/sync/sync_handler.dart';
import '../../../core/sync/sync_queue_dao.dart';

/// SyncHandler implementation for the ClientProfile entity.
///
/// Push: routes CREATE/UPDATE to the client profile REST endpoints.
/// - CREATE → POST /api/v1/clients/profiles
/// - UPDATE → PATCH /api/v1/clients/profiles/{id}
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

    switch (item.operation.toUpperCase()) {
      case 'CREATE':
        await _dioClient.pushWithIdempotency(
          '/clients/profiles',
          payload,
          item.id,
        );
      case 'UPDATE':
        final profileId = item.entityId;
        await _dioClient.pushWithIdempotency(
          '/clients/profiles/$profileId',
          payload,
          item.id,
          method: 'PATCH',
        );
      default:
        throw StateError(
          'ClientProfileSyncHandler: unknown operation "${item.operation}"',
        );
    }
  }

  @override
  Future<void> applyPulled(Map<String, dynamic> data) async {
    final deletedAt = data['deleted_at'] != null
        ? DateTime.parse(data['deleted_at'] as String)
        : null;

    final companion = ClientProfilesCompanion(
      id: Value(data['id'] as String),
      companyId: Value(data['company_id'] as String),
      userId: Value(data['user_id'] as String),
      billingAddress: Value(data['billing_address'] as String?),
      tags: data['tags'] != null
          ? Value(
              data['tags'] is String
                  ? data['tags'] as String
                  : jsonEncode(data['tags']),
            )
          : const Value.absent(),
      adminNotes: Value(data['admin_notes'] as String?),
      referralSource: Value(data['referral_source'] as String?),
      preferredContractorId:
          Value(data['preferred_contractor_id'] as String?),
      preferredContactMethod:
          Value(data['preferred_contact_method'] as String?),
      averageRating: data['average_rating'] != null
          ? Value((data['average_rating'] as num).toDouble())
          : const Value.absent(),
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

    await _db.into(_db.clientProfiles).insertOnConflictUpdate(companion);
  }
}
