// Schedule Config — Flutter E2E widget tests.
//
// Covers the two mobile "schedule config" screens end-to-end and documents the
// real (source-verified) relationship between them:
//
//   * ScheduleSettingsScreen  (weekly working-hours TEMPLATE editor)
//       - lib/features/schedule/presentation/screens/schedule_settings_screen.dart
//       - Data path is DIO / HTTP, NOT offline-first:
//           load: GET   /api/v1/scheduling/schedules/{contractorId}/weekly
//           save: PATCH  /api/v1/scheduling/schedules/{contractorId}/weekly
//         Both resolve Dio via getIt<DioClient>().instance, so we mock DioClient
//         with mocktail and assert on captured request path + payload. There is
//         NO Drift write in this screen.
//       - contractorId defaults to the authed userId (contractor self-service);
//         an explicit contractorId param puts it in "admin viewing another
//         contractor" mode which ONLY changes the AppBar title. There is NO role
//         gate — any authed user reaches the full editor (documented in a test).
//       - Failure taxonomy (source): a network-ish error string
//         (socket/connection/timeout/unreachable/not registered) → offline
//         banner + defaults; any other error → an error panel (load) or a red
//         "Failed to save" snackbar (save).
//
//   * ContractorScheduleScreen (contractor's personal daily schedule VIEW)
//       - lib/features/schedule/presentation/screens/contractor_schedule_screen.dart
//       - Data path is OFFLINE-FIRST / Drift: a StreamProvider watches
//         BookingDao.watchBookingsByContractorAndDate(userId, selectedDate) from
//         a REAL in-memory AppDatabase registered in getIt. Job metadata comes
//         from jobListNotifierProvider (getIt<JobDao>.watchJobsByCompany). We
//         seed real rows and assert rendering + reactive updates. Pull-to-refresh
//         calls getIt<SyncEngine>().syncNow() (mocked).
//       - Guards on AuthAuthenticated (spinner otherwise). List/Calendar toggle
//         + date navigation drive calendarDateProvider.
//
//   RELATIONSHIP: the two screens are siblings that share only the auth identity
//   (userId == contractorId). ContractorScheduleScreen shows a contractor's
//   *bookings for a day* (local Drift, reactive); ScheduleSettingsScreen edits
//   that contractor's *weekly availability template* (remote Dio). They use
//   completely different data layers and write paths — one never persists to the
//   other. The settings screen is reached from the schedule surface (gear icon in
//   a host AppBar, per the source doc-comments) but ContractorScheduleScreen
//   itself contains no navigation to it.
//
// Coverage map:
//   ScheduleSettingsScreen
//     1.  Renders 7 day rows + Save + quick actions on a clean load (defaults)
//     2.  Renders server-provided template (a day returned as "day off")
//     3.  Change a day + Save → PATCH called with correct path + 7-day payload,
//         success snackbar
//     4.  Quick action "All day off" → every row becomes a day off
//     5.  Quick action "Copy Mon to weekdays" → confirmation snackbar
//     6.  Save server error (non-network) → red "Failed to save" snackbar
//     7.  Save network error → "Offline — changes will sync when connected"
//     8.  Load non-network error → error panel
//     9.  Load network error → offline banner + Save action hidden + inputs off
//    10.  Admin-mode (contractorId != userId) → "Contractor Schedule" title,
//         GET path uses that contractorId
//    11.  No role gate — a contractor reaches the full editor (Save present)
//   ContractorScheduleScreen
//    12.  Renders today's seeded bookings: description, status chip, TODAY header
//    13.  Empty state → "No jobs scheduled"
//    14.  Multiple bookings render in ascending time order
//    15.  Overdue job → overdue prompt + "Report Delay" button
//    16.  Report Delay dialog opens; empty submit shows validation; Cancel closes
//    17.  Calendar toggle → ContractorCalendarView (time axis renders)
//    18.  Date navigation (next day) → reactive switch to tomorrow's booking
//    19.  Pull-to-refresh → SyncEngine.syncNow() invoked
//    20.  Not authenticated → spinner (guard), no header
//
// Harness rules (CLAUDE.md + MEMORY.md):
//   * Real Drift AppDatabase(NativeDatabase.memory()) for the contractor screen;
//     mocktail MockDioClient for the settings screen. getIt reset in tearDown.
//   * ProviderScope overrides authNotifierProvider with a fake AuthNotifier.
//   * pump() / pump(Duration(...)) only — never pumpAndSettle (Drift streams and
//     the settings spinner never settle). Drain Drift's zero-duration close timer
//     at the end of every test that mounts the contractor screen.

import 'package:contractorhub/core/database/app_database.dart' hide UserRole;
import 'package:contractorhub/core/di/service_locator.dart';
import 'package:contractorhub/core/network/dio_client.dart';
import 'package:contractorhub/core/sync/sync_engine.dart';
import 'package:contractorhub/features/auth/domain/auth_state.dart';
import 'package:contractorhub/features/auth/presentation/providers/auth_provider.dart';
import 'package:contractorhub/features/schedule/presentation/screens/contractor_schedule_screen.dart';
import 'package:contractorhub/features/schedule/presentation/screens/schedule_settings_screen.dart';
import 'package:contractorhub/features/schedule/presentation/widgets/contractor_schedule_header.dart';
import 'package:contractorhub/shared/models/user_role.dart';
import 'package:dio/dio.dart' as dio_pkg;
import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

// ---------------------------------------------------------------------------
// Constants
// ---------------------------------------------------------------------------

const _companyId = 'co-1';
const _contractorId = 'contractor-user-1';
const _adminId = 'admin-user-1';
const _otherContractorId = 'contractor-user-2';

const _weeklyPathSelf =
    '/api/v1/scheduling/schedules/$_contractorId/weekly';
const _weeklyPathOther =
    '/api/v1/scheduling/schedules/$_otherContractorId/weekly';

// ---------------------------------------------------------------------------
// Auth states
// ---------------------------------------------------------------------------

AuthState _contractorAuth() => const AuthState.authenticated(
      userId: _contractorId,
      companyId: _companyId,
      roles: {UserRole.contractor},
    );

AuthState _adminAuth() => const AuthState.authenticated(
      userId: _adminId,
      companyId: _companyId,
      roles: {UserRole.admin},
    );

// ---------------------------------------------------------------------------
// Fakes / mocks
// ---------------------------------------------------------------------------

/// Fake AuthNotifier — supplies a fixed AuthState without hitting
/// `getIt<AuthRepository>()` during build().
class _FakeAuthNotifier extends AuthNotifier {
  _FakeAuthNotifier(this._state);
  final AuthState _state;

  @override
  AuthState build() => _state;
}

class _MockDioClient extends Mock implements DioClient {}

class _MockDio extends Mock implements dio_pkg.Dio {}

class _MockSyncEngine extends Mock implements SyncEngine {}

// ---------------------------------------------------------------------------
// Dio stub/verify helpers (settings screen)
// ---------------------------------------------------------------------------

dio_pkg.Response<dynamic> _okResponse(Map<String, dynamic> data) =>
    dio_pkg.Response<dynamic>(
      data: data,
      statusCode: 200,
      requestOptions: dio_pkg.RequestOptions(),
    );

/// Stub GET to return [data] (defaults to an empty map → screen keeps defaults).
void _stubGet(_MockDio dio, {Map<String, dynamic> data = const {}}) {
  when(() => dio.get<dynamic>(
        any(),
        data: any(named: 'data'),
        queryParameters: any(named: 'queryParameters'),
        options: any(named: 'options'),
        cancelToken: any(named: 'cancelToken'),
        onReceiveProgress: any(named: 'onReceiveProgress'),
      )).thenAnswer((_) async => _okResponse(data));
}

void _stubGetThrows(_MockDio dio, Object error) {
  when(() => dio.get<dynamic>(
        any(),
        data: any(named: 'data'),
        queryParameters: any(named: 'queryParameters'),
        options: any(named: 'options'),
        cancelToken: any(named: 'cancelToken'),
        onReceiveProgress: any(named: 'onReceiveProgress'),
      )).thenThrow(error);
}

void _stubPatchOk(_MockDio dio) {
  when(() => dio.patch<dynamic>(
        any(),
        data: any(named: 'data'),
        queryParameters: any(named: 'queryParameters'),
        options: any(named: 'options'),
        cancelToken: any(named: 'cancelToken'),
        onSendProgress: any(named: 'onSendProgress'),
        onReceiveProgress: any(named: 'onReceiveProgress'),
      )).thenAnswer((_) async => _okResponse(const {}));
}

void _stubPatchThrows(_MockDio dio, Object error) {
  when(() => dio.patch<dynamic>(
        any(),
        data: any(named: 'data'),
        queryParameters: any(named: 'queryParameters'),
        options: any(named: 'options'),
        cancelToken: any(named: 'cancelToken'),
        onSendProgress: any(named: 'onSendProgress'),
        onReceiveProgress: any(named: 'onReceiveProgress'),
      )).thenThrow(error);
}

List<dynamic> _capturedGetPaths(_MockDio dio) {
  return verify(() => dio.get<dynamic>(
        captureAny(),
        data: any(named: 'data'),
        queryParameters: any(named: 'queryParameters'),
        options: any(named: 'options'),
        cancelToken: any(named: 'cancelToken'),
        onReceiveProgress: any(named: 'onReceiveProgress'),
      )).captured;
}

List<List<dynamic>> _capturedPatch(_MockDio dio) {
  final captured = verify(() => dio.patch<dynamic>(
        captureAny(),
        data: captureAny(named: 'data'),
        queryParameters: any(named: 'queryParameters'),
        options: any(named: 'options'),
        cancelToken: any(named: 'cancelToken'),
        onSendProgress: any(named: 'onSendProgress'),
        onReceiveProgress: any(named: 'onReceiveProgress'),
      )).captured;
  // captured is a flat list [path0, data0, path1, data1, ...]
  final calls = <List<dynamic>>[];
  for (var i = 0; i + 1 < captured.length; i += 2) {
    calls.add([captured[i], captured[i + 1]]);
  }
  return calls;
}

/// Build a network-flavoured DioException whose toString() contains a keyword
/// the screen treats as "offline".
dio_pkg.DioException _networkError() => dio_pkg.DioException(
      requestOptions: dio_pkg.RequestOptions(),
      type: dio_pkg.DioExceptionType.connectionTimeout,
      message: 'Connection timeout — host unreachable',
    );

/// Build a non-network server error (badResponse 500).
dio_pkg.DioException _serverError() => dio_pkg.DioException(
      requestOptions: dio_pkg.RequestOptions(),
      type: dio_pkg.DioExceptionType.badResponse,
      response: dio_pkg.Response<dynamic>(
        statusCode: 500,
        requestOptions: dio_pkg.RequestOptions(),
      ),
    );

// ---------------------------------------------------------------------------
// Drift seed helpers (contractor screen)
// ---------------------------------------------------------------------------

Future<void> _seedCompany(AppDatabase db) async {
  final now = DateTime.now();
  await db.into(db.companies).insert(
        CompaniesCompanion.insert(
          id: const Value(_companyId),
          name: 'Test Co',
          version: const Value(1),
          createdAt: now,
          updatedAt: now,
        ),
      );
}

Future<void> _seedJob(
  AppDatabase db, {
  required String id,
  required String description,
  String status = 'scheduled',
  DateTime? scheduledCompletion,
}) async {
  final now = DateTime.now();
  await db.into(db.jobs).insert(
        JobsCompanion.insert(
          id: Value(id),
          companyId: _companyId,
          description: description,
          tradeType: 'plumber',
          status: Value(status),
          statusHistory: const Value('[]'),
          priority: const Value('medium'),
          tags: const Value('[]'),
          scheduledCompletionDate: Value(scheduledCompletion),
          version: const Value(1),
          createdAt: now,
          updatedAt: now,
        ),
      );
}

Future<void> _seedBooking(
  AppDatabase db, {
  required String id,
  required String jobId,
  required DateTime start,
  required DateTime end,
  String contractorId = _contractorId,
}) async {
  await db.bookingDao.createBooking(
    id: id,
    companyId: _companyId,
    contractorId: contractorId,
    jobId: jobId,
    timeRangeStart: start,
    timeRangeEnd: end,
  );
}

DateTime _todayAt(int hour) {
  final now = DateTime.now();
  return DateTime(now.year, now.month, now.day, hour);
}

DateTime _dayOffsetAt(int dayOffset, int hour) {
  final now = DateTime.now();
  return DateTime(now.year, now.month, now.day, hour)
      .add(Duration(days: dayOffset));
}

// ---------------------------------------------------------------------------
// Pump helpers
// ---------------------------------------------------------------------------

Future<void> _pumpSettings(
  WidgetTester tester, {
  required AuthState auth,
  String? contractorId,
}) async {
  // Tall viewport so the 7-row ListView.builder lays out every day row (default
  // 800x600 only builds the visible ~4, breaking whole-list count assertions).
  tester.view.physicalSize = const Size(1000, 2600);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        authNotifierProvider.overrideWith(() => _FakeAuthNotifier(auth)),
      ],
      child: MaterialApp(
        home: ScheduleSettingsScreen(contractorId: contractorId),
      ),
    ),
  );
  // Let initState's GET future resolve. NO pumpAndSettle (spinner never settles
  // while _isSaving, and snackbars auto-dismiss on a timer).
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 100));
}

Future<void> _pumpContractor(
  WidgetTester tester, {
  required AuthState auth,
}) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        authNotifierProvider.overrideWith(() => _FakeAuthNotifier(auth)),
      ],
      child: const MaterialApp(
        home: Scaffold(body: ContractorScheduleScreen()),
      ),
    ),
  );
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 150));
}

/// Unmount and flush Drift's zero-duration close timer (MEMORY.md: Drift streams
/// never settle). Call at the END of every contractor-screen test.
Future<void> _drainDriftTimers(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox());
  await tester.pump(const Duration(milliseconds: 50));
}

void main() {
  // ==========================================================================
  // Group A — ScheduleSettingsScreen (weekly template, Dio-backed)
  // ==========================================================================
  group('ScheduleSettingsScreen E2E (Dio weekly template)', () {
    late _MockDioClient mockDioClient;
    late _MockDio mockDio;

    setUp(() {
      mockDioClient = _MockDioClient();
      mockDio = _MockDio();
      when(() => mockDioClient.instance).thenReturn(mockDio);

      if (getIt.isRegistered<DioClient>()) getIt.unregister<DioClient>();
      getIt.registerSingleton<DioClient>(mockDioClient);
    });

    tearDown(() async {
      await getIt.reset();
    });

    // ─── 1: clean load renders defaults ────────────────────────────────────
    testWidgets('renders 7 day rows, Save action, and quick actions on load',
        (tester) async {
      _stubGet(mockDio); // empty payload → defaults (Mon–Fri working)

      await _pumpSettings(tester, auth: _contractorAuth());

      // Contractor (self) mode title.
      expect(find.text('My Schedule Settings'), findsOneWidget);

      // All 7 day rows.
      for (final day in const [
        'Monday',
        'Tuesday',
        'Wednesday',
        'Thursday',
        'Friday',
        'Saturday',
        'Sunday',
      ]) {
        expect(find.text(day), findsOneWidget);
      }

      // Save action visible once loaded (not offline, not loading).
      expect(find.widgetWithText(TextButton, 'Save'), findsOneWidget);

      // Quick actions.
      expect(find.text('Copy Mon to weekdays'), findsOneWidget);
      expect(find.text('All day off'), findsOneWidget);

      // Defaults: Sat + Sun are days off → two "Day off" labels; the 5 working
      // days each expose a Start time picker.
      expect(find.text('Day off'), findsNWidgets(2));
      expect(find.text('Start'), findsNWidgets(5));

      // The GET hit the self endpoint.
      expect(_capturedGetPaths(mockDio), contains(_weeklyPathSelf));
    });

    // ─── 2: renders server template ────────────────────────────────────────
    testWidgets('renders server-provided template (Monday returned as day off)',
        (tester) async {
      // 7 days, index 0 (Monday) NOT working; rest working.
      final days = List.generate(
        7,
        (i) => <String, dynamic>{
          'is_working': i != 0,
          'start_time': '09:00',
          'end_time': '15:00',
        },
      );
      _stubGet(mockDio, data: {'days': days});

      await _pumpSettings(tester, auth: _contractorAuth());

      // Monday now a day off → 3 day-off labels total (Mon + Sat + Sun still
      // default? No — server drives all 7). Server marks only Monday off, the
      // other six working → exactly one "Day off".
      expect(find.text('Day off'), findsOneWidget);
      // Six working days → six Start pickers.
      expect(find.text('Start'), findsNWidgets(6));
    });

    // ─── 3: change a day + Save → PATCH path + payload ─────────────────────
    testWidgets('toggle a day then Save → PATCH weekly endpoint + success',
        (tester) async {
      _stubGet(mockDio);
      _stubPatchOk(mockDio);

      await _pumpSettings(tester, auth: _contractorAuth());

      // Toggle Monday (first Switch) from working → off.
      await tester.tap(find.byType(Switch).first);
      await tester.pump();

      await tester.tap(find.widgetWithText(TextButton, 'Save'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));

      // Success snackbar.
      expect(find.text('Schedule saved'), findsOneWidget);

      // Verify PATCH path + payload shape.
      final calls = _capturedPatch(mockDio);
      expect(calls, hasLength(1));
      expect(calls.first[0], _weeklyPathSelf);
      final payload = calls.first[1] as Map<String, dynamic>;
      final days = payload['days'] as List<dynamic>;
      expect(days, hasLength(7));
      // Monday (index 0) is now day off.
      expect((days[0] as Map)['is_working'], isFalse);
      // Tuesday still working.
      expect((days[1] as Map)['is_working'], isTrue);
    });

    // ─── 4: quick action "All day off" ─────────────────────────────────────
    testWidgets('quick action "All day off" turns every row into a day off',
        (tester) async {
      _stubGet(mockDio);

      await _pumpSettings(tester, auth: _contractorAuth());
      expect(find.text('Day off'), findsNWidgets(2)); // Sat + Sun default

      await tester.tap(find.text('All day off'));
      await tester.pump();

      expect(find.text('Day off'), findsNWidgets(7));
      // No working days → no Start pickers.
      expect(find.text('Start'), findsNothing);
    });

    // ─── 5: quick action "Copy Mon to weekdays" ────────────────────────────
    testWidgets('quick action "Copy Mon to weekdays" shows confirmation',
        (tester) async {
      _stubGet(mockDio);

      await _pumpSettings(tester, auth: _contractorAuth());

      await tester.tap(find.text('Copy Mon to weekdays'));
      await tester.pump();

      expect(find.text("Monday's hours copied to Tue–Fri"), findsOneWidget);
    });

    // ─── 6: Save server error → red snackbar ───────────────────────────────
    testWidgets('Save server error surfaces "Failed to save"', (tester) async {
      _stubGet(mockDio);
      _stubPatchThrows(mockDio, _serverError());

      await _pumpSettings(tester, auth: _contractorAuth());

      await tester.tap(find.widgetWithText(TextButton, 'Save'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));

      expect(
        find.textContaining('Failed to save'),
        findsOneWidget,
      );
    });

    // ─── 7: Save network error → offline sync message ──────────────────────
    testWidgets('Save network error shows offline-will-sync message',
        (tester) async {
      _stubGet(mockDio);
      _stubPatchThrows(mockDio, _networkError());

      await _pumpSettings(tester, auth: _contractorAuth());

      await tester.tap(find.widgetWithText(TextButton, 'Save'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));

      expect(
        find.text('Offline — changes will sync when connected'),
        findsOneWidget,
      );
    });

    // ─── 8: Load non-network error → error panel ───────────────────────────
    testWidgets('load non-network error renders the error panel',
        (tester) async {
      _stubGetThrows(mockDio, const FormatException('malformed response'));

      await _pumpSettings(tester, auth: _contractorAuth());

      expect(find.byIcon(Icons.error_outline), findsOneWidget);
      expect(find.textContaining('Failed to load schedule'), findsOneWidget);
    });

    // ─── 9: Load network error → offline banner + inputs disabled ──────────
    testWidgets('load network error shows offline banner and hides Save',
        (tester) async {
      _stubGetThrows(mockDio, _networkError());

      await _pumpSettings(tester, auth: _contractorAuth());

      expect(
        find.text('Connect to manage schedule — showing defaults'),
        findsOneWidget,
      );
      // Save action is hidden while offline.
      expect(find.widgetWithText(TextButton, 'Save'), findsNothing);
      // Day rows still render (defaults) but switches are disabled.
      expect(find.text('Monday'), findsOneWidget);
      final firstSwitch = tester.widget<Switch>(find.byType(Switch).first);
      expect(firstSwitch.onChanged, isNull);
    });

    // ─── 10: admin viewing another contractor → title + GET path ──────────
    testWidgets('admin mode (other contractorId) titles + targets that path',
        (tester) async {
      _stubGet(mockDio);

      await _pumpSettings(
        tester,
        auth: _adminAuth(),
        contractorId: _otherContractorId,
      );

      expect(find.text('Contractor Schedule'), findsOneWidget);
      expect(find.text('My Schedule Settings'), findsNothing);
      expect(_capturedGetPaths(mockDio), contains(_weeklyPathOther));
    });

    // ─── 11: no role gate — contractor reaches the full editor ────────────
    testWidgets('no role gate: contractor sees the full editable template',
        (tester) async {
      _stubGet(mockDio);

      await _pumpSettings(tester, auth: _contractorAuth());

      // Full editor available — Save + all interactive rows present.
      expect(find.widgetWithText(TextButton, 'Save'), findsOneWidget);
      expect(find.byType(Switch), findsNWidgets(7));
      final firstSwitch = tester.widget<Switch>(find.byType(Switch).first);
      expect(firstSwitch.onChanged, isNotNull); // enabled, not gated
    });
  });

  // ==========================================================================
  // Group B — ContractorScheduleScreen (offline-first Drift bookings)
  // ==========================================================================
  group('ContractorScheduleScreen E2E (Drift daily bookings)', () {
    late AppDatabase db;
    late _MockSyncEngine mockSyncEngine;

    setUp(() async {
      db = AppDatabase(NativeDatabase.memory());
      mockSyncEngine = _MockSyncEngine();
      when(() => mockSyncEngine.syncNow()).thenAnswer((_) async {});

      if (getIt.isRegistered<AppDatabase>()) getIt.unregister<AppDatabase>();
      getIt.registerSingleton<AppDatabase>(db);
      if (getIt.isRegistered<JobDao>()) getIt.unregister<JobDao>();
      getIt.registerSingleton<JobDao>(db.jobDao);
      if (getIt.isRegistered<BookingDao>()) getIt.unregister<BookingDao>();
      getIt.registerSingleton<BookingDao>(db.bookingDao);
      if (getIt.isRegistered<SyncEngine>()) getIt.unregister<SyncEngine>();
      getIt.registerSingleton<SyncEngine>(mockSyncEngine);

      await _seedCompany(db);
    });

    tearDown(() async {
      await getIt.reset();
      try {
        await db.close();
      } catch (_) {
        // Already closed.
      }
    });

    // ─── 12: renders today's bookings ──────────────────────────────────────
    testWidgets('renders today booking: description, status chip, TODAY header',
        (tester) async {
      await _seedJob(db, id: 'job-a', description: 'Fix kitchen sink');
      await _seedBooking(
        db,
        id: 'bk-a',
        jobId: 'job-a',
        start: _todayAt(9),
        end: _todayAt(11),
      );

      await _pumpContractor(tester, auth: _contractorAuth());

      expect(find.text('Fix kitchen sink'), findsOneWidget);
      expect(find.text('scheduled'), findsOneWidget); // status chip
      expect(find.text('TODAY'), findsOneWidget); // section header

      await _drainDriftTimers(tester);
    });

    // ─── 13: empty state ───────────────────────────────────────────────────
    testWidgets('empty day shows "No jobs scheduled"', (tester) async {
      await _pumpContractor(tester, auth: _contractorAuth());

      expect(find.text('No jobs scheduled'), findsOneWidget);

      await _drainDriftTimers(tester);
    });

    // ─── 14: multiple bookings, ascending order ────────────────────────────
    testWidgets('multiple bookings render in ascending time order',
        (tester) async {
      await _seedJob(db, id: 'job-am', description: 'Morning inspection');
      await _seedJob(db, id: 'job-pm', description: 'Afternoon repair');
      // Seed out of order — DAO orders by timeRangeStart asc.
      await _seedBooking(
        db,
        id: 'bk-pm',
        jobId: 'job-pm',
        start: _todayAt(15),
        end: _todayAt(17),
      );
      await _seedBooking(
        db,
        id: 'bk-am',
        jobId: 'job-am',
        start: _todayAt(8),
        end: _todayAt(10),
      );

      await _pumpContractor(tester, auth: _contractorAuth());

      expect(find.text('Morning inspection'), findsOneWidget);
      expect(find.text('Afternoon repair'), findsOneWidget);

      final morningY =
          tester.getTopLeft(find.text('Morning inspection')).dy;
      final afternoonY =
          tester.getTopLeft(find.text('Afternoon repair')).dy;
      expect(morningY, lessThan(afternoonY));

      await _drainDriftTimers(tester);
    });

    // ─── 15: overdue job → prompt + Report Delay button ────────────────────
    testWidgets('overdue job shows overdue prompt and Report Delay button',
        (tester) async {
      await _seedJob(
        db,
        id: 'job-late',
        description: 'Overdue boiler service',
        scheduledCompletion:
            DateTime.now().subtract(const Duration(days: 3)),
      );
      await _seedBooking(
        db,
        id: 'bk-late',
        jobId: 'job-late',
        start: _todayAt(9),
        end: _todayAt(12),
      );

      await _pumpContractor(tester, auth: _contractorAuth());

      expect(
        find.textContaining('past its scheduled completion'),
        findsOneWidget,
      );
      expect(find.text('Report Delay'), findsOneWidget);

      await _drainDriftTimers(tester);
    });

    // ─── 16: Report Delay dialog opens + validates + cancels ───────────────
    testWidgets('Report Delay opens dialog; empty submit validates; Cancel closes',
        (tester) async {
      await _seedJob(
        db,
        id: 'job-delay',
        description: 'Repair fence',
        status: 'in_progress',
      );
      await _seedBooking(
        db,
        id: 'bk-delay',
        jobId: 'job-delay',
        start: _todayAt(9),
        end: _todayAt(11),
      );

      await _pumpContractor(tester, auth: _contractorAuth());

      await tester.tap(find.text('Report Delay'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));

      // Dialog fields render.
      expect(find.text('Reason for delay *'), findsOneWidget);
      expect(find.widgetWithText(FilledButton, 'Submit'), findsOneWidget);

      // Empty submit → validation for both required fields.
      await tester.tap(find.widgetWithText(FilledButton, 'Submit'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      expect(find.text('Reason is required'), findsOneWidget);
      expect(find.text('New ETA date is required'), findsOneWidget);

      // Cancel closes the dialog.
      await tester.tap(find.widgetWithText(TextButton, 'Cancel'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));
      expect(find.text('Reason for delay *'), findsNothing);

      await _drainDriftTimers(tester);
    });

    // ─── 17: calendar toggle → ContractorCalendarView ──────────────────────
    testWidgets('toggle to Calendar view renders the time-axis calendar',
        (tester) async {
      await _seedJob(db, id: 'job-cal', description: 'Calendar job');
      await _seedBooking(
        db,
        id: 'bk-cal',
        jobId: 'job-cal',
        start: _todayAt(10),
        end: _todayAt(12),
      );

      await _pumpContractor(tester, auth: _contractorAuth());
      expect(find.text('Calendar job'), findsOneWidget); // list view first

      await tester.tap(find.text('Calendar'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400)); // scroll animation

      // Time axis hour labels appear only in the calendar view.
      expect(find.text('06:00'), findsWidgets);

      await _drainDriftTimers(tester);
    });

    // ─── 18: date navigation reactively switches days ──────────────────────
    testWidgets('next-day navigation reactively loads tomorrow booking',
        (tester) async {
      await _seedJob(db, id: 'job-tom', description: 'Tomorrow job');
      await _seedBooking(
        db,
        id: 'bk-tom',
        jobId: 'job-tom',
        start: _dayOffsetAt(1, 9),
        end: _dayOffsetAt(1, 11),
      );

      await _pumpContractor(tester, auth: _contractorAuth());

      // Today is empty.
      expect(find.text('Tomorrow job'), findsNothing);
      expect(find.text('No jobs scheduled'), findsOneWidget);

      // Advance one day.
      await tester.tap(find.byIcon(Icons.chevron_right));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));

      expect(find.text('Tomorrow job'), findsOneWidget);
      expect(find.text('TOMORROW'), findsOneWidget);

      await _drainDriftTimers(tester);
    });

    // ─── 19: pull-to-refresh → SyncEngine.syncNow() ────────────────────────
    testWidgets('pull-to-refresh invokes SyncEngine.syncNow()', (tester) async {
      await _pumpContractor(tester, auth: _contractorAuth());

      // Fling the scroll surface down to trigger the RefreshIndicator.
      await tester.fling(
        find.byType(CustomScrollView),
        const Offset(0, 350),
        1200,
      );
      await tester.pump(); // start the indicator
      await tester.pump(const Duration(milliseconds: 300));
      await tester.pump(const Duration(seconds: 1));

      verify(() => mockSyncEngine.syncNow()).called(1);

      await _drainDriftTimers(tester);
    });

    // ─── 20: unauthenticated guard ─────────────────────────────────────────
    testWidgets('unauthenticated auth state renders the loading guard',
        (tester) async {
      await _pumpContractor(tester, auth: const AuthState.loading());

      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      // Header (view toggle) is not built while unauthenticated.
      expect(find.byType(ContractorScheduleHeader), findsNothing);

      await _drainDriftTimers(tester);
    });
  });
}
