import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:webview_flutter/webview_flutter.dart';

import '../../data/contract_repository.dart';
import '../providers/contract_providers.dart';

/// Hosts the provider's embedded signing ceremony (Dropbox Sign) in a WebView.
///
/// Flow:
///   1. Fetch a fresh `sign_url` for [contractId] via [signUrlProvider].
///   2. Load it in the WebView.
///   3. Detect completion — Dropbox Sign's embedded frame `postMessage`
///      (`signature_request_signed` / `hellosign:*`) forwarded through a JS
///      channel, plus a navigation-URL fallback.
///   4. On completion: invalidate [contractProvider] so the caller sees the
///      refreshed `signed` status, then pop with `true`.
///
/// Pushed via [RouteNames.contractSign] / `contractSignPath(contractId)`.
class ContractSignScreen extends ConsumerStatefulWidget {
  const ContractSignScreen({required this.contractId, super.key});

  final String contractId;

  @override
  ConsumerState<ContractSignScreen> createState() => _ContractSignScreenState();
}

class _ContractSignScreenState extends ConsumerState<ContractSignScreen> {
  /// JS channel name the injected listener posts signing events to.
  static const _eventChannel = 'ContractSignEvents';

  /// Substrings that, in a postMessage or navigation URL, indicate the signer
  /// finished the ceremony successfully.
  static const _completionMarkers = <String>[
    'signature_request_signed',
    'signature_request_all_signed',
    'hellosign:sign',
    'hellosign:finish',
    'sign_complete',
    'signed=true',
  ];

  WebViewController? _controller;
  bool _completed = false;
  bool _pageLoadFailed = false;

  @override
  Widget build(BuildContext context) {
    final signUrlAsync = ref.watch(signUrlProvider(widget.contractId));

    return Scaffold(
      appBar: AppBar(title: const Text('Review & Sign')),
      body: signUrlAsync.when(
        data: (signUrl) => _buildWebView(signUrl),
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) => _ErrorState(
          message: _errorMessage(error),
          onRetry: () => ref.invalidate(signUrlProvider(widget.contractId)),
        ),
      ),
    );
  }

  Widget _buildWebView(String signUrl) {
    if (_pageLoadFailed) {
      return _ErrorState(
        message: 'The signing page could not be loaded. '
            'Please check your connection and try again.',
        onRetry: () {
          setState(() => _pageLoadFailed = false);
          ref.invalidate(signUrlProvider(widget.contractId));
        },
      );
    }

    final controller = _controller ??= _createController(signUrl);
    return WebViewWidget(controller: controller);
  }

  WebViewController _createController(String signUrl) {
    final controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..addJavaScriptChannel(
        _eventChannel,
        onMessageReceived: (message) => _handleSignal(message.message),
      )
      ..setNavigationDelegate(
        NavigationDelegate(
          onUrlChange: (change) => _handleSignal(change.url ?? ''),
          onPageFinished: (_) => _injectMessageListener(),
          onWebResourceError: (error) {
            // Ignore sub-resource errors; only a main-frame failure is fatal.
            if (error.isForMainFrame ?? true) {
              debugPrint('[ContractSignScreen] load error: ${error.description}');
              if (mounted) setState(() => _pageLoadFailed = true);
            }
          },
        ),
      )
      ..loadRequest(Uri.parse(signUrl));
    return controller;
  }

  /// Inject a `message` listener that forwards provider postMessage events
  /// (which may be JSON strings or objects) into the Flutter JS channel.
  void _injectMessageListener() {
    _controller?.runJavaScript('''
      (function() {
        if (window.__contractSignHooked) return;
        window.__contractSignHooked = true;
        window.addEventListener('message', function(event) {
          try {
            var payload = typeof event.data === 'string'
                ? event.data
                : JSON.stringify(event.data);
            $_eventChannel.postMessage(payload);
          } catch (e) {}
        });
      })();
    ''');
  }

  void _handleSignal(String raw) {
    if (_completed || raw.isEmpty) return;
    final lower = raw.toLowerCase();
    final isComplete =
        _completionMarkers.any((marker) => lower.contains(marker));
    if (isComplete) _onSigningComplete();
  }

  void _onSigningComplete() {
    if (_completed) return;
    _completed = true;
    // Refresh the contract so the caller reflects the new `signed` status.
    ref.invalidate(contractProvider(widget.contractId));
    if (mounted) Navigator.of(context).pop(true);
  }

  String _errorMessage(Object error) {
    if (error is ContractException) return error.message;
    return 'Could not start the signing session. Please try again.';
  }
}

/// Full-screen error placeholder with a retry action.
class _ErrorState extends StatelessWidget {
  const _ErrorState({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.error_outline, size: 48, color: theme.colorScheme.error),
            const SizedBox(height: 12),
            Text(
              message,
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium,
            ),
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: onRetry,
              icon: const Icon(Icons.refresh),
              label: const Text('Try Again'),
            ),
          ],
        ),
      ),
    );
  }
}
