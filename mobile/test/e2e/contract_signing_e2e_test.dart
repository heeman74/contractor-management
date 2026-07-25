// Contract Signing (e-signature) — Flutter E2E widget tests.
//
// Covers the client-facing signing ceremony hosted by [ContractSignScreen],
// which embeds the provider's (Dropbox Sign) signing page in a WebView and
// completes when the frame emits a completion signal (postMessage forwarded
// through a JS channel, or a navigation-URL marker).
//
// Because the signing "write" happens INSIDE the embedded provider frame, the
// mobile side only performs read requests:
//   - GET /contracts/{id}/sign-url   → { sign_url } (fresh embedded URL)
//   - GET /contracts/{id}            → contract JSON (re-fetched after signing)
// So the network assertions target those GET paths (via a mocked Dio), and the
// UI assertions target the WebView lifecycle: load → completion → pop(true).
//
// Strategy / harness (per CLAUDE.md + MEMORY.md):
//   - ProviderScope.overrideWith for signUrlProvider / contractProvider.
//   - A test WebViewPlatform implementation (webview_flutter_platform_interface)
//     so WebViewWidget builds in a headless test and completion callbacks can
//     be driven from the test — the repo's first WebView-backed E2E.
//   - MockDio (mocktail implements Dio) for the repository-layer request paths.
//   - pump() / pump(Duration(...)) — NEVER pumpAndSettle (no settle guarantee).
//   - Fake AuthNotifier(client role) — the client is the signer.
//
// Coverage:
//   1. Repository GET /contracts/{id}/sign-url returns the sign_url (happy path).
//   2. Repository maps 404/5xx DioException → user-safe ContractException.
//   3. Repository rejects a malformed sign-url payload (FormatException).
//   4. Screen renders AppBar 'Review & Sign' + spinner while sign-url loads.
//   5. Screen renders the WebView once the sign-url resolves.
//   6. Screen shows the error state + retry when sign-url fetch fails.
//   7. Retry re-fetches the sign-url after an error.
//   8. Completion via navigation-URL marker (signed=true) → pops(true).
//   9. Completion via JS-channel postMessage (signature_request_signed) → pops.
//  10. A non-completion signal does NOT complete/pop (still on the WebView).
//  11. Completing signing invalidates contractProvider (caller sees new status).
//  12. A main-frame load failure shows the load-error state + retry.

// The abstract Platform* base classes extended by the test WebView platform
// live only in webview_flutter_platform_interface (webview_flutter re-exports
// the value types but not those bases), so it is imported directly here.
// ignore_for_file: depend_on_referenced_packages

import 'dart:async';

import 'package:contractorhub/features/auth/domain/auth_state.dart';
import 'package:contractorhub/features/auth/presentation/providers/auth_provider.dart';
import 'package:contractorhub/features/contracts/data/contract_repository.dart';
import 'package:contractorhub/features/contracts/domain/contract.dart';
import 'package:contractorhub/features/contracts/presentation/providers/contract_providers.dart';
import 'package:contractorhub/features/contracts/presentation/screens/contract_sign_screen.dart';
import 'package:contractorhub/shared/models/user_role.dart';
import 'package:dio/dio.dart' hide ProgressCallback;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:webview_flutter_platform_interface/webview_flutter_platform_interface.dart';

// ---------------------------------------------------------------------------
// Constants
// ---------------------------------------------------------------------------

const _contractId = 'contract-001';
const _companyId = 'company-001';
const _clientUserId = 'client-001';
const _signUrl = 'https://app.hellosign.com/editor/embeddedSign?token=abc123';

// ---------------------------------------------------------------------------
// Auth (the client is the signer)
// ---------------------------------------------------------------------------

AuthState _clientAuthState() => const AuthState.authenticated(
      userId: _clientUserId,
      companyId: _companyId,
      roles: {UserRole.client},
    );

class _FakeAuthNotifier extends AuthNotifier {
  _FakeAuthNotifier(this._state);
  final AuthState _state;

  @override
  AuthState build() => _state;
}

// ---------------------------------------------------------------------------
// Dio mock (repository-layer request-path assertions)
// ---------------------------------------------------------------------------

class _MockDio extends Mock implements Dio {}

Response<dynamic> _okJson(Object? data, {String path = '/'}) => Response<dynamic>(
      data: data,
      statusCode: 200,
      requestOptions: RequestOptions(path: path),
    );

DioException _httpError(int statusCode, String path) => DioException(
      requestOptions: RequestOptions(path: path),
      response: Response<dynamic>(
        statusCode: statusCode,
        requestOptions: RequestOptions(path: path),
      ),
      type: DioExceptionType.badResponse,
    );

// ---------------------------------------------------------------------------
// Test WebView platform — lets WebViewWidget build headlessly and exposes the
// controller / navigation delegate so completion signals can be driven.
// ---------------------------------------------------------------------------

// The most-recently created fakes for the screen under test. One screen pumps
// exactly one controller + one navigation delegate, so "last" == "current".
_FakeWebViewController? _lastController;
_FakeNavigationDelegate? _lastNavigationDelegate;

void _resetWebViewProbe() {
  _lastController = null;
  _lastNavigationDelegate = null;
}

/// Simulate the embedded frame navigating to [url] (nav-delegate fallback).
void _emitUrl(String url) =>
    _lastNavigationDelegate?.onUrlChange?.call(UrlChange(url: url));

/// Simulate a provider postMessage forwarded through the JS channel.
void _emitJsMessage(String message) =>
    _lastController?.jsChannelOnMessage?.call(JavaScriptMessage(message: message));

/// Simulate the page finishing load (triggers the JS listener injection).
void _emitPageFinished(String url) =>
    _lastNavigationDelegate?.onPageFinished?.call(url);

/// Simulate a main-frame load failure.
void _emitMainFrameError() =>
    _lastNavigationDelegate?.onWebResourceError?.call(const WebResourceError(
      errorCode: -2,
      description: 'net::ERR_NAME_NOT_RESOLVED',
      isForMainFrame: true,
    ));

class _FakeWebViewPlatform extends WebViewPlatform {
  @override
  PlatformWebViewController createPlatformWebViewController(
    PlatformWebViewControllerCreationParams params,
  ) =>
      _lastController = _FakeWebViewController(params);

  @override
  PlatformNavigationDelegate createPlatformNavigationDelegate(
    PlatformNavigationDelegateCreationParams params,
  ) =>
      _lastNavigationDelegate = _FakeNavigationDelegate(params);

  @override
  PlatformWebViewWidget createPlatformWebViewWidget(
    PlatformWebViewWidgetCreationParams params,
  ) =>
      _FakeWebViewWidget(params);
}

class _FakeWebViewController extends PlatformWebViewController {
  _FakeWebViewController(super.params) : super.implementation();

  void Function(JavaScriptMessage)? jsChannelOnMessage;

  @override
  Future<void> setJavaScriptMode(JavaScriptMode javaScriptMode) async {}

  @override
  Future<void> addJavaScriptChannel(
    JavaScriptChannelParams javaScriptChannelParams,
  ) async {
    jsChannelOnMessage = javaScriptChannelParams.onMessageReceived;
  }

  @override
  Future<void> setPlatformNavigationDelegate(
    PlatformNavigationDelegate handler,
  ) async {}

  @override
  Future<void> loadRequest(LoadRequestParams params) async {}

  @override
  Future<void> runJavaScript(String javaScript) async {}

  @override
  Future<void> setBackgroundColor(Color color) async {}

  @override
  Future<void> setUserAgent(String? userAgent) async {}
}

class _FakeNavigationDelegate extends PlatformNavigationDelegate {
  _FakeNavigationDelegate(super.params) : super.implementation();

  UrlChangeCallback? onUrlChange;
  PageEventCallback? onPageFinished;
  WebResourceErrorCallback? onWebResourceError;

  @override
  Future<void> setOnUrlChange(UrlChangeCallback onUrlChange) async {
    this.onUrlChange = onUrlChange;
  }

  @override
  Future<void> setOnPageFinished(PageEventCallback onPageFinished) async {
    this.onPageFinished = onPageFinished;
  }

  @override
  Future<void> setOnWebResourceError(
    WebResourceErrorCallback onWebResourceError,
  ) async {
    this.onWebResourceError = onWebResourceError;
  }

  @override
  Future<void> setOnNavigationRequest(
    NavigationRequestCallback onNavigationRequest,
  ) async {}

  @override
  Future<void> setOnPageStarted(PageEventCallback onPageStarted) async {}

  @override
  Future<void> setOnProgress(ProgressCallback onProgress) async {}
}

class _FakeWebViewWidget extends PlatformWebViewWidget {
  _FakeWebViewWidget(super.params) : super.implementation();

  @override
  Widget build(BuildContext context) => const SizedBox(
        key: ValueKey('fake-webview'),
        width: 320,
        height: 480,
      );
}

// ---------------------------------------------------------------------------
// Widget-test harness
// ---------------------------------------------------------------------------

/// Pump [ContractSignScreen] under a ProviderScope with the given overrides.
/// Returns a `signedResult` sink so completion (pop(true)) can be asserted.
Future<List<bool?>> _pumpSignScreen(
  WidgetTester tester, {
  required List<Override> overrides,
}) async {
  final results = <bool?>[];

  await tester.pumpWidget(
    ProviderScope(
      overrides: overrides,
      // Riverpod 3 auto-retries errored providers (timer-backed), which would
      // keep an error state pinned in `loading` and hang the widget under test.
      // Disable retry so error/success states settle deterministically.
      retry: (_, __) => null,
      child: MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => Center(
              child: ElevatedButton(
                onPressed: () async {
                  final signed = await Navigator.of(context).push<bool>(
                    MaterialPageRoute(
                      builder: (_) =>
                          const ContractSignScreen(contractId: _contractId),
                    ),
                  );
                  results.add(signed);
                },
                child: const Text('Open'),
              ),
            ),
          ),
        ),
      ),
    ),
  );

  await tester.tap(find.text('Open'));
  await tester.pump(); // start push
  await tester.pump(const Duration(milliseconds: 350)); // route transition
  return results;
}

/// Advance past a pop's reverse transition and let the popped route dispose.
/// (retry timers are disabled, so a fixed advance is deterministic here.)
Future<void> _settlePop(WidgetTester tester) async {
  await tester.pump(); // process the pop
  await tester.pump(const Duration(milliseconds: 400)); // reverse transition
  await tester.pump(); // dispose the popped route
}

Override _authOverride() =>
    authNotifierProvider.overrideWith(() => _FakeAuthNotifier(_clientAuthState()));

Override _signUrlOverride(Future<String> Function() build) =>
    signUrlProvider(_contractId).overrideWith((ref) => build());

void main() {
  setUpAll(() {
    registerFallbackValue(RequestOptions(path: '/'));
    WebViewPlatform.instance = _FakeWebViewPlatform();
  });

  setUp(_resetWebViewProbe);

  // =========================================================================
  // Repository layer — request paths & error mapping (MockDio)
  // =========================================================================
  group('ContractRepository (signing endpoints)', () {
    late _MockDio dio;
    late ContractRepository repository;

    setUp(() {
      dio = _MockDio();
      repository = ContractRepository(dio: dio);
    });

    test('getSignUrl GETs /contracts/{id}/sign-url and returns sign_url',
        () async {
      when(() => dio.get<dynamic>(any())).thenAnswer(
        (_) async => _okJson(
          {'sign_url': _signUrl},
          path: '/contracts/$_contractId/sign-url',
        ),
      );

      final url = await repository.getSignUrl(_contractId);

      expect(url, _signUrl);
      verify(() => dio.get<dynamic>('/contracts/$_contractId/sign-url'))
          .called(1);
    });

    test('getSignUrl maps a 404 DioException to a user-safe ContractException',
        () async {
      when(() => dio.get<dynamic>(any())).thenThrow(
        _httpError(404, '/contracts/$_contractId/sign-url'),
      );

      await expectLater(
        () => repository.getSignUrl(_contractId),
        throwsA(
          isA<ContractException>().having(
            (e) => e.message,
            'message',
            'This contract could not be found.',
          ),
        ),
      );
    });

    test('getSignUrl maps a 5xx DioException to a retry-later message',
        () async {
      when(() => dio.get<dynamic>(any())).thenThrow(
        _httpError(503, '/contracts/$_contractId/sign-url'),
      );

      await expectLater(
        () => repository.getSignUrl(_contractId),
        throwsA(
          isA<ContractException>().having(
            (e) => e.message,
            'message',
            'The server is having trouble. Please try again shortly.',
          ),
        ),
      );
    });

    test('getSignUrl throws FormatException on a malformed payload', () async {
      when(() => dio.get<dynamic>(any())).thenAnswer(
        (_) async => _okJson(
          {'wrong_key': 123}, // no string sign_url
          path: '/contracts/$_contractId/sign-url',
        ),
      );

      await expectLater(
        () => repository.getSignUrl(_contractId),
        throwsA(isA<FormatException>()),
      );
    });
  });

  // =========================================================================
  // Screen — sign-url lifecycle (loading / data / error / retry)
  // =========================================================================
  group('ContractSignScreen — sign-url lifecycle', () {
    testWidgets('shows AppBar title and a spinner while the sign-url loads',
        (tester) async {
      // A never-completing future keeps the provider in the loading state.
      final pending = Completer<String>();

      await _pumpSignScreen(
        tester,
        overrides: [
          _authOverride(),
          _signUrlOverride(() => pending.future),
        ],
      );

      expect(find.text('Review & Sign'), findsOneWidget);
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      expect(find.byKey(const ValueKey('fake-webview')), findsNothing);
    });

    testWidgets('renders the WebView once the sign-url resolves',
        (tester) async {
      await _pumpSignScreen(
        tester,
        overrides: [
          _authOverride(),
          _signUrlOverride(() async => _signUrl),
        ],
      );
      await tester.pump();

      expect(find.byType(WebViewWidget), findsOneWidget);
      expect(find.byKey(const ValueKey('fake-webview')), findsOneWidget);
      // The screen wired a JS channel + navigation delegate for completion.
      expect(_lastController?.jsChannelOnMessage, isNotNull);
      expect(_lastNavigationDelegate?.onUrlChange, isNotNull);
    });

    testWidgets('shows the error state with a retry when sign-url fetch fails',
        (tester) async {
      await _pumpSignScreen(
        tester,
        overrides: [
          _authOverride(),
          _signUrlOverride(
            () async =>
                throw const ContractException('This contract could not be found.'),
          ),
        ],
      );
      await tester.pump();

      expect(find.text('This contract could not be found.'), findsOneWidget);
      expect(find.text('Try Again'), findsOneWidget);
      expect(find.byIcon(Icons.error_outline), findsOneWidget);
      expect(find.byType(WebViewWidget), findsNothing);
    });

    testWidgets('retry re-fetches the sign-url after an initial error',
        (tester) async {
      var attempts = 0;

      await _pumpSignScreen(
        tester,
        overrides: [
          _authOverride(),
          _signUrlOverride(() async {
            attempts++;
            if (attempts == 1) {
              throw const ContractException(
                  'Could not start the signing session. Please try again.');
            }
            return _signUrl;
          }),
        ],
      );
      await tester.pump();

      expect(find.text('Try Again'), findsOneWidget);
      expect(attempts, 1);

      await tester.tap(find.text('Try Again'));
      await tester.pump();
      await tester.pump();

      // Second attempt succeeds → WebView renders, error state gone.
      expect(attempts, 2);
      expect(find.byType(WebViewWidget), findsOneWidget);
      expect(find.text('Try Again'), findsNothing);
    });
  });

  // =========================================================================
  // Screen — signing completion (happy path) & edge cases
  // =========================================================================
  group('ContractSignScreen — completion', () {
    testWidgets('navigation-URL completion marker → pops with true',
        (tester) async {
      final results = await _pumpSignScreen(
        tester,
        overrides: [
          _authOverride(),
          _signUrlOverride(() async => _signUrl),
        ],
      );
      await tester.pump();
      expect(find.byType(WebViewWidget), findsOneWidget);

      // Dropbox Sign redirects to a URL carrying `signed=true` on success.
      _emitUrl('$_signUrl&signed=true');
      await _settlePop(tester);

      expect(results, [true]);
      expect(find.byType(WebViewWidget), findsNothing);
      expect(find.text('Open'), findsOneWidget); // back on the caller
    });

    testWidgets('JS-channel postMessage completion marker → pops with true',
        (tester) async {
      final results = await _pumpSignScreen(
        tester,
        overrides: [
          _authOverride(),
          _signUrlOverride(() async => _signUrl),
        ],
      );
      await tester.pump();

      // Provider frame posts an event object forwarded via the JS channel.
      _emitPageFinished(_signUrl); // injects the listener
      _emitJsMessage(
        '{"type":"signature_request_signed","signatureId":"sig_1"}',
      );
      await _settlePop(tester);

      expect(results, [true]);
      expect(find.byType(WebViewWidget), findsNothing);
    });

    testWidgets('a non-completion signal does NOT complete or pop',
        (tester) async {
      final results = await _pumpSignScreen(
        tester,
        overrides: [
          _authOverride(),
          _signUrlOverride(() async => _signUrl),
        ],
      );
      await tester.pump();

      // A benign navigation / progress event must not finish the ceremony.
      _emitUrl('$_signUrl&step=review');
      _emitJsMessage('{"type":"page_view"}');
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 350));

      expect(results, isEmpty); // never popped
      expect(find.byType(WebViewWidget), findsOneWidget); // still signing
    });

    testWidgets('completion invalidates contractProvider so the caller refreshes',
        (tester) async {
      var contractBuilds = 0;

      Contract buildContract() {
        contractBuilds++;
        return const Contract(id: _contractId, status: ContractStatus.viewed);
      }

      await _pumpSignScreen(
        tester,
        overrides: [
          _authOverride(),
          _signUrlOverride(() async => _signUrl),
          // A keepAlive listener below forces the provider to stay subscribed
          // so the invalidation triggers a rebuild we can count.
          contractProvider(_contractId).overrideWith((ref) async {
            ref.keepAlive();
            return buildContract();
          }),
        ],
      );
      await tester.pump();

      // Simulate the caller watching the contract: an active subscription keeps
      // the provider alive so the screen's invalidate() recomputes immediately.
      final container = ProviderScope.containerOf(
        tester.element(find.byType(ContractSignScreen)),
      );
      final subscription = container.listen(
        contractProvider(_contractId),
        (_, __) {},
        fireImmediately: true,
      );
      addTearDown(subscription.close);
      await tester.pump();
      final buildsBeforeSigning = contractBuilds;
      expect(buildsBeforeSigning, greaterThanOrEqualTo(1));

      _emitUrl('$_signUrl&sign_complete=1');
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 350));

      // The screen called ref.invalidate(contractProvider(id)) on completion,
      // which recomputed the (still-subscribed) provider.
      expect(contractBuilds, greaterThan(buildsBeforeSigning));
    });
  });

  // =========================================================================
  // Screen — WebView load failure (error path)
  // =========================================================================
  group('ContractSignScreen — load failure', () {
    testWidgets('a main-frame resource error shows the load-error state',
        (tester) async {
      final results = await _pumpSignScreen(
        tester,
        overrides: [
          _authOverride(),
          _signUrlOverride(() async => _signUrl),
        ],
      );
      await tester.pump();
      expect(find.byType(WebViewWidget), findsOneWidget);

      _emitMainFrameError();
      await tester.pump();

      expect(
        find.textContaining('signing page could not be loaded'),
        findsOneWidget,
      );
      expect(find.text('Try Again'), findsOneWidget);
      expect(find.byType(WebViewWidget), findsNothing);
      expect(results, isEmpty); // a load failure must NOT pop as success
    });
  });
}
