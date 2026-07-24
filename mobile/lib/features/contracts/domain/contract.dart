import 'package:flutter/foundation.dart';

/// Lifecycle status of a contract, mirroring the backend enum.
///
/// The backend guarantees one of `draft | sent | viewed | signed | declined |
/// voided`, but the enum includes an [unknown] fallback so a future/renamed
/// server value never crashes the client — [fromString] never throws.
enum ContractStatus {
  draft,
  sent,
  viewed,
  signed,
  declined,
  voided,

  /// Value the client does not recognise — treated as read-only / no actions.
  unknown;

  /// Parse a wire value into a [ContractStatus]. Unknown/`null` inputs map to
  /// [ContractStatus.unknown] rather than throwing (defensive parsing).
  static ContractStatus fromString(String? value) {
    switch (value) {
      case 'draft':
        return ContractStatus.draft;
      case 'sent':
        return ContractStatus.sent;
      case 'viewed':
        return ContractStatus.viewed;
      case 'signed':
        return ContractStatus.signed;
      case 'declined':
        return ContractStatus.declined;
      case 'voided':
        return ContractStatus.voided;
      default:
        return ContractStatus.unknown;
    }
  }

  /// Human-readable label for display in the client UI.
  String get displayLabel {
    switch (this) {
      case ContractStatus.draft:
        return 'Draft';
      case ContractStatus.sent:
        return 'Awaiting your signature';
      case ContractStatus.viewed:
        return 'Awaiting your signature';
      case ContractStatus.signed:
        return 'Signed';
      case ContractStatus.declined:
        return 'Declined';
      case ContractStatus.voided:
        return 'Voided';
      case ContractStatus.unknown:
        return 'Unknown';
    }
  }

  /// Whether the contract is ready for the client to open the signing ceremony.
  bool get isSignable =>
      this == ContractStatus.sent || this == ContractStatus.viewed;

  /// Whether a signed PDF is expected to be available.
  bool get isSigned => this == ContractStatus.signed;
}

/// Immutable domain model for a client contract.
///
/// Constructed only via [Contract.fromJson], which validates the wire shape
/// and throws a [FormatException] on a type mismatch (no bare `as` casts on
/// untrusted API data — per project rules).
@immutable
class Contract {
  const Contract({
    required this.id,
    required this.status,
    this.companyId,
    this.quoteId,
    this.jobId,
    this.clientUserId,
    this.termsSnapshot,
    this.validityStatement,
    this.unsignedPdfUrl,
    this.signedPdfUrl,
    this.provider,
    this.providerRequestId,
    this.signerName,
    this.signerEmail,
    this.sentAt,
    this.viewedAt,
    this.signedAt,
    this.declinedAt,
    this.createdAt,
    this.updatedAt,
  });

  final String id;
  final ContractStatus status;
  final String? companyId;
  final String? quoteId;
  final String? jobId;
  final String? clientUserId;
  final String? termsSnapshot;
  final String? validityStatement;
  final String? unsignedPdfUrl;
  final String? signedPdfUrl;
  final String? provider;
  final String? providerRequestId;
  final String? signerName;
  final String? signerEmail;
  final DateTime? sentAt;
  final DateTime? viewedAt;
  final DateTime? signedAt;
  final DateTime? declinedAt;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  /// Parse a contract JSON object from the backend.
  ///
  /// Throws [FormatException] when [json] is not a map or lacks a string `id`.
  /// Optional fields are parsed leniently: wrong-typed values become `null`
  /// rather than throwing, but the required identity fields are validated.
  factory Contract.fromJson(Object? json) {
    if (json is! Map<String, dynamic>) {
      throw FormatException(
        'Expected a JSON object for Contract, got ${json.runtimeType}',
      );
    }

    final id = json['id'];
    if (id is! String || id.isEmpty) {
      throw FormatException(
        'Contract JSON missing a valid string "id" (got ${id.runtimeType})',
      );
    }

    // Status must be a string when present; a non-string is a shape violation.
    final rawStatus = json['status'];
    if (rawStatus != null && rawStatus is! String) {
      throw FormatException(
        'Contract "status" must be a string, got ${rawStatus.runtimeType}',
      );
    }

    return Contract(
      id: id,
      status: ContractStatus.fromString(rawStatus is String ? rawStatus : null),
      companyId: _asString(json['company_id']),
      quoteId: _asString(json['quote_id']),
      jobId: _asString(json['job_id']),
      clientUserId: _asString(json['client_user_id']),
      termsSnapshot: _asString(json['terms_snapshot']),
      validityStatement: _asString(json['validity_statement']),
      unsignedPdfUrl: _asString(json['unsigned_pdf_url']),
      signedPdfUrl: _asString(json['signed_pdf_url']),
      provider: _asString(json['provider']),
      providerRequestId: _asString(json['provider_request_id']),
      signerName: _asString(json['signer_name']),
      signerEmail: _asString(json['signer_email']),
      sentAt: _asDate(json['sent_at']),
      viewedAt: _asDate(json['viewed_at']),
      signedAt: _asDate(json['signed_at']),
      declinedAt: _asDate(json['declined_at']),
      createdAt: _asDate(json['created_at']),
      updatedAt: _asDate(json['updated_at']),
    );
  }

  /// Return a string value, or `null` if the field is absent/non-string.
  static String? _asString(Object? value) => value is String ? value : null;

  /// Parse an ISO-8601 timestamp, tolerating `null`/non-string/unparseable.
  static DateTime? _asDate(Object? value) {
    if (value is! String) return null;
    return DateTime.tryParse(value);
  }
}
