import 'package:drift/drift.dart' hide isNotNull, isNull;

import '../../../core/database/app_database.dart';
import '../../../core/sync/sync_handler.dart';
import '../../../core/sync/sync_queue_dao.dart';

/// SyncHandler implementation for the JobSite entity.
///
/// JobSites are read-only from the mobile client's perspective:
/// - Pull: upserts received entities into the local Drift [jobSites] table.
/// - Push: NOT supported — job sites are created by admin on the backend
///   via geocoding and flow down to clients via sync pull only.
///
/// The [push] method throws [StateError] if called, as no job site mutations
/// should ever be queued from the mobile client.
class JobSiteSyncHandler extends SyncHandler {
  final AppDatabase _db;

  JobSiteSyncHandler(this._db);

  @override
  String get entityType => 'job_site';

  @override
  Future<void> push(SyncQueueData item) async {
    // Job sites are read-only on mobile — admin creates them on the backend.
    // If this is ever called, it indicates a programming error.
    throw StateError(
      'JobSiteSyncHandler: push is not supported. '
      'Job sites are read-only on mobile — they are created by admin via backend geocoding.',
    );
  }

  @override
  Future<void> applyPulled(Map<String, dynamic> data) async {
    final deletedAt = data['deleted_at'] != null
        ? DateTime.parse(data['deleted_at'] as String)
        : null;

    // Parse lat/lng — backend stores as Numeric(9,6), JSON serializes as number.
    final lat = data['lat'] is num ? (data['lat'] as num).toDouble() : null;
    final lng = data['lng'] is num ? (data['lng'] as num).toDouble() : null;

    final companion = JobSitesCompanion(
      id: Value(data['id'] as String),
      companyId: Value(data['company_id'] as String),
      address: Value(data['address'] as String),
      lat: Value(lat),
      lng: Value(lng),
      formattedAddress: Value(data['formatted_address'] as String?),
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

    await _db.into(_db.jobSites).insertOnConflictUpdate(companion);
  }
}
