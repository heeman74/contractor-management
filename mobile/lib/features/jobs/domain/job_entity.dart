import 'package:freezed_annotation/freezed_annotation.dart';

import 'job_status.dart';

part 'job_entity.freezed.dart';
part 'job_entity.g.dart';

/// Freezed domain entity for a Job.
///
/// The canonical representation of a job in the mobile domain layer.
/// Sourced from the local Drift DB (offline-first) and updated via sync.
///
/// [statusHistory] is decoded from the JSON TEXT column in Drift —
/// each entry: {status: String, timestamp: String, userId: String, reason: String?}
///
/// [tags] is decoded from the JSON TEXT column in Drift.
///
/// Use [jobStatus] to get the typed [JobStatus] enum from the raw [status] string.
@freezed
abstract class JobEntity with _$JobEntity {
  const JobEntity._(); // Allow custom getters on the generated class

  const factory JobEntity({
    required String id,
    required String companyId,
    String? clientId,
    String? contractorId,
    required String description,
    required String tradeType,
    required String status,
    required List<Map<String, dynamic>> statusHistory,
    required String priority,
    String? purchaseOrderNumber,
    String? externalReference,
    required List<String> tags,
    String? notes,
    int? estimatedDurationMinutes,
    DateTime? scheduledCompletionDate,
    double? gpsLatitude,
    double? gpsLongitude,
    String? gpsAddress,
    required int version,
    required DateTime createdAt,
    required DateTime updatedAt,
    DateTime? deletedAt,
  }) = _JobEntity;

  factory JobEntity.fromJson(Map<String, dynamic> json) =>
      _$JobEntityFromJson(json);

  /// Typed lifecycle status — parsed from the raw [status] string.
  JobStatus get jobStatus => JobStatus.fromString(status);
}
