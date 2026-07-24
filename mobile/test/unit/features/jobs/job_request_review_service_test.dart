/// Unit tests for [JobRequestReviewService] — the review API calls + response
/// parsing + error mapping extracted from the request review screen.
///
/// Uses mocktail to verify the exact endpoint/payload sent to Dio and the
/// typed parsing of the accept response, plus the shared error-message mapping.
library;

import 'package:contractorhub/features/jobs/data/job_request_review_service.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

class _MockDio extends Mock implements Dio {}

Response<dynamic> _response(Object? data) => Response<dynamic>(
      data: data,
      requestOptions: RequestOptions(path: '/x'),
    );

void main() {
  late _MockDio dio;
  late JobRequestReviewService service;

  setUp(() {
    dio = _MockDio();
    service = JobRequestReviewService(dio: dio);
  });

  group('accept', () {
    test('posts the accepted action and parses the created job', () async {
      when(() => dio.post<dynamic>(any(), data: any(named: 'data')))
          .thenAnswer((_) async => _response({
                'job': {
                  'id': 'job-1',
                  'description': 'Fix roof',
                  'trade_type': 'roofer',
                  'client_id': 'client-1',
                },
              }));

      final job = await service.accept('req-1');

      final captured = verify(() => dio.post<dynamic>(
            captureAny(),
            data: captureAny(named: 'data'),
          )).captured;
      expect(captured[0], '/jobs/requests/req-1/review');
      expect(captured[1], {'action': 'accepted'});
      expect(job.jobId, 'job-1');
      expect(job.description, 'Fix roof');
      expect(job.tradeType, 'roofer');
      expect(job.clientId, 'client-1');
    });

    test('returns empty job data when response has no job payload', () async {
      when(() => dio.post<dynamic>(any(), data: any(named: 'data')))
          .thenAnswer((_) async => _response({'request': {}}));

      final job = await service.accept('req-1');
      expect(job.jobId, isNull);
      expect(job.description, isNull);
    });

    test('tolerates a non-map response', () async {
      when(() => dio.post<dynamic>(any(), data: any(named: 'data')))
          .thenAnswer((_) async => _response('unexpected'));

      final job = await service.accept('req-1');
      expect(job.jobId, isNull);
    });
  });

  group('decline', () {
    test('posts reason and optional message', () async {
      when(() => dio.post<dynamic>(any(), data: any(named: 'data')))
          .thenAnswer((_) async => _response(null));

      await service.decline('req-2', reason: 'Fully booked', message: 'Sorry');

      final data = verify(() => dio.post<dynamic>(
            '/jobs/requests/req-2/review',
            data: captureAny(named: 'data'),
          )).captured.single as Map<String, dynamic>;
      expect(data['action'], 'declined');
      expect(data['decline_reason'], 'Fully booked');
      expect(data['decline_message'], 'Sorry');
    });

    test('omits the message key when null', () async {
      when(() => dio.post<dynamic>(any(), data: any(named: 'data')))
          .thenAnswer((_) async => _response(null));

      await service.decline('req-2', reason: 'Duplicate request');

      final data = verify(() => dio.post<dynamic>(
            any(),
            data: captureAny(named: 'data'),
          )).captured.single as Map<String, dynamic>;
      expect(data.containsKey('decline_message'), isFalse);
    });
  });

  group('requestInfo', () {
    test('posts the info_requested action', () async {
      when(() => dio.post<dynamic>(any(), data: any(named: 'data')))
          .thenAnswer((_) async => _response(null));

      await service.requestInfo('req-3', message: 'Need photos');

      final data = verify(() => dio.post<dynamic>(
            '/jobs/requests/req-3/review',
            data: captureAny(named: 'data'),
          )).captured.single as Map<String, dynamic>;
      expect(data['action'], 'info_requested');
      expect(data['message'], 'Need photos');
    });
  });

  group('errorMessage', () {
    DioException exceptionWith(int? statusCode) {
      final options = RequestOptions(path: '/x');
      return DioException(
        requestOptions: options,
        response: statusCode == null
            ? null
            : Response(requestOptions: options, statusCode: statusCode),
      );
    }

    test('maps known status codes to specific messages', () {
      expect(JobRequestReviewService.errorMessage(exceptionWith(401)),
          contains('log in'));
      expect(JobRequestReviewService.errorMessage(exceptionWith(403)),
          contains('permission'));
      expect(JobRequestReviewService.errorMessage(exceptionWith(404)),
          contains('already been reviewed'));
      expect(JobRequestReviewService.errorMessage(exceptionWith(422)),
          contains('Invalid'));
      expect(JobRequestReviewService.errorMessage(exceptionWith(503)),
          contains('Server error'));
    });

    test('falls back to a generic message for unknown codes', () {
      expect(JobRequestReviewService.errorMessage(exceptionWith(null)),
          contains('Failed to submit review'));
    });
  });
}
