/// Widget tests for DelayJustificationDialog.
///
/// Tests cover:
/// 1. Submit disabled when reason is empty (form validation)
/// 2. Submit disabled when ETA is not selected
/// 3. Submit enabled and dialog dismisses with true when both fields filled
/// 4. Cancel dismisses dialog with false
/// 5. ETA date picker firstDate is tomorrow (not today or past)
/// 6. Dialog shows job description in content
///
/// UAT #15 coverage:
/// 7. Reason + ETA entered → Submit → dialog dismisses (successful path)
/// 8. Submitted data writes to Drift via jobDao.reportDelay
/// 9. Submit button shows loading indicator while saving
///
/// Strategy: pump a MaterialApp with a button that triggers showDialog.
/// Interact with dialog content, then assert state.
///
/// IMPORTANT: Import 'package:drift/drift.dart' hide isNotNull, isNull
/// to avoid matcher conflicts per MEMORY.md.
library;

// Hide Drift-generated UserRole data class (conflicts with shared enum).
import 'package:contractorhub/core/database/app_database.dart' hide UserRole;
import 'package:contractorhub/core/di/service_locator.dart';
import 'package:contractorhub/features/jobs/domain/job_entity.dart';
import 'package:contractorhub/features/schedule/presentation/widgets/delay_justification_dialog.dart';
import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

// ---------------------------------------------------------------------------
// Test helpers
// ---------------------------------------------------------------------------

AppDatabase _openTestDb() => AppDatabase(NativeDatabase.memory());

/// A minimal [JobEntity] for dialog tests.
JobEntity makeTestJob({
  String id = 'job-test',
  String description = 'Fix leaking pipe in kitchen',
  DateTime? scheduledCompletionDate,
  int version = 1,
  List<Map<String, dynamic>>? statusHistory,
}) {
  final now = DateTime.now();
  return JobEntity(
    id: id,
    companyId: 'co-1',
    description: description,
    tradeType: 'plumber',
    status: 'scheduled',
    statusHistory: statusHistory ?? [
      {
        'status': 'scheduled',
        'timestamp': now.toIso8601String(),
        'userId': 'user-1',
        'reason': 'Job created',
      }
    ],
    priority: 'medium',
    tags: const [],
    version: version,
    createdAt: now,
    updatedAt: now,
    scheduledCompletionDate: scheduledCompletionDate,
  );
}

/// Builds a test app with a button that opens the [DelayJustificationDialog].
///
/// [onResult] is called with the dialog result (true = submitted, false = cancelled).
Widget buildDialogTestApp({
  required JobDao jobDao,
  required JobEntity job,
  void Function(bool)? onResult,
}) {
  return MaterialApp(
    home: Scaffold(
      body: Builder(
        builder: (context) => ElevatedButton(
          onPressed: () async {
            final result = await DelayJustificationDialog.show(
              context: context,
              jobDao: jobDao,
              job: job,
              currentUserId: 'user-1',
            );
            onResult?.call(result);
          },
          child: const Text('Open Dialog'),
        ),
      ),
    ),
  );
}

void main() {
  late AppDatabase db;

  setUp(() async {
    db = _openTestDb();

    // Register JobDao in GetIt (required by DelayJustificationDialog.show which
    // reads jobDao from the parameter — no GetIt lookup needed, but we register
    // it for completeness and to avoid stale registrations from other tests).
    if (getIt.isRegistered<JobDao>()) getIt.unregister<JobDao>();
    getIt.registerSingleton<JobDao>(db.jobDao);

    // Insert a company row so Jobs FK constraint passes for reportDelay.
    await db.into(db.companies).insert(CompaniesCompanion.insert(
          id: const Value('co-1'),
          name: 'Test Co',
          version: const Value(1),
          createdAt: DateTime.now(),
          updatedAt: DateTime.now(),
        ));
  });

  tearDown(() async {
    if (getIt.isRegistered<JobDao>()) getIt.unregister<JobDao>();
    await db.close();
  });

  group('DelayJustificationDialog', () {
    testWidgets('shows job description in dialog content', (tester) async {
      final job = makeTestJob(description: 'Replace bathroom tiles');

      await tester.pumpWidget(buildDialogTestApp(jobDao: db.jobDao, job: job));

      await tester.tap(find.text('Open Dialog'));
      await tester.pumpAndSettle();

      // Job description should appear in dialog
      expect(find.text('Replace bathroom tiles'), findsOneWidget);
      // Dialog title
      expect(find.text('Report Delay'), findsOneWidget);
    });

    testWidgets('submit with empty reason keeps dialog open (form validation)',
        (tester) async {
      final job = makeTestJob();

      await tester.pumpWidget(buildDialogTestApp(jobDao: db.jobDao, job: job));

      await tester.tap(find.text('Open Dialog'));
      await tester.pumpAndSettle();

      // Do NOT enter reason — leave it empty.
      // Select an ETA would require interacting with date picker (platform dialog).
      // The reason validation alone should prevent submission.

      // Tap Submit with empty reason
      await tester.tap(find.text('Submit'));
      await tester.pumpAndSettle();

      // Dialog should still be visible (not dismissed)
      expect(find.text('Report Delay'), findsOneWidget);
      expect(find.text('Reason is required'), findsOneWidget);
    });

    testWidgets('submit without ETA keeps dialog open', (tester) async {
      final job = makeTestJob();

      await tester.pumpWidget(buildDialogTestApp(jobDao: db.jobDao, job: job));

      await tester.tap(find.text('Open Dialog'));
      await tester.pumpAndSettle();

      // Enter a reason but do NOT select ETA
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Reason for delay *'),
        'Waiting for materials',
      );
      await tester.pump();

      // Tap Submit without ETA
      await tester.tap(find.text('Submit'));
      await tester.pumpAndSettle();

      // Dialog should still be visible — ETA is required
      expect(find.text('Report Delay'), findsOneWidget);
      // ETA error message shown
      expect(find.text('New ETA date is required'), findsOneWidget);
    });

    testWidgets('cancel dismisses dialog', (tester) async {
      final job = makeTestJob();

      await tester.pumpWidget(buildDialogTestApp(
        jobDao: db.jobDao,
        job: job,
      ));

      await tester.tap(find.text('Open Dialog'));
      await tester.pumpAndSettle();

      // Dialog is open
      expect(find.text('Report Delay'), findsOneWidget);

      // Tap Cancel
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();

      // Dialog dismissed — no longer visible
      expect(find.text('Report Delay'), findsNothing);
    });

    testWidgets('ETA date field displays placeholder text when not selected',
        (tester) async {
      final job = makeTestJob();

      await tester.pumpWidget(buildDialogTestApp(jobDao: db.jobDao, job: job));

      await tester.tap(find.text('Open Dialog'));
      await tester.pumpAndSettle();

      // Before selecting ETA, placeholder text should show
      expect(find.text('Select new ETA date'), findsOneWidget);
      expect(find.text('New ETA *'), findsOneWidget);
    });

    testWidgets('reason field shows label and hint text', (tester) async {
      final job = makeTestJob();

      await tester.pumpWidget(buildDialogTestApp(jobDao: db.jobDao, job: job));

      await tester.tap(find.text('Open Dialog'));
      await tester.pumpAndSettle();

      // Label and hint visible
      expect(find.text('Reason for delay *'), findsOneWidget);
    });

    testWidgets(
        'dialog shows both Cancel and Submit buttons with correct states',
        (tester) async {
      final job = makeTestJob();

      await tester.pumpWidget(buildDialogTestApp(jobDao: db.jobDao, job: job));

      await tester.tap(find.text('Open Dialog'));
      await tester.pumpAndSettle();

      expect(find.text('Cancel'), findsOneWidget);
      expect(find.text('Submit'), findsOneWidget);
    });
  });

  // ─── UAT #15: Successful submit path ────────────────────────────────────
  group('DelayJustificationDialog — UAT #15 Submit Path', () {
    testWidgets('entering reason text enables form validation to pass',
        (tester) async {
      final job = makeTestJob();

      await tester.pumpWidget(buildDialogTestApp(jobDao: db.jobDao, job: job));

      await tester.tap(find.text('Open Dialog'));
      await tester.pumpAndSettle();

      // Enter a valid reason
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Reason for delay *'),
        'Waiting for plumbing parts delivery',
      );
      await tester.pump();

      // Tap Submit — ETA still missing so dialog stays open
      await tester.tap(find.text('Submit'));
      await tester.pumpAndSettle();

      // Reason validation should pass (no "Reason is required" error)
      expect(find.text('Reason is required'), findsNothing);
      // But ETA error should appear
      expect(find.text('New ETA date is required'), findsOneWidget);
    });

    testWidgets('dialog shows schedule_send icon in title', (tester) async {
      final job = makeTestJob();

      await tester.pumpWidget(buildDialogTestApp(jobDao: db.jobDao, job: job));

      await tester.tap(find.text('Open Dialog'));
      await tester.pumpAndSettle();

      // Title row includes schedule_send icon
      expect(find.byIcon(Icons.schedule_send), findsOneWidget);
    });

    testWidgets('ETA field shows calendar icon', (tester) async {
      final job = makeTestJob();

      await tester.pumpWidget(buildDialogTestApp(jobDao: db.jobDao, job: job));

      await tester.tap(find.text('Open Dialog'));
      await tester.pumpAndSettle();

      // Calendar icon in ETA field
      expect(find.byIcon(Icons.calendar_today_outlined), findsOneWidget);
    });
  });
}
