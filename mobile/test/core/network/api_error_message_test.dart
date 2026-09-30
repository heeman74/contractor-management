import 'package:contractorhub/core/network/api_error_message.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';

/// The backend refuses some actions deliberately and explains why in `detail`.
/// Those sentences are the only thing that tells a contractor what to do next —
/// "this quote has no client" is actionable, a stringified DioException is not.
void main() {
  Response<dynamic> responseWith(dynamic data) => Response<dynamic>(
        data: data,
        statusCode: 400,
        requestOptions: RequestOptions(path: '/quotes/x/send'),
      );

  DioException dioErrorWith(dynamic data) => DioException(
        requestOptions: RequestOptions(path: '/quotes/x/send'),
        response: responseWith(data),
      );

  group('apiErrorMessage', () {
    test('returns the reason the backend gave', () {
      const reason =
          'This quote has no client. Add a client before sending it, so it reaches someone.';
      expect(apiErrorMessage(dioErrorWith({'detail': reason})), reason);
    });

    test('takes the first message from a validation error list', () {
      final error = dioErrorWith({
        'detail': [
          {
            'loc': ['body', 'email'],
            'msg': 'value is not a valid email address',
          },
        ],
      });
      expect(apiErrorMessage(error), 'value is not a valid email address');
    });

    test('falls back when detail is absent', () {
      expect(apiErrorMessage(dioErrorWith({})), kGenericApiErrorMessage);
    });

    test('falls back when detail is empty', () {
      expect(
        apiErrorMessage(dioErrorWith({'detail': '   '})),
        kGenericApiErrorMessage,
      );
    });

    test('falls back when the body is not a map', () {
      expect(apiErrorMessage(dioErrorWith('plain text')), kGenericApiErrorMessage);
    });

    test('falls back when a validation list carries no usable message', () {
      expect(
        apiErrorMessage(dioErrorWith({'detail': [123, null]})),
        kGenericApiErrorMessage,
      );
    });

    test('falls back when there is no response at all', () {
      final offline = DioException(
        requestOptions: RequestOptions(path: '/quotes/x/send'),
        type: DioExceptionType.connectionError,
      );
      expect(apiErrorMessage(offline), kGenericApiErrorMessage);
    });

    test('falls back for an error that is not a DioException', () {
      expect(apiErrorMessage(StateError('boom')), kGenericApiErrorMessage);
    });

    test('never surfaces the exception text itself', () {
      // The old behaviour interpolated the exception into the snackbar, which
      // showed a stack-trace-shaped string no user could act on.
      final message = apiErrorMessage(dioErrorWith({'detail': 'Quote not found'}));
      expect(message, isNot(contains('DioException')));
      expect(message, 'Quote not found');
    });
  });
}
