# Phase 6: Field Workflow - Context

**Gathered:** 2026-03-11
**Status:** Ready for planning

<domain>
## Phase Boundary

Contractors can capture job notes, photos, GPS location, sketches, and time on-site from their mobile device — all while offline — and the data syncs when connectivity returns. This phase builds field tools on top of Phase 4's job detail screen and Phase 2's offline sync engine.

Requirements: FIELD-01, FIELD-02, FIELD-03, FIELD-04

</domain>

<decisions>
## Implementation Decisions

### Job Notes Model
- Timestamped log of immutable note entries (not the existing single notes field)
- Each entry: text (max 2000 chars), timestamp, author, optional attachments (photos/PDFs/drawings)
- Newest first display order
- No categories or tags — plain text entries, fast for field use
- No editing or deletion after save — like an audit log
- Contractor + Admin can add notes; clients are view-only (Phase 7 portal)
- Per-job scope only — notes belong to individual jobs, not aggregated on client profile
- System keyboard dictation for voice input (no custom voice feature)
- Existing `notes` field on JobEntity kept as "Admin Notes" — editable summary on Details tab, separate from field notes

### Job Notes UI
- New 4th tab on job detail: Details | Schedule | Notes | History
- Notes tab shows timestamped field note log with inline photo/PDF thumbnails
- Badge count on Notes tab for unread notes (new notes since last admin view)
- Quick-add note from contractor job card action bar — opens minimal bottom sheet with text field + attachment options
- "Add Note" bottom sheet includes: text field, camera button, gallery button, PDF picker, drawing pad launcher

### Photo Capture & Storage
- Camera + gallery + PDF document picker (image_picker + file_picker)
- Supported formats: JPG, PNG, PDF
- Up to 10 attachments per note entry
- Optional one-line caption per attachment
- Auto-compress photos: 2K resolution max, 90% JPEG quality (~500KB-1MB per photo)
- Auto-embed GPS coordinates in photo metadata when captured via camera
- Thumbnails generated locally for fast display in note entries
- Thumbnail + compressed view on tap (no original full-resolution retained)
- Backend storage: local filesystem via /files/ endpoint (not S3 for v1)
- Drawings saved as PNG, treated same as photos in storage

### GPS Address Capture
- "Capture Location" button on job detail Details tab
- Available to both contractor and admin roles
- Tapping gets device GPS coordinates, reverse-geocodes to street address via backend ORS on sync
- Offline: store raw lat/lng immediately, display as coordinates, geocode to address when data syncs
- Store both geocoded address string AND raw coordinates (enables future map features)
- Graceful fallback when GPS permission denied: message explaining why + link to settings, address field remains manually editable
- Confirm dialog before overwriting an existing address with GPS-captured location

### Drawing Pad
- Freehand blank canvas (white background), full-screen overlay
- Supports landscape orientation (only screen in app that does — rest is portrait-only per Phase 5)
- Tools: pen, eraser, text tool, shapes (line, rectangle, circle, arrow)
- 8 preset colors: black, red, blue, green, orange, purple, brown, white
- 3 pen thickness presets: thin (1px), medium (3px), thick (6px)
- Text tool with free-size slider (no fixed presets)
- 3 fixed layers: Background (grid), Drawing, Text & Shapes — toggle visibility per layer
- Optional grid overlay toggle (grid not included in saved PNG)
- Canvas resolution matches device screen (1:1 mapping)
- Saved as final PNG — no re-editing after save (immutable, consistent with notes)
- Drawing attached to note entry (same as photos), not standalone
- Accessed from "Add Note" attachment options, not directly from job card

### Time Tracking
- Dedicated timer screen with large elapsed time display, clock in/out button, and session history
- One job at a time — clocking in to a new job auto-clocks out of the current one
- No break tracking — contractor clocks out for breaks, clocks back in (separate sessions)
- Clock in on Scheduled job auto-transitions to In Progress (recorded in status_history)
- Clock out does NOT auto-complete — contractor may return tomorrow
- Multiple sessions per job — total time = sum of all sessions
- Admin can edit/adjust time entry start/end times (with audit trail)
- Billable vs non-billable categorization deferred to Phase 8
- Cross-job daily time summary deferred to Phase 8 reporting dashboard

### Admin Time Visibility
- Time tracked section added to existing Schedule tab on job detail
- Shows all clock sessions grouped by date with start/end times and durations
- Total time summary (per-day and overall total)
- Per-job time only in Phase 6 — aggregate reporting in Phase 8

### Contractor Job Card Redesign
- Action bar at bottom of each job card: [Add Note] [Camera] [Clock In/Out]
- Active (clocked-in) job card: highlighted border + pinned to top of list + elapsed timer display
- Drawing pad accessed from within "Add Note" flow, not as separate card button
- Status transitions (Start, Complete) via long-press on status badge (not in action bar)
- Complete job cards: dimmed, show total tracked time, no action bar
- Contextual buttons based on job status (Clock In for Scheduled, Clock Out when active)

### Sync Strategy for Attachments
- Text-first sync: job status changes, note text, time entries, GPS coordinates sync before file uploads
- Photos/drawings/PDFs upload after all text data syncs
- Upload on any connection (WiFi or cellular) — compressed files are manageable on 4G
- 3 retries with exponential backoff (5s, 15s, 45s) for failed uploads, then park for next cycle
- Sync status indicator shows separate counts: "3 items synced, 5 photos uploading (2/5)"

### Claude's Discretion
- Drift table schema for job_notes and time_entries
- Backend API endpoint design for notes, attachments, time entries
- Sync handler registration for new entity types
- Drawing pad Flutter package selection (custom Canvas vs library)
- File upload endpoint implementation (multipart form data)
- Thumbnail generation approach
- Timer screen navigation (route or bottom sheet)
- Exact compression implementation details
- GPS permission request flow and timing

</decisions>

<specifics>
## Specific Ideas

- Contractor job cards should feel like a field dashboard — "what am I working on, how long have I been here, quick capture" at a glance
- The "Add Note" bottom sheet is the hub for all field capture: text + camera + gallery + PDF + drawing — one entry point, multiple attachment types
- Notes are immutable audit logs — like a job diary that can't be edited after the fact, which builds trust with clients and protects contractors
- Active job card pinned to top with highlighted border should be immediately obvious — "this is what you're doing right now"
- GPS capture should be one tap — contractor arrives at site, taps Capture Location, done. Address appears after sync.
- Drawing pad with landscape support is unique in the app — site layout sketches need the wider canvas

</specifics>

<code_context>
## Existing Code Insights

### Reusable Assets
- `JobEntity` (Freezed) with `notes` field — kept as admin summary, new field notes are separate entity
- `JobDao` with sync queue dual-write pattern — template for new NoteDao and TimeEntryDao
- `image_picker` dependency already added (Phase 4 gap closure)
- `JobDetailScreen` with TabController — extend from 3 to 4 tabs
- `ContractorJobsScreen` with job cards — add action bar to existing cards
- `DelayJustificationDialog` pattern — bottom sheet with form fields + save, template for Add Note bottom sheet
- `status_history` JSONB pattern on JobEntity — similar structured entry approach for notes
- ORS geocoding backend from Phase 3 — reverse geocode GPS coordinates to addresses
- `SyncEngine` + `SyncHandler` pattern — register new handlers for notes, time_entries, attachments
- `ConnectivityService` — check connection type for upload decisions
- `BookingDao.createBooking()` convenience method pattern — use for NoteDao/TimeEntryDao

### Established Patterns
- Feature-first Flutter structure: `lib/features/<domain>/`
- Drift streams + StreamProvider for reactive UI
- AsyncNotifier for state management
- UUID client-generated PKs for offline-first
- Sync queue dual-write in transactions
- ConsumerWidget/ConsumerStatefulWidget for all screens
- GetIt service locator for DAOs in dialogs/bottom sheets

### Integration Points
- Job detail TabController: extend from 3 to 4 tabs (add Notes)
- Contractor job cards: add action bar with Note/Camera/Clock buttons
- Drift migration v4→v5: add job_notes, time_entries, attachments tables
- SyncEngine: register note, time_entry, attachment sync handlers
- Sync status provider: extend to show separate text/file upload counts
- GoRouter: add route for timer screen
- AppDatabase: add NoteDao, TimeEntryDao accessors
- Backend: new endpoints for notes CRUD, file upload, time entries, GPS geocode-on-sync

</code_context>

<deferred>
## Deferred Ideas

- Photo annotation (draw on top of photos) — future enhancement to drawing pad
- Before/After photo tagging — could enhance Phase 7 client portal photo timeline
- Voice recording attachment (not dictation) — audio notes for complex descriptions
- Full document management (arbitrary file types beyond images/PDFs) — its own feature
- Aggregate time reporting across jobs — Phase 8 reporting dashboard (BIZ-04)
- Billable vs non-billable time categorization — Phase 8 business operations
- Auto-clock-in on GPS geofence proximity — advanced feature, needs geofencing infrastructure
- Cross-job client note timeline — aggregate notes from all jobs for a client on CRM detail

</deferred>

---

*Phase: 06-field-workflow*
*Context gathered: 2026-03-11*
