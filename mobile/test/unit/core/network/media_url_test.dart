import 'package:contractorhub/core/network/media_url.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('resolveMediaUrl', () {
    test('joins a relative /files path onto the API host', () {
      // Default BASE_URL host is http://10.0.2.2:8000 (no /api/v1).
      expect(
        resolveMediaUrl('/files/attachments/n1/x.png'),
        'http://10.0.2.2:8000/files/attachments/n1/x.png',
      );
    });

    test('joins a relative path without a leading slash', () {
      expect(
        resolveMediaUrl('files/images/co/y.png'),
        'http://10.0.2.2:8000/files/images/co/y.png',
      );
    });

    test('passes absolute http(s) URLs through unchanged', () {
      const absolute = 'https://cdn.example.com/a.png';
      expect(resolveMediaUrl(absolute), absolute);
      expect(resolveMediaUrl('http://host/b.png'), 'http://host/b.png');
    });

    test('returns null/empty inputs unchanged', () {
      expect(resolveMediaUrl(null), isNull);
      expect(resolveMediaUrl(''), '');
    });

    test('mediaHost strips the /api/v1 suffix', () {
      expect(mediaHost(), 'http://10.0.2.2:8000');
    });
  });
}
