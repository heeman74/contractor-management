import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:internet_connection_checker_plus/internet_connection_checker_plus.dart';

/// Wraps [Connectivity] with real internet verification before triggering sync.
///
/// Connectivity alone does not guarantee internet access — a device can be
/// connected to a Wi-Fi router with no upstream internet (Pitfall 2 from
/// RESEARCH.md). [ConnectivityService] uses [InternetConnection] to verify
/// actual internet access before notifying [SyncEngine].
///
/// Only triggers [onConnected] callback when:
/// 1. Connectivity result changes to non-none (network interface detected)
/// 2. AND [InternetConnection.hasInternetAccess] returns true
///
/// This avoids unnecessary sync attempts on captive portal or metered networks
/// where connectivity exists but HTTP requests will fail.
///
/// Constructor accepts optional [Connectivity] and [InternetConnection]
/// overrides for unit testing. Production code uses the default instances.
class ConnectivityService {
  final Connectivity _connectivity;
  final InternetConnection _internetChecker;

  StreamSubscription<List<ConnectivityResult>>? _subscription;

  /// Whether the service is currently tracking connectivity.
  bool _isListening = false;

  /// Stream of connectivity state for sync status UI.
  ///
  /// Emits [true] when the device has verified internet access,
  /// [false] when offline or connectivity is lost.
  final _onlineController = StreamController<bool>.broadcast();

  /// Creates a [ConnectivityService].
  ///
  /// [connectivity] and [internetChecker] are optional and default to the
  /// platform singletons. Override them in unit tests to inject mocks.
  ConnectivityService({
    Connectivity? connectivity,
    InternetConnection? internetChecker,
  })  : _connectivity = connectivity ?? Connectivity(),
        _internetChecker = internetChecker ?? InternetConnection();

  Stream<bool> get isOnlineStream => _onlineController.stream;

  /// Start listening to connectivity changes.
  ///
  /// [onConnected] is called whenever the device regains real internet
  /// access. The SyncEngine passes [_onConnectivityRestored] as the callback,
  /// which triggers drain + pull.
  ///
  /// Only one listener is active at a time. Calling [startListening] again
  /// while already listening is a no-op.
  void startListening(VoidCallback onConnected) {
    if (_isListening) return;
    _isListening = true;

    // connectivity_plus v7 returns List<ConnectivityResult> not a single value
    _subscription = _connectivity.onConnectivityChanged.listen(
      (results) async {
        final hasNetworkInterface =
            results.any((r) => r != ConnectivityResult.none);

        if (!hasNetworkInterface) {
          _onlineController.add(false);
          return;
        }

        // Network interface detected — verify actual internet access before
        // triggering sync. Captive portals and broken routers would fail
        // HTTP requests and waste the sync_queue drain cycle.
        final hasInternet = await _internetChecker.hasInternetAccess;
        _onlineController.add(hasInternet);

        if (hasInternet) {
          onConnected();
        }
      },
    );
  }

  /// Cancel the connectivity subscription and close the stream.
  ///
  /// Must be called when the owning service (SyncEngine) is disposed.
  void dispose() {
    _subscription?.cancel();
    _subscription = null;
    _isListening = false;
    _onlineController.close();
  }
}
