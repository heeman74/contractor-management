import 'package:freezed_annotation/freezed_annotation.dart';

part 'booking_entity.freezed.dart';
part 'booking_entity.g.dart';

/// Freezed domain entity for a Booking.
///
/// The canonical representation of a booking in the mobile domain layer.
/// Sourced from the local Drift DB (offline-first) and updated via sync.
///
/// A booking represents a scheduled time block for a contractor on a job.
/// Multi-day jobs produce multiple BookingEntity instances linked by
/// [parentBookingId] and ordered by [dayIndex].
///
/// [timeRangeStart] and [timeRangeEnd] are UTC — display layer converts
/// to local timezone using the device locale.
@freezed
abstract class BookingEntity with _$BookingEntity {
  const factory BookingEntity({
    required String id,
    required String companyId,
    required String contractorId,
    required String jobId,
    required DateTime timeRangeStart,
    required DateTime timeRangeEnd,
    required int version,
    required DateTime createdAt,
    required DateTime updatedAt,
    String? jobSiteId,
    int? dayIndex,
    String? parentBookingId,
    String? notes,
    DateTime? deletedAt,
  }) = _BookingEntity;

  factory BookingEntity.fromJson(Map<String, dynamic> json) =>
      _$BookingEntityFromJson(json);
}
