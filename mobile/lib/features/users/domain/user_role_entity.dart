import 'package:freezed_annotation/freezed_annotation.dart';

import '../../../shared/models/user_role.dart';

part 'user_role_entity.freezed.dart';
part 'user_role_entity.g.dart';

/// Freezed domain entity for a UserRole (junction between User and Company).
///
/// A user can hold multiple roles across different companies.
/// The [role] field uses the [UserRole] enum enforced both locally and
/// via a PostgreSQL CHECK constraint on the backend.
@freezed
abstract class UserRoleEntity with _$UserRoleEntity {
  const factory UserRoleEntity({
    required String id,
    required String userId,
    required String companyId,
    required UserRole role,
    required DateTime createdAt,
  }) = _UserRoleEntity;

  factory UserRoleEntity.fromJson(Map<String, dynamic> json) =>
      _$UserRoleEntityFromJson(json);
}
