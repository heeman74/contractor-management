import 'package:freezed_annotation/freezed_annotation.dart';

import '../../../shared/models/trade_type.dart';

part 'company_entity.freezed.dart';
part 'company_entity.g.dart';

/// Freezed domain entity for a Company (tenant root).
///
/// Maps from Drift [Company] row and backend [CompanyResponse] API schema.
/// Used throughout all feature screens — never use ORM rows directly in UI.
@freezed
abstract class CompanyEntity with _$CompanyEntity {
  const factory CompanyEntity({
    required String id,
    required String name,
    String? address,
    String? phone,
    @Default([]) List<TradeType> tradeTypes,
    String? logoUrl,
    String? businessNumber,
    required int version,
    required DateTime createdAt,
    required DateTime updatedAt,
  }) = _CompanyEntity;

  factory CompanyEntity.fromJson(Map<String, dynamic> json) =>
      _$CompanyEntityFromJson(json);
}
