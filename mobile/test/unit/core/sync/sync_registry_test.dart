/// Unit tests for SyncRegistry — entity type to handler mapping.
///
/// Tests cover:
/// 1. register/getHandler roundtrip
/// 2. getHandler throws StateError for unregistered type
/// 3. registeredTypes returns all registered type strings
/// 4. duplicate register overwrites previous handler
library;

import 'package:contractorhub/core/database/app_database.dart';
import 'package:contractorhub/core/sync/sync_handler.dart';
import 'package:contractorhub/core/sync/sync_registry.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

class MockSyncHandler extends Mock implements SyncHandler {}

void main() {
  group('SyncRegistry', () {
    late SyncRegistry registry;
    late MockSyncHandler companyHandler;
    late MockSyncHandler userHandler;

    setUp(() {
      registry = SyncRegistry();
      companyHandler = MockSyncHandler();
      userHandler = MockSyncHandler();

      when(() => companyHandler.entityType).thenReturn('company');
      when(() => userHandler.entityType).thenReturn('user');
    });

    test('register/getHandler roundtrip', () {
      registry.register(companyHandler);
      final handler = registry.getHandler('company');
      expect(handler, same(companyHandler));
    });

    test('getHandler throws StateError for unregistered type', () {
      expect(
        () => registry.getHandler('unknown'),
        throwsA(isA<StateError>()),
      );
    });

    test('registeredTypes returns all registered type strings', () {
      registry.register(companyHandler);
      registry.register(userHandler);

      expect(
        registry.registeredTypes,
        containsAll(['company', 'user']),
      );
    });

    test('duplicate register overwrites previous handler', () {
      final handler1 = MockSyncHandler();
      final handler2 = MockSyncHandler();
      when(() => handler1.entityType).thenReturn('company');
      when(() => handler2.entityType).thenReturn('company');

      registry.register(handler1);
      registry.register(handler2);

      expect(registry.getHandler('company'), same(handler2));
    });
  });
}
