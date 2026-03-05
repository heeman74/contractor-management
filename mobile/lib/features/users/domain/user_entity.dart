import 'package:freezed_annotation/freezed_annotation.dart';

part 'user_entity.freezed.dart';
part 'user_entity.g.dart';

/// Freezed domain entity for a User.
///
/// Users are tenant-scoped via [companyId] — always belongs to exactly one
/// company for auth purposes, though they may have roles in multiple companies
/// (represented via [UserRoleEntity]).
@freezed
abstract class UserEntity with _$UserEntity {
  const factory UserEntity({
    required String id,
    required String companyId,
    required String email,
    String? firstName,
    String? lastName,
    String? phone,
    required int version,
    required DateTime createdAt,
    required DateTime updatedAt,
  }) = _UserEntity;

  factory UserEntity.fromJson(Map<String, dynamic> json) =>
      _$UserEntityFromJson(json);
}
