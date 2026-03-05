/// Unit tests for ConnectivityService — network connectivity detection.
///
/// Tests verify:
/// 1. onConnected callback is triggered when WiFi connectivity detected
///    AND internet access confirmed
/// 2. onConnected NOT triggered when ConnectivityResult.none
/// 3. dispose() cancels the connectivity subscription — no callback after dispose
///
/// Uses mocktail to mock [Connectivity] and [InternetConnection] so tests
/// do not depend on actual network interfaces or platform channels.
///
/// ConnectivityService accepts optional constructor parameters for
/// [Connectivity] and [InternetConnection] injection — tests pass mocks here.
///
/// Requires Flutter SDK + build_runner to run.
library;

import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:contractorhub/core/sync/connectivity_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:internet_connection_checker_plus/internet_connection_checker_plus.dart';
import 'package:mocktail/mocktail.dart';

// ---------------------------------------------------------------------------
// Mocks
// ---------------------------------------------------------------------------

class MockConnectivity extends Mock implements Connectivity {}

class MockInternetConnection extends Mock implements InternetConnection {}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

void main() {
  group('ConnectivityService', () {
    late MockConnectivity mockConnectivity;
    late MockInternetConnection mockInternetChecker;
    late StreamController<List<ConnectivityResult>> connectivityController;

    setUp(() {
      mockConnectivity = MockConnectivity();
      mockInternetChecker = MockInternetConnection();
      connectivityController =
          StreamController<List<ConnectivityResult>>.broadcast();

      when(() => mockConnectivity.onConnectivityChanged)
          .thenAnswer((_) => connectivityController.stream);
    });

    tearDown(() {
      connectivityController.close();
    });

    test(
        '1. Triggers onConnected callback when WiFi connected and internet verified',
        () async {
      var callbackCalled = false;

      when(() => mockInternetChecker.hasInternetAccess)
          .thenAnswer((_) async => true);

      final service = ConnectivityService(
        connectivity: mockConnectivity,
        internetChecker: mockInternetChecker,
      );

      service.startListening(() {
        callbackCalled = true;
      });

      // Emit WiFi connection
      connectivityController.add([ConnectivityResult.wifi]);

      // Allow async processing of the connectivity event
      await Future<void>.delayed(const Duration(milliseconds: 50));

      expect(callbackCalled, isTrue,
          reason:
              'onConnected must be called when WiFi detected AND internet verified');

      service.dispose();
    });

    test('2. Does NOT trigger onConnected when ConnectivityResult.none', () async {
      var callbackCalled = false;

      final service = ConnectivityService(
        connectivity: mockConnectivity,
        internetChecker: mockInternetChecker,
      );

      service.startListening(() {
        callbackCalled = true;
      });

      // Emit no connectivity
      connectivityController.add([ConnectivityResult.none]);

      await Future<void>.delayed(const Duration(milliseconds: 50));

      expect(callbackCalled, isFalse,
          reason:
              'onConnected must NOT be called when ConnectivityResult.none');
      // hasInternetAccess must never be checked when no network interface
      verifyNever(() => mockInternetChecker.hasInternetAccess);

      service.dispose();
    });

    test(
        '3. dispose() cancels subscription — no callback after dispose',
        () async {
      var callbackCount = 0;

      when(() => mockInternetChecker.hasInternetAccess)
          .thenAnswer((_) async => true);

      final service = ConnectivityService(
        connectivity: mockConnectivity,
        internetChecker: mockInternetChecker,
      );

      service.startListening(() {
        callbackCount++;
      });

      // Emit once before dispose — should trigger callback
      connectivityController.add([ConnectivityResult.wifi]);
      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect(callbackCount, equals(1),
          reason: 'Should receive first callback before dispose');

      // Dispose cancels the subscription
      service.dispose();

      // Emit again after dispose — callback must NOT be called again
      connectivityController.add([ConnectivityResult.wifi]);
      await Future<void>.delayed(const Duration(milliseconds: 50));

      expect(callbackCount, equals(1),
          reason:
              'After dispose(), subscription is cancelled — no further callbacks');
    });
  });
}
