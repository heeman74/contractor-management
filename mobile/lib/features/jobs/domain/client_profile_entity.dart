import 'package:freezed_annotation/freezed_annotation.dart';

part 'client_profile_entity.freezed.dart';
part 'client_profile_entity.g.dart';

/// Freezed domain entity for a ClientProfile.
///
/// Extends a User (with 'client' role) with CRM-specific data per company.
/// The [userId] FK points to the Users table; [companyId] provides tenant scope.
///
/// [tags] holds decoded string labels for client segmentation.
/// [averageRating] is a cached aggregate recomputed on sync (1.0–5.0 or null).
@freezed
abstract class ClientProfileEntity with _$ClientProfileEntity {
  const factory ClientProfileEntity({
    required String id,
    required String companyId,
    required String userId,
    required List<String> tags, required int version, required DateTime createdAt, required DateTime updatedAt, String? billingAddress,
    String? adminNotes,
    String? referralSource,
    String? preferredContractorId,
    String? preferredContactMethod,
    double? averageRating,
    DateTime? deletedAt,
  }) = _ClientProfileEntity;

  factory ClientProfileEntity.fromJson(Map<String, dynamic> json) =>
      _$ClientProfileEntityFromJson(json);
}
