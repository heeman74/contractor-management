/// E2E widget tests for OnboardingScreen.
///
/// Tests cover:
/// 1. Title and tagline render correctly
/// 2. Sign In button is present with correct icon
/// 3. Create Account button is present with correct icon
/// 4. Both buttons navigate to correct routes
///
/// No Drift, no providers — pure StatelessWidget.
library;

import 'package:contractorhub/features/auth/presentation/screens/onboarding_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

void main() {
  // Track navigated routes
  late List<String> navigatedRoutes;

  Widget buildWidget() {
    navigatedRoutes = [];

    final router = GoRouter(
      initialLocation: '/',
      routes: [
        GoRoute(
          path: '/',
          builder: (_, __) => const OnboardingScreen(),
        ),
        GoRoute(
          path: '/login',
          builder: (_, __) {
            navigatedRoutes.add('/login');
            return const Scaffold(body: Text('Login'));
          },
        ),
        GoRoute(
          path: '/register',
          builder: (_, __) {
            navigatedRoutes.add('/register');
            return const Scaffold(body: Text('Register'));
          },
        ),
      ],
    );

    return MaterialApp.router(routerConfig: router);
  }

  group('OnboardingScreen', () {
    testWidgets('renders title and tagline', (tester) async {
      await tester.pumpWidget(buildWidget());
      await tester.pumpAndSettle();

      expect(find.text('ContractorHub'), findsOneWidget);
      expect(
        find.text('Contractor management made simple'),
        findsOneWidget,
      );
    });

    testWidgets('renders app icon', (tester) async {
      await tester.pumpWidget(buildWidget());
      await tester.pumpAndSettle();

      expect(find.byIcon(Icons.build_circle_outlined), findsOneWidget);
    });

    testWidgets('Sign In button is present', (tester) async {
      await tester.pumpWidget(buildWidget());
      await tester.pumpAndSettle();

      expect(find.text('Sign In'), findsOneWidget);
      expect(find.byIcon(Icons.login), findsOneWidget);
      expect(find.byType(FilledButton), findsOneWidget);
    });

    testWidgets('Create Account button is present', (tester) async {
      await tester.pumpWidget(buildWidget());
      await tester.pumpAndSettle();

      expect(find.text('Create Account'), findsOneWidget);
      expect(find.byIcon(Icons.person_add_outlined), findsOneWidget);
      expect(find.byType(OutlinedButton), findsOneWidget);
    });

    testWidgets('Sign In navigates to login route', (tester) async {
      await tester.pumpWidget(buildWidget());
      await tester.pumpAndSettle();

      await tester.tap(find.text('Sign In'));
      await tester.pumpAndSettle();

      expect(navigatedRoutes, contains('/login'));
    });

    testWidgets('Create Account navigates to register route', (tester) async {
      await tester.pumpWidget(buildWidget());
      await tester.pumpAndSettle();

      await tester.tap(find.text('Create Account'));
      await tester.pumpAndSettle();

      expect(navigatedRoutes, contains('/register'));
    });
  });
}
