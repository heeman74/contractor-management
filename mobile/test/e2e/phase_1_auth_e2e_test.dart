// Phase 1 E2E: Foundation / Auth flow
//
// Covers login, register, onboarding, and logout flows end-to-end.
// Tests exercise the full path: UI interaction → AuthNotifier → AuthRepository
// → state transition → UI update.
//
// Do NOT use pumpAndSettle() — Drift streams never settle. Use pump() instead.

import 'package:contractorhub/core/auth/auth_repository.dart';
import 'package:contractorhub/core/auth/token_storage.dart';
import 'package:contractorhub/core/di/service_locator.dart';
import 'package:contractorhub/features/auth/domain/auth_state.dart';
import 'package:contractorhub/features/auth/presentation/providers/auth_provider.dart';
import 'package:contractorhub/features/auth/presentation/screens/login_screen.dart';
import 'package:contractorhub/features/auth/presentation/screens/onboarding_screen.dart';
import 'package:contractorhub/features/auth/presentation/screens/register_screen.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

// ---------------------------------------------------------------------------
// Mocks
// ---------------------------------------------------------------------------

class MockAuthRepository extends Mock implements AuthRepository {}

class MockTokenStorage extends Mock implements TokenStorage {}

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

/// Wraps a screen in MaterialApp + ProviderScope for testing.
Widget buildTestApp(Widget child) {
  return ProviderScope(
    child: MaterialApp(
      home: child,
    ),
  );
}

/// A fake AuthResult for successful login/register.
AuthResult _successResult() => AuthResult(
      userId: 'user-123',
      companyId: 'company-456',
      roles: ['admin'],
    );

/// Creates a DioException with the given status code.
DioException _dioError(int statusCode) => DioException(
      requestOptions: RequestOptions(path: '/test'),
      response: Response(
        requestOptions: RequestOptions(path: '/test'),
        statusCode: statusCode,
      ),
      type: DioExceptionType.badResponse,
    );

/// Creates a DioException simulating a network error (no response).
DioException _networkError() => DioException(
      requestOptions: RequestOptions(path: '/test'),
      type: DioExceptionType.connectionTimeout,
    );

void main() {
  late MockAuthRepository mockAuthRepo;
  late MockTokenStorage mockTokenStorage;

  setUp(() {
    mockAuthRepo = MockAuthRepository();
    mockTokenStorage = MockTokenStorage();

    // AuthNotifier.build() calls getIt<AuthRepository>(), so we must register
    // before any ProviderScope creates the notifier.
    if (getIt.isRegistered<AuthRepository>()) {
      getIt.unregister<AuthRepository>();
    }
    if (getIt.isRegistered<TokenStorage>()) {
      getIt.unregister<TokenStorage>();
    }
    getIt.registerSingleton<AuthRepository>(mockAuthRepo);
    getIt.registerSingleton<TokenStorage>(mockTokenStorage);

    // Default: restoreSession returns null (unauthenticated)
    when(() => mockAuthRepo.restoreSession()).thenAnswer((_) async => null);
  });

  tearDown(() {
    if (getIt.isRegistered<AuthRepository>()) {
      getIt.unregister<AuthRepository>();
    }
    if (getIt.isRegistered<TokenStorage>()) {
      getIt.unregister<TokenStorage>();
    }
  });

  // =========================================================================
  // 1. Login screen — UI rendering and validation
  // =========================================================================
  group('Phase 1 E2E: Login screen UI and validation', () {
    testWidgets('renders login form with all fields and button',
        (tester) async {
      await tester.pumpWidget(buildTestApp(const LoginScreen()));
      await tester.pump(); // let build settle
      await tester.pump(); // let _restoreSession complete

      expect(find.text('Sign In'), findsWidgets); // title + button
      expect(find.byType(TextFormField), findsNWidgets(2)); // email + password
      expect(find.text('Email'), findsOneWidget);
      expect(find.text('Password'), findsOneWidget);
      expect(find.byType(FilledButton), findsOneWidget);
    });

    testWidgets('empty email shows "Email is required"', (tester) async {
      await tester.pumpWidget(buildTestApp(const LoginScreen()));
      await tester.pump();
      await tester.pump();

      // Leave email empty, type password, tap Sign In
      await tester.enterText(
          find.widgetWithText(TextFormField, 'Password'), 'password123');
      await tester.tap(find.widgetWithText(FilledButton, 'Sign In'));
      await tester.pump();

      expect(find.text('Email is required'), findsOneWidget);
    });

    testWidgets('invalid email shows "Enter a valid email"', (tester) async {
      await tester.pumpWidget(buildTestApp(const LoginScreen()));
      await tester.pump();
      await tester.pump();

      await tester.enterText(
          find.widgetWithText(TextFormField, 'Email'), 'notanemail');
      await tester.enterText(
          find.widgetWithText(TextFormField, 'Password'), 'password123');
      await tester.tap(find.widgetWithText(FilledButton, 'Sign In'));
      await tester.pump();

      expect(find.text('Enter a valid email'), findsOneWidget);
    });

    testWidgets('empty password shows "Password is required"', (tester) async {
      await tester.pumpWidget(buildTestApp(const LoginScreen()));
      await tester.pump();
      await tester.pump();

      await tester.enterText(
          find.widgetWithText(TextFormField, 'Email'), 'test@example.com');
      // Leave password empty
      await tester.tap(find.widgetWithText(FilledButton, 'Sign In'));
      await tester.pump();

      expect(find.text('Password is required'), findsOneWidget);
    });

    testWidgets('password visibility toggle works', (tester) async {
      await tester.pumpWidget(buildTestApp(const LoginScreen()));
      await tester.pump();
      await tester.pump();

      // Initially password is obscured (visibility_outlined icon shown)
      expect(find.byIcon(Icons.visibility_outlined), findsOneWidget);

      // Tap toggle
      await tester.tap(find.byIcon(Icons.visibility_outlined));
      await tester.pump();

      // Now visibility_off_outlined should show
      expect(find.byIcon(Icons.visibility_off_outlined), findsOneWidget);
    });
  });

  // =========================================================================
  // 2. Login success flow
  // =========================================================================
  group('Phase 1 E2E: Login success', () {
    testWidgets(
        'valid credentials → AuthNotifier.login returns null → no error shown',
        (tester) async {
      when(() => mockAuthRepo.login(
            email: any(named: 'email'),
            password: any(named: 'password'),
          )).thenAnswer((_) async => _successResult());

      await tester.pumpWidget(buildTestApp(const LoginScreen()));
      await tester.pump();
      await tester.pump();

      // Fill form
      await tester.enterText(
          find.widgetWithText(TextFormField, 'Email'), 'admin@acme.com');
      await tester.enterText(
          find.widgetWithText(TextFormField, 'Password'), 'securepass');

      // Submit
      await tester.tap(find.widgetWithText(FilledButton, 'Sign In'));
      await tester.pump(); // triggers setState _isLoading = true
      await tester.pump(); // let login future resolve
      await tester.pump(); // let setState _isLoading = false

      // No error message displayed
      expect(find.text('Invalid email or password'), findsNothing);
      expect(find.text('Network error. Please try again.'), findsNothing);

      // Verify AuthRepository.login was called with correct args
      verify(() => mockAuthRepo.login(
            email: 'admin@acme.com',
            password: 'securepass',
          )).called(1);
    });
  });

  // =========================================================================
  // 3. Login error flows
  // =========================================================================
  group('Phase 1 E2E: Login errors', () {
    testWidgets('401 → shows "Invalid email or password"', (tester) async {
      when(() => mockAuthRepo.login(
            email: any(named: 'email'),
            password: any(named: 'password'),
          )).thenThrow(_dioError(401));

      await tester.pumpWidget(buildTestApp(const LoginScreen()));
      await tester.pump();
      await tester.pump();

      await tester.enterText(
          find.widgetWithText(TextFormField, 'Email'), 'bad@example.com');
      await tester.enterText(
          find.widgetWithText(TextFormField, 'Password'), 'wrongpass');
      await tester.tap(find.widgetWithText(FilledButton, 'Sign In'));
      await tester.pump();
      await tester.pump();
      await tester.pump();

      expect(find.text('Invalid email or password'), findsOneWidget);
    });

    testWidgets('network error → shows "Network error. Please try again."',
        (tester) async {
      when(() => mockAuthRepo.login(
            email: any(named: 'email'),
            password: any(named: 'password'),
          )).thenThrow(_networkError());

      await tester.pumpWidget(buildTestApp(const LoginScreen()));
      await tester.pump();
      await tester.pump();

      await tester.enterText(
          find.widgetWithText(TextFormField, 'Email'), 'user@example.com');
      await tester.enterText(
          find.widgetWithText(TextFormField, 'Password'), 'password123');
      await tester.tap(find.widgetWithText(FilledButton, 'Sign In'));
      await tester.pump();
      await tester.pump();
      await tester.pump();

      expect(find.text('Network error. Please try again.'), findsOneWidget);
    });

    testWidgets('unexpected error → shows "An unexpected error occurred"',
        (tester) async {
      when(() => mockAuthRepo.login(
            email: any(named: 'email'),
            password: any(named: 'password'),
          )).thenThrow(Exception('Something broke'));

      await tester.pumpWidget(buildTestApp(const LoginScreen()));
      await tester.pump();
      await tester.pump();

      await tester.enterText(
          find.widgetWithText(TextFormField, 'Email'), 'user@example.com');
      await tester.enterText(
          find.widgetWithText(TextFormField, 'Password'), 'password123');
      await tester.tap(find.widgetWithText(FilledButton, 'Sign In'));
      await tester.pump();
      await tester.pump();
      await tester.pump();

      expect(find.text('An unexpected error occurred'), findsOneWidget);
    });
  });

  // =========================================================================
  // 4. Register screen — UI rendering and validation
  // =========================================================================
  group('Phase 1 E2E: Register screen UI and validation', () {
    testWidgets('renders register form with all fields', (tester) async {
      await tester.pumpWidget(buildTestApp(const RegisterScreen()));
      await tester.pump();
      await tester.pump();

      expect(find.text('Create Account'), findsWidgets); // title + button
      expect(find.text('Company Name'), findsOneWidget);
      expect(find.text('First Name'), findsOneWidget);
      expect(find.text('Last Name'), findsOneWidget);
      expect(find.text('Email'), findsOneWidget);
      expect(find.text('Password'), findsOneWidget);
      expect(find.text('Confirm Password'), findsOneWidget);
      expect(find.byType(FilledButton), findsOneWidget);
    });

    testWidgets('empty company name shows "Company name is required"',
        (tester) async {
      await tester.pumpWidget(buildTestApp(const RegisterScreen()));
      await tester.pump();
      await tester.pump();

      // Fill all fields except company name
      await tester.enterText(
          find.widgetWithText(TextFormField, 'Email'), 'test@example.com');
      await tester.enterText(
          find.widgetWithText(TextFormField, 'Password'), 'password123');
      await tester.enterText(
          find.widgetWithText(TextFormField, 'Confirm Password'),
          'password123');

      // Scroll down to make the button visible, then tap
      await tester.dragUntilVisible(
        find.widgetWithText(FilledButton, 'Create Account'),
        find.byType(SingleChildScrollView),
        const Offset(0, -100),
      );
      await tester.tap(find.widgetWithText(FilledButton, 'Create Account'));
      await tester.pump();

      expect(find.text('Company name is required'), findsOneWidget);
    });

    testWidgets('empty email shows "Email is required"', (tester) async {
      await tester.pumpWidget(buildTestApp(const RegisterScreen()));
      await tester.pump();
      await tester.pump();

      await tester.enterText(
          find.widgetWithText(TextFormField, 'Company Name'), 'Acme Inc');
      await tester.enterText(
          find.widgetWithText(TextFormField, 'Password'), 'password123');
      await tester.enterText(
          find.widgetWithText(TextFormField, 'Confirm Password'),
          'password123');

      await tester.dragUntilVisible(
        find.widgetWithText(FilledButton, 'Create Account'),
        find.byType(SingleChildScrollView),
        const Offset(0, -100),
      );
      await tester.tap(find.widgetWithText(FilledButton, 'Create Account'));
      await tester.pump();

      expect(find.text('Email is required'), findsOneWidget);
    });

    testWidgets('invalid email shows "Enter a valid email"', (tester) async {
      await tester.pumpWidget(buildTestApp(const RegisterScreen()));
      await tester.pump();
      await tester.pump();

      await tester.enterText(
          find.widgetWithText(TextFormField, 'Company Name'), 'Acme Inc');
      await tester.enterText(
          find.widgetWithText(TextFormField, 'Email'), 'bademail');
      await tester.enterText(
          find.widgetWithText(TextFormField, 'Password'), 'password123');
      await tester.enterText(
          find.widgetWithText(TextFormField, 'Confirm Password'),
          'password123');

      await tester.dragUntilVisible(
        find.widgetWithText(FilledButton, 'Create Account'),
        find.byType(SingleChildScrollView),
        const Offset(0, -100),
      );
      await tester.tap(find.widgetWithText(FilledButton, 'Create Account'));
      await tester.pump();

      expect(find.text('Enter a valid email'), findsOneWidget);
    });

    testWidgets(
        'password < 8 chars shows "Password must be at least 8 characters"',
        (tester) async {
      await tester.pumpWidget(buildTestApp(const RegisterScreen()));
      await tester.pump();
      await tester.pump();

      await tester.enterText(
          find.widgetWithText(TextFormField, 'Company Name'), 'Acme Inc');
      await tester.enterText(
          find.widgetWithText(TextFormField, 'Email'), 'test@example.com');
      await tester.enterText(
          find.widgetWithText(TextFormField, 'Password'), 'short');
      await tester.enterText(
          find.widgetWithText(TextFormField, 'Confirm Password'), 'short');

      await tester.dragUntilVisible(
        find.widgetWithText(FilledButton, 'Create Account'),
        find.byType(SingleChildScrollView),
        const Offset(0, -100),
      );
      await tester.tap(find.widgetWithText(FilledButton, 'Create Account'));
      await tester.pump();

      expect(
          find.text('Password must be at least 8 characters'), findsOneWidget);
    });

    testWidgets('mismatched passwords shows "Passwords do not match"',
        (tester) async {
      await tester.pumpWidget(buildTestApp(const RegisterScreen()));
      await tester.pump();
      await tester.pump();

      await tester.enterText(
          find.widgetWithText(TextFormField, 'Company Name'), 'Acme Inc');
      await tester.enterText(
          find.widgetWithText(TextFormField, 'Email'), 'test@example.com');
      await tester.enterText(
          find.widgetWithText(TextFormField, 'Password'), 'password123');
      await tester.enterText(
          find.widgetWithText(TextFormField, 'Confirm Password'),
          'differentpass');

      await tester.dragUntilVisible(
        find.widgetWithText(FilledButton, 'Create Account'),
        find.byType(SingleChildScrollView),
        const Offset(0, -100),
      );
      await tester.tap(find.widgetWithText(FilledButton, 'Create Account'));
      await tester.pump();

      expect(find.text('Passwords do not match'), findsOneWidget);
    });

    testWidgets('empty password shows "Password is required"', (tester) async {
      await tester.pumpWidget(buildTestApp(const RegisterScreen()));
      await tester.pump();
      await tester.pump();

      await tester.enterText(
          find.widgetWithText(TextFormField, 'Company Name'), 'Acme Inc');
      await tester.enterText(
          find.widgetWithText(TextFormField, 'Email'), 'test@example.com');
      // Leave password empty

      await tester.dragUntilVisible(
        find.widgetWithText(FilledButton, 'Create Account'),
        find.byType(SingleChildScrollView),
        const Offset(0, -100),
      );
      await tester.tap(find.widgetWithText(FilledButton, 'Create Account'));
      await tester.pump();

      expect(find.text('Password is required'), findsOneWidget);
    });
  });

  // =========================================================================
  // 5. Register success flow
  // =========================================================================
  group('Phase 1 E2E: Register success', () {
    testWidgets('valid form → AuthNotifier.register returns null → no error',
        (tester) async {
      when(() => mockAuthRepo.register(
            email: any(named: 'email'),
            password: any(named: 'password'),
            companyName: any(named: 'companyName'),
            firstName: any(named: 'firstName'),
            lastName: any(named: 'lastName'),
          )).thenAnswer((_) async => _successResult());

      await tester.pumpWidget(buildTestApp(const RegisterScreen()));
      await tester.pump();
      await tester.pump();

      // Fill all fields
      await tester.enterText(
          find.widgetWithText(TextFormField, 'Company Name'), 'Acme Inc');
      await tester.enterText(
          find.widgetWithText(TextFormField, 'First Name'), 'John');
      await tester.enterText(
          find.widgetWithText(TextFormField, 'Last Name'), 'Doe');
      await tester.enterText(
          find.widgetWithText(TextFormField, 'Email'), 'john@acme.com');
      await tester.enterText(
          find.widgetWithText(TextFormField, 'Password'), 'securepass123');
      await tester.enterText(
          find.widgetWithText(TextFormField, 'Confirm Password'),
          'securepass123');

      // Scroll and submit
      await tester.dragUntilVisible(
        find.widgetWithText(FilledButton, 'Create Account'),
        find.byType(SingleChildScrollView),
        const Offset(0, -100),
      );
      await tester.tap(find.widgetWithText(FilledButton, 'Create Account'));
      await tester.pump();
      await tester.pump();
      await tester.pump();

      // No error message displayed
      expect(find.text('Email already registered'), findsNothing);
      expect(find.text('Network error. Please try again.'), findsNothing);

      // Verify register called with correct args
      verify(() => mockAuthRepo.register(
            email: 'john@acme.com',
            password: 'securepass123',
            companyName: 'Acme Inc',
            firstName: 'John',
            lastName: 'Doe',
          )).called(1);
    });

    testWidgets(
        'register without optional names sends null for firstName/lastName',
        (tester) async {
      when(() => mockAuthRepo.register(
            email: any(named: 'email'),
            password: any(named: 'password'),
            companyName: any(named: 'companyName'),
            firstName: any(named: 'firstName'),
            lastName: any(named: 'lastName'),
          )).thenAnswer((_) async => _successResult());

      await tester.pumpWidget(buildTestApp(const RegisterScreen()));
      await tester.pump();
      await tester.pump();

      // Fill required fields only (skip first/last name)
      await tester.enterText(
          find.widgetWithText(TextFormField, 'Company Name'), 'Solo LLC');
      await tester.enterText(
          find.widgetWithText(TextFormField, 'Email'), 'solo@example.com');
      await tester.enterText(
          find.widgetWithText(TextFormField, 'Password'), 'mypassword1');
      await tester.enterText(
          find.widgetWithText(TextFormField, 'Confirm Password'),
          'mypassword1');

      await tester.dragUntilVisible(
        find.widgetWithText(FilledButton, 'Create Account'),
        find.byType(SingleChildScrollView),
        const Offset(0, -100),
      );
      await tester.tap(find.widgetWithText(FilledButton, 'Create Account'));
      await tester.pump();
      await tester.pump();
      await tester.pump();

      // firstName and lastName should be null (empty strings → null)
      verify(() => mockAuthRepo.register(
            email: 'solo@example.com',
            password: 'mypassword1',
            companyName: 'Solo LLC',
            firstName: null,
            lastName: null,
          )).called(1);
    });
  });

  // =========================================================================
  // 6. Register error flows
  // =========================================================================
  group('Phase 1 E2E: Register errors', () {
    testWidgets('409 → shows "Email already registered"', (tester) async {
      when(() => mockAuthRepo.register(
            email: any(named: 'email'),
            password: any(named: 'password'),
            companyName: any(named: 'companyName'),
            firstName: any(named: 'firstName'),
            lastName: any(named: 'lastName'),
          )).thenThrow(_dioError(409));

      await tester.pumpWidget(buildTestApp(const RegisterScreen()));
      await tester.pump();
      await tester.pump();

      await tester.enterText(
          find.widgetWithText(TextFormField, 'Company Name'), 'Acme Inc');
      await tester.enterText(
          find.widgetWithText(TextFormField, 'Email'), 'dupe@example.com');
      await tester.enterText(
          find.widgetWithText(TextFormField, 'Password'), 'password123');
      await tester.enterText(
          find.widgetWithText(TextFormField, 'Confirm Password'),
          'password123');

      await tester.dragUntilVisible(
        find.widgetWithText(FilledButton, 'Create Account'),
        find.byType(SingleChildScrollView),
        const Offset(0, -100),
      );
      await tester.tap(find.widgetWithText(FilledButton, 'Create Account'));
      await tester.pump();
      await tester.pump();
      await tester.pump();

      expect(find.text('Email already registered'), findsOneWidget);
    });

    testWidgets('network error → shows "Network error. Please try again."',
        (tester) async {
      when(() => mockAuthRepo.register(
            email: any(named: 'email'),
            password: any(named: 'password'),
            companyName: any(named: 'companyName'),
            firstName: any(named: 'firstName'),
            lastName: any(named: 'lastName'),
          )).thenThrow(_networkError());

      await tester.pumpWidget(buildTestApp(const RegisterScreen()));
      await tester.pump();
      await tester.pump();

      await tester.enterText(
          find.widgetWithText(TextFormField, 'Company Name'), 'Acme Inc');
      await tester.enterText(
          find.widgetWithText(TextFormField, 'Email'), 'test@example.com');
      await tester.enterText(
          find.widgetWithText(TextFormField, 'Password'), 'password123');
      await tester.enterText(
          find.widgetWithText(TextFormField, 'Confirm Password'),
          'password123');

      await tester.dragUntilVisible(
        find.widgetWithText(FilledButton, 'Create Account'),
        find.byType(SingleChildScrollView),
        const Offset(0, -100),
      );
      await tester.tap(find.widgetWithText(FilledButton, 'Create Account'));
      await tester.pump();
      await tester.pump();
      await tester.pump();

      expect(find.text('Network error. Please try again.'), findsOneWidget);
    });
  });

  // =========================================================================
  // 7. Onboarding screen
  // =========================================================================
  group('Phase 1 E2E: Onboarding screen', () {
    testWidgets('renders ContractorHub title and tagline', (tester) async {
      await tester.pumpWidget(buildTestApp(const OnboardingScreen()));
      await tester.pump();

      expect(find.text('ContractorHub'), findsOneWidget);
      expect(
          find.text('Contractor management made simple'), findsOneWidget);
    });

    testWidgets('shows Sign In and Create Account buttons', (tester) async {
      await tester.pumpWidget(buildTestApp(const OnboardingScreen()));
      await tester.pump();

      expect(find.text('Sign In'), findsOneWidget);
      expect(find.text('Create Account'), findsOneWidget);
    });

    testWidgets('shows app icon', (tester) async {
      await tester.pumpWidget(buildTestApp(const OnboardingScreen()));
      await tester.pump();

      expect(find.byIcon(Icons.build_circle_outlined), findsOneWidget);
    });

    testWidgets('Sign In is a FilledButton, Create Account is OutlinedButton',
        (tester) async {
      await tester.pumpWidget(buildTestApp(const OnboardingScreen()));
      await tester.pump();

      // Sign In should be inside a FilledButton
      expect(
        find.ancestor(
          of: find.text('Sign In'),
          matching: find.byType(FilledButton),
        ),
        findsOneWidget,
      );

      // Create Account should be inside an OutlinedButton
      expect(
        find.ancestor(
          of: find.text('Create Account'),
          matching: find.byType(OutlinedButton),
        ),
        findsOneWidget,
      );
    });
  });

  // =========================================================================
  // 8. Logout flow
  // =========================================================================
  group('Phase 1 E2E: Logout', () {
    testWidgets(
        'AuthNotifier.logout calls AuthRepository.logout and sets unauthenticated',
        (tester) async {
      // Start as authenticated
      when(() => mockAuthRepo.restoreSession())
          .thenAnswer((_) async => _successResult());
      when(() => mockAuthRepo.logout()).thenAnswer((_) async {});

      late ProviderContainer container;

      await tester.pumpWidget(
        ProviderScope(
          child: Builder(builder: (context) {
            return MaterialApp(
              home: Consumer(builder: (context, ref, _) {
                container = ProviderScope.containerOf(context);
                final authState = ref.watch(authNotifierProvider);
                return Scaffold(
                  body: Center(
                    child: Text(
                      authState.map(
                        loading: (_) => 'loading',
                        unauthenticated: (_) => 'unauthenticated',
                        authenticated: (_) => 'authenticated',
                      ),
                    ),
                  ),
                );
              }),
            );
          }),
        ),
      );
      await tester.pump();
      await tester.pump(); // let _restoreSession resolve
      await tester.pump();

      // Should be authenticated after restoreSession
      expect(find.text('authenticated'), findsOneWidget);

      // Trigger logout
      await container
          .read(authNotifierProvider.notifier)
          .logout();
      await tester.pump();

      // Should now be unauthenticated
      expect(find.text('unauthenticated'), findsOneWidget);

      // Verify AuthRepository.logout was called
      verify(() => mockAuthRepo.logout()).called(1);
    });
  });

  // =========================================================================
  // 9. Auth state transitions
  // =========================================================================
  group('Phase 1 E2E: Auth state transitions', () {
    testWidgets('login success transitions state to authenticated',
        (tester) async {
      when(() => mockAuthRepo.login(
            email: any(named: 'email'),
            password: any(named: 'password'),
          )).thenAnswer((_) async => _successResult());

      late ProviderContainer container;

      await tester.pumpWidget(
        ProviderScope(
          child: Builder(builder: (context) {
            return MaterialApp(
              home: Consumer(builder: (context, ref, _) {
                container = ProviderScope.containerOf(context);
                final authState = ref.watch(authNotifierProvider);
                return Scaffold(
                  body: Center(
                    child: Text(
                      authState.map(
                        loading: (_) => 'loading',
                        unauthenticated: (_) => 'unauthenticated',
                        authenticated: (s) =>
                            'authenticated:${s.userId}:${s.companyId}',
                      ),
                    ),
                  ),
                );
              }),
            );
          }),
        ),
      );
      await tester.pump();
      await tester.pump(); // let _restoreSession resolve (returns null)
      await tester.pump();

      expect(find.text('unauthenticated'), findsOneWidget);

      // Perform login
      final error = await container
          .read(authNotifierProvider.notifier)
          .login(email: 'a@b.com', password: 'pass');
      await tester.pump();

      expect(error, isNull);
      expect(find.text('authenticated:user-123:company-456'), findsOneWidget);
    });

    testWidgets('register success transitions state to authenticated',
        (tester) async {
      when(() => mockAuthRepo.register(
            email: any(named: 'email'),
            password: any(named: 'password'),
            companyName: any(named: 'companyName'),
            firstName: any(named: 'firstName'),
            lastName: any(named: 'lastName'),
          )).thenAnswer((_) async => _successResult());

      late ProviderContainer container;

      await tester.pumpWidget(
        ProviderScope(
          child: Builder(builder: (context) {
            return MaterialApp(
              home: Consumer(builder: (context, ref, _) {
                container = ProviderScope.containerOf(context);
                final authState = ref.watch(authNotifierProvider);
                return Scaffold(
                  body: Center(
                    child: Text(
                      authState.map(
                        loading: (_) => 'loading',
                        unauthenticated: (_) => 'unauthenticated',
                        authenticated: (s) =>
                            'authenticated:${s.userId}:${s.companyId}',
                      ),
                    ),
                  ),
                );
              }),
            );
          }),
        ),
      );
      await tester.pump();
      await tester.pump();
      await tester.pump();

      expect(find.text('unauthenticated'), findsOneWidget);

      // Perform register
      final error = await container
          .read(authNotifierProvider.notifier)
          .register(
            email: 'new@co.com',
            password: 'pass12345',
            companyName: 'NewCo',
          );
      await tester.pump();

      expect(error, isNull);
      expect(find.text('authenticated:user-123:company-456'), findsOneWidget);
    });

    testWidgets('restoreSession with valid token → authenticated on startup',
        (tester) async {
      when(() => mockAuthRepo.restoreSession())
          .thenAnswer((_) async => _successResult());

      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(
            home: Consumer(builder: (context, ref, _) {
              final authState = ref.watch(authNotifierProvider);
              return Scaffold(
                body: Center(
                  child: Text(
                    authState.map(
                      loading: (_) => 'loading',
                      unauthenticated: (_) => 'unauthenticated',
                      authenticated: (_) => 'authenticated',
                    ),
                  ),
                ),
              );
            }),
          ),
        ),
      );
      await tester.pump(); // initial build → loading
      await tester.pump(); // _restoreSession resolves
      await tester.pump();

      expect(find.text('authenticated'), findsOneWidget);
    });
  });
}
