---
phase: 07-client-portal-and-notifications
plan: 03
subsystem: mobile-fcm-notifications
tags: [flutter, firebase, fcm, push-notifications, deep-link, android]
dependency_graph:
  requires:
    - 07-01 (POST /api/v1/notifications/token backend endpoint)
    - 07-02 (RouteNames.clientJobDetailPath, client portal routing)
  provides:
    - FcmService (token registration, message handlers, cold-start deep link)
    - Firebase Android integration (google-services plugin, notification channel)
  affects:
    - mobile/lib/main.dart
    - mobile/lib/features/auth/presentation/providers/auth_provider.dart
    - mobile/lib/core/routing/app_router.dart
tech_stack:
  added:
    - firebase_core ^4.5.0 (Firebase initialization)
    - firebase_messaging ^16.1.2 (FCM token and message handling)
    - com.google.gms.google-services 4.4.2 (Android Gradle plugin, Kotlin DSL)
  patterns:
    - Top-level background handler with @pragma('vm:entry-point')
    - Fire-and-forget FCM registration in AuthNotifier (non-blocking)
    - GetIt singleton for FcmService (accessed from auth and router layers)
    - Cold-start deep link via getInitialMessage -> GetIt 'fcmInitialRoute' string
    - DioClient.instance for POST /notifications/token (AuthInterceptor injects Bearer)
key_files:
  created:
    - mobile/lib/core/notifications/fcm_service.dart
  modified:
    - mobile/pubspec.yaml
    - mobile/android/settings.gradle.kts
    - mobile/android/app/build.gradle.kts
    - mobile/android/app/src/main/AndroidManifest.xml
    - mobile/lib/main.dart
    - mobile/lib/features/auth/presentation/providers/auth_provider.dart
    - mobile/lib/core/routing/app_router.dart
decisions:
  - "Kotlin DSL (settings.gradle.kts + app/build.gradle.kts) requires google-services in settings.gradle.kts plugins block — not in root build.gradle.kts as in Groovy DSL"
  - "DioClient.instance used (not DioClient.dio) — matches existing DioClient API; path is /notifications/token (relative, base URL configured in DioClient)"
  - "_registerFcmToken() is fire-and-forget in AuthNotifier — not awaited, uses .catchError() to log failures without blocking state transitions"
  - "FcmService registered in GetIt singleton — allows access from routerProvider (setupMessageHandlers) without passing through widget tree"
  - "No in-app foreground notification UI — OS tray handles display via job_updates channel; per CONTEXT.md 'keep it simple' decision"
  - "google-services.json not included — user must download from Firebase Console per plan user_setup instructions"
metrics:
  duration: "5 min"
  completed_date: "2026-03-13"
  tasks_completed: 1
  files_modified: 8
---

# Phase 7 Plan 03: FCM Mobile Integration Summary

Firebase Cloud Messaging setup for Android with FCM token registration on every login/session-restore, background message handler, and notification-tap deep-link to `/client/jobs/:id`.

## What Was Built

### FcmService (`mobile/lib/core/notifications/fcm_service.dart`)

Full FCM integration service with three public entry points:

- **`registerToken(DioClient)`**: Requests OS notification permission, gets FCM token, POSTs `{token, platform: 'android'}` to `/notifications/token`, listens to `onTokenRefresh` for automatic re-registration. All failures logged, none propagated.

- **`setupMessageHandlers(GoRouter)`**: Wires `onMessage` (foreground, no-op — OS tray shows notification) and `onMessageOpenedApp` (background-to-foreground tap, navigates to `clientJobDetailPath(jobId)`).

- **`getInitialRoute()`**: Calls `getInitialMessage()` for cold-start (terminated app) notification taps, returns `clientJobDetailPath(jobId)` or `null`.

### Background Handler
Top-level function `firebaseMessagingBackgroundHandler` with `@pragma('vm:entry-point')` re-initializes Firebase in the background isolate. No navigation (OS handles tray notification display).

### Android Build Configuration
- `settings.gradle.kts`: Added `id("com.google.gms.google-services") version "4.4.2" apply false`
- `app/build.gradle.kts`: Added `id("com.google.gms.google-services")` in plugins block
- `AndroidManifest.xml`: Added `com.google.firebase.messaging.default_notification_channel_id` meta-data with value `"job_updates"` — ensures FCM notifications display on Android 8+ without flutter_local_notifications

### Auth Integration (`auth_provider.dart`)
`_registerFcmToken()` helper calls `FcmService.registerToken()` fire-and-forget after:
- Successful `login()`
- Successful `register()`
- Successful `_restoreSession()` (app launch with stored tokens)

Wrapped in try/catch — FcmService unavailability (e.g., test environment) is logged, not raised.

### Main Initialization (`main.dart`)
1. `await Firebase.initializeApp()` before `setupServiceLocator()`
2. `FirebaseMessaging.onBackgroundMessage(firebaseMessagingBackgroundHandler)` registered before `runApp`
3. `FcmService()` created, registered as GetIt singleton
4. `getInitialRoute()` checked for cold-start deep link, stored in GetIt as `'fcmInitialRoute'` string

### Router Integration (`app_router.dart`)
After GoRouter creation, `getIt<FcmService>().setupMessageHandlers(router)` is called. Wrapped in try/catch for test environment safety.

## Checkpoint Paused At

Task 2 is a `checkpoint:human-verify` — requires human verification:
- Firebase project setup + `google-services.json` placement
- Backend GOOGLE_APPLICATION_CREDENTIALS configured
- Migration 0010 applied cleanly
- Token registration POST visible in backend logs
- Client portal screens visually correct

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 1 - Bug] DioClient exposes `instance` not `dio`**
- **Found during:** Task 1 — `_postToken` method in FcmService
- **Issue:** Plan spec showed `dioClient.dio.post(...)` but `DioClient` exposes `instance` as its `Dio` getter
- **Fix:** Changed to `dioClient.instance.post(...)` and updated path to `/notifications/token` (relative, not full URL) since base URL is configured in DioClient
- **Files modified:** `fcm_service.dart`
- **Commit:** cb39661

**2. [Rule 3 - Blocking] Kotlin DSL requires different Google Services plugin placement**
- **Found during:** Task 1 — Android build file configuration
- **Issue:** Plan spec referenced `build.gradle` (Groovy DSL) but project uses `build.gradle.kts` (Kotlin DSL); google-services plugin must go in `settings.gradle.kts` plugins block in Kotlin DSL
- **Fix:** Added plugin to `settings.gradle.kts` with `apply false`, then applied in `app/build.gradle.kts` plugins block — correct Kotlin DSL pattern
- **Files modified:** `settings.gradle.kts`, `app/build.gradle.kts`
- **Commit:** cb39661

## Self-Check: PASSED

All created/modified files verified present. Commit cb39661 verified in git log.
- `mobile/lib/core/notifications/fcm_service.dart`: present (170 lines)
- `mobile/pubspec.yaml`: firebase_core and firebase_messaging added
- `mobile/android/settings.gradle.kts`: google-services plugin declared
- `mobile/android/app/build.gradle.kts`: google-services plugin applied
- `mobile/android/app/src/main/AndroidManifest.xml`: notification channel meta-data added
- `mobile/lib/main.dart`: Firebase.initializeApp, background handler, FcmService GetIt registration
- `mobile/lib/features/auth/presentation/providers/auth_provider.dart`: _registerFcmToken wired
- `mobile/lib/core/routing/app_router.dart`: setupMessageHandlers wired
