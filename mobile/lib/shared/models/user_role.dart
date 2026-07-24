/// User role types — the roles that users can hold within a company.
///
/// A user can have multiple roles simultaneously (e.g. admin + contractor).
/// Enforced via the UserRoles junction table and backend RLS policies. The
/// backend uses snake_case slugs (e.g. 'project_manager'); see [slug]/[fromString].
enum UserRole {
  owner,
  admin,
  projectManager,
  gc,
  foreman,
  contractor,
  worker,
  client;

  /// Convert from the backend snake_case slug.
  ///
  /// Returns null for an unknown/future role rather than throwing, so a single
  /// unrecognized role never crashes login. Callers filter with whereType.
  static UserRole? fromString(String value) {
    switch (value) {
      case 'owner':
        return UserRole.owner;
      case 'admin':
        return UserRole.admin;
      case 'project_manager':
        return UserRole.projectManager;
      case 'gc':
        return UserRole.gc;
      case 'foreman':
        return UserRole.foreman;
      case 'contractor':
        return UserRole.contractor;
      case 'worker':
        return UserRole.worker;
      case 'client':
        return UserRole.client;
      default:
        return null;
    }
  }

  /// The backend snake_case slug for this role (round-trips with [fromString]).
  String get slug {
    switch (this) {
      case UserRole.projectManager:
        return 'project_manager';
      default:
        return name;
    }
  }

  /// Human-readable label for UI display.
  String get displayLabel {
    switch (this) {
      case UserRole.owner:
        return 'Owner';
      case UserRole.admin:
        return 'Admin';
      case UserRole.projectManager:
        return 'Project Manager';
      case UserRole.gc:
        return 'General Contractor';
      case UserRole.foreman:
        return 'Foreman';
      case UserRole.contractor:
        return 'Contractor';
      case UserRole.worker:
        return 'Worker';
      case UserRole.client:
        return 'Client';
    }
  }

  /// Owner or admin — full administrative capability.
  bool get isAdminLevel => this == UserRole.owner || this == UserRole.admin;

  /// Owner, admin, or project manager — can manage operations.
  bool get isManagerLevel => isAdminLevel || this == UserRole.projectManager;

  /// Owner, admin, or GC — oversees construction (inspections, foreman).
  bool get isGcLevel => isAdminLevel || this == UserRole.gc;
}
