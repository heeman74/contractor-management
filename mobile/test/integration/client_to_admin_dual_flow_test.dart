/// Integration tests for the client → admin dual flow.
///
/// Verifies Phase 4 item 3 — Full E2E:
/// 1. Client portal has "Submit a Job Request" button navigating to job request form
/// 2. GoRouter resolves /client/request to JobRequestFormScreen for client role
/// 3. Client submits request → success screen → Drift DB contains pending request
/// 4. Admin sees request in ReviewScreen with description and Accept button
/// 5. Data flow through Drift: insertJobRequest → watchPending → insertJob → watchJobs
library;

import 'dart:convert';

// Hide Drift-generated UserRole data class (conflicts with shared enum).
import 'package:contractorhub/core/database/app_database.dart' hide UserRole;
import 'package:contractorhub/core/di/service_locator.dart';
import 'package:contractorhub/core/network/dio_client.dart';
import 'package:contractorhub/core/routing/app_router.dart';
import 'package:contractorhub/core/routing/route_names.dart';
import 'package:contractorhub/features/auth/domain/auth_state.dart';
import 'package:contractorhub/features/auth/presentation/providers/auth_provider.dart';
import 'package:contractorhub/features/client/presentation/screens/client_portal_screen.dart';
import 'package:contractorhub/features/client/presentation/screens/job_request_form_screen.dart';
import 'package:contractorhub/features/jobs/presentation/screens/request_review_screen.dart';
import 'package:contractorhub/shared/models/user_role.dart';
import 'package:dio/dio.dart' as dio_pkg;
import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:mocktail/mocktail.dart';
import 'package:uuid/uuid.dart';

// ---------------------------------------------------------------------------
// Test helpers (self-contained per CLAUDE.md pattern)
// ---------------------------------------------------------------------------

class _StubAuthNotifier extends AuthNotifier {
  _StubAuthNotifier(this._fixedState);
  final AuthState _fixedState;

  @override
  AuthState build() => _fixedState;
}

AppDatabase _openTestDb() => AppDatabase(NativeDatabase.memory());

class MockDioClient extends Mock implements DioClient {}

class MockDio extends Mock implements dio_pkg.Dio {}

/// Extract the current location from GoRouter after widget pump.
String _routerLocation(WidgetTester tester) {
  final element = tester.element(find.byType(Router<Object>).first);
  final router = Router.of(element);
  final routeInformationProvider = router.routeInformationProvider;
  return routeInformationProvider?.value.uri.path ?? '';
}

// ---------------------------------------------------------------------------
// Constants
// ---------------------------------------------------------------------------

const _clientAuth = AuthState.authenticated(
  userId: 'client-1',
  companyId: 'co-1',
  roles: {UserRole.client},
);

const _adminAuth = AuthState.authenticated(
  userId: 'admin-1',
  companyId: 'co-1',
  roles: {UserRole.admin},
);

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

void main() {
  late AppDatabase db;
  late MockDioClient mockDioClient;
  late MockDio mockDio;

  setUp(() async {
    db = _openTestDb();

    // Seed company
    await db.into(db.companies).insert(CompaniesCompanion.insert(
          id: const Value('co-1'),
          name: 'Test Co',
          version: const Value(1),
          createdAt: DateTime.now(),
          updatedAt: DateTime.now(),
        ));

    // Register in GetIt
    if (getIt.isRegistered<JobDao>()) getIt.unregister<JobDao>();
    getIt.registerSingleton<JobDao>(db.jobDao);

    mockDioClient = MockDioClient();
    mockDio = MockDio();
    when(() => mockDioClient.instance).thenReturn(mockDio);

    if (getIt.isRegistered<DioClient>()) getIt.unregister<DioClient>();
    getIt.registerSingleton<DioClient>(mockDioClient);
  });

  tearDown(() async {
    if (getIt.isRegistered<JobDao>()) getIt.unregister<JobDao>();
    if (getIt.isRegistered<DioClient>()) getIt.unregister<DioClient>();
    await db.close();
  });

  /// Insert a pending job request into the in-memory DB.
  Future<void> seedRequest({
    required String id,
    required String description,
    String? submittedName,
    String urgency = 'normal',
    String? tradeType,
    double? budgetMin,
    double? budgetMax,
    List<String> photos = const [],
    DateTime? createdAt,
  }) async {
    final now = createdAt ?? DateTime.now();
    final photosJson = '[${photos.map((p) => '"$p"').join(',')}]';
    await db.into(db.jobRequests).insert(JobRequestsCompanion.insert(
          id: Value(id),
          companyId: 'co-1',
          description: description,
          photos: Value(photosJson),
          urgency: Value(urgency),
          tradeType: Value(tradeType),
          budgetMin: Value(budgetMin),
          budgetMax: Value(budgetMax),
          createdAt: now,
          updatedAt: now,
          submittedName: Value(submittedName),
        ));
  }

  // ── 1. Portal navigation button ──────────────────────────────────────────

  group('Client portal navigation', () {
    testWidgets('"Submit a Job Request" button exists on ClientPortalScreen',
        (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Navigator(
            onGenerateRoute: (_) => MaterialPageRoute<void>(
              builder: (_) => const ClientPortalScreen(),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // FilledButton.icon with "Submit a Job Request" text
      expect(find.text('Submit a Job Request'), findsOneWidget);
      expect(find.byIcon(Icons.add_task), findsOneWidget);
      expect(find.byType(FilledButton), findsOneWidget);

      await tester.pumpWidget(Container());
      await tester.pump(Duration.zero);
    });
  });

  // ── 2. Route resolution ──────────────────────────────────────────────────

  group('GoRouter resolves /client/request', () {
    testWidgets('client role navigates to /client/request successfully',
        (tester) async {
      // Use a Builder inside the router tree so we get a context with GoRouter
      late BuildContext navContext;

      final widget = ProviderScope(
        overrides: [
          authNotifierProvider
              .overrideWith(() => _StubAuthNotifier(_clientAuth)),
        ],
        child: Consumer(
          builder: (context, ref, _) {
            final router = ref.watch(routerProvider);
            return MaterialApp.router(
              routerConfig: router,
              builder: (context, child) {
                navContext = context;
                return child ?? const SizedBox();
              },
            );
          },
        ),
      );

      await tester.pumpWidget(widget);
      await tester.pumpAndSettle();

      // Navigate to job request form
      GoRouter.of(navContext).go(RouteNames.jobRequestForm);
      await tester.pumpAndSettle();

      expect(
          _routerLocation(tester), equals(RouteNames.jobRequestForm));

      await tester.pumpWidget(Container());
      await tester.pump(Duration.zero);
    });
  });

  // ── 3. Client submits request ────────────────────────────────────────────

  group('Client job request submission', () {
    testWidgets(
        'filling form and submitting creates pending request in Drift',
        (tester) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            authNotifierProvider
                .overrideWith(() => _StubAuthNotifier(_clientAuth)),
          ],
          child: MaterialApp(
            home: Navigator(
              onGenerateRoute: (_) => MaterialPageRoute<void>(
                builder: (_) => const JobRequestFormScreen(),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Fill description (min 20 chars)
      final descriptionField =
          find.widgetWithText(TextFormField, 'Description *');
      await tester.enterText(descriptionField,
          'Fix the broken pipe under the kitchen sink urgently');

      // Scroll down to find Submit button
      await tester.dragUntilVisible(
        find.text('Submit Request'),
        find.byType(ListView),
        const Offset(0, -200),
      );
      await tester.pumpAndSettle();

      // Tap Submit Request
      await tester.tap(find.text('Submit Request'));
      await tester.pumpAndSettle();

      // Success screen should appear
      expect(find.text('Request Submitted!'), findsOneWidget);

      // Verify Drift DB has the pending request
      final requests =
          await db.jobDao.watchPendingRequestsByCompany('co-1').first;
      expect(requests, hasLength(1));
      expect(requests.first.description,
          equals('Fix the broken pipe under the kitchen sink urgently'));
      expect(requests.first.requestStatus, equals('pending'));

      await tester.pumpWidget(Container());
      await tester.pump(Duration.zero);
    });
  });

  // ── 4. Admin sees request ────────────────────────────────────────────────

  group('Admin request review', () {
    testWidgets(
        'admin sees pending request with description and Accept button',
        (tester) async {
      // Seed a pending request
      final now = DateTime.now();
      await db.into(db.jobRequests).insert(JobRequestsCompanion.insert(
            id: const Value('req-review-1'),
            companyId: 'co-1',
            description: 'Rewire the garage electrical panel',
            createdAt: now,
            updatedAt: now,
            submittedName: const Value('Alice'),
          ));

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            authNotifierProvider
                .overrideWith(() => _StubAuthNotifier(_adminAuth)),
          ],
          child: const MaterialApp(home: RequestReviewScreen()),
        ),
      );
      await tester.pumpAndSettle();

      // Description text visible
      expect(
          find.text('Rewire the garage electrical panel'), findsOneWidget);
      // Accept button visible
      expect(find.text('Accept'), findsOneWidget);
      // Submitter name visible
      expect(find.text('Alice'), findsOneWidget);

      await tester.pumpWidget(Container());
      await tester.pump(Duration.zero);
    });
  });

  // ── 5. Data flow through Drift (DAO-level) ──────────────────────────────

  group('Drift data flow pipeline', () {
    test('insertJobRequest → watchPending emits the request', () async {
      final now = DateTime.now();
      await db.jobDao.insertJobRequest(JobRequestsCompanion(
        id: Value(const Uuid().v4()),
        companyId: const Value('co-1'),
        clientId: const Value('client-1'),
        description: const Value('Install new ceiling fan in bedroom'),
        urgency: const Value('normal'),
        photos: const Value('[]'),
        requestStatus: const Value('pending'),
        version: const Value(1),
        createdAt: Value(now),
        updatedAt: Value(now),
      ));

      final requests =
          await db.jobDao.watchPendingRequestsByCompany('co-1').first;
      expect(requests, hasLength(1));
      expect(requests.first.description,
          equals('Install new ceiling fan in bedroom'));
      expect(requests.first.requestStatus, equals('pending'));
    });

    test('insertJob → watchJobsByCompany emits the job', () async {
      final now = DateTime.now();
      final jobId = const Uuid().v4();
      await db.jobDao.insertJob(JobsCompanion(
        id: Value(jobId),
        companyId: const Value('co-1'),
        description: const Value('Full bathroom renovation'),
        tradeType: const Value('Plumbing'),
        status: const Value('quote'),
        statusHistory: Value(jsonEncode([
          {
            'status': 'quote',
            'timestamp': now.toIso8601String(),
            'user_id': 'admin-1',
          }
        ])),
        priority: const Value('medium'),
        tags: const Value('[]'),
        version: const Value(1),
        createdAt: Value(now),
        updatedAt: Value(now),
      ));

      final jobs = await db.jobDao.watchJobsByCompany('co-1').first;
      expect(jobs, hasLength(1));
      expect(jobs.first.description, equals('Full bathroom renovation'));
      expect(jobs.first.status, equals('quote'));
    });

    test('end-to-end: request → job pipeline via Drift', () async {
      final now = DateTime.now();
      final requestId = const Uuid().v4();

      // 1. Insert job request (simulates client submission)
      await db.jobDao.insertJobRequest(JobRequestsCompanion(
        id: Value(requestId),
        companyId: const Value('co-1'),
        clientId: const Value('client-1'),
        description: const Value('Repair roof leak after storm'),
        tradeType: const Value('Roofing'),
        urgency: const Value('urgent'),
        photos: const Value('[]'),
        requestStatus: const Value('pending'),
        version: const Value(1),
        createdAt: Value(now),
        updatedAt: Value(now),
      ));

      // 2. Verify request appears in pending stream
      final pendingRequests =
          await db.jobDao.watchPendingRequestsByCompany('co-1').first;
      expect(pendingRequests, hasLength(1));
      expect(pendingRequests.first.id, equals(requestId));

      // 3. Admin accepts → creates a job (simulates backend response flow)
      final jobId = const Uuid().v4();
      await db.jobDao.insertJob(JobsCompanion(
        id: Value(jobId),
        companyId: const Value('co-1'),
        clientId: const Value('client-1'),
        description: const Value('Repair roof leak after storm'),
        tradeType: const Value('Roofing'),
        status: const Value('quote'),
        statusHistory: Value(jsonEncode([
          {
            'status': 'quote',
            'timestamp': now.toIso8601String(),
            'user_id': 'admin-1',
          }
        ])),
        priority: const Value('high'),
        tags: const Value('[]'),
        version: const Value(1),
        createdAt: Value(now),
        updatedAt: Value(now),
      ));

      // 4. Verify job appears in company job stream
      final jobs = await db.jobDao.watchJobsByCompany('co-1').first;
      expect(jobs, hasLength(1));
      expect(jobs.first.id, equals(jobId));
      expect(
          jobs.first.description, equals('Repair roof leak after storm'));
      expect(jobs.first.tradeType, equals('Roofing'));
      expect(jobs.first.status, equals('quote'));
    });
  });

  // ── 6. Admin Accept dialog flow ──────────────────────────────────────────

  group('Admin Accept dialog flow', () {
    Widget buildAdminReview() {
      return ProviderScope(
        overrides: [
          authNotifierProvider
              .overrideWith(() => _StubAuthNotifier(_adminAuth)),
        ],
        child: const MaterialApp(home: RequestReviewScreen()),
      );
    }

    testWidgets(
        'Accept dialog appears with submitter name and Cancel/Accept buttons',
        (tester) async {
      await seedRequest(
          id: 'req-accept-1',
          description: 'Install new water heater',
          submittedName: 'Alice');

      await tester.pumpWidget(buildAdminReview());
      await tester.pumpAndSettle();

      // Tap Accept on the card
      await tester.tap(find.text('Accept'));
      await tester.pumpAndSettle();

      // Dialog shows submitter name in content
      expect(find.text('Accept Request'), findsOneWidget);
      // Alice appears on the card name AND in the dialog content text
      expect(find.textContaining('Alice'), findsNWidgets(2));
      // Cancel and Accept buttons in dialog
      expect(find.text('Cancel'), findsOneWidget);
      // Two "Accept" texts: one in dialog button, one on the card behind
      expect(find.text('Accept'), findsNWidgets(2));

      // Dismiss dialog
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();

      await tester.pumpWidget(Container());
      await tester.pump(Duration.zero);
    });

    testWidgets('confirming Accept calls DioClient POST with accepted action',
        (tester) async {
      await seedRequest(
          id: 'req-accept-2',
          description: 'Fix broken doorbell',
          submittedName: 'Bob');

      when(() => mockDio.post<dynamic>(
            any(),
            data: any(named: 'data'),
            queryParameters: any(named: 'queryParameters'),
            options: any(named: 'options'),
            cancelToken: any(named: 'cancelToken'),
            onSendProgress: any(named: 'onSendProgress'),
            onReceiveProgress: any(named: 'onReceiveProgress'),
          )).thenAnswer((_) async => dio_pkg.Response(
            data: <String, dynamic>{
              'job': <String, dynamic>{
                'id': 'job-99',
                'description': 'Fix broken doorbell',
                'trade_type': null,
                'client_id': null,
              },
            },
            statusCode: 200,
            requestOptions: dio_pkg.RequestOptions(path: ''),
          ));

      await tester.pumpWidget(buildAdminReview());
      await tester.pumpAndSettle();

      // Tap Accept → confirm in dialog
      await tester.tap(find.text('Accept'));
      await tester.pumpAndSettle();

      // Tap the dialog's Accept button (FilledButton is the second Accept)
      final acceptButtons = find.widgetWithText(FilledButton, 'Accept');
      // In dialog: the dialog's FilledButton
      await tester.tap(acceptButtons.last);
      await tester.pumpAndSettle();

      // Verify the POST was called with correct path and data
      final captured = verify(() => mockDio.post<dynamic>(
            captureAny(),
            data: captureAny(named: 'data'),
            queryParameters: any(named: 'queryParameters'),
            options: any(named: 'options'),
            cancelToken: any(named: 'cancelToken'),
            onSendProgress: any(named: 'onSendProgress'),
            onReceiveProgress: any(named: 'onReceiveProgress'),
          )).captured;

      expect(captured[0], equals('/jobs/requests/req-accept-2/review'));
      expect(captured[1], equals({'action': 'accepted'}));

      await tester.pumpWidget(Container());
      await tester.pump(Duration.zero);
    });

    testWidgets('Accept server error shows red snackbar', (tester) async {
      await seedRequest(
          id: 'req-accept-3',
          description: 'Repair garage door motor',
          submittedName: 'Charlie');

      when(() => mockDio.post<dynamic>(
            any(),
            data: any(named: 'data'),
            queryParameters: any(named: 'queryParameters'),
            options: any(named: 'options'),
            cancelToken: any(named: 'cancelToken'),
            onSendProgress: any(named: 'onSendProgress'),
            onReceiveProgress: any(named: 'onReceiveProgress'),
          )).thenThrow(dio_pkg.DioException(
        requestOptions: dio_pkg.RequestOptions(path: ''),
        response: dio_pkg.Response(
          statusCode: 500,
          requestOptions: dio_pkg.RequestOptions(path: ''),
        ),
        type: dio_pkg.DioExceptionType.badResponse,
      ));

      await tester.pumpWidget(buildAdminReview());
      await tester.pumpAndSettle();

      // Tap Accept → confirm in dialog
      await tester.tap(find.text('Accept'));
      await tester.pumpAndSettle();

      final acceptButtons = find.widgetWithText(FilledButton, 'Accept');
      await tester.tap(acceptButtons.last);
      await tester.pumpAndSettle();

      // Red snackbar with server error message
      expect(find.text('Server error. Please try again.'), findsOneWidget);

      await tester.pumpWidget(Container());
      await tester.pump(Duration.zero);
    });
  });

  // ── 7. Admin Decline dialog flow ─────────────────────────────────────────

  group('Admin Decline dialog flow', () {
    Widget buildAdminReview() {
      return ProviderScope(
        overrides: [
          authNotifierProvider
              .overrideWith(() => _StubAuthNotifier(_adminAuth)),
        ],
        child: const MaterialApp(home: RequestReviewScreen()),
      );
    }

    testWidgets('Decline dialog shows reason dropdown and message field',
        (tester) async {
      await seedRequest(
          id: 'req-decline-1',
          description: 'Resurface the driveway',
          submittedName: 'Diana');

      await tester.pumpWidget(buildAdminReview());
      await tester.pumpAndSettle();

      // Tap Decline on the card
      await tester.tap(find.text('Decline'));
      await tester.pumpAndSettle();

      // Dialog title
      expect(find.text('Decline Request'), findsOneWidget);
      // Reason dropdown with default value
      expect(find.text('Outside service area'), findsOneWidget);
      // Message text field
      expect(find.text('Optional message to client'), findsOneWidget);
      // Cancel and Decline buttons
      expect(find.text('Cancel'), findsOneWidget);
      // Two "Decline" texts: card button + dialog button
      expect(find.text('Decline'), findsNWidgets(2));

      // Dismiss
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();

      await tester.pumpWidget(Container());
      await tester.pump(Duration.zero);
    });

    testWidgets(
        'confirming Decline calls DioClient POST with reason and message',
        (tester) async {
      await seedRequest(
          id: 'req-decline-2',
          description: 'Build a new deck',
          submittedName: 'Eve');

      when(() => mockDio.post<dynamic>(
            any(),
            data: any(named: 'data'),
            queryParameters: any(named: 'queryParameters'),
            options: any(named: 'options'),
            cancelToken: any(named: 'cancelToken'),
            onSendProgress: any(named: 'onSendProgress'),
            onReceiveProgress: any(named: 'onReceiveProgress'),
          )).thenAnswer((_) async => dio_pkg.Response(
            data: <String, dynamic>{'status': 'declined'},
            statusCode: 200,
            requestOptions: dio_pkg.RequestOptions(path: ''),
          ));

      await tester.pumpWidget(buildAdminReview());
      await tester.pumpAndSettle();

      // Tap Decline on the card
      await tester.tap(find.text('Decline'));
      await tester.pumpAndSettle();

      // Select "Fully booked" from dropdown
      await tester.tap(find.text('Outside service area'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Fully booked').last);
      await tester.pumpAndSettle();

      // Enter message
      await tester.enterText(
        find.widgetWithText(TextField, 'Optional message to client'),
        'We are at full capacity until next month.',
      );

      // Confirm decline — tap the dialog's Decline FilledButton
      final declineButtons = find.widgetWithText(FilledButton, 'Decline');
      await tester.tap(declineButtons.last);
      await tester.pumpAndSettle();

      // Verify POST called with correct data
      final captured = verify(() => mockDio.post<dynamic>(
            captureAny(),
            data: captureAny(named: 'data'),
            queryParameters: any(named: 'queryParameters'),
            options: any(named: 'options'),
            cancelToken: any(named: 'cancelToken'),
            onSendProgress: any(named: 'onSendProgress'),
            onReceiveProgress: any(named: 'onReceiveProgress'),
          )).captured;

      expect(captured[0], equals('/jobs/requests/req-decline-2/review'));
      expect(
          captured[1],
          equals({
            'action': 'declined',
            'decline_reason': 'Fully booked',
            'decline_message': 'We are at full capacity until next month.',
          }));

      await tester.pumpWidget(Container());
      await tester.pump(Duration.zero);
    });
  });

  // ── 8. Request card detail rendering ─────────────────────────────────────

  group('Request card detail rendering', () {
    Widget buildAdminReview() {
      return ProviderScope(
        overrides: [
          authNotifierProvider
              .overrideWith(() => _StubAuthNotifier(_adminAuth)),
        ],
        child: const MaterialApp(home: RequestReviewScreen()),
      );
    }

    testWidgets('urgent request shows URGENT badge', (tester) async {
      await seedRequest(
        id: 'req-urgent-1',
        description: 'Emergency pipe burst in basement',
        submittedName: 'Frank',
        urgency: 'urgent',
      );

      await tester.pumpWidget(buildAdminReview());
      await tester.pumpAndSettle();

      expect(find.text('URGENT'), findsOneWidget);

      await tester.pumpWidget(Container());
      await tester.pump(Duration.zero);
    });

    testWidgets('request with trade type and budget shows info chips',
        (tester) async {
      await seedRequest(
        id: 'req-chips-1',
        description: 'Complete kitchen renovation and plumbing',
        submittedName: 'Grace',
        tradeType: 'Plumbing',
        budgetMin: 500,
        budgetMax: 2000,
      );

      await tester.pumpWidget(buildAdminReview());
      await tester.pumpAndSettle();

      // Trade type chip
      expect(find.byIcon(Icons.build_outlined), findsOneWidget);
      expect(find.text('Plumbing'), findsOneWidget);
      // Budget chip
      expect(find.byIcon(Icons.attach_money), findsOneWidget);
      expect(find.text('\$500 – \$2000'), findsOneWidget);

      await tester.pumpWidget(Container());
      await tester.pump(Duration.zero);
    });

    testWidgets('multiple requests sorted oldest first', (tester) async {
      final older = DateTime(2024, 1, 1, 10, 0);
      final newer = DateTime(2024, 6, 15, 14, 30);

      await seedRequest(
        id: 'req-newer',
        description: 'This is the newer request from June',
        submittedName: 'Newer Person',
        createdAt: newer,
      );
      await seedRequest(
        id: 'req-older',
        description: 'This is the older request from January',
        submittedName: 'Older Person',
        createdAt: older,
      );

      await tester.pumpWidget(buildAdminReview());
      await tester.pumpAndSettle();

      // Both descriptions visible
      expect(find.text('This is the older request from January'),
          findsOneWidget);
      expect(
          find.text('This is the newer request from June'), findsOneWidget);

      // Verify vertical ordering: older should appear before newer.
      // Get the y-positions of the two description texts.
      final olderOffset = tester
          .getTopLeft(find.text('This is the older request from January'));
      final newerOffset = tester
          .getTopLeft(find.text('This is the newer request from June'));

      expect(olderOffset.dy, lessThan(newerOffset.dy),
          reason: 'Oldest request should be rendered above newer one');

      await tester.pumpWidget(Container());
      await tester.pump(Duration.zero);
    });
  });
}
