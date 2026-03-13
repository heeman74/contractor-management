# Phase 7: Client Portal and Notifications - Context

**Gathered:** 2026-03-12
**Status:** Ready for planning

<domain>
## Phase Boundary

Clients can view live job status, progress photos, and delay reasons through a client-facing portal, and receive push notifications at every significant job milestone. The portal is role-gated — no contractor or admin data is accessible from the client view.

Requirements: CLNT-02, CLNT-03, CLNT-05

</domain>

<decisions>
## Implementation Decisions

### Job Status Display
- Step progress bar showing lifecycle stages: Quote → Scheduled → In Progress → Complete → Invoiced
- Cancelled jobs show a "Cancelled" banner instead of the stepper
- Client-specific detail screen (NOT reusing admin JobDetailScreen): progress stepper at top, then tabs for Photos, Notes, Details
- Contractor name + trade type visible; no contact info (client contacts the company, not contractor directly)
- No pricing/cost info in Phase 7 — deferred to Phase 8 (BIZ-01, BIZ-03)
- Details tab shows both scheduled date/time window AND expected completion date (ETA)

### Portal List (Home Screen)
- Keep existing status badge on job cards; add ETA date beneath the status chip
- Completed/invoiced jobs: dimmed with green checkmark — clearly "done"
- "Pending Requests" section at top when pending/declined requests exist; hidden when empty
- Pending request cards show: description, preferred dates, urgency, submission date, status (Pending/Accepted/Declined)
- Declined requests stay visible with red badge and admin's decline reason; can be dismissed manually
- "Request More Info" status shows admin's message; client cannot reply in-app (consistent with Phase 4: no edits after submit)
- Accepted requests disappear from pending section; new job appears in main active list
- Keep existing "Request Job" FAB for new submissions

### Photo Timeline (Photos Tab)
- Chronological feed showing photos and drawings (no PDFs — those are internal)
- Each entry shows: photo/drawing thumbnail, caption (if any), timestamp
- Full note body NOT shown — captions only; full notes in the Notes tab
- Tap opens full-screen viewer with pinch-to-zoom, swipe between photos, download button to save to device gallery
- Only uploaded photos shown (upload_status='uploaded' with valid remote_url); no pending uploads visible to clients
- Photo count badge on Photos tab
- Empty state: camera icon + "No progress photos yet — photos will appear here as work progresses."

### Delay Visibility
- Orange/yellow warning banner at top of client job detail screen: delay reason + original ETA → new ETA comparison
- Expandable delay history for jobs with multiple delays — latest shown by default, "View previous delays" to expand
- Banner persists until job reaches Complete status
- Small orange warning icon + updated ETA on job card in portal list
- Delays appear as system entries in the Notes tab (orange icon, "Delay reported" header) alongside contractor notes and status transitions

### Client Notes Tab (Activity Log)
- Read-only for clients — no commenting ability
- Shows chronologically: contractor field notes (text + attachment count), delay events (system entries), and status transitions (job scheduled, work started, completed)
- Complete activity log — client sees the full story of their job

### Push Notifications (FCM)
- Firebase Cloud Messaging for real push notifications
- Four triggers: job scheduled, work started (In Progress), job completed, job delayed
- Clients only in Phase 7 — admin/contractor notifications deferred
- FCM token registered for ALL users at login (infrastructure supports future role expansion)
- Token registration on every app launch + onTokenRefresh callback → POST /api/v1/notifications/token
- No notification preferences in Phase 7 — all four types always sent
- Tapping notification deep-links to the specific job's client detail screen
- OS notification tray only — no in-app notification center/history
- Notification body includes milestone event + job description (e.g., "Your job 'Kitchen renovation at 123 Main St' has been scheduled for Mar 15.")

### FCM Backend Architecture
- Inline dispatch in service layer — JobService calls NotificationService.send() on status transitions and delays
- Firebase Admin SDK (Python) for FCM API interaction
- New device_tokens table: user_id, token, platform (android/ios), created_at, last_used_at; multiple tokens per user (multiple devices)
- Fire-and-forget on FCM API failure — log error to stdout, don't retry
- No notification_log table — stdout logging only for v1
- Token cleanup on 401/invalid token response from FCM

### Role Gating Enforcement
- Client portal lives in its own GoRouter branch — separate from admin/contractor routes
- Client-specific providers only fetch client-visible data (jobs where client_id = current user)
- Backend enforcement: API endpoints filter by client_id from JWT (defense in depth)
- Sync delta endpoint checks role — clients only receive their own jobs, notes, and attachments
- Same SyncEngine, backend filters response by role — no new sync infrastructure

### Offline Behavior
- Show cached data from Drift DB with "Last updated: X ago" relative time indicator (switches to date after 24 hours)
- Pull-to-refresh attempts sync
- Photos: thumbnails cached by Flutter image cache; full-size fetched on-demand when tapped
- Job request submission works offline — queued to Drift + sync queue, consistent with offline-first architecture

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

</decisions>

<specifics>
## Specific Ideas

- The step progress bar should give clients confidence — "I can see exactly where my job is in the process"
- Photo timeline is a key trust-builder — clients see tangible proof of progress without calling the contractor
- Delay transparency (original ETA → new ETA comparison) communicates honestly without being alarming
- The Notes tab as a complete activity log (notes + delays + milestones) tells the full story of the job like a diary
- Pending requests section gives clients visibility into what happens after they submit — no more "did they get my request?"
- Push notifications close the loop — client doesn't need to keep opening the app to check for updates

</specifics>

<code_context>
## Existing Code Insights

### Reusable Assets
- `ClientPortalScreen` (Phase 4): existing job list with status cards, "Request Job" FAB, RefreshIndicator — enhance, don't rebuild
- `_JobCard` widget with status colors and icons — extend with ETA and delay indicator
- `clientJobHistoryNotifierProvider` — existing provider for client's jobs, streams from Drift
- `NoteEntity` + `AttachmentEntity` (Phase 6): Freezed models with all fields needed for client display
- `AttachmentUploadService` (Phase 6): upload status tracking, remote URLs for photos
- `JobStatus` enum with `displayLabel` and color mapping — reuse for progress stepper
- `status_history` JSONB on JobEntity: delay entries `{type: "delay", reason, new_eta, timestamp}` ready to parse
- `SyncEngine` + `SyncHandler` pattern: add role-based filtering to existing sync delta endpoint
- `DelayJustificationDialog` (Phase 5): delay data already persisted to status_history
- `JobDao`, `NoteDao` (Phase 6): Drift DAOs with sync queue dual-write — query patterns for client-scoped data

### Established Patterns
- Feature-first Flutter structure: `lib/features/client/` for portal screens
- Drift streams + StreamProvider for reactive UI
- ConsumerWidget pattern for all screens
- GoRouter + StatefulShellRoute with role-based branch selection
- Pull-to-refresh via `SyncEngine.syncNow()`
- UUID client-generated PKs for offline-first
- Empty state pattern with contextual messaging
- Sync queue dual-write for offline mutations

### Integration Points
- GoRouter: client branch already exists; add client job detail route, photo viewer route
- Sync delta endpoint: add role check to filter jobs/notes/attachments by client_id
- Backend JobService: add NotificationService.send() calls on status transitions
- Backend: new device_tokens table (Alembic migration), token registration endpoint, NotificationService
- Mobile: firebase_messaging + firebase_core Flutter packages
- Mobile: FCM token registration in auth flow (post-login)
- ClientPortalScreen: enhance existing screen with pending requests section and updated job cards

</code_context>

<deferred>
## Deferred Ideas

- Admin/contractor push notifications — separate phase or Phase 9
- In-app notification center with bell icon and unread count — future enhancement
- Per-type notification preferences (toggle which notifications to receive) — future enhancement
- Client commenting/replying to notes — approaches messaging (explicitly out of scope per REQUIREMENTS.md)
- notification_log table for analytics — add when needed
- Before/After photo tagging in timeline — noted in Phase 6 deferred ideas
- Client rating of completed jobs from portal — Phase 4 already has mutual ratings model

</deferred>

---

*Phase: 07-client-portal-and-notifications*
*Context gathered: 2026-03-12*
