import 'package:drift/drift.dart' show Value;
import 'package:uuid/uuid.dart';

import '../../../core/database/app_database.dart' hide UserRole;
import '../../../shared/models/user_role.dart';

/// Details for a new team member entered in the Add Member sheet.
class NewMember {
  const NewMember({
    required this.email,
    required this.role,
    this.firstName,
    this.lastName,
    this.phone,
  });

  final String email;
  final UserRole role;
  final String? firstName;
  final String? lastName;
  final String? phone;
}

/// Team membership writes: creating members and assigning roles.
///
/// Encapsulates the user/role/client-profile inserts that were duplicated
/// across the Add Member sheet and Assign Role dialog in the screen.
class TeamManagementService {
  TeamManagementService({required AppDatabase database, Uuid uuid = const Uuid()})
      : _db = database,
        _uuid = uuid;

  static const int _initialVersion = 1;

  final AppDatabase _db;
  final Uuid _uuid;

  /// Creates a user, assigns [member].role, and (for clients) a client profile.
  Future<String> addMember({
    required String companyId,
    required NewMember member,
  }) async {
    final userId = _uuid.v4();
    final now = DateTime.now();

    await _db.userDao.insertUser(
      UsersCompanion.insert(
        id: Value(userId),
        companyId: companyId,
        email: member.email,
        firstName: Value(member.firstName),
        lastName: Value(member.lastName),
        phone: Value(member.phone),
        version: const Value(_initialVersion),
        createdAt: now,
        updatedAt: now,
      ),
    );

    await _assignRole(
      userId: userId,
      companyId: companyId,
      role: member.role,
      now: now,
    );
    return userId;
  }

  /// Assigns [role] to an existing user, creating a client profile if needed.
  Future<void> assignRole({
    required String userId,
    required String companyId,
    required UserRole role,
  }) {
    return _assignRole(
      userId: userId,
      companyId: companyId,
      role: role,
      now: DateTime.now(),
    );
  }

  Future<void> _assignRole({
    required String userId,
    required String companyId,
    required UserRole role,
    required DateTime now,
  }) async {
    await _db.userDao.assignRole(
      UserRolesCompanion.insert(
        id: Value(_uuid.v4()),
        userId: userId,
        companyId: companyId,
        role: role.name,
        createdAt: now,
      ),
    );

    if (role == UserRole.client) {
      await _db.jobDao.insertClientProfile(
        ClientProfilesCompanion.insert(
          id: Value(_uuid.v4()),
          companyId: companyId,
          userId: userId,
          createdAt: now,
          updatedAt: now,
        ),
      );
    }
  }
}
