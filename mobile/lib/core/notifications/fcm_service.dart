import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:go_router/go_router.dart';

import '../network/dio_client.dart';
import '../routing/route_names.dart';

/// Top-level background message handler — MUST be a top-level function (not a
/// class method). The @pragma annotation ensures it is preserved by the Dart
/// tree-shaker in release builds.
///
/// Called by FirebaseMessaging when the app is terminated or in the background.
/// Navigation is NOT performed here — the OS places the notification in the
/// system tray; the user taps it to open the app (handled via getInitialMessage
/// for cold starts or onMessageOpenedApp for background-to-foreground).
@pragma('vm:entry-point')
Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  // Firebase must be re-initialized in the background isolate — it runs in a
  // separate Dart isolate with fresh memory (separate from the main isolate).
  await Firebase.initializeApp();
  // No navigation here — OS shows the tray notification automatically.
  debugPrint('[FCM] Background message received: ${message.messageId}');
}

/// Service for Firebase Cloud Messaging integration.
///
/// Responsibilities:
/// - Request notification permission from the OS
/// - Register the FCM token with the backend (POST /api/v1/notifications/token)
/// - Re-register on token rotation (onTokenRefresh stream)
/// - Handle notification taps (background-to-foreground deep-link)
/// - Provide initial route for cold-start deep-link (getInitialMessage)
///
/// Token registration failures are caught and logged — they MUST NOT block
/// the auth flow. The user is authenticated regardless of FCM success.
class FcmService {
  FcmService({this.enabled = true});

  /// Whether Firebase was successfully initialized. When false, all FCM
  /// operations are no-ops (local dev without google-services.json).
  final bool enabled;

  /// Registers the FCM token with the backend after successful authentication.
  ///
  /// Flow:
  ///   1. Request OS permission for notifications
  ///   2. Get the current FCM token
  ///   3. POST {token, platform: 'android'} to /api/v1/notifications/token
  ///   4. Subscribe to onTokenRefresh to re-POST on token rotation
  ///
  /// [dioClient]: The authenticated Dio client from GetIt. Must be called
  /// AFTER the user is authenticated (Bearer token set in AuthInterceptor).
  Future<void> registerToken(DioClient dioClient) async {
    if (!enabled) {
      debugPrint('[FCM] Firebase not available — skipping token registration');
      return;
    }
    try {
      // Request OS permission — on Android 13+ this shows the notification
      // permission dialog; on earlier Android versions it is always granted.
      final settings = await FirebaseMessaging.instance.requestPermission(
        
      );

      if (settings.authorizationStatus == AuthorizationStatus.denied) {
        debugPrint('[FCM] Notification permission denied — skipping token registration');
        return;
      }

      // Get the FCM registration token.
      // Returns null if the device cannot reach FCM servers, or if
      // google-services.json is missing (graceful degradation in dev).
      final token = await FirebaseMessaging.instance.getToken();
      if (token == null) {
        debugPrint('[FCM] Token is null — google-services.json may be missing or FCM unavailable');
        return;
      }

      await _postToken(dioClient, token);

      // Re-register whenever FCM rotates the token (server-side invalidation,
      // app reinstall, device restore, etc.).
      FirebaseMessaging.instance.onTokenRefresh.listen((newToken) async {
        debugPrint('[FCM] Token refreshed — re-registering with backend');
        try {
          await _postToken(dioClient, newToken);
        } catch (e) {
          // Token refresh registration failure is non-fatal — backend will
          // attempt to re-deliver using the previous token until it expires.
          debugPrint('[FCM] Token refresh registration failed: $e');
        }
      });
    } catch (e) {
      // FCM registration failure must NOT block auth — the user is authenticated
      // and should see the app normally even without push notifications.
      debugPrint('[FCM] Token registration failed (non-fatal): $e');
    }
  }

  /// POSTs the FCM token to the backend notification token endpoint.
  Future<void> _postToken(DioClient dioClient, String token) async {
    // Use DioClient.instance (the underlying Dio instance) to make the POST.
    // The base URL is already configured in DioClient — only the path is needed.
    // DioClient.instance has the AuthInterceptor attached — Bearer token is
    // injected automatically from TokenStorage.
    await dioClient.instance.post<void>(
      '/notifications/token',
      data: {'token': token, 'platform': 'android'},
    );
    debugPrint('[FCM] Token registered with backend');
  }

  /// Wires up notification tap handlers for foreground and background states.
  ///
  /// - [FirebaseMessaging.onMessage]: App is in foreground — per CONTEXT.md
  ///   decision, we rely on the OS tray notification (no-op / log only).
  ///   The OS tray fires because the default_notification_channel_id is set
  ///   in AndroidManifest.xml.
  ///
  /// - [FirebaseMessaging.onMessageOpenedApp]: User tapped the notification
  ///   while app was in background — navigate to the specific job detail.
  ///
  /// [router]: The GoRouter instance from routerProvider. Called after the
  /// router is created to enable navigation.
  void setupMessageHandlers(GoRouter router) {
    if (!enabled) return;
    // Foreground: notification is delivered while the user is using the app.
    // The OS shows a heads-up notification via the job_updates channel.
    // No in-app UI per CONTEXT.md "Keep it simple" decision.
    FirebaseMessaging.onMessage.listen((message) {
      debugPrint('[FCM] Foreground message: ${message.messageId}');
      // Intentional no-op — OS tray handles the notification display.
    });

    // Background -> foreground: user tapped a notification in the system tray.
    // Extract job_id from message data and deep-link to generic job detail.
    FirebaseMessaging.onMessageOpenedApp.listen((message) {
      debugPrint('[FCM] Notification tapped (background->foreground): ${message.messageId}');
      _navigateToJob(router, message);
    });
  }

  /// Returns the initial deep-link route for cold-start notification taps.
  ///
  /// When the app is fully terminated and the user taps a notification,
  /// [FirebaseMessaging.instance.getInitialMessage()] returns the message.
  /// This is called from main() before runApp() to set the router's
  /// initialLocation to the specific job's detail screen.
  ///
  /// Returns null if the app was not launched from a notification.
  Future<String?> getInitialRoute() async {
    if (!enabled) return null;
    try {
      final message = await FirebaseMessaging.instance.getInitialMessage();
      if (message != null) {
        debugPrint('[FCM] App launched from notification: ${message.messageId}');
        final jobId = message.data['job_id'] as String?;
        if (jobId != null && jobId.isNotEmpty) {
          return RouteNames.jobDetailPath(jobId);
        }
      }
    } catch (e) {
      // getInitialMessage failure is non-fatal — app opens at default route.
      debugPrint('[FCM] getInitialMessage failed (non-fatal): $e');
    }
    return null;
  }

  /// Extracts job_id from a [RemoteMessage] and navigates to the generic job
  /// detail screen (works for all roles). Silently skips if job_id is missing.
  void _navigateToJob(GoRouter router, RemoteMessage message) {
    final jobId = message.data['job_id'] as String?;
    if (jobId == null || jobId.isEmpty) {
      debugPrint('[FCM] Notification missing job_id — skipping navigation');
      return;
    }
    router.go(RouteNames.jobDetailPath(jobId));
  }
}
