import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/auth/auth_repository.dart';
import '../../../../core/di/service_locator.dart';
import '../../../../shared/models/user_role.dart';
import '../../domain/auth_state.dart';

part 'auth_provider.g.dart';

class AuthNotifier extends Notifier<AuthState> {
  late final AuthRepository _authRepository;

  @override
  AuthState build() {
    _authRepository = getIt<AuthRepository>();

    // Try to restore session from stored tokens on app start
    _restoreSession();

    return const AuthState.loading();
  }

  Future<void> _restoreSession() async {
    try {
      final result = await _authRepository.restoreSession();
      if (result != null) {
        state = AuthState.authenticated(
          userId: result.userId,
          companyId: result.companyId,
          roles: result.roles.map(UserRole.fromString).toSet(),
        );
      } else {
        state = const AuthState.unauthenticated();
      }
    } catch (_) {
      state = const AuthState.unauthenticated();
    }
  }

  /// Login with email + password.
  /// Returns null on success, error message on failure.
  Future<String?> login({
    required String email,
    required String password,
  }) async {
    try {
      final result = await _authRepository.login(
        email: email,
        password: password,
      );
      state = AuthState.authenticated(
        userId: result.userId,
        companyId: result.companyId,
        roles: result.roles.map(UserRole.fromString).toSet(),
      );
      return null;
    } on DioException catch (e) {
      if (e.response?.statusCode == 401) {
        return 'Invalid email or password';
      }
      return 'Network error. Please try again.';
    } catch (e) {
      return 'An unexpected error occurred';
    }
  }

  /// Register a new company + admin user.
  /// Returns null on success, error message on failure.
  Future<String?> register({
    required String email,
    required String password,
    required String companyName,
    String? firstName,
    String? lastName,
  }) async {
    try {
      final result = await _authRepository.register(
        email: email,
        password: password,
        companyName: companyName,
        firstName: firstName,
        lastName: lastName,
      );
      state = AuthState.authenticated(
        userId: result.userId,
        companyId: result.companyId,
        roles: result.roles.map(UserRole.fromString).toSet(),
      );
      return null;
    } on DioException catch (e) {
      if (e.response?.statusCode == 409) {
        return 'Email already registered';
      }
      return 'Network error. Please try again.';
    } catch (e) {
      return 'An unexpected error occurred';
    }
  }

  /// Clears the current session and returns to the unauthenticated state.
  Future<void> logout() async {
    await _authRepository.logout();
    state = const AuthState.unauthenticated();
  }
}
