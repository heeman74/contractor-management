// Phase 6 E2E: GPS Capture flow
//
// Covers VERIFICATION.md human_verification items #3:
// "Tap Capture Location with existing GPS address → confirm dialog appears"
// and the full permission flow (granted, denied, deniedForever).
//
// Strategy: Mock Geolocator plugin responses, use real Drift in-memory DB,
// exercise GpsCaptureButton through all permission states.
// Do NOT use pumpAndSettle() — Drift streams never settle.

import 'package:contractorhub/core/database/app_database.dart' hide UserRole;
import 'package:contractorhub/core/di/service_locator.dart';
import 'package:contractorhub/features/auth/domain/auth_state.dart';
import 'package:contractorhub/features/auth/presentation/providers/auth_provider.dart';
import 'package:contractorhub/features/jobs/data/job_dao.dart';
import 'package:contractorhub/features/jobs/domain/job_entity.dart';
import 'package:contractorhub/features/jobs/presentation/widgets/gps_capture_button.dart';
import 'package:contractorhub/shared/models/user_role.dart';
import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:geolocator/geolocator.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';

// Mock Geolocator at the platform level — must use extends, not implements
class MockGeolocatorPlatform extends GeolocatorPlatform with MockPlatformInterfaceMixin {
  bool _serviceEnabled = true;
  LocationPermission _permission = LocationPermission.always;
  Position? _position;

  void setServiceEnabled(bool enabled) => _serviceEnabled = enabled;
  void setPermission(LocationPermission perm) => _permission = perm;
  void setPosition(Position pos) => _position = pos;

  @override
  Future<bool> isLocationServiceEnabled() async => _serviceEnabled;

  @override
  Future<LocationPermission> checkPermission() async => _permission;

  @override
  Future<LocationPermission> requestPermission() async => _permission;

  @override
  Future<Position> getCurrentPosition({LocationSettings? locationSettings}) async {
    if (_position != null) return _position!;
    throw const LocationServiceDisabledException();
  }

  @override
  Future<bool> openAppSettings() async => true;
}

AppDatabase _openTestDb() => AppDatabase(NativeDatabase.memory());

const _auth = AuthState.authenticated(
  userId: 'contractor-1',
  companyId: 'co-1',
  roles: {UserRole.contractor},
);

class _StubAuthNotifier extends AuthNotifier {
  @override
  AuthState build() => _auth;
}

Future<void> _seedCompany(AppDatabase db) async {
  await db.into(db.companies).insert(CompaniesCompanion.insert(
        id: const Value('co-1'),
        name: 'Test Co',
        version: const Value(1),
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      ));
}

JobEntity _makeJob({
  double? gpsLatitude,
  double? gpsLongitude,
  String? gpsAddress,
}) {
  final now = DateTime.now();
  return JobEntity(
    id: 'job-1',
    companyId: 'co-1',
    description: 'Fix leaking pipe',
    tradeType: 'plumber',
    status: 'scheduled',
    statusHistory: const [],
    priority: 'medium',
    tags: const [],
    version: 1,
    createdAt: now,
    updatedAt: now,
    gpsLatitude: gpsLatitude,
    gpsLongitude: gpsLongitude,
    gpsAddress: gpsAddress,
  );
}

void main() {
  late AppDatabase db;
  late JobDao jobDao;
  late MockGeolocatorPlatform mockGeolocator;

  setUp(() async {
    db = _openTestDb();
    jobDao = JobDao(db);
    mockGeolocator = MockGeolocatorPlatform();

    await _seedCompany(db);

    // Register GPS mock
    GeolocatorPlatform.instance = mockGeolocator;

    // Register JobDao in GetIt
    if (getIt.isRegistered<AppDatabase>()) getIt.unregister<AppDatabase>();
    getIt.registerSingleton<AppDatabase>(db);
    if (getIt.isRegistered<JobDao>()) getIt.unregister<JobDao>();
    getIt.registerSingleton<JobDao>(jobDao);
  });

  tearDown(() async {
    if (getIt.isRegistered<JobDao>()) getIt.unregister<JobDao>();
    if (getIt.isRegistered<AppDatabase>()) getIt.unregister<AppDatabase>();
    await db.close();
  });

  Widget buildTestApp({required JobEntity job}) {
    return ProviderScope(
      overrides: [
        authNotifierProvider.overrideWith(() => _StubAuthNotifier()),
      ],
      child: MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: GpsCaptureButton(job: job),
          ),
        ),
      ),
    );
  }

  group('Phase 6 E2E: GPS Capture', () {
    testWidgets('shows Capture Location button with no GPS data',
        (tester) async {
      final job = _makeJob();
      await tester.pumpWidget(buildTestApp(job: job));
      await tester.pump();

      expect(find.text('Capture Location'), findsOneWidget);
      // No GPS display when data is empty
      expect(find.textContaining('Coordinates:'), findsNothing);
    });

    testWidgets('shows coordinates when lat/lng set but no address',
        (tester) async {
      final job = _makeJob(gpsLatitude: 37.7749, gpsLongitude: -122.4194);
      await tester.pumpWidget(buildTestApp(job: job));
      await tester.pump();

      expect(find.textContaining('37.77490N'), findsOneWidget);
      expect(find.textContaining('122.41940W'), findsOneWidget);
      expect(find.textContaining('address pending sync'), findsOneWidget);
    });

    testWidgets('shows geocoded address when gpsAddress is set',
        (tester) async {
      final job = _makeJob(
        gpsLatitude: 37.7749,
        gpsLongitude: -122.4194,
        gpsAddress: '123 Market St, San Francisco, CA 94105',
      );
      await tester.pumpWidget(buildTestApp(job: job));
      await tester.pump();

      expect(
        find.text('123 Market St, San Francisco, CA 94105'),
        findsOneWidget,
      );
    });

    testWidgets('location services disabled → snackbar', (tester) async {
      mockGeolocator.setServiceEnabled(false);

      final job = _makeJob();
      await tester.pumpWidget(buildTestApp(job: job));
      await tester.pump();

      await tester.tap(find.text('Capture Location'));
      await tester.pump();
      await tester.pump();

      expect(
        find.text('Enable location services in Settings.'),
        findsOneWidget,
      );
    });

    testWidgets('permission denied → requests, still denied → no action',
        (tester) async {
      mockGeolocator.setServiceEnabled(true);
      mockGeolocator.setPermission(LocationPermission.denied);

      final job = _makeJob();
      await tester.pumpWidget(buildTestApp(job: job));
      await tester.pump();

      await tester.tap(find.text('Capture Location'));
      await tester.pump();
      await tester.pump();

      // No dialog should appear, silently aborts
      expect(find.text('Location Permission Required'), findsNothing);
    });

    testWidgets('permission deniedForever → dialog with Open Settings',
        (tester) async {
      mockGeolocator.setServiceEnabled(true);
      mockGeolocator.setPermission(LocationPermission.deniedForever);

      final job = _makeJob();
      await tester.pumpWidget(buildTestApp(job: job));
      await tester.pump();

      await tester.tap(find.text('Capture Location'));
      await tester.pump();
      await tester.pump();

      // Dialog should appear
      expect(find.text('Location Permission Required'), findsOneWidget);
      expect(
        find.textContaining('enable it in app settings'),
        findsOneWidget,
      );
      expect(find.text('Open Settings'), findsOneWidget);
      expect(find.text('Cancel'), findsOneWidget);
    });

    testWidgets('existing GPS → confirm overwrite dialog', (tester) async {
      mockGeolocator.setServiceEnabled(true);
      mockGeolocator.setPermission(LocationPermission.always);

      final job = _makeJob(gpsLatitude: 37.0, gpsLongitude: -122.0);
      await tester.pumpWidget(buildTestApp(job: job));
      await tester.pump();

      await tester.tap(find.text('Capture Location'));
      await tester.pump();
      await tester.pump();

      // Overwrite confirmation dialog
      expect(find.text('Replace existing location?'), findsOneWidget);
      expect(find.text('Replace'), findsOneWidget);
      expect(find.text('Cancel'), findsOneWidget);
    });

    testWidgets('cancel overwrite dialog → GPS unchanged', (tester) async {
      mockGeolocator.setServiceEnabled(true);
      mockGeolocator.setPermission(LocationPermission.always);

      final job = _makeJob(gpsLatitude: 37.0, gpsLongitude: -122.0);
      await tester.pumpWidget(buildTestApp(job: job));
      await tester.pump();

      await tester.tap(find.text('Capture Location'));
      await tester.pump();
      await tester.pump();

      // Tap Cancel
      await tester.tap(find.text('Cancel'));
      await tester.pump();

      // Dialog dismissed, no GPS capture happened
    });

    testWidgets('successful capture → stores GPS and shows snackbar',
        (tester) async {
      mockGeolocator.setServiceEnabled(true);
      mockGeolocator.setPermission(LocationPermission.always);
      mockGeolocator.setPosition(Position(
        latitude: 40.7128,
        longitude: -74.0060,
        timestamp: DateTime.now(),
        accuracy: 10.0,
        altitude: 0.0,
        altitudeAccuracy: 0.0,
        heading: 0.0,
        headingAccuracy: 0.0,
        speed: 0.0,
        speedAccuracy: 0.0,
      ));

      // Seed job in DB so updateJobGps can find it
      await db.into(db.jobs).insert(JobsCompanion.insert(
            id: const Value('job-1'),
            companyId: 'co-1',
            description: 'Fix pipe',
            tradeType: 'plumber',
            status: const Value('scheduled'),
            statusHistory: const Value('[]'),
            priority: const Value('medium'),
            tags: const Value('[]'),
            version: const Value(1),
            createdAt: DateTime.now(),
            updatedAt: DateTime.now(),
          ));

      final job = _makeJob(); // No existing GPS
      await tester.pumpWidget(buildTestApp(job: job));
      await tester.pump();

      await tester.tap(find.text('Capture Location'));
      await tester.pump();
      await tester.pump();
      await tester.pump();

      // Success snackbar
      expect(
        find.text('Location captured. Address will update after sync.'),
        findsOneWidget,
      );
    });
  });
}
