/// Unit tests for [ContractRepository] — verifies the exact endpoints called,
/// type-safe parsing of the contract + sign-url payloads, and that malformed
/// responses throw [FormatException] (never a silent bad cast).
///
/// Mocks Dio with mocktail following the repo test convention (a local
/// `_MockDio` implementing [Dio]); the repository is constructed with the mock.
library;

import 'package:contractorhub/features/contracts/data/contract_repository.dart';
import 'package:contractorhub/features/contracts/domain/contract.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

class _MockDio extends Mock implements Dio {}

Response<dynamic> _response(Object? data) => Response<dynamic>(
      data: data,
      requestOptions: RequestOptions(path: '/x'),
    );

DioException _dioError(int? statusCode) {
  final options = RequestOptions(path: '/x');
  return DioException(
    requestOptions: options,
    response: statusCode == null
        ? null
        : Response<dynamic>(requestOptions: options, statusCode: statusCode),
  );
}

void main() {
  late _MockDio dio;
  late ContractRepository repository;

  setUp(() {
    dio = _MockDio();
    repository = ContractRepository(dio: dio);
  });

  group('getContract', () {
    test('calls GET /contracts/{id} and parses status + dates', () async {
      when(() => dio.get<dynamic>(any())).thenAnswer(
        (_) async => _response({
          'id': 'contract-1',
          'company_id': 'company-1',
          'quote_id': 'quote-1',
          'job_id': 'job-1',
          'client_user_id': 'client-1',
          'status': 'signed',
          'signed_pdf_url': '/files/contracts/company-1/contract-1/signed.pdf',
          'signer_name': 'Jane Client',
          'signer_email': 'jane@example.com',
          'sent_at': '2026-07-20T10:00:00Z',
          'signed_at': '2026-07-21T12:30:00Z',
          'created_at': '2026-07-19T09:00:00Z',
          'updated_at': '2026-07-21T12:30:00Z',
        }),
      );

      final contract = await repository.getContract('contract-1');

      final path = verify(() => dio.get<dynamic>(captureAny())).captured.single;
      expect(path, '/contracts/contract-1');
      expect(contract.id, 'contract-1');
      expect(contract.status, ContractStatus.signed);
      expect(contract.status.isSigned, isTrue);
      expect(contract.quoteId, 'quote-1');
      expect(contract.jobId, 'job-1');
      expect(contract.signerEmail, 'jane@example.com');
      expect(contract.sentAt, DateTime.parse('2026-07-20T10:00:00Z'));
      expect(contract.signedAt, DateTime.parse('2026-07-21T12:30:00Z'));
    });

    test('maps unknown status string to ContractStatus.unknown', () async {
      when(() => dio.get<dynamic>(any())).thenAnswer(
        (_) async => _response({'id': 'c-2', 'status': 'archived'}),
      );

      final contract = await repository.getContract('c-2');
      expect(contract.status, ContractStatus.unknown);
    });

    test('sent/viewed statuses are signable', () async {
      when(() => dio.get<dynamic>(any())).thenAnswer(
        (_) async => _response({'id': 'c-3', 'status': 'sent'}),
      );

      final contract = await repository.getContract('c-3');
      expect(contract.status, ContractStatus.sent);
      expect(contract.status.isSignable, isTrue);
    });

    test('throws FormatException when payload is not a map', () async {
      when(() => dio.get<dynamic>(any()))
          .thenAnswer((_) async => _response('not-json'));

      expect(
        () => repository.getContract('c-4'),
        throwsA(isA<FormatException>()),
      );
    });

    test('throws FormatException when id is missing', () async {
      when(() => dio.get<dynamic>(any())).thenAnswer(
        (_) async => _response({'status': 'sent'}),
      );

      expect(
        () => repository.getContract('c-5'),
        throwsA(isA<FormatException>()),
      );
    });

    test('throws FormatException when status is a non-string', () async {
      when(() => dio.get<dynamic>(any())).thenAnswer(
        (_) async => _response({'id': 'c-6', 'status': 42}),
      );

      expect(
        () => repository.getContract('c-6'),
        throwsA(isA<FormatException>()),
      );
    });

    test('maps DioException to a ContractException with a friendly message',
        () async {
      when(() => dio.get<dynamic>(any())).thenThrow(_dioError(404));

      await expectLater(
        repository.getContract('missing'),
        throwsA(
          isA<ContractException>().having(
            (e) => e.message,
            'message',
            contains('could not be found'),
          ),
        ),
      );
    });
  });

  group('getSignUrl', () {
    test('calls GET /contracts/{id}/sign-url and returns sign_url', () async {
      when(() => dio.get<dynamic>(any())).thenAnswer(
        (_) async => _response({'sign_url': 'https://sign.example/embed/abc'}),
      );

      final url = await repository.getSignUrl('contract-1');

      final path = verify(() => dio.get<dynamic>(captureAny())).captured.single;
      expect(path, '/contracts/contract-1/sign-url');
      expect(url, 'https://sign.example/embed/abc');
    });

    test('throws FormatException when sign_url is missing', () async {
      when(() => dio.get<dynamic>(any()))
          .thenAnswer((_) async => _response({'other': 'value'}));

      expect(
        () => repository.getSignUrl('contract-1'),
        throwsA(isA<FormatException>()),
      );
    });

    test('throws FormatException when sign_url is not a string', () async {
      when(() => dio.get<dynamic>(any()))
          .thenAnswer((_) async => _response({'sign_url': 123}));

      expect(
        () => repository.getSignUrl('contract-1'),
        throwsA(isA<FormatException>()),
      );
    });

    test('throws FormatException when response is not a map', () async {
      when(() => dio.get<dynamic>(any()))
          .thenAnswer((_) async => _response('nope'));

      expect(
        () => repository.getSignUrl('contract-1'),
        throwsA(isA<FormatException>()),
      );
    });

    test('maps 403 DioException to a permission ContractException', () async {
      when(() => dio.get<dynamic>(any())).thenThrow(_dioError(403));

      await expectLater(
        repository.getSignUrl('contract-1'),
        throwsA(
          isA<ContractException>().having(
            (e) => e.message,
            'message',
            contains('permission'),
          ),
        ),
      );
    });
  });

  group('signedPdfUrl', () {
    test('resolves a relative /files path to an absolute URL', () {
      const contract = Contract(
        id: 'c-1',
        status: ContractStatus.signed,
        signedPdfUrl: '/files/contracts/company-1/c-1/signed.pdf',
      );

      final url = repository.signedPdfUrl(contract);
      expect(url, isNotNull);
      expect(url, endsWith('/files/contracts/company-1/c-1/signed.pdf'));
      expect(url, startsWith('http'));
    });

    test('returns null when no signed PDF url is present', () {
      const contract = Contract(id: 'c-1', status: ContractStatus.sent);
      expect(repository.signedPdfUrl(contract), isNull);
    });
  });
}
