import 'package:flutter_test/flutter_test.dart';

import 'package:contractorhub/core/auth/token_storage.dart';

void main() {
  group('TokenStorage.decodeJwtPayload', () {
    test('decodes a valid JWT payload', () {
      // JWT with payload: {"sub": "user-123", "company_id": "comp-456", "roles": ["admin"]}
      // Header: {"alg": "HS256", "typ": "JWT"}
      // base64url encoded
      const token =
          'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9'
          '.eyJzdWIiOiJ1c2VyLTEyMyIsImNvbXBhbnlfaWQiOiJjb21wLTQ1NiIsInJvbGVzIjpbImFkbWluIl19'
          '.signature';

      final payload = TokenStorage.decodeJwtPayload(token);

      expect(payload, isNotNull);
      expect(payload!['sub'], 'user-123');
      expect(payload['company_id'], 'comp-456');
      expect(payload['roles'], ['admin']);
    });

    test('returns null for invalid token format', () {
      expect(TokenStorage.decodeJwtPayload('not-a-jwt'), isNull);
      expect(TokenStorage.decodeJwtPayload(''), isNull);
      expect(TokenStorage.decodeJwtPayload('a.b'), isNull);
    });

    test('returns null for invalid base64 in payload', () {
      expect(TokenStorage.decodeJwtPayload('valid.!!!invalid!!!.sig'), isNull);
    });
  });
}
