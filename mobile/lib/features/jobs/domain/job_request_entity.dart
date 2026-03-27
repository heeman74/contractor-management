import 'package:freezed_annotation/freezed_annotation.dart';

part 'job_request_entity.freezed.dart';
part 'job_request_entity.g.dart';

/// Freezed domain entity for a JobRequest.
///
/// A JobRequest is a client-initiated service enquiry pending admin review.
/// Admins can Accept (converting to a Job) or Decline (with a reason).
///
/// [photos] holds file paths or URLs for attached photos.
/// [requestStatus] lifecycle: 'pending' → 'accepted' | 'declined'
@freezed
abstract class JobRequestEntity with _$JobRequestEntity {
  const factory JobRequestEntity({
    required String id,
    required String companyId,
    required String description, required String urgency, required List<String> photos, required String requestStatus, required int version, required DateTime createdAt, required DateTime updatedAt, String? clientId,
    String? tradeType,
    DateTime? preferredDateStart,
    DateTime? preferredDateEnd,
    double? budgetMin,
    double? budgetMax,
    String? declineReason,
    String? declineMessage,
    String? convertedJobId,
    String? submittedName,
    String? submittedEmail,
    String? submittedPhone,
    DateTime? deletedAt,
  }) = _JobRequestEntity;

  factory JobRequestEntity.fromJson(Map<String, dynamic> json) =>
      _$JobRequestEntityFromJson(json);
}
