import 'package:drift/drift.dart' hide isNotNull, isNull;

import '../../../core/database/app_database.dart';
import '../../../core/sync/sync_handler.dart';

/// Type-safe helpers for parsing API response data.
///
/// These avoid bare `as` casts on dynamic maps, throwing [FormatException]
/// with clear messages when the response shape doesn't match expectations.
String _requireString(Map<String, dynamic> data, String key) {
  final value = data[key];
  if (value is! String) {
    throw FormatException('Expected String for $key, got ${value.runtimeType}');
  }
  return value;
}

String? _optionalString(Map<String, dynamic> data, String key) {
  final value = data[key];
  if (value == null) return null;
  if (value is! String) {
    throw FormatException('Expected String? for $key, got ${value.runtimeType}');
  }
  return value;
}

int _requireInt(Map<String, dynamic> data, String key) {
  final value = data[key];
  if (value is! int) {
    throw FormatException('Expected int for $key, got ${value.runtimeType}');
  }
  return value;
}

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
    final deletedAtStr = _optionalString(data, 'deleted_at');
    final deletedAt =
        deletedAtStr != null ? DateTime.parse(deletedAtStr) : null;

    // Parse latitude/longitude — backend JobSiteResponse field names.
    // The Drift column names (lat, lng) differ from the backend JSON keys.
    final lat =
        data['latitude'] is num ? (data['latitude'] as num).toDouble() : null;
    final lng =
        data['longitude'] is num ? (data['longitude'] as num).toDouble() : null;

    final createdAtStr = _optionalString(data, 'created_at');
    final updatedAtStr = _optionalString(data, 'updated_at');

    final companion = JobSitesCompanion(
      id: Value(_requireString(data, 'id')),
      companyId: Value(_requireString(data, 'company_id')),
      address: Value(_requireString(data, 'address')),
      lat: Value(lat),
      lng: Value(lng),
      formattedAddress: Value(_optionalString(data, 'formatted_address')),
      version: data['version'] != null
          ? Value(_requireInt(data, 'version'))
          : const Value.absent(),
      createdAt: createdAtStr != null
          ? Value(DateTime.parse(createdAtStr))
          : const Value.absent(),
      updatedAt: updatedAtStr != null
          ? Value(DateTime.parse(updatedAtStr))
          : const Value.absent(),
      deletedAt: Value(deletedAt),
    );

    await _db.into(_db.jobSites).insertOnConflictUpdate(companion);
  }
}
