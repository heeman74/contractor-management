// Authenticated media serving — Flutter E2E widget tests.
//
// Guards the StaticFiles security fix on the mobile side: uploaded images are
// now served from AUTHENTICATED, tenant-scoped backend endpoints (/files and
// /uploads/chat). Every `Image.network` that loads backend media must therefore
//   1) resolve a server-relative URL (e.g. `/files/task-attachments/...`) to the
//      absolute API host — Flutter's Image.network uses its own HttpClient and
//      does NOT prepend Dio's base URL, so a relative URL would never load; and
//   2) carry the `Authorization: Bearer <token>` header, or the backend 401s.
//
// These tests inspect the widget tree's NetworkImage provider (url + headers)
// rather than performing real HTTP — the established pattern in this repo
// (see request_review_photos_test.dart). No network is hit.
//
// Coverage:
//   - resolveMediaUrl: relative -> absolute, absolute passthrough, null/empty
//   - mediaAuthHeaders: Bearer header when a token is cached, empty when logged out
//   - MessageBubble photo bubble: NetworkImage(resolved chat URL, Bearer header)
//   - TaskPhotoViewerScreen: NetworkImage(resolved /files URL, Bearer header)
//   - logged-out state: NetworkImage still resolves URL but sends no auth header

import 'package:contractorhub/core/auth/token_storage.dart';
import 'package:contractorhub/core/database/app_database.dart' hide UserRole;
import 'package:contractorhub/core/network/media_url.dart';
import 'package:contractorhub/features/chat/presentation/widgets/message_bubble.dart';
import 'package:contractorhub/features/projects/presentation/screens/task_photo_viewer_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

// ---------------------------------------------------------------------------
// Constants
// ---------------------------------------------------------------------------

const _token = 'test-access-token-abc123';
const _companyId = 'company-001';

// media_url.dart falls back to BASE_URL=http://10.0.2.2:8000/api/v1 with no
// --dart-define, so the media host (API host minus /api/v1) is:
const _host = 'http://10.0.2.2:8000';

// ---------------------------------------------------------------------------
// Mock secure storage — lets us warm/clear the static cached access token
// ---------------------------------------------------------------------------

class _MockSecureStorage extends Mock implements FlutterSecureStorage {}

TokenStorage _tokenStorageWith(_MockSecureStorage storage) {
  when(() => storage.write(key: any(named: 'key'), value: any(named: 'value')))
      .thenAnswer((_) async {});
  when(() => storage.delete(key: any(named: 'key'))).thenAnswer((_) async {});
  return TokenStorage(storage: storage);
}

Future<void> _login() async {
  await _tokenStorageWith(_MockSecureStorage()).saveTokens(
    accessToken: _token,
    refreshToken: 'refresh',
  );
}

Future<void> _logout() async {
  await _tokenStorageWith(_MockSecureStorage()).clearTokens();
}

// ---------------------------------------------------------------------------
// Data factories
// ---------------------------------------------------------------------------

ChatMessage _photoMessage({required String attachmentUrl}) {
  final now = DateTime.now();
  return ChatMessage(
    id: 'msg-photo',
    companyId: _companyId,
    threadId: 'thread-001',
    senderId: 'user-001',
    senderName: 'Test User',
    seq: 1,
    attachmentUrl: attachmentUrl,
    attachmentType: 'photo',
    mentions: '[]',
    mentionAll: false,
    status: 'sent',
    createdAt: now,
  );
}

TaskAttachment _photoAttachment({required String remoteUrl}) {
  final now = DateTime.now();
  return TaskAttachment(
    id: 'att-001',
    companyId: _companyId,
    taskId: 'task-001',
    attachmentType: 'photo',
    remoteUrl: remoteUrl,
    sortOrder: 0,
    version: 1,
    createdAt: now,
    updatedAt: now,
  );
}

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

/// The single NetworkImage in the pumped tree, or fails the test.
NetworkImage _onlyNetworkImage(WidgetTester tester) {
  final image = tester.widget<Image>(find.byType(Image));
  expect(image.image, isA<NetworkImage>(),
      reason: 'backend media must load via NetworkImage');
  return image.image as NetworkImage;
}

void main() {
  setUp(() async {
    await _login();
  });

  tearDown(() async {
    await _logout();
  });

  group('resolveMediaUrl', () {
    test('prepends the API host to a server-relative /files path', () {
      expect(
        resolveMediaUrl('/files/task-attachments/task-001/p.png'),
        '$_host/files/task-attachments/task-001/p.png',
      );
    });

    test('prepends the API host to a relative /uploads/chat path', () {
      expect(
        resolveMediaUrl('/uploads/chat/msg-1/photo.jpg'),
        '$_host/uploads/chat/msg-1/photo.jpg',
      );
    });

    test('adds a leading slash when the relative path lacks one', () {
      expect(resolveMediaUrl('files/x.png'), '$_host/files/x.png');
    });

    test('passes an absolute URL through unchanged', () {
      const abs = 'https://cdn.example.com/x.png';
      expect(resolveMediaUrl(abs), abs);
    });

    test('returns null/empty inputs unchanged', () {
      expect(resolveMediaUrl(null), isNull);
      expect(resolveMediaUrl(''), '');
    });
  });

  group('mediaAuthHeaders', () {
    test('returns a Bearer header when a token is cached', () async {
      await _login();
      expect(mediaAuthHeaders(), {'Authorization': 'Bearer $_token'});
    });

    test('returns an empty map when logged out', () async {
      await _logout();
      expect(mediaAuthHeaders(), isEmpty);
    });
  });

  group('MessageBubble photo bubble', () {
    testWidgets('resolves the chat URL and attaches the Bearer header',
        (tester) async {
      final message =
          _photoMessage(attachmentUrl: '/uploads/chat/msg-photo/photo.jpg');

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(body: MessageBubble(message: message, isOwn: false)),
        ),
      );
      await tester.pump();

      final network = _onlyNetworkImage(tester);
      expect(network.url, '$_host/uploads/chat/msg-photo/photo.jpg');
      expect(network.headers, {'Authorization': 'Bearer $_token'});
    });

    testWidgets('sends no auth header when logged out', (tester) async {
      await _logout();
      final message =
          _photoMessage(attachmentUrl: '/uploads/chat/msg-photo/photo.jpg');

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(body: MessageBubble(message: message, isOwn: false)),
        ),
      );
      await tester.pump();

      final network = _onlyNetworkImage(tester);
      expect(network.url, '$_host/uploads/chat/msg-photo/photo.jpg');
      expect(network.headers, isEmpty);
    });
  });

  group('TaskPhotoViewerScreen', () {
    testWidgets(
        'resolves the /files task-attachment URL and attaches the Bearer header',
        (tester) async {
      const relativeUrl = '/files/task-attachments/task-001/progress.png';
      final attachment = _photoAttachment(remoteUrl: relativeUrl);

      await tester.pumpWidget(
        MaterialApp(
          home: TaskPhotoViewerScreen(
            taskId: 'task-001',
            attachment: attachment,
            allPhotos: [attachment],
            initialIndex: 0,
          ),
        ),
      );
      await tester.pump();

      final network = _onlyNetworkImage(tester);
      expect(network.url, '$_host$relativeUrl');
      expect(network.headers, {'Authorization': 'Bearer $_token'});
    });
  });
}
