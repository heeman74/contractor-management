/// Unit tests for CostReceiptUploadService.
///
/// Tests cover:
/// 1. empty pending list does nothing (no Dio calls)
/// 2. uploadPending sets status to 'uploading' before the upload attempt
/// 3. successful upload posts to /cost-entries/{id}/receipts and calls
///    markUploaded with the remoteUrl from the response
/// 4. a 4xx response marks the receipt failed (incrementRetry) without retry
library;

import 'dart:io';

import 'package:contractorhub/core/database/app_database.dart';
import 'package:contractorhub/core/network/dio_client.dart';
import 'package:contractorhub/features/finance/services/cost_receipt_upload_service.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

// ---------------------------------------------------------------------------
// Mocks
// ---------------------------------------------------------------------------

class MockDioClient extends Mock implements DioClient {}

class MockDio extends Mock implements Dio {}

class MockCostReceiptDao extends Mock implements CostReceiptDao {}

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

CostReceipt makeReceipt({
  required String localPath,
  String id = 'receipt-1',
  String companyId = 'co-1',
  String costEntryId = 'entry-1',
  String? thumbnailPath,
  String? caption,
  String uploadStatus = 'pending_upload',
  String? remoteUrl,
  int retryCount = 0,
}) {
  final now = DateTime.now();
  return CostReceipt(
    id: id,
    companyId: companyId,
    costEntryId: costEntryId,
    localPath: localPath,
    thumbnailPath: thumbnailPath,
    caption: caption,
    uploadStatus: uploadStatus,
    remoteUrl: remoteUrl,
    retryCount: retryCount,
    createdAt: now,
    updatedAt: now,
  );
}

void main() {
  late MockDioClient mockDioClient;
  late MockDio mockDio;
  late MockCostReceiptDao mockCostReceiptDao;
  late CostReceiptUploadService service;
  late File tempFile;

  setUpAll(() {
    registerFallbackValue(FormData());
    registerFallbackValue(Options());
  });

  setUp(() async {
    mockDioClient = MockDioClient();
    mockDio = MockDio();
    mockCostReceiptDao = MockCostReceiptDao();

    when(() => mockDioClient.instance).thenReturn(mockDio);

    final dir = Directory.systemTemp;
    tempFile = File('${dir.path}/test_cost_receipt.jpg');
    await tempFile.writeAsBytes([0x00, 0x01, 0x02]);

    service = CostReceiptUploadService(
      dioClient: mockDioClient,
      costReceiptDao: mockCostReceiptDao,
    );
  });

  tearDown(() async {
    service.dispose();
    if (tempFile.existsSync()) {
      await tempFile.delete();
    }
  });

  test('empty pending list does nothing (no Dio calls)', () async {
    when(() => mockCostReceiptDao.getPendingUploads())
        .thenAnswer((_) async => []);

    await service.uploadPending();

    verifyNever(() => mockDio.post<Map<String, dynamic>>(
          any(),
          data: any(named: 'data'),
          options: any(named: 'options'),
        ));
  });

  test('uploadPending sets status to uploading before upload attempt',
      () async {
    final receipt = makeReceipt(
      id: 'receipt-uploading',
      localPath: tempFile.path,
    );

    when(() => mockCostReceiptDao.getPendingUploads())
        .thenAnswer((_) async => [receipt]);
    when(() => mockCostReceiptDao.setUploadStatus(any(), any()))
        .thenAnswer((_) async {});
    when(() => mockCostReceiptDao.markUploaded(any(), any()))
        .thenAnswer((_) async {});
    when(() => mockDio.post<Map<String, dynamic>>(
          any(),
          data: any(named: 'data'),
          options: any(named: 'options'),
        )).thenAnswer((_) async => Response<Map<String, dynamic>>(
          requestOptions: RequestOptions(path: '/cost-entries/entry-1/receipts'),
          statusCode: 201,
          data: {'remote_url': '/files/cost-receipts/entry-1/abc.jpg'},
        ));

    await service.uploadPending();

    verify(() =>
            mockCostReceiptDao.setUploadStatus('receipt-uploading', 'uploading'))
        .called(1);
  });

  test(
      'successful upload posts to /cost-entries/{id}/receipts and calls markUploaded',
      () async {
    final receipt = makeReceipt(
      id: 'receipt-success',
      costEntryId: 'entry-42',
      localPath: tempFile.path,
    );

    when(() => mockCostReceiptDao.getPendingUploads())
        .thenAnswer((_) async => [receipt]);
    when(() => mockCostReceiptDao.setUploadStatus(any(), any()))
        .thenAnswer((_) async {});
    when(() => mockCostReceiptDao.markUploaded(any(), any()))
        .thenAnswer((_) async {});

    String? capturedPath;
    when(() => mockDio.post<Map<String, dynamic>>(
          any(),
          data: any(named: 'data'),
          options: any(named: 'options'),
        )).thenAnswer((invocation) async {
      capturedPath = invocation.positionalArguments[0] as String;
      return Response<Map<String, dynamic>>(
        requestOptions: RequestOptions(path: capturedPath!),
        statusCode: 201,
        data: {'remote_url': '/files/cost-receipts/entry-42/xyz.jpg'},
      );
    });

    await service.uploadPending();

    expect(capturedPath, '/cost-entries/entry-42/receipts');
    verify(() => mockCostReceiptDao.markUploaded(
        'receipt-success', '/files/cost-receipts/entry-42/xyz.jpg')).called(1);
  });

  test('a 4xx response marks the receipt failed without retry', () async {
    final receipt = makeReceipt(
      id: 'receipt-4xx',
      localPath: tempFile.path,
    );

    when(() => mockCostReceiptDao.getPendingUploads())
        .thenAnswer((_) async => [receipt]);
    when(() => mockCostReceiptDao.setUploadStatus(any(), any()))
        .thenAnswer((_) async {});
    when(() => mockCostReceiptDao.incrementRetry(any()))
        .thenAnswer((_) async {});
    when(() => mockDio.post<Map<String, dynamic>>(
          any(),
          data: any(named: 'data'),
          options: any(named: 'options'),
        )).thenThrow(DioException(
      requestOptions: RequestOptions(path: '/cost-entries/entry-1/receipts'),
      response: Response(
        requestOptions:
            RequestOptions(path: '/cost-entries/entry-1/receipts'),
        statusCode: 422,
      ),
      type: DioExceptionType.badResponse,
    ));

    await service.uploadPending();

    verify(() => mockCostReceiptDao.incrementRetry('receipt-4xx')).called(1);
    // 4xx is a no-retry failure — exactly one POST attempt is made.
    verify(() => mockDio.post<Map<String, dynamic>>(
          any(),
          data: any(named: 'data'),
          options: any(named: 'options'),
        )).called(1);
  });
}
