import 'package:contractorhub/core/network/api_error_message.dart';
import 'package:contractorhub/features/quotes/data/quote_client_repository.dart';
import 'package:contractorhub/features/quotes/domain/quote_client.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

class MockDio extends Mock implements Dio {}

/// The quote send transition refuses a quote with no client. Without this
/// repository a quote raised on mobile against a job with no client could not
/// be sent at all — the app could report the refusal but never resolve it.
void main() {
  late MockDio dio;
  late QuoteClientRepository repository;

  Response<dynamic> ok(dynamic data) => Response<dynamic>(
        data: data,
        statusCode: 200,
        requestOptions: RequestOptions(path: '/crm/clients'),
      );

  DioException refusal(String detail, {int status = 409}) => DioException(
        requestOptions: RequestOptions(path: '/crm/clients'),
        response: Response<dynamic>(
          data: {'detail': detail},
          statusCode: status,
          requestOptions: RequestOptions(path: '/crm/clients'),
        ),
      );

  setUp(() {
    dio = MockDio();
    repository = QuoteClientRepository(dio: dio);
  });

  group('listClients', () {
    test('parses the roster', () async {
      when(() => dio.get<dynamic>(any(), queryParameters: any(named: 'queryParameters')))
          .thenAnswer((_) async => ok([
                {
                  'user_id': 'u-1',
                  'email': 'nora@example.com',
                  'first_name': 'Nora',
                  'last_name': 'Client',
                },
              ]));

      final clients = await repository.listClients();

      expect(clients, hasLength(1));
      expect(clients.single.userId, 'u-1');
      expect(clients.single.displayName, 'Nora Client');
    });

    test('omits the search parameter when it is blank', () async {
      when(() => dio.get<dynamic>(any(), queryParameters: any(named: 'queryParameters')))
          .thenAnswer((_) async => ok(<dynamic>[]));

      await repository.listClients(search: '   ');

      final captured = verify(
        () => dio.get<dynamic>(any(), queryParameters: captureAny(named: 'queryParameters')),
      ).captured.single as Map<String, dynamic>;
      expect(captured.containsKey('search'), isFalse);
    });

    test('reports the backend reason rather than the exception', () async {
      when(() => dio.get<dynamic>(any(), queryParameters: any(named: 'queryParameters')))
          .thenThrow(refusal('Clients are not available.', status: 403));

      expect(
        () => repository.listClients(),
        throwsA(
          isA<QuoteClientException>().having(
            (e) => e.message,
            'message',
            'Clients are not available.',
          ),
        ),
      );
    });
  });

  group('createClient', () {
    test('sends only the fields that were filled in', () async {
      when(() => dio.post<dynamic>(any(), data: any(named: 'data'))).thenAnswer(
        (_) async => ok({'user_id': 'u-new', 'email': 'fresh@example.com'}),
      );

      final created = await repository.createClient(
        email: '  fresh@example.com  ',
        firstName: '  ',
      );

      expect(created.userId, 'u-new');
      // With no name, the email is what the list can show.
      expect(created.displayName, 'fresh@example.com');

      final body = verify(
        () => dio.post<dynamic>(any(), data: captureAny(named: 'data')),
      ).captured.single as Map<String, dynamic>;
      expect(body['email'], 'fresh@example.com', reason: 'email must be trimmed');
      expect(body.containsKey('first_name'), isFalse);
      expect(body.containsKey('last_name'), isFalse);
    });

    test('surfaces an address owned by another account', () async {
      when(() => dio.post<dynamic>(any(), data: any(named: 'data'))).thenThrow(
        refusal('That email address already belongs to another account.'),
      );

      expect(
        () => repository.createClient(email: 'taken@example.com'),
        throwsA(
          isA<QuoteClientException>().having(
            (e) => e.message,
            'message',
            contains('another account'),
          ),
        ),
      );
    });
  });

  group('assignClient', () {
    test('patches the quote with the chosen client', () async {
      when(() => dio.patch<dynamic>(any(), data: any(named: 'data')))
          .thenAnswer((_) async => ok(<String, dynamic>{}));

      await repository.assignClient(quoteId: 'q-1', clientId: 'u-1');

      final path = verify(
        () => dio.patch<dynamic>(captureAny(), data: captureAny(named: 'data')),
      ).captured;
      expect(path.first, '/quotes/q-1');
      expect((path.last as Map<String, dynamic>)['client_id'], 'u-1');
    });

    test('falls back to a generic message when the backend explains nothing',
        () async {
      when(() => dio.patch<dynamic>(any(), data: any(named: 'data'))).thenThrow(
        DioException(requestOptions: RequestOptions(path: '/quotes/q-1')),
      );

      expect(
        () => repository.assignClient(quoteId: 'q-1', clientId: 'u-1'),
        throwsA(
          isA<QuoteClientException>()
              .having((e) => e.message, 'message', kGenericApiErrorMessage),
        ),
      );
    });
  });

  group('QuoteClient', () {
    test('rejects a payload with no user_id', () {
      expect(
        () => QuoteClient.fromJson({'email': 'a@b.co'}),
        throwsA(isA<FormatException>()),
      );
    });

    test('rejects a payload that is not an object', () {
      expect(() => QuoteClient.fromJson('nope'), throwsA(isA<FormatException>()));
    });
  });
}
