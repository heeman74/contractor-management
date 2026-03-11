/// Widget tests for the JobWizardScreen client selector (Step 1).
///
/// Verifies Phase 4 item 1 — client selector scope:
/// - Dropdown contains only "No client selected" (CRM deferred to Plan 07)
/// - Label decoration is "Client (optional)"
/// - Null client selection does not block step progression
///
/// Strategy: pumpWidget renders the first frame with _isOffline=false (4 steps).
/// We use runAsync to let the connectivity check complete without pumping frames,
/// then do all assertions on the already-rendered widget tree. This avoids the
/// Stepper assertion crash (step count change) entirely.
library;

// Hide Drift-generated UserRole data class (conflicts with shared enum).
import 'package:contractorhub/core/database/app_database.dart' hide UserRole;
import 'package:contractorhub/core/di/service_locator.dart';
import 'package:contractorhub/features/auth/domain/auth_state.dart';
import 'package:contractorhub/features/auth/presentation/providers/auth_provider.dart';
import 'package:contractorhub/features/jobs/presentation/providers/job_providers.dart';
import 'package:contractorhub/features/jobs/presentation/screens/job_wizard_screen.dart';
import 'package:contractorhub/shared/models/user_role.dart';
import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

// ---------------------------------------------------------------------------
// Test helpers
// ---------------------------------------------------------------------------

class _StubAuthNotifier extends AuthNotifier {
  _StubAuthNotifier(this._fixedState);
  final AuthState _fixedState;

  @override
  AuthState build() => _fixedState;
}

AppDatabase _openTestDb() => AppDatabase(NativeDatabase.memory());

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

void main() {
  late AppDatabase db;

  setUp(() async {
    dotenv.loadFromString(envString: 'GOOGLE_PLACES_API_KEY=test-key');

    db = _openTestDb();

    await db.into(db.companies).insert(CompaniesCompanion.insert(
          id: const Value('co-1'),
          name: 'Test Co',
          version: const Value(1),
          createdAt: DateTime.now(),
          updatedAt: DateTime.now(),
        ));

    if (getIt.isRegistered<JobDao>()) getIt.unregister<JobDao>();
    getIt.registerSingleton<JobDao>(db.jobDao);
  });

  tearDown(() async {
    if (getIt.isRegistered<JobDao>()) getIt.unregister<JobDao>();
    await db.close();
  });

  Widget buildWidget(AuthState authState) {
    return ProviderScope(
      overrides: [
        authNotifierProvider
            .overrideWith(() => _StubAuthNotifier(authState)),
        jobDaoProvider.overrideWithValue(db.jobDao),
      ],
      child: MaterialApp(
        home: Navigator(
          onGenerateRoute: (_) => MaterialPageRoute<void>(
            builder: (_) => const JobWizardScreen(),
          ),
        ),
      ),
    );
  }

  /// Let the fire-and-forget connectivity check complete in real async,
  /// then replace the widget tree to avoid Stepper step-count crash.
  Future<void> settleAndCleanup(WidgetTester tester) async {
    // Let pending async (connectivity check) complete in real async
    await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 500)));
    // Replace tree — avoids Stepper rebuild with changed step count
    await tester.pumpWidget(const SizedBox());
    await tester.pump(Duration.zero);
  }

  group('Job wizard Step 1 — client selector', () {
    const adminState = AuthState.authenticated(
      userId: 'admin-1',
      companyId: 'co-1',
      roles: {UserRole.admin},
    );

    testWidgets('dropdown only contains "No client selected" (CRM deferred)',
        (tester) async {
      await tester.pumpWidget(buildWidget(adminState));
      // First frame is rendered with _isOffline=false (4 steps).
      // Don't pump again — connectivity check would change step count.

      // Client dropdown is the first DropdownButtonFormField<String>
      expect(find.text('Client (optional)'), findsOneWidget);
      expect(find.text('No client selected'), findsOneWidget);
      // No CRM client entries loaded
      expect(find.textContaining('client-'), findsNothing);

      await settleAndCleanup(tester);
    });

    testWidgets('dropdown label is "Client (optional)"', (tester) async {
      await tester.pumpWidget(buildWidget(adminState));

      expect(find.text('Client (optional)'), findsOneWidget);

      await settleAndCleanup(tester);
    });

    testWidgets(
        'dropdown still shows only "No client selected" even with seeded client profiles',
        (tester) async {
      // Seed a Users row + ClientProfiles row in Drift — proves the CRM
      // lookup is genuinely not wired (not just empty data).
      final now = DateTime.now();
      await db.into(db.users).insert(UsersCompanion.insert(
            id: const Value('user-client-1'),
            companyId: 'co-1',
            email: 'alice@example.com',
            firstName: const Value('Alice'),
            lastName: const Value('Smith'),
            createdAt: now,
            updatedAt: now,
          ));
      await db.into(db.clientProfiles).insert(ClientProfilesCompanion.insert(
            id: const Value('cp-1'),
            companyId: 'co-1',
            userId: 'user-client-1',
            createdAt: now,
            updatedAt: now,
          ));

      await tester.pumpWidget(buildWidget(adminState));

      // Dropdown still only shows the placeholder — CRM deferred to Plan 07
      expect(find.text('Client (optional)'), findsOneWidget);
      expect(find.text('No client selected'), findsOneWidget);
      // No CRM client names or IDs leaked into the dropdown
      expect(find.text('Alice'), findsNothing);
      expect(find.text('Alice Smith'), findsNothing);
      expect(find.textContaining('client-'), findsNothing);

      await settleAndCleanup(tester);
    });

    testWidgets('null client selection does not block step progression',
        (tester) async {
      await tester.pumpWidget(buildWidget(adminState));
      // Drain connectivity check before interacting with widget
      await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 500)));
      // Rebuild in stable state (offline mode, 3 steps)
      await tester.pump();

      // Enter description into the labeled field
      final descriptionField =
          find.widgetWithText(TextFormField, 'Job description *');
      expect(descriptionField, findsOneWidget);
      await tester.enterText(
          descriptionField, 'Fix the broken pipe in bathroom');

      // Tap Continue on the current step (first visible Continue button)
      await tester.tap(find.text('Continue').first);
      await tester.pump();

      // Step 2 title should exist
      expect(find.text('Location & Trade'), findsOneWidget);

      await tester.pumpWidget(const SizedBox());
      await tester.pump(Duration.zero);
    });

    testWidgets('short description blocks step progression', (tester) async {
      await tester.pumpWidget(buildWidget(adminState));
      // Drain connectivity check before interacting
      await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 500)));
      await tester.pump();

      final descriptionField =
          find.widgetWithText(TextFormField, 'Job description *');
      await tester.enterText(descriptionField, 'Short');

      await tester.tap(find.text('Continue').first);
      await tester.pump();

      expect(find.text('Description must be at least 10 characters.'),
          findsAtLeastNWidgets(1));

      await tester.pumpWidget(const SizedBox());
      await tester.pump(Duration.zero);
    });
  });
}
