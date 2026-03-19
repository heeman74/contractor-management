import 'dart:convert';

import 'package:drift/drift.dart' hide isNotNull, isNull;

import '../../../core/database/app_database.dart';
import '../../../core/network/dio_client.dart';
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

int? _optionalInt(Map<String, dynamic> data, String key) {
  final value = data[key];
  if (value == null) return null;
  if (value is! int) {
    throw FormatException('Expected int? for $key, got ${value.runtimeType}');
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

/// SyncHandler implementation for the Booking entity.
///
/// Push: routes CREATE/UPDATE/DELETE to the appropriate REST endpoints.
/// - CREATE → POST /api/v1/scheduling/bookings
/// - UPDATE → PATCH /api/v1/scheduling/bookings/{id}
/// - DELETE → PATCH /api/v1/scheduling/bookings/{id} (soft-delete via PATCH with deleted_at)
///
/// Pull: upserts received entities into the local Drift [bookings] table.
/// Tombstones (non-null [deleted_at]) are propagated as soft deletes.
class BookingSyncHandler extends SyncHandler {
  final DioClient _dioClient;
  final AppDatabase _db;

  BookingSyncHandler(this._dioClient, this._db);

  @override
  String get entityType => 'booking';

  @override
  Future<void> push(SyncQueueData item) async {
    final payload = jsonDecode(item.payload) as Map<String, dynamic>;

    switch (item.operation.toUpperCase()) {
      case 'CREATE':
        await _dioClient.pushWithIdempotency(
          '/scheduling/bookings',
          payload,
          item.id,
        );
      case 'UPDATE':
        final bookingId = item.entityId;
        await _dioClient.pushWithIdempotency(
          '/scheduling/bookings/$bookingId',
          payload,
          item.id,
          method: 'PATCH',
        );
      case 'DELETE':
        final bookingId = item.entityId;
        await _dioClient.pushWithIdempotency(
          '/scheduling/bookings/$bookingId',
          payload,
          item.id,
          method: 'PATCH',
        );
      default:
        throw StateError(
          'BookingSyncHandler: unknown operation "${item.operation}"',
        );
    }
  }

  @override
  Future<void> applyPulled(Map<String, dynamic> data) async {
    final deletedAtStr = _optionalString(data, 'deleted_at');
    final deletedAt =
        deletedAtStr != null ? DateTime.parse(deletedAtStr) : null;

    final timeRangeStartStr = _optionalString(data, 'time_range_start');
    final timeRangeEndStr = _optionalString(data, 'time_range_end');
    final createdAtStr = _optionalString(data, 'created_at');
    final updatedAtStr = _optionalString(data, 'updated_at');

    final companion = BookingsCompanion(
      id: Value(_requireString(data, 'id')),
      companyId: Value(_requireString(data, 'company_id')),
      contractorId: Value(_requireString(data, 'contractor_id')),
      jobId: Value(_requireString(data, 'job_id')),
      jobSiteId: Value(_optionalString(data, 'job_site_id')),
      timeRangeStart: timeRangeStartStr != null
          ? Value(DateTime.parse(timeRangeStartStr))
          : const Value.absent(),
      timeRangeEnd: timeRangeEndStr != null
          ? Value(DateTime.parse(timeRangeEndStr))
          : const Value.absent(),
      dayIndex: Value(_optionalInt(data, 'day_index')),
      parentBookingId: Value(_optionalString(data, 'parent_booking_id')),
      notes: Value(_optionalString(data, 'notes')),
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

    await _db.into(_db.bookings).insertOnConflictUpdate(companion);
  }
}
