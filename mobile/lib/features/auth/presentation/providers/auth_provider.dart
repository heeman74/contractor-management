import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/auth/auth_repository.dart';
import '../../../../core/di/service_locator.dart';
import '../../../../core/network/dio_client.dart';
import '../../../../core/notifications/fcm_service.dart';
import '../../../../shared/models/user_role.dart';
import '../../domain/auth_state.dart';

final authNotifierProvider =
    NotifierProvider<AuthNotifier, AuthState>(AuthNotifier.new);

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
        // Register FCM token after session restore — fire-and-forget.
        // Failure must NOT block the restored auth state.
        _registerFcmToken();
      } else {
        state = const AuthState.unauthenticated();
      }
    } catch (_) {
      state = const AuthState.unauthenticated();
    }
  }

  /// Registers the FCM token with the backend.
  ///
  /// Called after every successful authentication (login, register, session
  /// restore). Wrapped in try/catch — FCM registration failure must NOT affect
  /// the auth flow. The user remains authenticated regardless of FCM success.
  ///
  /// Fire-and-forget: not awaited by callers (auth completes immediately).
  void _registerFcmToken() {
    try {
      final fcmService = getIt<FcmService>();
      final dioClient = getIt<DioClient>();
      // Not awaited — fire-and-forget to avoid blocking state transitions.
      // If registration fails, the error is caught inside FcmService.registerToken.
      fcmService.registerToken(dioClient).catchError((Object e) {
        debugPrint('[AuthNotifier] FCM token registration error (non-fatal): $e');
      });
    } catch (e) {
      // FcmService or DioClient not registered (e.g., test environment).
      debugPrint('[AuthNotifier] FCM service unavailable (non-fatal): $e');
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
      // Register FCM token after successful login — fire-and-forget.
      _registerFcmToken();
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
      // Register FCM token after successful registration — fire-and-forget.
      _registerFcmToken();
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
