# Phase 7: Client Portal and Notifications - Research

**Researched:** 2026-03-12
**Domain:** Flutter client portal UI, Firebase Cloud Messaging (FCM), Python firebase-admin SDK
**Confidence:** HIGH

<user_constraints>
## User Constraints (from CONTEXT.md)

### Locked Decisions

**Job Status Display**
- Step progress bar showing lifecycle stages: Quote → Scheduled → In Progress → Complete → Invoiced
- Cancelled jobs show a "Cancelled" banner instead of the stepper
- Client-specific detail screen (NOT reusing admin JobDetailScreen): progress stepper at top, then tabs for Photos, Notes, Details
- Contractor name + trade type visible; no contact info
- No pricing/cost info in Phase 7 — deferred to Phase 8
- Details tab shows both scheduled date/time window AND expected completion date (ETA)

**Portal List (Home Screen)**
- Keep existing status badge on job cards; add ETA date beneath the status chip
- Completed/invoiced jobs: dimmed with green checkmark
- "Pending Requests" section at top when pending/declined requests exist; hidden when empty
- Pending request cards: description, preferred dates, urgency, submission date, status (Pending/Accepted/Declined)
- Declined requests stay visible with red badge and decline reason; can be dismissed manually
- "Request More Info" status shows admin's message; client cannot reply in-app
- Accepted requests disappear; converted job appears in main active list
- Keep existing "Request Job" FAB

**Photo Timeline (Photos Tab)**
- Chronological feed: photos and drawings only (no PDFs)
- Each entry: thumbnail, caption (if any), timestamp
- Full note body NOT shown — captions only; full notes in Notes tab
- Tap opens full-screen viewer with pinch-to-zoom, swipe between photos, download to gallery
- Only upload_status='uploaded' attachments with valid remote_url visible to clients
- Photo count badge on Photos tab
- Empty state: camera icon + "No progress photos yet — photos will appear here as work progresses."

**Delay Visibility**
- Orange/yellow warning banner at top of client job detail screen: reason + original ETA → new ETA
- Expandable delay history for multiple delays; latest shown by default
- Banner persists until job reaches Complete status
- Small orange warning icon + updated ETA on job card in portal list
- Delays appear as system entries in Notes tab (orange icon, "Delay reported" header)

**Client Notes Tab (Activity Log)**
- Read-only; no commenting ability
- Shows chronologically: contractor field notes, delay events (system entries), status transitions
- Complete activity log — client sees full story of their job

**Push Notifications (FCM)**
- Firebase Cloud Messaging for real push notifications
- Four triggers: job scheduled, work started (In Progress), job completed, job delayed
- Clients only in Phase 7; admin/contractor deferred
- FCM token registered for ALL users at login (infrastructure for future expansion)
- Token registration: every app launch + onTokenRefresh → POST /api/v1/notifications/token
- No notification preferences in Phase 7 — all four types always sent
- Tapping notification deep-links to the specific job's client detail screen
- OS notification tray only — no in-app notification center
- Notification body includes: milestone event + job description

**FCM Backend Architecture**
- Inline dispatch in service layer — JobService calls NotificationService.send() on transitions and delays
- Firebase Admin SDK (Python) for FCM
- New device_tokens table: user_id, token, platform (android/ios), created_at, last_used_at; multiple tokens per user
- Fire-and-forget on FCM failure — log error to stdout, don't retry
- No notification_log table — stdout logging only for v1
- Token cleanup on 401/invalid token response from FCM

**Role Gating Enforcement**
- Client portal lives in its own GoRouter branch (Branch 6 already exists)
- Client-specific providers only fetch jobs where client_id = current user
- Backend enforcement: sync delta endpoint filters by role
- Same SyncEngine; backend filters response by role — no new sync infrastructure

**Offline Behavior**
- Show cached Drift data with "Last updated: X ago" (switches to date after 24 hours)
- Pull-to-refresh attempts sync
- Photos: thumbnails cached; full-size fetched on-demand on tap
- Job request submission works offline — queued to sync queue

### Claude's Discretion
- Client detail screen layout and styling
- Step progress bar widget implementation
- Photo full-screen viewer implementation (package selection or custom)
- Delay banner animation and styling
- System entry styling in Notes tab (icons, colors, typography)
- FCM notification channel configuration (Android)
- Firebase project setup documentation
- Device token cleanup strategy details
- Photo caching implementation details
- Exact "Last updated" threshold for switching from relative to absolute time

### Deferred Ideas (OUT OF SCOPE)
- Admin/contractor push notifications
- In-app notification center with bell icon and unread count
- Per-type notification preferences
- Client commenting/replying to notes
- notification_log table for analytics
- Before/After photo tagging in timeline
- Client rating of completed jobs from portal
</user_constraints>

<phase_requirements>
## Phase Requirements

| ID | Description | Research Support |
|----|-------------|-----------------|
| CLNT-02 | Client notifications (job scheduled, started, completed, delayed) | FCM integration with firebase_messaging (Flutter) + firebase-admin (Python); four-trigger model researched and documented |
| CLNT-03 | Client portal with live job status and progress photos | Enhances existing ClientPortalScreen; new ClientJobDetailScreen with step progress bar + tab view; photo timeline from NoteEntity/AttachmentEntity |
| CLNT-05 | Delay reasons and updated ETAs visible to clients in portal | status_history JSONB already stores delay entries; UI reads and surfaces them as banner + Notes tab system entries |
</phase_requirements>

---

## Summary

Phase 7 enhances the existing client portal and adds FCM push notifications. The Flutter app already has `ClientPortalScreen` (Branch 6 in GoRouter), `clientJobHistoryNotifierProvider`, `NoteEntity`/`AttachmentEntity` domain models with all needed fields, and a sync engine that pulls data reactively. The Phase 7 work is principally additive: a new `ClientJobDetailScreen` with tabs, a photo timeline, delay visibility UI, and FCM token/dispatch infrastructure.

The FCM integration requires two new packages (`firebase_core` v4.5.0 + `firebase_messaging` v16.1.2) on the Flutter side and the `firebase-admin` Python package on the backend. The backend needs one new Alembic migration (migration 0010) for the `device_tokens` table and a new `NotificationService` class. Existing `JobService.transition_status()` and `report_delay()` methods are the correct injection points for notification dispatch calls.

The largest risk area is Firebase project setup (google-services.json for Android, GoogleService-Info.plist for iOS) and the `GOOGLE_APPLICATION_CREDENTIALS` environment variable on the backend. These are configuration gates that must be resolved in Wave 0 before any other notification work can proceed.

**Primary recommendation:** Build the portal UI (plans 07-01 through 07-03) first because they depend only on already-synced Drift data. Wire FCM (plan 07-04) as the final backend layer, with E2E tests (plan 07-05) shipped alongside.

---

## Standard Stack

### Core
| Library | Version | Purpose | Why Standard |
|---------|---------|---------|--------------|
| firebase_core | ^4.5.0 | Firebase app initialization (required by all Firebase Flutter plugins) | Mandatory peer dependency for firebase_messaging |
| firebase_messaging | ^16.1.2 | FCM token management, foreground/background message handling | Official Firebase Flutter plugin — only production-ready FCM solution for Flutter |
| firebase-admin (Python) | latest stable (~6.x) | Server-side FCM message dispatch via FCM v1 HTTP API | Firebase's own Admin SDK; uses service account credentials; no third-party dependencies |

### Supporting
| Library | Version | Purpose | When to Use |
|---------|---------|---------|-------------|
| photo_view (pub.dev) | ^0.15.0 | Pinch-to-zoom + swipe between photos in full-screen viewer | Discrete package used for photo timeline viewer — saves implementing GestureDetector + TransformationController from scratch |
| image_gallery_saver / gal | latest | Save photo from network URL to device gallery (download button in photo viewer) | Triggered only on explicit download button tap |

### Alternatives Considered
| Instead of | Could Use | Tradeoff |
|------------|-----------|----------|
| photo_view package | Custom InteractiveViewer + PageView | photo_view is purpose-built; custom saves ~50 lines but adds gesture edge cases |
| firebase-admin Python SDK | pyfcm | firebase-admin is the official SDK; uses FCM v1 API automatically; pyfcm is community |

### Installation
```bash
# Flutter (run from mobile/)
flutter pub add firebase_core firebase_messaging

# Backend (run from backend/)
uv add firebase-admin
```

---

## Architecture Patterns

### Recommended Project Structure
```
mobile/lib/features/client/
├── presentation/
│   └── screens/
│       ├── client_portal_screen.dart     # EXISTING — enhance
│       ├── client_job_detail_screen.dart # NEW — Phase 7
│       └── photo_viewer_screen.dart      # NEW — Phase 7

backend/app/features/notifications/
├── __init__.py
├── models.py        # DeviceToken SQLAlchemy model
├── repository.py    # NotificationRepository
├── schemas.py       # TokenRegisterRequest
├── service.py       # NotificationService
└── router.py        # POST /api/v1/notifications/token

backend/migrations/versions/
└── 0010_device_tokens.py  # device_tokens table migration
```

### Pattern 1: FCM Token Registration (Flutter)
**What:** Register FCM token on login, then re-register on every app launch and on token refresh
**When to use:** Post-authentication flow (after AuthAuthenticated state is reached)
**Example:**
```dart
// Source: https://firebase.flutter.dev/docs/messaging/usage/
Future<void> registerFcmToken() async {
  final messaging = FirebaseMessaging.instance;

  // Request permission (required on iOS 13+ and Android 13+)
  await messaging.requestPermission();

  // Get current token
  final token = await messaging.getToken();
  if (token != null) {
    await _postTokenToBackend(token);
  }

  // Refresh callback — called when FCM rotates the token
  FirebaseMessaging.instance.onTokenRefresh.listen(_postTokenToBackend);
}
```

### Pattern 2: Foreground + Background Message Handling (Flutter)
**What:** Route notification taps to the correct client job detail screen via GoRouter deep link
**When to use:** All states: foreground, background, terminated
**Example:**
```dart
// Source: https://firebase.flutter.dev/docs/messaging/usage/

// Top-level background handler (must be top-level function, not closure)
@pragma('vm:entry-point')
Future<void> _firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  await Firebase.initializeApp();
  // No UI navigation here — OS shows tray notification
}

// In main.dart — register before runApp
FirebaseMessaging.onBackgroundMessage(_firebaseMessagingBackgroundHandler);

// Notification tap while app is open (foreground)
FirebaseMessaging.onMessageOpenedApp.listen((message) {
  final jobId = message.data['job_id'];
  if (jobId != null) {
    router.go('/client/jobs/$jobId');
  }
});

// Notification tap that launched app from terminated state
final initial = await FirebaseMessaging.instance.getInitialMessage();
if (initial != null) {
  final jobId = initial.data['job_id'];
  if (jobId != null) {
    router.go('/client/jobs/$jobId');
  }
}
```

### Pattern 3: FCM Dispatch (Python backend)
**What:** NotificationService calls FCM API per user's device tokens on status transitions
**When to use:** Called from JobService.transition_status() and JobService.report_delay() inline
**Example:**
```python
# Source: https://firebase.google.com/docs/cloud-messaging/send/admin-sdk
import firebase_admin
from firebase_admin import credentials, messaging

# Initialize once at app startup (not on every request)
cred = credentials.Certificate(os.environ["GOOGLE_APPLICATION_CREDENTIALS"])
firebase_admin.initialize_app(cred)

# Send notification to a single device token
message = messaging.Message(
    notification=messaging.Notification(
        title="Job Update",
        body="Your Kitchen renovation at 123 Main St has been scheduled for Mar 15.",
    ),
    data={"job_id": str(job_id), "event": "scheduled"},
    token=device_token,
)
try:
    response = messaging.send(message)
except messaging.UnregisteredError:
    # Token is invalid — clean up from device_tokens table
    await self._remove_token(token)
except Exception as exc:
    # Fire-and-forget: log and continue (per CONTEXT.md locked decision)
    logger.error("FCM send failed: %s", exc)
```

### Pattern 4: Step Progress Bar Widget (Flutter)
**What:** Horizontal stepper showing Quote → Scheduled → In Progress → Complete → Invoiced
**When to use:** Top of ClientJobDetailScreen; cancelled jobs show banner instead
**Example:**
```dart
// Custom widget using Row + Expanded + divider lines
// JobStatus.values (ordered) already has displayLabel
// Use Theme.of(context).colorScheme.primary for active, grey for future
Widget _buildProgressStepper(JobStatus currentStatus) {
  final orderedStages = [
    JobStatus.quote,
    JobStatus.scheduled,
    JobStatus.inProgress,
    JobStatus.complete,
    JobStatus.invoiced,
  ];
  final currentIndex = orderedStages.indexOf(currentStatus);
  // ...
}
```

### Pattern 5: Delay Banner from status_history
**What:** Parse delay entries from status_history JSONB and surface as warning banner
**When to use:** ClientJobDetailScreen when job has delay entries and is not yet complete
**Example:**
```dart
// status_history entries with type='delay' are already in JobEntity.statusHistory
final delayEntries = job.statusHistory
    .where((e) => e['type'] == 'delay')
    .toList()
  ..sort((a, b) => DateTime.parse(b['timestamp']).compareTo(DateTime.parse(a['timestamp'])));

final latestDelay = delayEntries.isNotEmpty ? delayEntries.first : null;
// Show orange banner if latestDelay != null && job.status != 'complete'
```

### Pattern 6: Photo Timeline from Drift
**What:** Stream only 'uploaded' attachments of type 'photo' or 'drawing' for a job via NoteDao
**When to use:** Photos tab in ClientJobDetailScreen
**Example:**
```dart
// Reuse notesForJobProvider — filter attachments by uploadStatus
final photosForJobProvider = StreamProvider.autoDispose
    .family<List<AttachmentEntity>, String>((ref, jobId) async* {
  await for (final notes in ref.watch(notesForJobProvider(jobId).stream)) {
    final photos = notes
        .expand((n) => n.attachments)
        .where((a) =>
            a.uploadStatus == 'uploaded' &&
            a.remoteUrl != null &&
            (a.attachmentType == 'photo' || a.attachmentType == 'drawing'))
        .toList()
      ..sort((a, b) => a.createdAt.compareTo(b.createdAt));
    yield photos;
  }
});
```

### Anti-Patterns to Avoid
- **Calling FirebaseMessaging.instance.getToken() before Firebase.initializeApp():** Will throw — Firebase must be initialized in main() before runApp().
- **Registering FCM background handler inside a class method:** The background handler MUST be a top-level function (annotated with `@pragma('vm:entry-point')`). Closures or class methods silently break background delivery.
- **Sending FCM in a loop per-token:** Use `messaging.send_each_for_multicast()` for multiple tokens. However, per CONTEXT.md, fire-and-forget per token in a simple loop is acceptable for Phase 7 (no SLA on delivery).
- **firebase_admin.initialize_app() called on every request:** Must be called exactly once at app startup. Guard with `if not firebase_admin._apps:`.
- **Including firebase_admin in requirements.txt as a version range:** Pin to avoid breaking changes in the Admin SDK's FCM v1 HTTP interface.

---

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| Pinch-to-zoom photo viewer | Custom GestureDetector + TransformationController | photo_view package | Handles hero animations, double-tap-to-zoom, boundary constraints, and swipe-between-photos correctly |
| FCM token refresh management | Manual polling or timer | `FirebaseMessaging.instance.onTokenRefresh` stream | FCM rotates tokens unpredictably; the stream is the only reliable callback |
| FCM message send | Raw HTTP POST to fcm.googleapis.com | `firebase-admin` Python SDK | Admin SDK handles auth, FCM v1 API versioning, error code mapping, and token validation |
| Firebase app initialization in tests | Real Firebase connection | `firebase_admin.initialize_app()` with `App(options=...)` in test fixture | Can mock messaging calls; full Firebase connection not needed for unit tests |

**Key insight:** FCM token management is deceptively complex — tokens rotate, expire, and differ per platform. The official SDKs abstract all of this; any hand-rolled token management will miss edge cases.

---

## Common Pitfalls

### Pitfall 1: firebase_admin.initialize_app() Called Multiple Times
**What goes wrong:** `ValueError: The default Firebase app already exists` crashes the backend on hot reload or test runs.
**Why it happens:** App startup logic is called multiple times (uvicorn reloader, pytest fixtures).
**How to avoid:** Guard initialization: `if not firebase_admin._apps: firebase_admin.initialize_app(cred)`.
**Warning signs:** `ValueError` with "already exists" in logs on second startup.

### Pitfall 2: FCM Background Handler Must Be Top-Level
**What goes wrong:** Notifications are received in foreground but silently dropped when app is backgrounded/terminated.
**Why it happens:** Flutter's isolate model requires background handlers to be resolvable as top-level functions. Class methods or lambdas cannot be deserialized across isolates.
**How to avoid:** Declare `_firebaseMessagingBackgroundHandler` as a top-level function with `@pragma('vm:entry-point')` annotation.
**Warning signs:** Background notifications never arrive; no error thrown.

### Pitfall 3: Token Registration Race Condition on First Launch
**What goes wrong:** `getToken()` returns null on very first app launch before FCM registers with Google Play Services.
**Why it happens:** Token generation is async and may not complete immediately.
**How to avoid:** Always null-check `getToken()` result. The `onTokenRefresh` stream will fire when the token becomes available — register the listener before calling `getToken()`.
**Warning signs:** Null token sent to backend; POST /notifications/token silently stores null.

### Pitfall 4: Notification Tap Deep Link Not Handled on Cold Start
**What goes wrong:** Tapping a notification when the app is terminated navigates to home instead of the specific job.
**Why it happens:** `onMessageOpenedApp` stream only fires for already-running app instances. Terminated-state launch requires `getInitialMessage()`.
**How to avoid:** Call `FirebaseMessaging.instance.getInitialMessage()` in the GoRouter's `redirect` or in main() after Firebase initialization, and navigate if a message is returned.
**Warning signs:** Notification taps work when app is in background but not from cold start.

### Pitfall 5: Photo Thumbnail Shown for Pending Uploads
**What goes wrong:** Client sees a broken image placeholder for photos that haven't finished uploading.
**Why it happens:** AttachmentEntity has a `localPath` but no `remoteUrl` while uploadStatus is 'pending_upload'.
**How to avoid:** Filter strictly: `a.uploadStatus == 'uploaded' && a.remoteUrl != null`. The CONTEXT.md decision explicitly states only uploaded photos are visible to clients.
**Warning signs:** Image load errors in client photo timeline.

### Pitfall 6: Android Notification Channel Not Configured
**What goes wrong:** FCM notifications on Android 8.0+ are silently dropped without a notification channel.
**Why it happens:** Android 8+ requires an explicit `NotificationChannel` to be created before delivering notifications.
**How to avoid:** Create a default channel in `MainActivity.kt` or via `flutter_local_notifications` channel setup. `firebase_messaging` requires a default channel ID specified in `AndroidManifest.xml`.
**Warning signs:** Notifications never appear on Android physical device/emulator running API 26+.

### Pitfall 7: Sync Role Filtering — Client Receives Other Clients' Data
**What goes wrong:** All clients receive all jobs in the company via sync delta.
**Why it happens:** Current `SyncService.get_jobs_since()` uses RLS (company-scoped) but does NOT filter by client_id. All users in a company see all jobs via RLS.
**How to avoid:** In the sync endpoint, check the current user's role from JWT; if role is 'client', add `Job.client_id == current_user_id` to the WHERE clause.
**Warning signs:** Client's Drift DB contains jobs belonging to other clients.

---

## Code Examples

Verified patterns from official sources:

### Firebase Admin SDK Initialization (Python)
```python
# Source: https://firebase.google.com/docs/cloud-messaging/send/admin-sdk
import os
import firebase_admin
from firebase_admin import credentials

def initialize_firebase() -> None:
    """Initialize Firebase Admin SDK once at app startup."""
    if firebase_admin._apps:
        return  # Already initialized — idempotent guard
    cred = credentials.Certificate(os.environ["GOOGLE_APPLICATION_CREDENTIALS"])
    firebase_admin.initialize_app(cred)
```

### Send FCM Notification (Python)
```python
# Source: https://firebase.google.com/docs/cloud-messaging/send/admin-sdk
from firebase_admin import messaging

async def send_job_notification(
    token: str,
    title: str,
    body: str,
    job_id: str,
    event: str,
) -> bool:
    """Fire-and-forget notification dispatch. Returns True on success."""
    message = messaging.Message(
        notification=messaging.Notification(title=title, body=body),
        data={"job_id": job_id, "event": event},
        token=token,
    )
    try:
        messaging.send(message)
        return True
    except messaging.UnregisteredError:
        return False  # Signal: remove this token
    except Exception as exc:
        print(f"[FCM] send failed for event={event} job={job_id}: {exc}")
        return True  # Non-registration error — keep token
```

### Token Registration Endpoint (FastAPI)
```python
# New endpoint: POST /api/v1/notifications/token
@router.post("/token", status_code=204)
async def register_device_token(
    data: TokenRegisterRequest,
    db: AsyncSession = Depends(get_db),
    current_user: CurrentUser = Depends(get_current_user),
) -> None:
    svc = NotificationService(db)
    await svc.upsert_token(
        user_id=current_user.user_id,
        token=data.token,
        platform=data.platform,
    )
```

### FCM Token Registration (Flutter)
```dart
// Source: https://firebase.flutter.dev/docs/messaging/usage/
Future<void> registerFcmToken(DioClient dioClient) async {
  final messaging = FirebaseMessaging.instance;
  await messaging.requestPermission();

  final token = await messaging.getToken();
  if (token != null) {
    await _sendTokenToBackend(dioClient, token);
  }

  // Re-register when FCM rotates the token
  messaging.onTokenRefresh.listen((newToken) async {
    await _sendTokenToBackend(dioClient, newToken);
  });
}

Future<void> _sendTokenToBackend(DioClient client, String token) async {
  try {
    await client.dio.post(
      '/api/v1/notifications/token',
      data: {
        'token': token,
        'platform': Platform.isAndroid ? 'android' : 'ios',
      },
    );
  } catch (e) {
    debugPrint('[FCM] Token registration failed: $e');
  }
}
```

### deep-link routing on notification tap (Flutter)
```dart
// In GoRouter setup — handle initial message (app launched from notification)
final initialMessage = await FirebaseMessaging.instance.getInitialMessage();
if (initialMessage != null) {
  final jobId = initialMessage.data['job_id'];
  if (jobId != null && jobId.isNotEmpty) {
    initialLocation = '/client/jobs/$jobId';
  }
}

// Handle notification tap while app is in background/foreground
FirebaseMessaging.onMessageOpenedApp.listen((RemoteMessage message) {
  final jobId = message.data['job_id'];
  if (jobId != null && jobId.isNotEmpty) {
    router.go('/client/jobs/$jobId');
  }
});
```

---

## State of the Art

| Old Approach | Current Approach | When Changed | Impact |
|--------------|------------------|--------------|--------|
| FCM Legacy HTTP API (firebase-admin < 5.x) | FCM v1 API (firebase-admin 6.x+) | 2024 — Legacy API deprecated | Admin SDK now uses v1 automatically; no code change needed |
| Separate `firebase_core` init in each screen | Single `Firebase.initializeApp()` in `main()` | FlutterFire stable release | Must initialize once; all plugins share the same app instance |
| `messaging.sendMulticast()` | `messaging.send_each_for_multicast()` | firebase-admin ~6.0 | Old method renamed; same semantics |

**Deprecated/outdated:**
- `FirebaseMessaging.configure()`: Removed in firebase_messaging v9. Use `FirebaseMessaging.onMessage`, `onMessageOpenedApp`, `onBackgroundMessage` instead.
- FCM Legacy HTTP API (`https://fcm.googleapis.com/fcm/send`): Deprecated June 2023, shut down June 2024. Admin SDK handles v1 automatically.

---

## Open Questions

1. **GOOGLE_APPLICATION_CREDENTIALS for local dev vs. production**
   - What we know: Firebase Admin SDK requires a service account JSON file path in environment.
   - What's unclear: How does this work in Docker/CI — is the JSON file baked in or mounted?
   - Recommendation: Add `GOOGLE_APPLICATION_CREDENTIALS` to `.env` pointing to a `firebase-service-account.json` file in `backend/`. Add the JSON file to `.gitignore`. Document in Wave 0.

2. **`google-services.json` / `GoogleService-Info.plist` placement**
   - What we know: Required files for Android and iOS Firebase initialization.
   - What's unclear: Not present in the repo yet. Must be downloaded from Firebase Console.
   - Recommendation: Create as Wave 0 blocker. The Android file goes to `mobile/android/app/google-services.json`; iOS to `mobile/ios/Runner/GoogleService-Info.plist`.

3. **Notification tap routing when client role accesses `/client/jobs/:id`**
   - What we know: GoRouter Branch 6 currently only has `/client/portal` and `/client/request`. A new `/client/jobs/:id` route is needed for deep-link navigation.
   - What's unclear: Should this be a sub-route of `/client/portal` or a top-level push route?
   - Recommendation: Add `/client/jobs/:id` as a nested route under Branch 6 (consistent with admin `/jobs/:id` pattern). The route name constant goes in `RouteNames`.

4. **Sync delta filtering by client role**
   - What we know: Current `SyncService.get_jobs_since()` uses RLS (company-scoped) but all company users see all jobs.
   - What's unclear: `current_user` is available in the sync router from JWT. Need to verify the correct SQLAlchemy WHERE clause pattern.
   - Recommendation: In `SyncService`, accept an optional `client_user_id` param. The sync router passes it when the JWT role is 'client'. Add `.where(Job.client_id == client_user_id)` filter.

---

## Validation Architecture

### Test Framework
| Property | Value |
|----------|-------|
| Framework | pytest (backend) + flutter_test / mocktail (mobile) |
| Config file | `backend/pyproject.toml` (asyncio_mode=auto) |
| Quick run command | `cd backend && uv run python -m pytest tests/ -x -q` |
| Full suite command | `cd backend && uv run python -m pytest tests/ && cd ../mobile && flutter test` |

### Phase Requirements → Test Map
| Req ID | Behavior | Test Type | Automated Command | File Exists? |
|--------|----------|-----------|-------------------|-------------|
| CLNT-02 | FCM token registered on login | unit | `flutter test test/features/notifications/fcm_token_test.dart` | ❌ Wave 0 |
| CLNT-02 | NotificationService.send() called on job scheduled transition | integration | `uv run python -m pytest tests/test_phase_7_e2e.py::test_notification_on_scheduled -x` | ❌ Wave 0 |
| CLNT-02 | NotificationService.send() called on job in_progress transition | integration | `uv run python -m pytest tests/test_phase_7_e2e.py::test_notification_on_in_progress -x` | ❌ Wave 0 |
| CLNT-02 | NotificationService.send() called on job complete transition | integration | `uv run python -m pytest tests/test_phase_7_e2e.py::test_notification_on_complete -x` | ❌ Wave 0 |
| CLNT-02 | NotificationService.send() called on delay report | integration | `uv run python -m pytest tests/test_phase_7_e2e.py::test_notification_on_delay -x` | ❌ Wave 0 |
| CLNT-02 | Invalid FCM token cleaned up (401 from FCM) | unit | `uv run python -m pytest tests/test_notification_service.py::test_token_cleanup -x` | ❌ Wave 0 |
| CLNT-03 | Client portal shows job list filtered to current user | E2E widget | `flutter test test/e2e/phase_7_client_portal_e2e_test.dart` | ❌ Wave 0 |
| CLNT-03 | ClientJobDetailScreen shows step progress bar | E2E widget | `flutter test test/e2e/phase_7_client_portal_e2e_test.dart::progress_stepper` | ❌ Wave 0 |
| CLNT-03 | Photos tab shows only uploaded attachments | E2E widget | `flutter test test/e2e/phase_7_client_portal_e2e_test.dart::photo_timeline` | ❌ Wave 0 |
| CLNT-03 | Role gating: client cannot access admin/contractor routes | E2E widget | `flutter test test/e2e/phase_7_client_portal_e2e_test.dart::role_gating` | ❌ Wave 0 |
| CLNT-05 | Delay banner shows on active job with delay in status_history | E2E widget | `flutter test test/e2e/phase_7_client_portal_e2e_test.dart::delay_banner` | ❌ Wave 0 |
| CLNT-05 | Sync delta filters jobs by client_id for client role | integration | `uv run python -m pytest tests/test_phase_7_e2e.py::test_sync_client_role_filter -x` | ❌ Wave 0 |

### Sampling Rate
- **Per task commit:** `cd backend && uv run python -m pytest tests/ -x -q -m 'not slow'`
- **Per wave merge:** `cd backend && uv run python -m pytest tests/ && cd ../mobile && flutter test`
- **Phase gate:** Full suite green before `/gsd:verify-work`

### Wave 0 Gaps
- [ ] `mobile/test/e2e/phase_7_client_portal_e2e_test.dart` — covers CLNT-03, CLNT-05
- [ ] `backend/tests/test_phase_7_e2e.py` — covers CLNT-02, CLNT-05 backend
- [ ] `backend/tests/test_notification_service.py` — unit tests for NotificationService
- [ ] Firebase project setup: `mobile/android/app/google-services.json` and `mobile/ios/Runner/GoogleService-Info.plist` (manual step — download from Firebase Console)
- [ ] Backend env var: `GOOGLE_APPLICATION_CREDENTIALS` pointing to service account JSON
- [ ] `backend/firebase-service-account.json` added to `.gitignore`

---

## Sources

### Primary (HIGH confidence)
- [firebase.flutter.dev/docs/messaging/usage](https://firebase.flutter.dev/docs/messaging/usage/) — FlutterFire official FCM usage guide; token registration, foreground/background handlers
- [pub.dev/packages/firebase_messaging](https://pub.dev/packages/firebase_messaging) — Latest version 16.1.2 confirmed
- [pub.dev/packages/firebase_core](https://pub.dev/packages/firebase_core) — Latest version 4.5.0 confirmed
- [firebase.google.com/docs/cloud-messaging/send/admin-sdk](https://firebase.google.com/docs/cloud-messaging/send/admin-sdk) — Python Admin SDK send patterns

### Secondary (MEDIUM confidence)
- Existing codebase — `ClientPortalScreen`, `NoteEntity`, `AttachmentEntity`, `JobService`, `SyncService`, `JobDao` inspected directly; all integration points confirmed
- `07-CONTEXT.md` — all locked decisions verified against codebase

### Tertiary (LOW confidence)
- photo_view package selection — based on community knowledge; verify latest version compatibility with Flutter SDK >=3.8.0 before use

---

## Metadata

**Confidence breakdown:**
- Standard stack: HIGH — pub.dev versions confirmed, official Firebase docs consulted
- Architecture: HIGH — existing codebase inspected directly; integration points identified precisely
- Pitfalls: HIGH — pitfalls verified against official Firebase docs and existing codebase patterns
- FCM Python patterns: HIGH — official Firebase Admin SDK documentation confirmed

**Research date:** 2026-03-12
**Valid until:** 2026-04-12 (Firebase SDK versions move quickly — re-verify if >30 days)
