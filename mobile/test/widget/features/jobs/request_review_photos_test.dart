/// Widget tests for photo thumbnails in the admin request review screen.
///
/// Verifies Phase 4 item 2 — photo rendering in RequestReviewScreen:
/// - Request with photos: horizontal ListView renders Container widgets
///   with BoxDecoration.image set to DecorationImage(image: NetworkImage(url))
/// - Request without photos: no photo ListView rendered
/// - Max 5 cap: request with 7 photos only renders 5 photo containers
/// - Photo container dimensions: 60x60
/// - Fallback icon: Icons.image_outlined present as child
///
/// NetworkImage will fail in test (no HTTP), but the DecorationImage's
/// onError: (_, __) {} swallows it. We verify widget tree structure.
///
/// Drift stream disposal schedules a zero-duration timer; each test ends
/// with `pumpWidget(Container()) + pump(Duration.zero)` to clear it.
library;

// Hide Drift-generated UserRole data class (conflicts with shared enum).
import 'package:contractorhub/core/database/app_database.dart' hide UserRole;
import 'package:contractorhub/core/di/service_locator.dart';
import 'package:contractorhub/core/network/dio_client.dart';
import 'package:contractorhub/features/auth/domain/auth_state.dart';
import 'package:contractorhub/features/auth/presentation/providers/auth_provider.dart';
import 'package:contractorhub/features/jobs/presentation/screens/request_review_screen.dart';
import 'package:contractorhub/shared/models/user_role.dart';
import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

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

class MockDioClient extends Mock implements DioClient {}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

void main() {
  late AppDatabase db;

  const adminState = AuthState.authenticated(
    userId: 'admin-1',
    companyId: 'co-1',
    roles: {UserRole.admin},
  );

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

    // Register mocks in GetIt
    if (getIt.isRegistered<JobDao>()) getIt.unregister<JobDao>();
    getIt.registerSingleton<JobDao>(db.jobDao);

    if (getIt.isRegistered<DioClient>()) getIt.unregister<DioClient>();
    getIt.registerSingleton<DioClient>(MockDioClient());
  });

  tearDown(() async {
    if (getIt.isRegistered<JobDao>()) getIt.unregister<JobDao>();
    if (getIt.isRegistered<DioClient>()) getIt.unregister<DioClient>();
    await db.close();
  });

  /// Build the screen wrapped with required providers.
  Widget buildWidget() {
    return ProviderScope(
      overrides: [
        authNotifierProvider
            .overrideWith(() => _StubAuthNotifier(adminState)),
      ],
      child: const MaterialApp(home: RequestReviewScreen()),
    );
  }

  /// Insert a pending job request into the in-memory DB.
  Future<void> seedRequest({
    required String id,
    required String description,
    List<String> photos = const [],
    String? submittedName,
  }) async {
    final now = DateTime.now();
    final photosJson = '[${photos.map((p) => '"$p"').join(',')}]';
    await db.into(db.jobRequests).insert(JobRequestsCompanion.insert(
          id: Value(id),
          companyId: 'co-1',
          description: description,
          photos: Value(photosJson),
          createdAt: now,
          updatedAt: now,
          submittedName: Value(submittedName),
        ));
  }

  group('RequestReviewScreen — photo thumbnails', () {
    testWidgets('request with photos renders containers with DecorationImage',
        (tester) async {
      final photoUrls = [
        'https://example.com/photo1.jpg',
        'https://example.com/photo2.jpg',
      ];
      await seedRequest(
        id: 'req-1',
        description: 'Fix leaking faucet in kitchen',
        photos: photoUrls,
        submittedName: 'Alice',
      );

      await tester.pumpWidget(buildWidget());
      await tester.pumpAndSettle();

      // Find containers with NetworkImage decorations
      final containers =
          tester.widgetList<Container>(find.byType(Container));
      final photoContainers = containers.where((c) {
        final decoration = c.decoration;
        if (decoration is BoxDecoration && decoration.image != null) {
          return decoration.image!.image is NetworkImage;
        }
        return false;
      }).toList();

      expect(photoContainers, hasLength(2));

      // Verify first container uses the correct URL
      final firstDeco =
          (photoContainers.first.decoration as BoxDecoration).image!;
      expect((firstDeco.image as NetworkImage).url, equals(photoUrls[0]));

      // Clean up Drift timer
      await tester.pumpWidget(Container());
      await tester.pump(Duration.zero);
    });

    testWidgets('request without photos does not render photo containers',
        (tester) async {
      await seedRequest(
        id: 'req-2',
        description: 'Paint the living room walls',
        photos: [],
        submittedName: 'Bob',
      );

      await tester.pumpWidget(buildWidget());
      await tester.pumpAndSettle();

      // No containers with NetworkImage decoration
      final containers =
          tester.widgetList<Container>(find.byType(Container));
      final photoContainers = containers.where((c) {
        final decoration = c.decoration;
        return decoration is BoxDecoration && decoration.image != null;
      }).toList();

      expect(photoContainers, isEmpty);

      await tester.pumpWidget(Container());
      await tester.pump(Duration.zero);
    });

    testWidgets('max 5 photos rendered when request has 7', (tester) async {
      final photoUrls =
          List.generate(7, (i) => 'https://example.com/photo$i.jpg');
      await seedRequest(
        id: 'req-3',
        description: 'Full bathroom renovation project',
        photos: photoUrls,
        submittedName: 'Charlie',
      );

      await tester.pumpWidget(buildWidget());
      await tester.pumpAndSettle();

      final containers =
          tester.widgetList<Container>(find.byType(Container));
      final photoContainers = containers.where((c) {
        final decoration = c.decoration;
        return decoration is BoxDecoration &&
            decoration.image != null &&
            decoration.image!.image is NetworkImage;
      }).toList();

      expect(photoContainers, hasLength(5));

      await tester.pumpWidget(Container());
      await tester.pump(Duration.zero);
    });

    testWidgets('photo containers are 60x60', (tester) async {
      await seedRequest(
        id: 'req-4',
        description: 'Replace kitchen cabinet doors',
        photos: ['https://example.com/photo.jpg'],
        submittedName: 'Diana',
      );

      await tester.pumpWidget(buildWidget());
      await tester.pumpAndSettle();

      final containers =
          tester.widgetList<Container>(find.byType(Container));
      final photoContainer = containers.firstWhere((c) {
        final decoration = c.decoration;
        return decoration is BoxDecoration &&
            decoration.image != null &&
            decoration.image!.image is NetworkImage;
      });

      expect(photoContainer.constraints?.maxWidth, equals(60));
      expect(photoContainer.constraints?.maxHeight, equals(60));

      await tester.pumpWidget(Container());
      await tester.pump(Duration.zero);
    });

    testWidgets('fallback icon Icons.image_outlined is present',
        (tester) async {
      await seedRequest(
        id: 'req-5',
        description: 'Install new light fixtures in hallway',
        photos: ['https://example.com/photo.jpg'],
        submittedName: 'Eve',
      );

      await tester.pumpWidget(buildWidget());
      await tester.pumpAndSettle();

      expect(find.byIcon(Icons.image_outlined), findsOneWidget);

      await tester.pumpWidget(Container());
      await tester.pump(Duration.zero);
    });

    testWidgets(
        'photo container background color matches theme surfaceContainerHighest',
        (tester) async {
      await seedRequest(
        id: 'req-color-1',
        description: 'Check the grey placeholder background color',
        photos: ['https://example.com/photo.jpg'],
        submittedName: 'Fiona',
      );

      await tester.pumpWidget(buildWidget());
      await tester.pumpAndSettle();

      // Find the photo container with NetworkImage decoration
      final containers =
          tester.widgetList<Container>(find.byType(Container));
      final photoContainer = containers.firstWhere((c) {
        final decoration = c.decoration;
        return decoration is BoxDecoration &&
            decoration.image != null &&
            decoration.image!.image is NetworkImage;
      });

      // Grab the theme from any element in the tree
      final context = tester.element(find.byType(RequestReviewScreen));
      final expectedColor =
          Theme.of(context).colorScheme.surfaceContainerHighest;

      final deco = photoContainer.decoration as BoxDecoration;
      expect(deco.color, equals(expectedColor));

      await tester.pumpWidget(Container());
      await tester.pump(Duration.zero);
    });

    testWidgets('empty state shows inbox icon when no requests',
        (tester) async {
      // No requests seeded
      await tester.pumpWidget(buildWidget());
      await tester.pumpAndSettle();

      expect(find.byIcon(Icons.inbox_outlined), findsOneWidget);
      expect(find.text('No pending requests'), findsOneWidget);

      await tester.pumpWidget(Container());
      await tester.pump(Duration.zero);
    });
  });
}
