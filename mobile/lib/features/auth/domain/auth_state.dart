import 'package:freezed_annotation/freezed_annotation.dart';

import '../../../shared/models/user_role.dart';

part 'auth_state.freezed.dart';

/// Authentication state — drives route guards and UI rendering across the app.
///
/// AuthLoading: initial state while app bootstraps (shows splash screen).
/// AuthUnauthenticated: no user session (shows onboarding/login).
/// AuthAuthenticated: active session with userId, companyId, and roles set.
///
/// NOTE: Using a Set<UserRole> for roles supports the multi-role requirement
/// (e.g., contractor in company A, admin in company B — two separate AuthAuthenticated
/// states when switching companies, or a user with both admin + contractor in one company).
@freezed
sealed class AuthState with _$AuthState {
  const factory AuthState.loading() = AuthLoading;
  const factory AuthState.unauthenticated() = AuthUnauthenticated;
  const factory AuthState.authenticated({
    required String userId,
    required String companyId,
    required Set<UserRole> roles,
  }) = AuthAuthenticated;
}
