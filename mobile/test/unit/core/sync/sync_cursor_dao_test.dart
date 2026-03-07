/// Unit tests for SyncCursorDao — delta sync cursor tracking.
///
/// Uses Drift in-memory database (NativeDatabase.memory()) to test actual
/// SQL queries without mocking.
///
/// Tests cover:
/// 1. getCursor returns null initially (first launch)
/// 2. updateCursor roundtrip — write then read
/// 3. updateCursor overwrites previous value
library;

import 'package:contractorhub/core/database/app_database.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

AppDatabase openTestDatabase() {
  return AppDatabase(NativeDatabase.memory());
}

void main() {
  group('SyncCursorDao', () {
    late AppDatabase db;

    setUp(() {
      db = openTestDatabase();
    });

    tearDown(() async {
      await db.close();
    });

    test('getCursor returns null initially', () async {
      final cursor = await db.syncCursorDao.getCursor();
      expect(cursor, isNull);
    });

    test('updateCursor roundtrip — write then read', () async {
      final timestamp = DateTime(2024, 6, 15, 10, 30);
      await db.syncCursorDao.updateCursor(timestamp);

      final cursor = await db.syncCursorDao.getCursor();
      expect(cursor, isNotNull);
      expect(cursor, equals(timestamp));
    });

    test('updateCursor overwrites previous value', () async {
      final first = DateTime(2024, 1, 1);
      final second = DateTime(2024, 6, 15);

      await db.syncCursorDao.updateCursor(first);
      await db.syncCursorDao.updateCursor(second);

      final cursor = await db.syncCursorDao.getCursor();
      expect(cursor, equals(second));
    });
  });
}
