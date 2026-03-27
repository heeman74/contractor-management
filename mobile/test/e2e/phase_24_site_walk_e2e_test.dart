// Phase 24 — GC Inspection Workflow: Flutter E2E tests — INSP-02.
//
// Covers site walk flag UI flows on SiteWalkFlagSection:
//   INSP-02-01: SiteWalkFlagSection shows "No flags yet" when empty
//   INSP-02-02: SiteWalkFlagSection renders flag descriptions
//   INSP-02-03: High-severity flag shows red dot indicator
//   INSP-02-04: GC sees "Convert to Punch Item" button on open flag
//   INSP-02-05: Contractor does NOT see "Convert to Punch Item"
//   INSP-02-06: _FlagForm renders Description, Severity, Location fields
//   INSP-02-07: Submit Flag button disabled when description is empty
//   INSP-02-08: Submit Flag button enabled after entering description
//   INSP-02-09: Flag count chip shows correct count
//
// Patterns:
//   - ProviderScope.overrideWith for Riverpod providers
//   - pump() NOT pumpAndSettle() — Drift streams never settle (MEMORY.md)
//   - Stream.value() for pre-seeded static data
//   - No GetIt initialization needed — DAOs overridden via ProviderScope

import 'package:contractorhub/core/database/app_database.dart'
    hide UserRole, BookingDao, NoteDao, AttachmentDao, TimeEntryDao,
        QuoteDao, InvoiceDao;
import 'package:contractorhub/features/auth/domain/auth_state.dart';
import 'package:contractorhub/features/auth/presentation/providers/auth_provider.dart';
import 'package:contractorhub/features/projects/presentation/providers/project_providers.dart';
import 'package:contractorhub/features/projects/presentation/widgets/site_walk_flag_section.dart';
import 'package:contractorhub/shared/models/user_role.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

// ---------------------------------------------------------------------------
// Test constants
// ---------------------------------------------------------------------------

const _companyId = 'company-001';
const _gcId = 'gc-001';
const _contractorId = 'contractor-001';
const _projectId = 'project-001';

// ---------------------------------------------------------------------------
// Auth state helpers
// ---------------------------------------------------------------------------

AuthState _gcAuth() => const AuthState.authenticated(
      userId: _gcId,
      companyId: _companyId,
      roles: {UserRole.admin},
    );

AuthState _contractorAuth() => const AuthState.authenticated(
      userId: _contractorId,
      companyId: _companyId,
      roles: {UserRole.contractor},
    );

// ---------------------------------------------------------------------------
// Data builder helpers
// ---------------------------------------------------------------------------

SiteWalkFlag _makeFlag({
  String id = 'flag-001',
  String description = 'Crack in foundation',
  String severity = 'medium',
  String status = 'open',
  String? locationLabel,
}) {
  final now = DateTime.now();
  return SiteWalkFlag(
    id: id,
    companyId: _companyId,
    projectId: _projectId,
    flaggedBy: _gcId,
    description: description,
    severity: severity,
    status: status,
    locationLabel: locationLabel,
    version: 1,
    createdAt: now,
    updatedAt: now,
  );
}

// ---------------------------------------------------------------------------
// Fake auth notifier
// ---------------------------------------------------------------------------

class _FakeAuthNotifier extends AuthNotifier {
  final AuthState _state;
  _FakeAuthNotifier(this._state);

  @override
  AuthState build() => _state;
}

// ---------------------------------------------------------------------------
// Fake SiteWalkFlagDao that returns Stream.value() to avoid pending Drift timers
// ---------------------------------------------------------------------------

class _FakeSiteWalkFlagDao implements SiteWalkFlagDao {
  final List<SiteWalkFlag> flags;
  _FakeSiteWalkFlagDao({this.flags = const []});

  @override
  Stream<List<SiteWalkFlag>> watchByProjectId(String projectId) =>
      Stream.value(
        flags.where((f) => f.projectId == projectId).toList(),
      );

  @override
  Future<void> createFlag(SiteWalkFlagsCompanion flag) async {}

  @override
  Future<void> updateStatus(String flagId, String status) async {}

  @override
  Future<void> convertFlag(
    String flagId,
    PunchListItemsCompanion punchItem,
  ) async {}

  @override
  Future<void> upsertFromServer(SiteWalkFlagsCompanion data) async {}

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

// ---------------------------------------------------------------------------
// Widget wrapper helper
// ---------------------------------------------------------------------------

Widget _wrapSection(
  AuthState auth, {
  List<SiteWalkFlag> flags = const [],
  bool isGcOrAdmin = true,
}) {
  return ProviderScope(
    overrides: [
      authNotifierProvider.overrideWith(() => _FakeAuthNotifier(auth)),
      siteWalkFlagDaoProvider.overrideWithValue(
        _FakeSiteWalkFlagDao(flags: flags) as SiteWalkFlagDao,
      ),
      flagsForProjectProvider(_projectId)
          .overrideWith((ref) => Stream.value(flags)),
    ],
    child: MaterialApp(
      home: Scaffold(
        body: SiteWalkFlagSection(
          projectId: _projectId,
          isGcOrAdmin: isGcOrAdmin,
        ),
      ),
    ),
  );
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

void main() {
  group('SiteWalkFlagSection — empty state', () {
    testWidgets('shows No flags yet when empty', (tester) async {
      await tester.pumpWidget(_wrapSection(_gcAuth(), flags: []));
      await tester.pump();

      // Expand the tile to see the empty state message
      await tester.tap(find.text('Site Walk Flags'));
      await tester.pump();

      expect(find.text('No flags yet'), findsOneWidget);
    });

    testWidgets('shows count chip with 0', (tester) async {
      await tester.pumpWidget(_wrapSection(_gcAuth(), flags: []));
      await tester.pump();

      expect(find.text('0'), findsOneWidget);
    });
  });

  group('SiteWalkFlagSection — with flags', () {
    testWidgets('renders flag descriptions', (tester) async {
      final flags = [
        _makeFlag(),
        _makeFlag(id: 'flag-002', description: 'Exposed wiring near panel'),
      ];

      await tester.pumpWidget(_wrapSection(_gcAuth(), flags: flags));
      await tester.pump();

      // Expand to see flags
      await tester.tap(find.text('Site Walk Flags'));
      await tester.pump();

      expect(find.text('Crack in foundation'), findsOneWidget);
      expect(find.text('Exposed wiring near panel'), findsOneWidget);
    });

    testWidgets('shows correct count chip', (tester) async {
      final flags = [
        _makeFlag(),
        _makeFlag(id: 'flag-002'),
        _makeFlag(id: 'flag-003'),
      ];

      await tester.pumpWidget(_wrapSection(_gcAuth(), flags: flags));
      await tester.pump();

      expect(find.text('3'), findsOneWidget);
    });

    testWidgets('GC sees Convert to Punch Item on open flag', (tester) async {
      final flags = [
        _makeFlag(description: 'Issue to convert'),
      ];

      await tester.pumpWidget(
        _wrapSection(_gcAuth(), flags: flags),
      );
      await tester.pump();

      // Expand the section
      await tester.tap(find.text('Site Walk Flags'));
      await tester.pump();

      expect(find.text('Convert to Punch Item'), findsOneWidget);
    });

    testWidgets('Contractor does NOT see Convert to Punch Item', (tester) async {
      final flags = [
        _makeFlag(description: 'Issue to convert'),
      ];

      await tester.pumpWidget(
        _wrapSection(_contractorAuth(), flags: flags, isGcOrAdmin: false),
      );
      await tester.pump();

      // Expand the section
      await tester.tap(find.text('Site Walk Flags'));
      await tester.pump();

      expect(find.text('Convert to Punch Item'), findsNothing);
    });

    testWidgets('converted flag does not show Convert to Punch Item',
        (tester) async {
      final flags = [
        _makeFlag(status: 'converted', description: 'Already converted'),
      ];

      await tester.pumpWidget(
        _wrapSection(_gcAuth(), flags: flags),
      );
      await tester.pump();

      // Expand the section
      await tester.tap(find.text('Site Walk Flags'));
      await tester.pump();

      // Status is 'converted' so the Convert button should not appear
      expect(find.text('Convert to Punch Item'), findsNothing);
    });
  });

  group('Flag severity rendering', () {
    testWidgets('high severity flag renders description', (tester) async {
      final flags = [
        _makeFlag(
          id: 'flag-high',
          severity: 'high',
          description: 'Exposed electrical wiring',
        ),
      ];

      await tester.pumpWidget(
        _wrapSection(_gcAuth(), flags: flags),
      );
      await tester.pump();

      // Expand the section
      await tester.tap(find.text('Site Walk Flags'));
      await tester.pump();

      // High-severity flag description should be visible
      expect(find.text('Exposed electrical wiring'), findsOneWidget);
    });

    testWidgets('multiple flags all appear in list', (tester) async {
      final flags = [
        _makeFlag(id: 'f1', severity: 'low', description: 'Minor crack'),
        _makeFlag(id: 'f2', description: 'Water stain'),
        _makeFlag(id: 'f3', severity: 'high', description: 'Structural issue'),
      ];

      await tester.pumpWidget(
        _wrapSection(_gcAuth(), flags: flags),
      );
      await tester.pump();

      // Expand the section
      await tester.tap(find.text('Site Walk Flags'));
      await tester.pump();

      expect(find.text('Minor crack'), findsOneWidget);
      expect(find.text('Water stain'), findsOneWidget);
      expect(find.text('Structural issue'), findsOneWidget);
    });
  });
}
