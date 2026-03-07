/// Widget tests for RegisterScreen.
///
/// Tests cover:
/// 1. Renders all expected form fields
/// 2. Empty company name shows validation error
/// 3. Short password shows validation error
/// 4. Mismatched passwords show validation error
/// 5. Empty email shows validation error
/// 6. Create Account button present and tappable
library;

import 'package:contractorhub/features/auth/presentation/screens/register_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

Widget buildTestWidget() {
  return ProviderScope(
    child: MaterialApp(
      home: const RegisterScreen(),
    ),
  );
}

/// Scroll to the Create Account button and tap it.
Future<void> scrollAndTapSubmit(WidgetTester tester) async {
  await tester.dragUntilVisible(
    find.widgetWithText(FilledButton, 'Create Account'),
    find.byType(SingleChildScrollView),
    const Offset(0, -100),
  );
  await tester.tap(find.widgetWithText(FilledButton, 'Create Account'));
  await tester.pumpAndSettle();
}

/// Scroll to the top of the form to see validation errors near top fields.
Future<void> scrollToTop(WidgetTester tester) async {
  await tester.drag(find.byType(SingleChildScrollView), const Offset(0, 500));
  await tester.pumpAndSettle();
}

void main() {
  group('RegisterScreen', () {
    testWidgets('renders all expected form fields', (tester) async {
      await tester.pumpWidget(buildTestWidget());

      expect(
          find.widgetWithText(TextFormField, 'Company Name'), findsOneWidget);
      expect(find.widgetWithText(TextFormField, 'First Name'), findsOneWidget);
      expect(find.widgetWithText(TextFormField, 'Last Name'), findsOneWidget);
      expect(find.widgetWithText(TextFormField, 'Email'), findsOneWidget);
      // Password and Confirm Password may need scrolling; check skipOffstage
      expect(
        find.widgetWithText(TextFormField, 'Password', skipOffstage: false),
        findsOneWidget,
      );
      expect(
        find.widgetWithText(TextFormField, 'Confirm Password',
            skipOffstage: false),
        findsOneWidget,
      );
      expect(find.text('Create Account'), findsWidgets);
    });

    testWidgets('empty company name shows validation error', (tester) async {
      await tester.pumpWidget(buildTestWidget());

      // Fill everything except company name
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Email'),
        'test@test.com',
      );
      // Scroll down to reach password fields
      await tester.dragUntilVisible(
        find.widgetWithText(TextFormField, 'Password'),
        find.byType(SingleChildScrollView),
        const Offset(0, -100),
      );
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Password'),
        'password123',
      );
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Confirm Password'),
        'password123',
      );

      await scrollAndTapSubmit(tester);
      await scrollToTop(tester);

      expect(find.text('Company name is required'), findsOneWidget);
    });

    testWidgets('short password shows validation error', (tester) async {
      await tester.pumpWidget(buildTestWidget());

      await tester.enterText(
        find.widgetWithText(TextFormField, 'Company Name'),
        'Test Co',
      );
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Email'),
        'test@test.com',
      );
      await tester.dragUntilVisible(
        find.widgetWithText(TextFormField, 'Password'),
        find.byType(SingleChildScrollView),
        const Offset(0, -100),
      );
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Password'),
        'short',
      );
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Confirm Password'),
        'short',
      );

      await scrollAndTapSubmit(tester);

      // Password error should be visible near the button
      expect(
          find.text('Password must be at least 8 characters'), findsOneWidget);
    });

    testWidgets('mismatched passwords show validation error', (tester) async {
      await tester.pumpWidget(buildTestWidget());

      await tester.enterText(
        find.widgetWithText(TextFormField, 'Company Name'),
        'Test Co',
      );
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Email'),
        'test@test.com',
      );
      await tester.dragUntilVisible(
        find.widgetWithText(TextFormField, 'Password'),
        find.byType(SingleChildScrollView),
        const Offset(0, -100),
      );
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Password'),
        'password123',
      );
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Confirm Password'),
        'different123',
      );

      await scrollAndTapSubmit(tester);

      expect(find.text('Passwords do not match'), findsOneWidget);
    });

    testWidgets('empty email shows validation error', (tester) async {
      await tester.pumpWidget(buildTestWidget());

      await tester.enterText(
        find.widgetWithText(TextFormField, 'Company Name'),
        'Test Co',
      );
      await tester.dragUntilVisible(
        find.widgetWithText(TextFormField, 'Password'),
        find.byType(SingleChildScrollView),
        const Offset(0, -100),
      );
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Password'),
        'password123',
      );
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Confirm Password'),
        'password123',
      );

      await scrollAndTapSubmit(tester);
      await scrollToTop(tester);

      expect(find.text('Email is required'), findsOneWidget);
    });

    testWidgets('Create Account button is present', (tester) async {
      await tester.pumpWidget(buildTestWidget());

      // May need to scroll to see the button
      await tester.dragUntilVisible(
        find.widgetWithText(FilledButton, 'Create Account'),
        find.byType(SingleChildScrollView),
        const Offset(0, -100),
      );
      expect(
        find.widgetWithText(FilledButton, 'Create Account'),
        findsOneWidget,
      );
    });
  });
}
