import 'dart:convert';

import 'package:drift/drift.dart' hide isNotNull, isNull;

import '../../../core/database/app_database.dart';
import '../../../core/network/dio_client.dart';
import '../../../core/sync/sync_handler.dart';
import '../../../core/sync/sync_queue_dao.dart'; // SyncQueueData type

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
    final deletedAt = data['deleted_at'] != null
        ? DateTime.parse(data['deleted_at'] as String)
        : null;

    final companion = BookingsCompanion(
      id: Value(data['id'] as String),
      companyId: Value(data['company_id'] as String),
      contractorId: Value(data['contractor_id'] as String),
      jobId: Value(data['job_id'] as String),
      jobSiteId: Value(data['job_site_id'] as String?),
      timeRangeStart: data['time_range_start'] != null
          ? Value(DateTime.parse(data['time_range_start'] as String))
          : const Value.absent(),
      timeRangeEnd: data['time_range_end'] != null
          ? Value(DateTime.parse(data['time_range_end'] as String))
          : const Value.absent(),
      dayIndex: Value(data['day_index'] as int?),
      parentBookingId: Value(data['parent_booking_id'] as String?),
      notes: Value(data['notes'] as String?),
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

    await _db.into(_db.bookings).insertOnConflictUpdate(companion);
  }
}
