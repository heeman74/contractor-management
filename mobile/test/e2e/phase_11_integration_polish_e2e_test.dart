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

import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

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
import 'package:contractorhub/features/schedule/presentation/widgets/travel_time_block.dart';
import 'package:contractorhub/features/users/domain/user_entity.dart';
import 'package:contractorhub/features/users/presentation/providers/user_providers.dart';
import 'package:contractorhub/shared/models/user_role.dart';

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
    createdAt: DateTime(2026, 1, 1),
    updatedAt: DateTime(2026, 1, 1),
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
    createdAt: DateTime(2026, 1, 1),
    updatedAt: DateTime(2026, 1, 1),
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
    notes: null,
    purchaseOrderNumber: null,
    externalReference: null,
    estimatedDurationMinutes: 60,
    scheduledCompletionDate: DateTime.now().subtract(const Duration(days: 3)),
    clientId: clientId,
    contractorId: contractorId,
    gpsLatitude: null,
    gpsLongitude: null,
    gpsAddress: null,
    version: 1,
    createdAt: DateTime(2026, 1, 1),
    updatedAt: DateTime(2026, 1, 1),
    deletedAt: null,
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
        fail('Wave 0 stub — will be filled in Task 2');
      },
    );

    test(
      'int01_old_fields_ignored: applyPulled with lat/lng keys stores null lat/lng',
      () async {
        fail('Wave 0 stub — will be filled in Task 2');
      },
    );
  });

  // -------------------------------------------------------------------------
  // group: int02_travel_block — CalendarDayView generates travel_buffer intervals
  // -------------------------------------------------------------------------

  group('int02_travel_block', () {
    testWidgets(
      'int02_travel_interval: CalendarDayView renders TravelTimeBlock between bookings with gap',
      (tester) async {
        fail('Wave 0 stub — will be filled in Task 2');
      },
    );

    testWidgets(
      'int02_no_travel_no_gap: No TravelTimeBlock when bookings are back-to-back',
      (tester) async {
        fail('Wave 0 stub — will be filled in Task 2');
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
        fail('Wave 0 stub — will be filled in Task 2');
      },
    );
  });

  // -------------------------------------------------------------------------
  // group: int03_display_names — overdueJobsProvider resolves names
  // -------------------------------------------------------------------------

  group('int03_display_names', () {
    test(
      'int03_names: overdueJobsProvider returns FirstName LastName, not UUID',
      () async {
        fail('Wave 0 stub — will be filled in Task 2');
      },
    );

    test(
      'int03_no_auth: overdueJobsProvider returns empty list when not authenticated',
      () async {
        fail('Wave 0 stub — will be filled in Task 2');
      },
    );
  });

  // -------------------------------------------------------------------------
  // group: int03_panel_names — OverduePanel displays resolved names
  // -------------------------------------------------------------------------

  group('int03_panel_names', () {
    testWidgets(
      'int03_panel: OverduePanel displays resolved client name, not UUID',
      (tester) async {
        fail('Wave 0 stub — will be filled in Task 2');
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
        fail('Wave 0 stub — will be filled in Task 2');
      },
    );
  });
}
