import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../../../shared/models/user_role.dart';
import '../../domain/auth_state.dart';

part 'auth_provider.g.dart';

/// Phase 1 auth stub — provides mock user authentication for testing route guards
/// and role-based navigation without real JWT authentication.
///
/// In v2 (Phase 6), this will be replaced by a real auth flow:
/// - Company admin enters email/password (or SSO)
/// - JWT is validated, company tenant is resolved
/// - Real userId/companyId/roles are loaded from backend
///
/// For now, [setMockUser] allows testers to pick any role combination and explore
/// the app as that user type. [logout] returns to the unauthenticated state.
@riverpod
class AuthNotifier extends _$AuthNotifier {
  @override
  AuthState build() {
    // Start in loading state — simulates the brief app bootstrap check.
    // In a real app, this is where we'd check stored tokens/session.
    return const AuthState.loading();
  }

  /// Sets a mock authenticated user for Phase 1 testing.
  ///
  /// Call this from the onboarding screen when the tester selects a role.
  /// [roles] is a Set to support multi-role users — pass multiple roles
  /// to test a user who has both admin and contractor privileges.
  void setMockUser({
    required String userId,
    required String companyId,
    required Set<UserRole> roles,
  }) {
    state = AuthState.authenticated(
      userId: userId,
      companyId: companyId,
      roles: roles,
    );
  }

  /// Clears the current session and returns to the unauthenticated state.
  /// Routes will redirect to /onboarding after this is called.
  void logout() {
    state = const AuthState.unauthenticated();
  }
}
