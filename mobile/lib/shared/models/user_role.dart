/// User role types — the three roles that users can hold within a company.
///
/// A user can have multiple roles across different companies.
/// Enforced via UserRoles junction table and backend RLS policies.
enum UserRole {
  admin,
  contractor,
  client;

  /// Convert from string stored in DB/API.
  static UserRole fromString(String value) {
    return UserRole.values.firstWhere(
      (r) => r.name == value,
      orElse: () => throw ArgumentError('Unknown UserRole: $value'),
    );
  }
}
