/// Shared test helpers for schedule feature widget tests.
///
/// Centralises duplicated helpers across schedule test files:
///   - Entity factories: makeJob(), makeBooking(), makeContractor()
///   - Auth state constants: adminAuthState, contractorAuthState
///   - Stub notifiers: StubAuthNotifier, StubBookingsNotifier, etc.
///   - buildScheduleTestApp() — reusable ProviderScope wrapper
library;

import 'package:contractorhub/features/auth/domain/auth_state.dart';
import 'package:contractorhub/features/auth/presentation/providers/auth_provider.dart';
import 'package:contractorhub/features/jobs/domain/job_entity.dart';
import 'package:contractorhub/features/jobs/presentation/providers/job_providers.dart'
    as job_providers;
import 'package:contractorhub/features/schedule/domain/booking_entity.dart';
import 'package:contractorhub/features/schedule/presentation/providers/calendar_providers.dart';
import 'package:contractorhub/features/schedule/presentation/providers/overdue_providers.dart';
import 'package:contractorhub/features/schedule/presentation/screens/schedule_screen.dart';
import 'package:contractorhub/features/users/domain/user_entity.dart';
import 'package:contractorhub/shared/models/user_role.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

// ---------------------------------------------------------------------------
// Auth state constants
// ---------------------------------------------------------------------------

const adminAuthState = AuthState.authenticated(
  userId: 'admin-user-1',
  companyId: 'co-1',
  roles: {UserRole.admin},
);

const contractorAuthState = AuthState.authenticated(
  userId: 'contractor-user-1',
  companyId: 'co-1',
  roles: {UserRole.contractor},
);

// ---------------------------------------------------------------------------
// Entity factories
// ---------------------------------------------------------------------------

/// Create a minimal [JobEntity] for tests.
JobEntity makeJob({
  String id = 'job-1',
  String companyId = 'co-1',
  String description = 'Repair water heater',
  String tradeType = 'plumber',
  String status = 'scheduled',
  String priority = 'medium',
  DateTime? scheduledCompletionDate,
  List<Map<String, dynamic>>? statusHistory,
  int version = 1,
  String? contractorId,
  String? clientId,
}) {
  final now = DateTime.now();
  return JobEntity(
    id: id,
    companyId: companyId,
    description: description,
    tradeType: tradeType,
    status: status,
    statusHistory: statusHistory ?? [],
    priority: priority,
    tags: const [],
    version: version,
    createdAt: now,
    updatedAt: now,
    scheduledCompletionDate: scheduledCompletionDate,
    contractorId: contractorId,
    clientId: clientId,
  );
}

/// Create a minimal [BookingEntity] for tests.
BookingEntity makeBooking({
  String id = 'booking-1',
  String companyId = 'co-1',
  String contractorId = 'contractor-user-1',
  String jobId = 'job-1',
  DateTime? timeRangeStart,
  DateTime? timeRangeEnd,
  int version = 1,
}) {
  final now = DateTime.now();
  return BookingEntity(
    id: id,
    companyId: companyId,
    contractorId: contractorId,
    jobId: jobId,
    timeRangeStart: timeRangeStart ?? now,
    timeRangeEnd: timeRangeEnd ?? now.add(const Duration(hours: 2)),
    version: version,
    createdAt: now,
    updatedAt: now,
  );
}

/// Create a minimal [UserEntity] for contractor tests.
UserEntity makeContractor({
  String id = 'contractor-user-1',
  String companyId = 'co-1',
  String email = 'john@test.com',
  String? firstName = 'John',
  String? lastName = 'Smith',
}) {
  final now = DateTime.now();
  return UserEntity(
    id: id,
    companyId: companyId,
    email: email,
    firstName: firstName,
    lastName: lastName,
    version: 1,
    createdAt: now,
    updatedAt: now,
  );
}

/// Returns a past date [days] days before today (time stripped to midnight).
DateTime pastDate(int days) {
  final now = DateTime.now();
  final today = DateTime(now.year, now.month, now.day);
  return today.subtract(Duration(days: days));
}

/// Returns a future date [days] days after today (time stripped to midnight).
DateTime futureDate(int days) {
  final now = DateTime.now();
  final today = DateTime(now.year, now.month, now.day);
  return today.add(Duration(days: days));
}

// ---------------------------------------------------------------------------
// Stub notifiers
// ---------------------------------------------------------------------------

/// Stub auth notifier that returns a fixed auth state.
class StubAuthNotifier extends AuthNotifier {
  StubAuthNotifier(this._fixedState);
  final AuthState _fixedState;

  @override
  AuthState build() => _fixedState;
}

/// Stub bookings notifier returning an empty list by default.
class StubBookingsNotifier extends BookingsForDateNotifier {
  StubBookingsNotifier([this._bookings = const []]);
  final List<BookingEntity> _bookings;

  @override
  Future<List<BookingEntity>> build() async => _bookings;
}

/// Stub contractors notifier returning an empty list by default.
class StubContractorsNotifier extends ContractorsNotifier {
  StubContractorsNotifier([this._contractors = const []]);
  final List<UserEntity> _contractors;

  @override
  Future<List<UserEntity>> build() async => _contractors;
}

/// Stub job list notifier returning an empty list by default.
class StubJobListNotifier extends job_providers.JobListNotifier {
  StubJobListNotifier([this._jobs = const []]);
  final List<JobEntity> _jobs;

  @override
  Future<List<JobEntity>> build() async => _jobs;
}

// ---------------------------------------------------------------------------
// Test app builders
// ---------------------------------------------------------------------------

/// Build a ScheduleScreen wrapped in a ProviderScope with all providers
/// overridden for isolation.
Widget buildScheduleTestApp({
  AuthState authState = adminAuthState,
  List<BookingEntity> bookings = const [],
  List<UserEntity> contractors = const [],
  List<JobEntity> jobs = const [],
  int overdueCount = 0,
  List<OverdueJobInfo> overdueJobs = const [],
}) {
  return ProviderScope(
    overrides: [
      authNotifierProvider
          .overrideWith(() => StubAuthNotifier(authState)),
      bookingsForDateProvider
          .overrideWith(() => StubBookingsNotifier(bookings)),
      contractorsProvider
          .overrideWith(() => StubContractorsNotifier(contractors)),
      job_providers.jobListNotifierProvider
          .overrideWith(() => StubJobListNotifier(jobs)),
      overdueJobCountProvider.overrideWithValue(overdueCount),
      overdueJobsProvider.overrideWithValue(overdueJobs),
    ],
    child: const MaterialApp(
      home: Scaffold(
        body: ScheduleScreen(),
      ),
    ),
  );
}
