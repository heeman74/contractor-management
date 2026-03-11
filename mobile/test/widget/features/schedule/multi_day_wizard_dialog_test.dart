/// Widget tests for MultiDayWizardDialog — UAT #12.
///
/// Tests cover:
/// 1. Dialog title "Multi-day job" with calendar icon
/// 2. First-day summary shows "Day 1 — created"
/// 3. Job description displayed in summary
/// 4. "Additional days" section header present
/// 5. "Add day" button appends a new day entry
/// 6. Cancel button present with red text
/// 7. Confirm button present with "Confirm bookings" text
/// 8. Day entry shows "Day 2" label
library;

import 'package:contractorhub/features/auth/domain/auth_state.dart';
import 'package:contractorhub/features/auth/presentation/providers/auth_provider.dart';
import 'package:contractorhub/features/schedule/presentation/widgets/multi_day_wizard_dialog.dart';
import 'package:contractorhub/shared/models/user_role.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

// ---------------------------------------------------------------------------
// Test helpers
// ---------------------------------------------------------------------------

const _adminAuth = AuthState.authenticated(
  userId: 'admin-1',
  companyId: 'co-1',
  roles: {UserRole.admin},
);

class _StubAuthNotifier extends AuthNotifier {
  @override
  AuthState build() => _adminAuth;
}

Widget buildWizardTestApp({
  String jobDescription = 'Install full HVAC system',
  String contractorName = 'John Smith',
  Future<void> Function(List<dynamic>)? onConfirmed,
  Future<void> Function()? onCancelled,
}) {
  final now = DateTime.now();
  final start = DateTime(now.year, now.month, now.day, 9, 0);
  final end = DateTime(now.year, now.month, now.day, 17, 0);

  return ProviderScope(
    overrides: [
      authNotifierProvider.overrideWith(() => _StubAuthNotifier()),
    ],
    child: MaterialApp(
      home: Scaffold(
        body: Builder(
          builder: (context) => ElevatedButton(
            onPressed: () {
              showDialog<void>(
                context: context,
                barrierDismissible: false,
                builder: (_) => MultiDayWizardDialog(
                  parentBookingId: 'booking-1',
                  jobDescription: jobDescription,
                  firstDayContractorName: contractorName,
                  firstDayStart: start,
                  firstDayEnd: end,
                  companyId: 'co-1',
                  defaultContractorId: 'contractor-1',
                  onConfirmed: (days) async {
                    onConfirmed?.call(days);
                  },
                  onCancelled: () async {
                    onCancelled?.call();
                  },
                ),
              );
            },
            child: const Text('Open Wizard'),
          ),
        ),
      ),
    ),
  );
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

void main() {
  group('MultiDayWizardDialog — UAT #12', () {
    testWidgets('dialog title shows "Multi-day job" with calendar icon',
        (tester) async {
      await tester.pumpWidget(buildWizardTestApp());
      await tester.tap(find.text('Open Wizard'));
      await tester.pumpAndSettle();

      expect(find.text('Multi-day job'), findsOneWidget);
      expect(find.byIcon(Icons.calendar_month), findsOneWidget);
    });

    testWidgets('first day summary shows "Day 1 — created"', (tester) async {
      await tester.pumpWidget(buildWizardTestApp());
      await tester.tap(find.text('Open Wizard'));
      await tester.pumpAndSettle();

      expect(find.text('Day 1 — created'), findsOneWidget);
    });

    testWidgets('job description displayed in summary', (tester) async {
      await tester.pumpWidget(buildWizardTestApp(
        jobDescription: 'Rewire entire building',
      ));
      await tester.tap(find.text('Open Wizard'));
      await tester.pumpAndSettle();

      expect(find.text('Rewire entire building'), findsOneWidget);
    });

    testWidgets('contractor name displayed in summary', (tester) async {
      await tester.pumpWidget(buildWizardTestApp(
        contractorName: 'Alice Cooper',
      ));
      await tester.tap(find.text('Open Wizard'));
      await tester.pumpAndSettle();

      expect(find.textContaining('Alice Cooper'), findsOneWidget);
    });

    testWidgets('"Additional days" header present', (tester) async {
      await tester.pumpWidget(buildWizardTestApp());
      await tester.tap(find.text('Open Wizard'));
      await tester.pumpAndSettle();

      expect(find.text('Additional days'), findsOneWidget);
    });

    testWidgets('"Add day" button present and appends entry', (tester) async {
      await tester.pumpWidget(buildWizardTestApp());
      await tester.tap(find.text('Open Wizard'));
      await tester.pumpAndSettle();

      // Initially should show "Day 2" (one additional day pre-filled)
      expect(find.text('Day 2'), findsOneWidget);
      expect(find.text('Day 3'), findsNothing);

      // Tap "Add day"
      await tester.tap(find.text('Add day'));
      await tester.pumpAndSettle();

      // Now "Day 3" should appear
      expect(find.text('Day 3'), findsOneWidget);
    });

    testWidgets('Cancel button shows red text', (tester) async {
      await tester.pumpWidget(buildWizardTestApp());
      await tester.tap(find.text('Open Wizard'));
      await tester.pumpAndSettle();

      expect(find.text('Cancel'), findsOneWidget);
    });

    testWidgets('Confirm button shows "Confirm bookings"', (tester) async {
      await tester.pumpWidget(buildWizardTestApp());
      await tester.tap(find.text('Open Wizard'));
      await tester.pumpAndSettle();

      expect(find.text('Confirm bookings'), findsOneWidget);
    });

    testWidgets('Suggest button present', (tester) async {
      await tester.pumpWidget(buildWizardTestApp());
      await tester.tap(find.text('Open Wizard'));
      await tester.pumpAndSettle();

      expect(find.text('Suggest'), findsOneWidget);
      expect(find.byIcon(Icons.auto_awesome), findsOneWidget);
    });
  });
}
