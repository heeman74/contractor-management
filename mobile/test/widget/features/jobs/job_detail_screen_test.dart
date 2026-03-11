/// E2E widget tests for JobDetailScreen.
///
/// Tests cover:
/// 1. Tab rendering (Details, Schedule, History)
/// 2. Job info display in Details tab
/// 3. Empty history state
/// 4. History entries display
/// 5. Report Delay button for scheduled/in-progress jobs
/// 6. No Report Delay for completed jobs
/// 7. Job not found state
///
/// IMPORTANT: Never use pumpAndSettle() — Drift StreamProvider timers
/// cause infinite loops in flushTimers. Use pump() for frames.
library;

import 'package:contractorhub/core/database/app_database.dart' hide UserRole;
import 'package:contractorhub/core/di/service_locator.dart';
import 'package:contractorhub/features/auth/domain/auth_state.dart';
import 'package:contractorhub/features/auth/presentation/providers/auth_provider.dart';
import 'package:contractorhub/features/jobs/data/attachment_dao.dart';
import 'package:contractorhub/features/jobs/data/job_dao.dart';
import 'package:contractorhub/features/jobs/data/note_dao.dart';
import 'package:contractorhub/features/jobs/presentation/screens/job_detail_screen.dart';
import 'package:contractorhub/shared/models/user_role.dart';
import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

class _StubAuthNotifier extends AuthNotifier {
  _StubAuthNotifier(this._fixedState);
  final AuthState _fixedState;
  @override
  AuthState build() => _fixedState;
}

AppDatabase _openTestDb() => AppDatabase(NativeDatabase.memory());

const _adminState = AuthState.authenticated(
  userId: 'admin-1',
  companyId: 'co-1',
  roles: {UserRole.admin},
);

Future<void> _seedCompany(AppDatabase db) async {
  await db.into(db.companies).insert(CompaniesCompanion.insert(
        id: const Value('co-1'),
        name: 'Test Co',
        version: const Value(1),
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      ));
}

Future<void> _seedJob(
  AppDatabase db, {
  required String id,
  String status = 'scheduled',
  String description = 'Test job',
  String tradeType = 'plumber',
  String priority = 'medium',
  String? clientId,
  String? contractorId,
  String? notes,
  String statusHistory = '[]',
  String tags = '[]',
}) async {
  final now = DateTime.now();
  await db.jobDao.insertJob(JobsCompanion.insert(
    id: Value(id),
    companyId: 'co-1',
    clientId: Value(clientId),
    contractorId: Value(contractorId),
    description: description,
    tradeType: tradeType,
    status: Value(status),
    statusHistory: Value(statusHistory),
    priority: Value(priority),
    tags: Value(tags),
    notes: Value(notes),
    version: const Value(1),
    createdAt: now,
    updatedAt: now,
  ));
}

Future<void> _cleanup(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox());
  await tester.pump(Duration.zero);
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

void main() {
  late AppDatabase db;

  setUp(() async {
    db = _openTestDb();
    await _seedCompany(db);

    if (getIt.isRegistered<AppDatabase>()) getIt.unregister<AppDatabase>();
    getIt.registerSingleton<AppDatabase>(db);

    if (getIt.isRegistered<JobDao>()) getIt.unregister<JobDao>();
    getIt.registerSingleton<JobDao>(db.jobDao);

    // Phase 6: NotesTab requires NoteDao and AttachmentDao in GetIt
    if (getIt.isRegistered<NoteDao>()) getIt.unregister<NoteDao>();
    getIt.registerSingleton<NoteDao>(db.noteDao);

    if (getIt.isRegistered<AttachmentDao>()) getIt.unregister<AttachmentDao>();
    getIt.registerSingleton<AttachmentDao>(db.attachmentDao);
  });

  tearDown(() async {
    if (getIt.isRegistered<AttachmentDao>()) getIt.unregister<AttachmentDao>();
    if (getIt.isRegistered<NoteDao>()) getIt.unregister<NoteDao>();
    if (getIt.isRegistered<JobDao>()) getIt.unregister<JobDao>();
    if (getIt.isRegistered<AppDatabase>()) getIt.unregister<AppDatabase>();
    await db.close();
  });

  Widget buildWidget(String jobId) {
    return ProviderScope(
      overrides: [
        authNotifierProvider
            .overrideWith(() => _StubAuthNotifier(_adminState)),
      ],
      child: MaterialApp(home: JobDetailScreen(jobId: jobId)),
    );
  }

  group('JobDetailScreen — tabs', () {
    testWidgets('renders all four tabs including Notes', (tester) async {
      await _seedJob(db, id: 'j-1', description: 'Fix pipe');

      await tester.pumpWidget(buildWidget('j-1'));
      await tester.pump(); // stream emits

      expect(find.text('Details'), findsOneWidget);
      expect(find.text('Schedule'), findsOneWidget);
      expect(find.text('Notes'), findsOneWidget);
      expect(find.text('History'), findsOneWidget);

      await _cleanup(tester);
    });
  });

  group('JobDetailScreen — details tab', () {
    testWidgets('shows job description and trade type', (tester) async {
      await _seedJob(db,
          id: 'j-1',
          description: 'Replace bathroom faucet',
          tradeType: 'plumber');

      await tester.pumpWidget(buildWidget('j-1'));
      await tester.pump();

      expect(find.text('Replace bathroom faucet'), findsWidgets); // AppBar + detail
      expect(find.text('plumber'), findsOneWidget);

      await _cleanup(tester);
    });

    testWidgets('shows priority', (tester) async {
      await _seedJob(db, id: 'j-1', priority: 'high');

      await tester.pumpWidget(buildWidget('j-1'));
      await tester.pump();

      expect(find.text('high'), findsOneWidget);

      await _cleanup(tester);
    });

    testWidgets('shows client and contractor when set', (tester) async {
      await _seedJob(db,
          id: 'j-1', clientId: 'client-1', contractorId: 'contractor-1');

      await tester.pumpWidget(buildWidget('j-1'));
      await tester.pump();

      expect(find.text('client-1'), findsOneWidget);
      expect(find.text('contractor-1'), findsOneWidget);

      await _cleanup(tester);
    });

    testWidgets('shows notes when present', (tester) async {
      await _seedJob(db, id: 'j-1', notes: 'Use copper pipes only');

      await tester.pumpWidget(buildWidget('j-1'));
      await tester.pump();

      expect(find.text('Use copper pipes only'), findsOneWidget);

      await _cleanup(tester);
    });

    testWidgets('shows status chip in AppBar', (tester) async {
      await _seedJob(db, id: 'j-1', status: 'scheduled');

      await tester.pumpWidget(buildWidget('j-1'));
      await tester.pump();

      expect(find.text('Scheduled'), findsOneWidget);
      expect(find.byType(Chip), findsOneWidget);

      await _cleanup(tester);
    });
  });

  group('JobDetailScreen — schedule tab', () {
    testWidgets('shows placeholder text', (tester) async {
      await _seedJob(db, id: 'j-1');

      await tester.pumpWidget(buildWidget('j-1'));
      await tester.pump();

      // Tap Schedule tab
      await tester.tap(find.text('Schedule'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(find.textContaining('Booking details will appear here'),
          findsOneWidget);

      await _cleanup(tester);
    });
  });

  group('JobDetailScreen — history tab', () {
    testWidgets('shows empty history message', (tester) async {
      await _seedJob(db, id: 'j-1', statusHistory: '[]');

      await tester.pumpWidget(buildWidget('j-1'));
      await tester.pump();

      // Tap History tab
      await tester.tap(find.text('History'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(find.text('No status history yet.'), findsOneWidget);

      await _cleanup(tester);
    });

    testWidgets('shows status history entries', (tester) async {
      final history = '[{"status":"scheduled","timestamp":"2024-01-15T10:00:00Z"},'
          '{"status":"in_progress","timestamp":"2024-01-16T09:00:00Z"}]';

      await _seedJob(db, id: 'j-1', statusHistory: history);

      await tester.pumpWidget(buildWidget('j-1'));
      await tester.pump();

      await tester.tap(find.text('History'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300)); // tab animation

      expect(find.text('SCHEDULED'), findsOneWidget);
      expect(find.text('IN PROGRESS'), findsOneWidget);

      await _cleanup(tester);
    });

    testWidgets('shows delay entry with reason', (tester) async {
      final history =
          '[{"type":"delay","reason":"Material delay","new_eta":"2024-02-01","timestamp":"2024-01-20T10:00:00Z"}]';

      await _seedJob(db, id: 'j-1', statusHistory: history);

      await tester.pumpWidget(buildWidget('j-1'));
      await tester.pump();

      await tester.tap(find.text('History'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300)); // tab animation

      expect(find.text('DELAY REPORTED'), findsOneWidget);
      expect(find.text('Reason: Material delay'), findsOneWidget);
      expect(find.text('New ETA: 2024-02-01'), findsOneWidget);

      await _cleanup(tester);
    });
  });

  group('JobDetailScreen — report delay', () {
    testWidgets('shows Report Delay for scheduled job', (tester) async {
      await _seedJob(db, id: 'j-1', status: 'scheduled');

      await tester.pumpWidget(buildWidget('j-1'));
      await tester.pump();

      expect(find.text('Report Delay'), findsOneWidget);

      await _cleanup(tester);
    });

    testWidgets('shows Report Delay for in-progress job', (tester) async {
      await _seedJob(db, id: 'j-1', status: 'in_progress');

      await tester.pumpWidget(buildWidget('j-1'));
      await tester.pump();

      expect(find.text('Report Delay'), findsOneWidget);

      await _cleanup(tester);
    });

    testWidgets('no Report Delay for completed job', (tester) async {
      await _seedJob(db, id: 'j-1', status: 'complete');

      await tester.pumpWidget(buildWidget('j-1'));
      await tester.pump();

      expect(find.text('Report Delay'), findsNothing);

      await _cleanup(tester);
    });
  });

  group('JobDetailScreen — not found', () {
    testWidgets('shows Job not found for nonexistent ID', (tester) async {
      await tester.pumpWidget(buildWidget('nonexistent'));
      await tester.pump();

      expect(find.text('Job not found'), findsOneWidget);

      await _cleanup(tester);
    });
  });
}
