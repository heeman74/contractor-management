// Phase 11 — Integration Polish: Flutter E2E tests for INT-01, INT-02, INT-03.
//
// Tests cover three cross-phase wiring gaps identified in the v1.0 milestone audit:
//   - INT-01: JobSiteSyncHandler reads latitude/longitude (not lat/lng) from backend JSON
//   - INT-02: CalendarDayView generates travel_buffer BlockedInterval entries between bookings
//   - INT-03: OverduePanel displays human-readable names, not raw UUIDs
//
// Patterns:
//   - import 'package:drift/drift.dart' hide isNotNull, isNull; — avoids matcher conflicts
//   - pump() NOT pumpAndSettle() for Drift stream providers (streams never settle)
//   - ProviderScope overrides for Riverpod providers
//   - Fake notifiers extend original class for Riverpod 3 type safety

import 'dart:async';

import 'package:contractorhub/core/database/app_database.dart' hide UserRole;
import 'package:contractorhub/features/auth/domain/auth_state.dart';
import 'package:contractorhub/features/auth/presentation/providers/auth_provider.dart';
import 'package:contractorhub/features/jobs/domain/job_entity.dart';
import 'package:contractorhub/features/jobs/presentation/providers/job_providers.dart';
import 'package:contractorhub/features/schedule/data/job_site_sync_handler.dart';
import 'package:contractorhub/features/schedule/domain/booking_entity.dart';
import 'package:contractorhub/features/schedule/domain/overdue_service.dart';
import 'package:contractorhub/features/schedule/presentation/providers/calendar_providers.dart';
import 'package:contractorhub/features/schedule/presentation/providers/overdue_providers.dart';
import 'package:contractorhub/features/schedule/presentation/widgets/calendar_day_view.dart';
import 'package:contractorhub/features/schedule/presentation/widgets/overdue_panel.dart';
import 'package:contractorhub/features/schedule/presentation/widgets/travel_time_block.dart';
import 'package:contractorhub/features/users/domain/user_entity.dart';
import 'package:contractorhub/features/users/presentation/providers/user_providers.dart';
import 'package:contractorhub/shared/models/user_role.dart';
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

AppDatabase _makeInMemoryDb() {
  return AppDatabase(NativeDatabase.memory());
}

AuthState _adminAuthState({String companyId = 'company-001'}) =>
    AuthState.authenticated(
      userId: 'user-001',
      companyId: companyId,
      roles: const {UserRole.admin},
    );

UserEntity _makeUser({
  String id = 'user-001',
  String companyId = 'company-001',
  String email = 'alice@example.com',
  String? firstName = 'Alice',
  String? lastName = 'Smith',
}) {
  return UserEntity(
    id: id,
    companyId: companyId,
    email: email,
    firstName: firstName,
    lastName: lastName,
    version: 1,
    createdAt: DateTime(2026),
    updatedAt: DateTime(2026),
  );
}

BookingEntity _makeBooking({
  required String contractorId,
  required DateTime start,
  required DateTime end,
  String id = 'booking-001',
  String jobId = 'job-001',
}) {
  return BookingEntity(
    id: id,
    companyId: 'company-001',
    contractorId: contractorId,
    jobId: jobId,
    timeRangeStart: start,
    timeRangeEnd: end,
    version: 1,
    createdAt: DateTime(2026),
    updatedAt: DateTime(2026),
  );
}

JobEntity _makeJob({
  String id = 'job-001',
  String status = 'scheduled',
  String? clientId,
  String? contractorId,
}) {
  return JobEntity(
    id: id,
    companyId: 'company-001',
    description: 'Fix Roof',
    tradeType: 'roofing',
    status: status,
    statusHistory: const [],
    priority: 'medium',
    tags: const [],
    estimatedDurationMinutes: 60,
    scheduledCompletionDate: DateTime.now().subtract(const Duration(days: 3)),
    clientId: clientId,
    contractorId: contractorId,
    version: 1,
    createdAt: DateTime(2026),
    updatedAt: DateTime(2026),
  );
}

// Fake notifiers for Riverpod 3 type-safe overrides.

class _FakeAuthNotifier extends AuthNotifier {
  final AuthState _state;
  _FakeAuthNotifier(this._state);

  @override
  AuthState build() => _state;
}

class _StubJobListNotifier extends JobListNotifier {
  final List<JobEntity> _jobs;
  _StubJobListNotifier(this._jobs);

  @override
  Future<List<JobEntity>> build() async => _jobs;
}

// ---------------------------------------------------------------------------
// main
// ---------------------------------------------------------------------------

void main() {
  // -------------------------------------------------------------------------
  // group: int01_field_names — JobSiteSyncHandler latitude/longitude field names
  // -------------------------------------------------------------------------

  group('int01_field_names', () {
    test(
      'int01_correct_fields: applyPulled with latitude/longitude populates lat/lng in Drift',
      () async {
        final db = _makeInMemoryDb();
        final handler = JobSiteSyncHandler(db);

        final data = <String, dynamic>{
          'id': 'site-001',
          'company_id': 'company-001',
          'address': '123 Main St',
          'formatted_address': '123 Main St, New York, NY',
          'latitude': 40.7128,
          'longitude': -74.006,
          'version': 1,
          'created_at': '2026-01-01T00:00:00Z',
          'updated_at': '2026-01-01T00:00:00Z',
          'deleted_at': null,
        };

        await handler.applyPulled(data);

        final sites = await db.select(db.jobSites).get();
        expect(sites, hasLength(1));
        expect(sites.first.lat, closeTo(40.7128, 0.0001));
        expect(sites.first.lng, closeTo(-74.006, 0.0001));

        await db.close();
      },
    );

    test(
      'int01_old_fields_ignored: applyPulled with lat/lng keys stores null lat/lng',
      () async {
        final db = _makeInMemoryDb();
        final handler = JobSiteSyncHandler(db);

        // Old field names that the backend no longer sends.
        final data = <String, dynamic>{
          'id': 'site-002',
          'company_id': 'company-001',
          'address': '456 Elm St',
          'formatted_address': null,
          'lat': 40.7128,  // old field name — should NOT be read
          'lng': -74.006,  // old field name — should NOT be read
          'version': 1,
          'created_at': '2026-01-01T00:00:00Z',
          'updated_at': '2026-01-01T00:00:00Z',
          'deleted_at': null,
        };

        await handler.applyPulled(data);

        final sites = await db.select(db.jobSites).get();
        expect(sites, hasLength(1));
        // Old field names are not read — lat/lng should be null.
        expect(sites.first.lat, isNull);
        expect(sites.first.lng, isNull);

        await db.close();
      },
    );
  });

  // -------------------------------------------------------------------------
  // group: int02_travel_block — CalendarDayView generates travel_buffer intervals
  // -------------------------------------------------------------------------

  group('int02_travel_block', () {
    Widget buildCalendarTestWidget({
      required List<BookingEntity> bookings,
      required List<UserEntity> contractors,
      required Map<String, JobEntity> jobs,
    }) {
      final day = DateTime(2026, 3, 15);
      return ProviderScope(
        overrides: [
          authNotifierProvider
              .overrideWith(() => _FakeAuthNotifier(_adminAuthState())),
          showCompletedJobsProvider.overrideWith((ref) => false),
          contractorPageCountProvider.overrideWith((ref) => 1),
        ],
        // Use MediaQuery to provide a known screen size so _calcLaneWidth
        // returns a stable value (laneWidth = (800 - 44) / 1 = 756).
        child: MediaQuery(
          data: const MediaQueryData(size: Size(800, 1200)),
          child: MaterialApp(
            home: Scaffold(
              body: CalendarDayView(
                selectedDate: day,
                bookings: bookings,
                contractors: contractors,
                jobs: jobs,
                companyId: 'company-001',
              ),
            ),
          ),
        ),
      );
    }

    testWidgets(
      'int02_travel_interval: CalendarDayView renders TravelTimeBlock between bookings with gap',
      (tester) async {
        // Set window size to match the MediaQuery override.
        tester.view.physicalSize = const Size(800, 1200);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(() {
          tester.view.resetPhysicalSize();
          tester.view.resetDevicePixelRatio();
        });

        final day = DateTime(2026, 3, 15);
        const contractorId = 'contractor-001';

        // Two bookings with a 20-minute gap between them.
        final booking1 = _makeBooking(
          contractorId: contractorId,
          start: day.add(const Duration(hours: 9)),              // 09:00
          end: day.add(const Duration(hours: 10)),               // 10:00
        );
        final booking2 = _makeBooking(
          id: 'booking-002',
          contractorId: contractorId,
          start: day.add(const Duration(hours: 10, minutes: 20)), // 10:20
          end: day.add(const Duration(hours: 11, minutes: 20)),   // 11:20
          jobId: 'job-002',
        );

        final contractor = _makeUser(id: contractorId);
        final jobs = {
          'job-001': _makeJob(),
          'job-002': _makeJob(id: 'job-002'),
        };

        await tester.pumpWidget(
          buildCalendarTestWidget(
            bookings: [booking1, booking2],
            contractors: [contractor],
            jobs: jobs,
          ),
        );

        // Use pump() not pumpAndSettle() — Drift stream providers never settle.
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 100));

        // TravelTimeBlock should appear between the two bookings.
        expect(find.byType(TravelTimeBlock), findsOneWidget);
      },
    );

    testWidgets(
      'int02_no_travel_no_gap: No TravelTimeBlock when bookings are back-to-back',
      (tester) async {
        tester.view.physicalSize = const Size(800, 1200);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(() {
          tester.view.resetPhysicalSize();
          tester.view.resetDevicePixelRatio();
        });

        final day = DateTime(2026, 3, 15);
        const contractorId = 'contractor-001';

        // Two back-to-back bookings with NO gap.
        final booking1 = _makeBooking(
          contractorId: contractorId,
          start: day.add(const Duration(hours: 9)),  // 09:00
          end: day.add(const Duration(hours: 10)),   // 10:00
        );
        final booking2 = _makeBooking(
          id: 'booking-002',
          contractorId: contractorId,
          start: day.add(const Duration(hours: 10)),  // 10:00 — no gap
          end: day.add(const Duration(hours: 11)),    // 11:00
          jobId: 'job-002',
        );

        final contractor = _makeUser(id: contractorId);
        final jobs = {
          'job-001': _makeJob(),
          'job-002': _makeJob(id: 'job-002'),
        };

        await tester.pumpWidget(
          buildCalendarTestWidget(
            bookings: [booking1, booking2],
            contractors: [contractor],
            jobs: jobs,
          ),
        );

        await tester.pump();
        await tester.pump(const Duration(milliseconds: 100));

        // No gap means no travel buffer block.
        expect(find.byType(TravelTimeBlock), findsNothing);
      },
    );
  });

  // -------------------------------------------------------------------------
  // group: int02_travel_renders — TravelTimeBlock widget renders
  // -------------------------------------------------------------------------

  group('int02_travel_renders', () {
    testWidgets(
      'int02_render: TravelTimeBlock widget renders with Travel label when tall enough',
      (tester) async {
        // 40 logical pixels — above the 30px threshold for the "Travel" label.
        await tester.pumpWidget(
          const MaterialApp(
            home: Scaffold(
              body: TravelTimeBlock(height: 40, width: 100),
            ),
          ),
        );

        await tester.pump();

        expect(find.byType(TravelTimeBlock), findsOneWidget);
        // "Travel" label visible when height >= 30px.
        expect(find.text('Travel'), findsOneWidget);
      },
    );
  });

  // -------------------------------------------------------------------------
  // group: int03_display_names — overdueJobsProvider resolves names
  // -------------------------------------------------------------------------

  group('int03_display_names', () {
    testWidgets(
      'int03_names: overdueJobsProvider returns FirstName LastName, not UUID',
      (tester) async {
        final client = _makeUser(
          id: 'client-uuid-001',
        );
        final overdueJob = _makeJob(
          clientId: 'client-uuid-001',
        );

        // Use a ConsumerWidget to read the provider inside a real widget context.
        // This allows StreamProvider stream emissions to resolve properly.
        List<OverdueJobInfo>? capturedJobs;
        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              authNotifierProvider.overrideWith(
                () => _FakeAuthNotifier(_adminAuthState()),
              ),
              jobListNotifierProvider.overrideWith(
                () => _StubJobListNotifier([overdueJob]),
              ),
              companyUsersProvider('company-001').overrideWith(
                (ref) => Stream.value([client]),
              ),
            ],
            child: Consumer(
              builder: (context, ref, _) {
                capturedJobs = ref.watch(overdueJobsProvider);
                return const MaterialApp(home: Scaffold(body: SizedBox.shrink()));
              },
            ),
          ),
        );

        // pump() once to allow providers to build and stream to emit.
        await tester.pump();
        // Second pump allows stream subscription to deliver first value.
        await tester.pump(const Duration(milliseconds: 50));

        expect(capturedJobs, isNotNull);
        expect(capturedJobs, hasLength(1));
        // clientName should be "Alice Smith", not the raw UUID.
        expect(capturedJobs!.first.clientName, equals('Alice Smith'));
      },
    );

    test(
      'int03_no_auth: overdueJobsProvider returns empty list when not authenticated',
      () async {
        final container = ProviderContainer(
          overrides: [
            authNotifierProvider.overrideWith(
              () => _FakeAuthNotifier(const AuthState.unauthenticated()),
            ),
            jobListNotifierProvider.overrideWith(
              () => _StubJobListNotifier([_makeJob()]),
            ),
          ],
        );
        addTearDown(container.dispose);

        // No auth — overdueJobsProvider should return empty immediately.
        final overdueJobs = container.read(overdueJobsProvider);
        // Without auth, provider returns empty list (no crash).
        expect(overdueJobs, isEmpty);
      },
    );
  });

  // -------------------------------------------------------------------------
  // group: int03_panel_names — OverduePanel displays resolved names
  // -------------------------------------------------------------------------

  group('int03_panel_names', () {
    testWidgets(
      'int03_panel: OverduePanel displays resolved contractor name, not UUID',
      (tester) async {
        // OverduePanel shows info.contractorName in the row (not clientName).
        // Verify the resolved display name appears, not the raw UUID string.
        final overdueInfo = OverdueJobInfo(
          jobId: 'job-001',
          description: 'Roof Repair',
          scheduledCompletionDate:
              DateTime.now().subtract(const Duration(days: 5)),
          daysOverdue: 5,
          severity: OverdueSeverity.warning,
          hasDelayReport: false,
          clientName: 'Alice Smith',         // resolved from companyUsersProvider
          contractorName: 'Bob Jones',       // resolved from companyUsersProvider
        );

        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              authNotifierProvider.overrideWith(
                () => _FakeAuthNotifier(_adminAuthState()),
              ),
              showOverduePanelProvider.overrideWith((ref) => true),
              overdueJobsProvider.overrideWith((ref) => [overdueInfo]),
            ],
            child: const MaterialApp(
              home: Scaffold(body: OverduePanel()),
            ),
          ),
        );

        await tester.pump();
        await tester.pump(const Duration(milliseconds: 300));

        expect(find.byType(OverduePanel), findsOneWidget);
        // OverduePanel renders contractorName in the person-icon row.
        expect(find.text('Bob Jones'), findsOneWidget);
        // Raw UUID strings must NOT appear as names.
        expect(find.text('contractor-uuid-001'), findsNothing);
        expect(find.text('client-uuid-001'), findsNothing);
      },
    );
  });

  // -------------------------------------------------------------------------
  // group: e2e_coordinate_flow — full sync payload to Drift round-trip
  // -------------------------------------------------------------------------

  group('e2e_coordinate_flow', () {
    test(
      'e2e_coordinates: Full sync payload with latitude/longitude yields non-null lat/lng in Drift',
      () async {
        final db = _makeInMemoryDb();
        final handler = JobSiteSyncHandler(db);

        // Realistic sync payload matching the backend JobSiteResponse schema.
        final syncPayload = <String, dynamic>{
          'id': 'site-e2e-001',
          'company_id': 'company-001',
          'address': '350 5th Ave, New York, NY',
          'formatted_address': '350 5th Ave, New York, NY 10118',
          'latitude': 40.7484,
          'longitude': -73.9967,
          'version': 3,
          'created_at': '2026-03-01T10:00:00Z',
          'updated_at': '2026-03-14T08:30:00Z',
          'deleted_at': null,
        };

        // Simulate the full sync pull path: handler receives payload, upserts to Drift.
        await handler.applyPulled(syncPayload);

        // Re-call to verify upsert idempotency (no duplicate errors).
        await handler.applyPulled(syncPayload);

        final sites = await db.select(db.jobSites).get();
        expect(sites, hasLength(1));

        final site = sites.first;
        expect(site.id, equals('site-e2e-001'));
        expect(site.lat, isNotNull);
        expect(site.lng, isNotNull);
        expect(site.lat, closeTo(40.7484, 0.0001));
        expect(site.lng, closeTo(-73.9967, 0.0001));
        expect(site.address, equals('350 5th Ave, New York, NY'));

        await db.close();
      },
    );
  });
}
