/// Unit tests for AuthRepository — auth orchestration logic.
///
/// Tests cover login, register, refresh, logout, and session restoration
/// using mocktail mocks for DioClient, TokenStorage, and Dio.
///
/// Tests verify:
/// - Token storage on successful auth operations
/// - Error propagation from DioException
/// - Token cleanup on failed refresh
/// - Session restore with expired/valid/malformed tokens
/// - FormatException on malformed responses
/// - whereType<String> filtering on non-string roles
library;

import 'package:contractorhub/core/auth/auth_repository.dart';
import 'package:contractorhub/core/auth/token_storage.dart';
import 'package:contractorhub/core/network/dio_client.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

// ---------------------------------------------------------------------------
// Mocks
// ---------------------------------------------------------------------------

class MockDioClient extends Mock implements DioClient {}

class MockTokenStorage extends Mock implements TokenStorage {}

class MockDio extends Mock implements Dio {}

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

/// A valid JWT token response from the backend.
Map<String, dynamic> validTokenResponse({
  String accessToken = 'eyJhbGciOiJIUzI1NiJ9.eyJzdWIiOiJ1c2VyLTEiLCJjb21wYW55X2lkIjoiY28tMSIsInJvbGVzIjpbImFkbWluIl0sImV4cCI6OTk5OTk5OTk5OX0.test',
  String refreshToken = 'refresh-jwt-token',
  String userId = 'user-1',
  String companyId = 'co-1',
  List<String> roles = const ['admin'],
}) {
  return {
    'access_token': accessToken,
    'refresh_token': refreshToken,
    'user_id': userId,
    'company_id': companyId,
    'roles': roles,
  };
}

/// Build a minimal valid JWT with the given payload fields encoded in segment 1.
/// This is a 3-part JWT: header.payload.signature
String buildTestJwt({
  required String sub,
  required String companyId,
  List<String> roles = const ['admin'],
  int? exp,
}) {
  // Build a base64url-encoded payload
  final payloadJson = '{"sub":"$sub","company_id":"$companyId",'
      '"roles":${roles.map((r) => '"$r"').toList()},'
      '"exp":${exp ?? (DateTime.now().millisecondsSinceEpoch ~/ 1000 + 3600)}}';
  final encoded = Uri.encodeComponent(payloadJson);
  // Real JWT uses base64url but TokenStorage.decodeJwtPayload handles it
  final bytes = payloadJson.codeUnits;
  final base64Payload = _base64UrlEncode(bytes);
  return 'eyJhbGciOiJIUzI1NiJ9.$base64Payload.signature';
}

String _base64UrlEncode(List<int> bytes) {
  final encoded = Uri.dataFromBytes(bytes).toString();
  // Simple base64url encoding
  var base64 = '';
  for (var i = 0; i < bytes.length; i += 3) {
    final remaining = bytes.length - i;
    final b1 = bytes[i];
    final b2 = remaining > 1 ? bytes[i + 1] : 0;
    final b3 = remaining > 2 ? bytes[i + 2] : 0;

    base64 += _b64Char(b1 >> 2);
    base64 += _b64Char(((b1 & 3) << 4) | (b2 >> 4));
    if (remaining > 1) {
      base64 += _b64Char(((b2 & 15) << 2) | (b3 >> 6));
    }
    if (remaining > 2) {
      base64 += _b64Char(b3 & 63);
    }
  }
  return base64;
}

String _b64Char(int index) {
  const chars =
      'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-_';
  return chars[index & 63];
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

void main() {
  late MockDioClient mockDioClient;
  late MockTokenStorage mockTokenStorage;
  late MockDio mockDio;
  late AuthRepository repository;

  setUp(() {
    mockDioClient = MockDioClient();
    mockTokenStorage = MockTokenStorage();
    mockDio = MockDio();

    when(() => mockDioClient.instance).thenReturn(mockDio);
    when(() => mockTokenStorage.saveTokens(
          accessToken: any(named: 'accessToken'),
          refreshToken: any(named: 'refreshToken'),
        )).thenAnswer((_) async {});
    when(() => mockTokenStorage.clearTokens()).thenAnswer((_) async {});

    repository = AuthRepository(mockDioClient, mockTokenStorage);
  });

  group('login', () {
    test('success stores tokens and returns AuthResult', () async {
      final responseData = validTokenResponse();
      when(() => mockDio.post<Map<String, dynamic>>(
            '/auth/login',
            data: any(named: 'data'),
          )).thenAnswer((_) async => Response(
            data: responseData,
            statusCode: 200,
            requestOptions: RequestOptions(path: '/auth/login'),
          ));

      final result = await repository.login(
        email: 'test@test.com',
        password: 'password123',
      );

      expect(result.userId, equals('user-1'));
      expect(result.companyId, equals('co-1'));
      expect(result.roles, equals(['admin']));
      verify(() => mockTokenStorage.saveTokens(
            accessToken: any(named: 'accessToken'),
            refreshToken: any(named: 'refreshToken'),
          )).called(1);
    });

    test('DioException propagates', () async {
      when(() => mockDio.post<Map<String, dynamic>>(
            '/auth/login',
            data: any(named: 'data'),
          )).thenThrow(DioException(
        requestOptions: RequestOptions(path: '/auth/login'),
        type: DioExceptionType.badResponse,
        response: Response(
          statusCode: 401,
          requestOptions: RequestOptions(path: '/auth/login'),
        ),
      ));

      expect(
        () => repository.login(email: 'x@x.com', password: 'wrong'),
        throwsA(isA<DioException>()),
      );
    });
  });

  group('register', () {
    test('success stores tokens and returns AuthResult', () async {
      final responseData = validTokenResponse();
      when(() => mockDio.post<Map<String, dynamic>>(
            '/auth/register',
            data: any(named: 'data'),
          )).thenAnswer((_) async => Response(
            data: responseData,
            statusCode: 201,
            requestOptions: RequestOptions(path: '/auth/register'),
          ));

      final result = await repository.register(
        email: 'new@test.com',
        password: 'password123',
        companyName: 'Test Co',
      );

      expect(result.userId, equals('user-1'));
      expect(result.companyId, equals('co-1'));
      expect(result.roles, equals(['admin']));
    });

    test('passes optional firstName/lastName', () async {
      final responseData = validTokenResponse();
      when(() => mockDio.post<Map<String, dynamic>>(
            '/auth/register',
            data: any(named: 'data'),
          )).thenAnswer((_) async => Response(
            data: responseData,
            statusCode: 201,
            requestOptions: RequestOptions(path: '/auth/register'),
          ));

      await repository.register(
        email: 'new@test.com',
        password: 'password123',
        companyName: 'Test Co',
        firstName: 'Jane',
        lastName: 'Doe',
      );

      final captured = verify(() => mockDio.post<Map<String, dynamic>>(
            '/auth/register',
            data: captureAny(named: 'data'),
          )).captured.single as Map<String, dynamic>;

      expect(captured['first_name'], equals('Jane'));
      expect(captured['last_name'], equals('Doe'));
    });
  });

  group('refreshToken', () {
    test('with no stored token returns null', () async {
      when(() => mockTokenStorage.readRefreshToken())
          .thenAnswer((_) async => null);

      final result = await repository.refreshToken();
      expect(result, isNull);
    });

    test('success saves new tokens', () async {
      when(() => mockTokenStorage.readRefreshToken())
          .thenAnswer((_) async => 'old-refresh-token');

      final responseData = validTokenResponse(
        accessToken: 'new-access',
        refreshToken: 'new-refresh',
      );
      when(() => mockDio.post<Map<String, dynamic>>(
            '/auth/refresh',
            data: any(named: 'data'),
          )).thenAnswer((_) async => Response(
            data: responseData,
            statusCode: 200,
            requestOptions: RequestOptions(path: '/auth/refresh'),
          ));

      final result = await repository.refreshToken();
      expect(result, isNotNull);
      expect(result!.userId, equals('user-1'));
      verify(() => mockTokenStorage.saveTokens(
            accessToken: 'new-access',
            refreshToken: 'new-refresh',
          )).called(1);
    });

    test('on DioException clears tokens and returns null', () async {
      when(() => mockTokenStorage.readRefreshToken())
          .thenAnswer((_) async => 'bad-refresh');

      when(() => mockDio.post<Map<String, dynamic>>(
            '/auth/refresh',
            data: any(named: 'data'),
          )).thenThrow(DioException(
        requestOptions: RequestOptions(path: '/auth/refresh'),
        type: DioExceptionType.badResponse,
        response: Response(
          statusCode: 401,
          requestOptions: RequestOptions(path: '/auth/refresh'),
        ),
      ));

      final result = await repository.refreshToken();
      expect(result, isNull);
      verify(() => mockTokenStorage.clearTokens()).called(1);
    });
  });

  group('logout', () {
    test('sends request and clears tokens', () async {
      when(() => mockTokenStorage.readRefreshToken())
          .thenAnswer((_) async => 'refresh-token');
      when(() => mockTokenStorage.readAccessToken())
          .thenAnswer((_) async => 'access-token');
      when(() => mockDio.post<void>(
            '/auth/logout',
            data: any(named: 'data'),
            options: any(named: 'options'),
          )).thenAnswer((_) async => Response(
            statusCode: 204,
            requestOptions: RequestOptions(path: '/auth/logout'),
          ));

      await repository.logout();

      verify(() => mockTokenStorage.clearTokens()).called(1);
    });

    test('clears tokens even when backend fails', () async {
      when(() => mockTokenStorage.readRefreshToken())
          .thenAnswer((_) async => 'refresh-token');
      when(() => mockTokenStorage.readAccessToken())
          .thenAnswer((_) async => 'access-token');
      when(() => mockDio.post<void>(
            '/auth/logout',
            data: any(named: 'data'),
            options: any(named: 'options'),
          )).thenThrow(DioException(
        requestOptions: RequestOptions(path: '/auth/logout'),
      ));

      await repository.logout();

      verify(() => mockTokenStorage.clearTokens()).called(1);
    });

    test('with no tokens skips network call', () async {
      when(() => mockTokenStorage.readRefreshToken())
          .thenAnswer((_) async => null);
      when(() => mockTokenStorage.readAccessToken())
          .thenAnswer((_) async => null);

      await repository.logout();

      verifyNever(() => mockDio.post<void>(
            any(),
            data: any(named: 'data'),
            options: any(named: 'options'),
          ));
      verify(() => mockTokenStorage.clearTokens()).called(1);
    });
  });

  group('restoreSession', () {
    test('with no stored token returns null', () async {
      when(() => mockTokenStorage.readAccessToken())
          .thenAnswer((_) async => null);

      final result = await repository.restoreSession();
      expect(result, isNull);
    });

    test('with valid token returns AuthResult', () async {
      // Build a JWT that won't be expired
      final jwt = buildTestJwt(
        sub: 'user-1',
        companyId: 'co-1',
        roles: ['admin'],
        exp: (DateTime.now().millisecondsSinceEpoch ~/ 1000) + 3600,
      );
      when(() => mockTokenStorage.readAccessToken())
          .thenAnswer((_) async => jwt);

      final result = await repository.restoreSession();
      expect(result, isNotNull);
      expect(result!.userId, equals('user-1'));
      expect(result.companyId, equals('co-1'));
    });

    test('with expired token calls refresh', () async {
      // Build an expired JWT
      final jwt = buildTestJwt(
        sub: 'user-1',
        companyId: 'co-1',
        exp: (DateTime.now().millisecondsSinceEpoch ~/ 1000) - 3600,
      );
      when(() => mockTokenStorage.readAccessToken())
          .thenAnswer((_) async => jwt);
      when(() => mockTokenStorage.readRefreshToken())
          .thenAnswer((_) async => 'refresh-token');

      final responseData = validTokenResponse();
      when(() => mockDio.post<Map<String, dynamic>>(
            '/auth/refresh',
            data: any(named: 'data'),
          )).thenAnswer((_) async => Response(
            data: responseData,
            statusCode: 200,
            requestOptions: RequestOptions(path: '/auth/refresh'),
          ));

      final result = await repository.restoreSession();
      // Should have called refresh
      verify(() => mockTokenStorage.readRefreshToken()).called(1);
      expect(result, isNotNull);
    });

    test('with malformed token clears and returns null', () async {
      when(() => mockTokenStorage.readAccessToken())
          .thenAnswer((_) async => 'not-a-jwt');

      final result = await repository.restoreSession();
      expect(result, isNull);
      verify(() => mockTokenStorage.clearTokens()).called(1);
    });
  });

  group('_handleTokenResponse', () {
    test('throws FormatException on missing access_token', () async {
      when(() => mockDio.post<Map<String, dynamic>>(
            '/auth/login',
            data: any(named: 'data'),
          )).thenAnswer((_) async => Response(
            data: <String, dynamic>{
              'refresh_token': 'rt',
              'user_id': 'u',
              'company_id': 'c',
              'roles': <String>[],
            },
            statusCode: 200,
            requestOptions: RequestOptions(path: '/auth/login'),
          ));

      expect(
        () => repository.login(email: 'x@x.com', password: 'pass1234'),
        throwsA(isA<FormatException>()),
      );
    });

    test('filters non-string roles via whereType', () async {
      when(() => mockDio.post<Map<String, dynamic>>(
            '/auth/login',
            data: any(named: 'data'),
          )).thenAnswer((_) async => Response(
            data: <String, dynamic>{
              'access_token': 'at',
              'refresh_token': 'rt',
              'user_id': 'u',
              'company_id': 'c',
              'roles': ['admin', 42, null, 'contractor'],
            },
            statusCode: 200,
            requestOptions: RequestOptions(path: '/auth/login'),
          ));

      final result = await repository.login(
        email: 'x@x.com',
        password: 'pass1234',
      );
      expect(result.roles, equals(['admin', 'contractor']));
    });
  });
}
