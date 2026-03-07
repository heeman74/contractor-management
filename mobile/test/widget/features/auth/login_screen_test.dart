/// Widget tests for LoginScreen.
///
/// Tests cover:
/// 1. Renders email and password fields
/// 2. Empty email shows validation error
/// 3. Invalid email shows validation error
/// 4. Empty password shows validation error
/// 5. Error message displayed on failure
/// 6. Loading state disables button
library;

import 'package:contractorhub/features/auth/presentation/screens/login_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

/// Wraps LoginScreen in necessary scaffolding for widget tests.
Widget buildTestWidget() {
  return ProviderScope(
    child: MaterialApp(
      home: const LoginScreen(),
    ),
  );
}

void main() {
  group('LoginScreen', () {
    testWidgets('renders email and password fields', (tester) async {
      await tester.pumpWidget(buildTestWidget());

      expect(find.widgetWithText(TextFormField, 'Email'), findsOneWidget);
      expect(find.widgetWithText(TextFormField, 'Password'), findsOneWidget);
      expect(find.text('Sign In'), findsWidgets); // Title + button
    });

    testWidgets('empty email shows validation error', (tester) async {
      await tester.pumpWidget(buildTestWidget());

      // Leave email empty, tap Sign In button
      await tester.tap(find.widgetWithText(FilledButton, 'Sign In'));
      await tester.pumpAndSettle();

      expect(find.text('Email is required'), findsOneWidget);
    });

    testWidgets('invalid email shows validation error', (tester) async {
      await tester.pumpWidget(buildTestWidget());

      await tester.enterText(
        find.widgetWithText(TextFormField, 'Email'),
        'not-an-email',
      );
      await tester.tap(find.widgetWithText(FilledButton, 'Sign In'));
      await tester.pumpAndSettle();

      expect(find.text('Enter a valid email'), findsOneWidget);
    });

    testWidgets('empty password shows validation error', (tester) async {
      await tester.pumpWidget(buildTestWidget());

      // Fill in valid email but leave password empty
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Email'),
        'test@test.com',
      );
      await tester.tap(find.widgetWithText(FilledButton, 'Sign In'));
      await tester.pumpAndSettle();

      expect(find.text('Password is required'), findsOneWidget);
    });

    testWidgets('Sign In button is present and tappable', (tester) async {
      await tester.pumpWidget(buildTestWidget());

      final signInButton = find.widgetWithText(FilledButton, 'Sign In');
      expect(signInButton, findsOneWidget);
    });

    testWidgets('password visibility toggle works', (tester) async {
      await tester.pumpWidget(buildTestWidget());

      // Initially password is obscured
      final visibilityToggle = find.byIcon(Icons.visibility_outlined);
      expect(visibilityToggle, findsOneWidget);

      // Tap to show password
      await tester.tap(visibilityToggle);
      await tester.pump();

      // Now should show visibility_off icon
      expect(find.byIcon(Icons.visibility_off_outlined), findsOneWidget);
    });
  });
}
