/// Unit tests for AuthNotifier state management.
///
/// Uses mocktail to mock AuthRepository registered in GetIt.
/// Tests verify auth state transitions through login/logout/register.
library;

import 'package:contractorhub/core/auth/auth_repository.dart';
import 'package:contractorhub/core/di/service_locator.dart';
import 'package:contractorhub/features/auth/domain/auth_state.dart';
import 'package:contractorhub/features/auth/presentation/providers/auth_provider.dart';
import 'package:contractorhub/shared/models/user_role.dart';
import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

class MockAuthRepository extends Mock implements AuthRepository {}

void main() {
  late MockAuthRepository mockAuthRepo;
  late ProviderContainer container;

  setUp(() {
    mockAuthRepo = MockAuthRepository();

    // Reset GetIt and register mock
    if (getIt.isRegistered<AuthRepository>()) {
      getIt.unregister<AuthRepository>();
    }
    getIt.registerSingleton<AuthRepository>(mockAuthRepo);

    // Default: restoreSession returns null -> unauthenticated
    when(() => mockAuthRepo.restoreSession()).thenAnswer((_) async => null);
    // Default: logout succeeds
    when(() => mockAuthRepo.logout()).thenAnswer((_) async {});

    container = ProviderContainer();
  });

  tearDown(() {
    container.dispose();
  });

  /// Wait for async _restoreSession to finish.
  Future<void> waitForRestore() async {
    // Pump microtasks until state is no longer loading
    for (var i = 0; i < 20; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 10));
      final s = container.read(authNotifierProvider);
      if (s is! AuthLoading) break;
    }
  }

  test('starts in loading state, then transitions to unauthenticated', () async {
    final state = container.read(authNotifierProvider);
    expect(state, isA<AuthLoading>());

    await waitForRestore();
    expect(container.read(authNotifierProvider), isA<AuthUnauthenticated>());
  });

  test('login success transitions to authenticated state', () async {
    await waitForRestore();

    when(() => mockAuthRepo.login(
          email: any(named: 'email'),
          password: any(named: 'password'),
        )).thenAnswer((_) async => AuthResult(
          userId: 'user-123',
          companyId: 'company-456',
          roles: ['admin'],
        ));

    final notifier = container.read(authNotifierProvider.notifier);
    final error = await notifier.login(
      email: 'test@test.com',
      password: 'password123',
    );

    expect(error, isNull);
    final state = container.read(authNotifierProvider) as AuthAuthenticated;
    expect(state.userId, equals('user-123'));
    expect(state.companyId, equals('company-456'));
    expect(state.roles, contains(UserRole.admin));
  });

  test('login 401 returns error message', () async {
    await waitForRestore();

    when(() => mockAuthRepo.login(
          email: any(named: 'email'),
          password: any(named: 'password'),
        )).thenThrow(DioException(
      requestOptions: RequestOptions(path: '/auth/login'),
      type: DioExceptionType.badResponse,
      response: Response(
        statusCode: 401,
        requestOptions: RequestOptions(path: '/auth/login'),
      ),
    ));

    final notifier = container.read(authNotifierProvider.notifier);
    final error = await notifier.login(email: 'bad@test.com', password: 'wrong');

    expect(error, equals('Invalid email or password'));
  });

  test('logout transitions to unauthenticated state', () async {
    await waitForRestore();

    when(() => mockAuthRepo.login(
          email: any(named: 'email'),
          password: any(named: 'password'),
        )).thenAnswer((_) async => AuthResult(
          userId: 'u-1',
          companyId: 'c-1',
          roles: ['contractor'],
        ));

    final notifier = container.read(authNotifierProvider.notifier);
    await notifier.login(email: 'x@x.com', password: 'pass1234');
    expect(container.read(authNotifierProvider), isA<AuthAuthenticated>());

    await notifier.logout();
    expect(container.read(authNotifierProvider), isA<AuthUnauthenticated>());
  });

  test('authenticated state with multiple roles contains all roles', () async {
    await waitForRestore();

    when(() => mockAuthRepo.login(
          email: any(named: 'email'),
          password: any(named: 'password'),
        )).thenAnswer((_) async => AuthResult(
          userId: 'u-1',
          companyId: 'c-1',
          roles: ['admin', 'contractor'],
        ));

    final notifier = container.read(authNotifierProvider.notifier);
    await notifier.login(email: 'x@x.com', password: 'pass1234');

    final state = container.read(authNotifierProvider) as AuthAuthenticated;
    expect(state.roles, contains(UserRole.admin));
    expect(state.roles, contains(UserRole.contractor));
    expect(state.roles, hasLength(2));
  });

  test('all three role types can be set', () async {
    await waitForRestore();

    when(() => mockAuthRepo.login(
          email: any(named: 'email'),
          password: any(named: 'password'),
        )).thenAnswer((_) async => AuthResult(
          userId: 'u-1',
          companyId: 'c-1',
          roles: ['admin', 'contractor', 'client'],
        ));

    final notifier = container.read(authNotifierProvider.notifier);
    await notifier.login(email: 'x@x.com', password: 'pass1234');

    final state = container.read(authNotifierProvider) as AuthAuthenticated;
    expect(state.roles, containsAll([
      UserRole.admin,
      UserRole.contractor,
      UserRole.client,
    ]));
    expect(state.roles, hasLength(3));
  });

  test('register 409 returns duplicate email message', () async {
    await waitForRestore();

    when(() => mockAuthRepo.register(
          email: any(named: 'email'),
          password: any(named: 'password'),
          companyName: any(named: 'companyName'),
          firstName: any(named: 'firstName'),
          lastName: any(named: 'lastName'),
        )).thenThrow(DioException(
      requestOptions: RequestOptions(path: '/auth/register'),
      type: DioExceptionType.badResponse,
      response: Response(
        statusCode: 409,
        requestOptions: RequestOptions(path: '/auth/register'),
      ),
    ));

    final notifier = container.read(authNotifierProvider.notifier);
    final error = await notifier.register(
      email: 'dupe@test.com',
      password: 'password123',
      companyName: 'Test Co',
    );

    expect(error, equals('Email already registered'));
  });
}
