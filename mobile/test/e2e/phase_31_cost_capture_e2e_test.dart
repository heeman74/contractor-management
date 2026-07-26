// Phase 31 Plan 05 E2E: Mobile Cost Capture UI
//
// Covers COST-01/02/03 + D-06 on the field surface:
// 1. Offline create — a cost entry + local receipt are persisted to Drift and
//    enqueued to sync_queue while offline (no Dio calls).
// 2. Reconnect drain — SyncEngine.drainQueue() pushes the queued cost entry
//    to POST /cost-entries, then SyncEngine.pullDelta() drives
//    CostReceiptUploadService.uploadPending() which POSTs to
//    /cost-entries/{id}/receipts and transitions the receipt to 'uploaded'.
// 3. Gating — the Costs section is absent when the finance permission
//    provider reports no finance.view, and present (with the real
//    CostListSection empty state) when it does.
//
// Strategy: real Drift in-memory DB (never mock what a real DB can cover),
// MockDioClient/MockDio for the HTTP layer, mocktail for verification.
library;

import 'dart:io';

import 'package:contractorhub/core/database/app_database.dart' hide UserRole;
import 'package:contractorhub/core/network/dio_client.dart';
import 'package:contractorhub/core/sync/connectivity_service.dart';
import 'package:contractorhub/core/sync/handlers/cost_entry_sync_handler.dart';
import 'package:contractorhub/core/sync/sync_engine.dart';
import 'package:contractorhub/core/sync/sync_registry.dart';
import 'package:contractorhub/features/finance/presentation/providers/cost_providers.dart';
import 'package:contractorhub/features/finance/presentation/widgets/cost_list_section.dart';
import 'package:contractorhub/features/finance/services/cost_receipt_upload_service.dart';
import 'package:dio/dio.dart';
import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

// ---------------------------------------------------------------------------
// Mocks
// ---------------------------------------------------------------------------

class MockDioClient extends Mock implements DioClient {}

class MockDio extends Mock implements Dio {}

class MockConnectivityService extends Mock implements ConnectivityService {}

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

AppDatabase _openTestDb() => AppDatabase(NativeDatabase.memory());

Future<void> _seedCompany(AppDatabase db, String id) async {
  await db.companyDao.insertCompany(CompaniesCompanion.insert(
    id: Value(id),
    name: 'Company $id',
    version: const Value(1),
    createdAt: DateTime.now(),
    updatedAt: DateTime.now(),
  ));
}

void main() {
  setUpAll(() {
    registerFallbackValue(<String, dynamic>{});
    registerFallbackValue(Options());
    registerFallbackValue(FormData());
  });

  // =========================================================================
  // Test 1: Offline create — entry + receipt persisted, queued, no Dio calls
  // =========================================================================
  group('Offline create: cost entry + receipt persist while offline', () {
    late AppDatabase db;
    late MockDioClient mockDioClient;
    late MockDio mockDio;
    late File tempReceiptFile;

    setUp(() async {
      db = _openTestDb();
      mockDioClient = MockDioClient();
      mockDio = MockDio();
      when(() => mockDioClient.instance).thenReturn(mockDio);

      await _seedCompany(db, 'co-1');

      tempReceiptFile =
          File('${Directory.systemTemp.path}/phase31_receipt_test.jpg');
      await tempReceiptFile.writeAsBytes([0x00, 0x01, 0x02]);
    });

    tearDown(() async {
      await db.close();
      if (tempReceiptFile.existsSync()) {
        await tempReceiptFile.delete();
      }
    });

    test(
        'insertCostEntry + insertReceipt persist locally, enqueue sync_queue, '
        'and never call Dio', () async {
      final entryId = await db.costEntryDao.insertCostEntry(
        companyId: 'co-1',
        jobId: 'job-1',
        categoryId: 'cat-materials',
        amount: 125.50,
        incurredDate: '2026-07-25',
        vendor: 'ACME Supply',
        note: 'Lumber for framing',
      );

      final receiptId = await db.costReceiptDao.insertReceipt(
        companyId: 'co-1',
        costEntryId: entryId,
        localPath: tempReceiptFile.path,
      );

      // Persisted locally — offline-first.
      final entries = await db.costEntryDao.watchByJob('job-1').first;
      expect(entries, hasLength(1));
      expect(entries.first.id, entryId);
      expect(entries.first.amount, 125.50);

      final receipts = await db.costReceiptDao.watchByCostEntry(entryId).first;
      expect(receipts, hasLength(1));
      expect(receipts.first.id, receiptId);
      expect(receipts.first.uploadStatus, 'pending_upload');

      // Enqueued to the outbox — entityType 'cost_entry', CREATE, pending.
      final queueItems = await db.syncQueueDao.getAllItems();
      final entryQueueItems = queueItems
          .where((item) =>
              item.entityType == 'cost_entry' && item.entityId == entryId)
          .toList();
      expect(entryQueueItems, hasLength(1));
      expect(entryQueueItems.first.operation, 'CREATE');
      expect(entryQueueItems.first.status, 'pending');

      // Fully offline: no Dio calls of any kind were made.
      verifyNever(() => mockDioClient.pushWithIdempotency(any(), any(), any()));
      verifyNever(() => mockDio.post<Map<String, dynamic>>(
            any(),
            data: any(named: 'data'),
            options: any(named: 'options'),
          ));
    });
  });

  // =========================================================================
  // Test 2: Reconnect drain — drainQueue pushes cost-entries, pullDelta
  // drains the receipt upload; receipt transitions to 'uploaded'.
  // =========================================================================
  group('Reconnect drain: cost-entry push + receipt upload on reconnect', () {
    late AppDatabase db;
    late MockDioClient mockDioClient;
    late MockDio mockDio;
    late MockConnectivityService mockConnectivity;
    late SyncEngine engine;
    late CostReceiptUploadService costReceiptUploadService;
    late File tempReceiptFile;

    setUp(() async {
      db = _openTestDb();
      mockDioClient = MockDioClient();
      mockDio = MockDio();
      mockConnectivity = MockConnectivityService();
      when(() => mockDioClient.instance).thenReturn(mockDio);

      final registry = SyncRegistry();
      registry.register(CostEntrySyncHandler(mockDioClient, db));

      engine = SyncEngine(db, mockDioClient, registry, mockConnectivity);

      costReceiptUploadService = CostReceiptUploadService(
        dioClient: mockDioClient,
        costReceiptDao: db.costReceiptDao,
      );
      engine.setCostReceiptUploadService(costReceiptUploadService);

      await _seedCompany(db, 'co-1');

      tempReceiptFile =
          File('${Directory.systemTemp.path}/phase31_receipt_drain_test.jpg');
      await tempReceiptFile.writeAsBytes([0x00, 0x01, 0x02]);
    });

    tearDown(() async {
      engine.dispose();
      costReceiptUploadService.dispose();
      await db.close();
      if (tempReceiptFile.existsSync()) {
        await tempReceiptFile.delete();
      }
    });

    test(
        'drainQueue POSTs /cost-entries then pullDelta POSTs '
        '/cost-entries/{id}/receipts and marks the receipt uploaded',
        () async {
      final entryId = await db.costEntryDao.insertCostEntry(
        companyId: 'co-1',
        tradeScopeId: 'scope-1',
        categoryId: 'cat-subcontractor',
        amount: 480.0,
        incurredDate: '2026-07-25',
        vendor: 'Bob the Sub',
      );
      final receiptId = await db.costReceiptDao.insertReceipt(
        companyId: 'co-1',
        costEntryId: entryId,
        localPath: tempReceiptFile.path,
      );

      // Stub the cost-entry CREATE push.
      String? capturedPushPath;
      Map<String, dynamic>? capturedPushPayload;
      when(() => mockDioClient.pushWithIdempotency(any(), any(), any()))
          .thenAnswer((invocation) async {
        capturedPushPath = invocation.positionalArguments[0] as String;
        capturedPushPayload =
            invocation.positionalArguments[1] as Map<String, dynamic>;
        return Response<dynamic>(
          statusCode: 201,
          requestOptions: RequestOptions(path: capturedPushPath!),
          data: {'id': entryId},
        );
      });

      // Stub GET /sync so pullDelta() runs without pulling cost data —
      // cost_entry is deliberately NOT in pullDelta's entity list (Pitfall 2).
      when(() => mockDio.get<Map<String, dynamic>>(
            '/sync',
            queryParameters: any(named: 'queryParameters'),
          )).thenAnswer((_) async => Response(
            requestOptions: RequestOptions(path: '/sync'),
            statusCode: 200,
            data: {'server_timestamp': '2026-07-25T12:00:00Z'},
          ));

      // Stub the receipt binary upload.
      String? capturedUploadPath;
      when(() => mockDio.post<Map<String, dynamic>>(
            any(),
            data: any(named: 'data'),
            options: any(named: 'options'),
          )).thenAnswer((invocation) async {
        capturedUploadPath = invocation.positionalArguments[0] as String;
        return Response<Map<String, dynamic>>(
          requestOptions: RequestOptions(path: capturedUploadPath!),
          statusCode: 201,
          data: {'remote_url': '/files/cost-receipts/$entryId/receipt.jpg'},
        );
      });

      // 1) Reconnect: drain the outbox — pushes the cost entry.
      await engine.drainQueue();

      expect(capturedPushPath, '/cost-entries/');
      expect(capturedPushPayload?['job_id'], isNull);
      expect(capturedPushPayload?['trade_scope_id'], 'scope-1');
      expect(capturedPushPayload?['category_id'], 'cat-subcontractor');
      expect(capturedPushPayload?['amount'], 480.0);

      // markSynced deletes the outbox row (the entity table is the source
      // of truth for already-synced items) — the queue should be empty.
      final queueItemsAfterDrain = await db.syncQueueDao.getAllItems();
      expect(
        queueItemsAfterDrain.where((item) => item.entityId == entryId),
        isEmpty,
      );

      // 2) pullDelta() — drives the text-first-then-binary receipt upload.
      await engine.pullDelta();

      expect(capturedUploadPath, '/cost-entries/$entryId/receipts');

      final receipts = await db.costReceiptDao.watchByCostEntry(entryId).first;
      expect(receipts, hasLength(1));
      expect(receipts.first.id, receiptId);
      expect(receipts.first.uploadStatus, 'uploaded');
      expect(
        receipts.first.remoteUrl,
        '/files/cost-receipts/$entryId/receipt.jpg',
      );
    });
  });

  // =========================================================================
  // Test 3: Gating — Costs section absent without finance.view, present with it.
  // =========================================================================
  group('Gating: Costs section respects finance.view', () {
    testWidgets('Costs section is absent when finance.view is not granted',
        (tester) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            myPermissionsProvider.overrideWith((ref) async => <String>{}),
          ],
          child: const MaterialApp(home: _CostsGateHost(jobId: 'job-1')),
        ),
      );
      await tester.pump();
      await tester.pump();

      expect(find.text('Costs'), findsNothing);
      expect(find.byType(CostListSection), findsNothing);
    });

    testWidgets('Costs section is present when finance.view is granted',
        (tester) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            myPermissionsProvider
                .overrideWith((ref) async => <String>{'finance.view'}),
          ],
          child: const MaterialApp(home: _CostsGateHost(jobId: 'job-1')),
        ),
      );
      await tester.pump();
      await tester.pump();

      expect(find.text('Costs'), findsOneWidget);
      expect(find.byType(CostListSection), findsOneWidget);
      expect(find.text('No costs recorded yet.'), findsOneWidget);
    });
  });
}

/// Mirrors the gating pattern used by job/trade-scope/project detail
/// screens: `if (financePermission.canView) CostListSection(...)`.
class _CostsGateHost extends ConsumerWidget {
  const _CostsGateHost({required this.jobId});

  final String jobId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final canView = ref.watch(financePermissionProvider).canView;

    return Scaffold(
      body: canView
          ? CostListSection(entries: const [], jobId: jobId)
          : const SizedBox.shrink(),
    );
  }
}
