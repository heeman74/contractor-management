# Phase 6: Field Workflow - Research

**Researched:** 2026-03-11
**Domain:** Flutter offline-first field capture (notes, photos, GPS, drawing, time tracking) + FastAPI file endpoints
**Confidence:** HIGH

---

<user_constraints>
## User Constraints (from CONTEXT.md)

### Locked Decisions

**Job Notes Model**
- Timestamped log of immutable note entries (not the existing single notes field)
- Each entry: text (max 2000 chars), timestamp, author, optional attachments (photos/PDFs/drawings)
- Newest first display order
- No categories or tags — plain text entries, fast for field use
- No editing or deletion after save — like an audit log
- Contractor + Admin can add notes; clients are view-only (Phase 7 portal)
- Per-job scope only — notes belong to individual jobs
- System keyboard dictation for voice input (no custom voice feature)
- Existing `notes` field on JobEntity kept as "Admin Notes" — editable summary on Details tab

**Job Notes UI**
- New 4th tab on job detail: Details | Schedule | Notes | History
- Notes tab shows timestamped field note log with inline photo/PDF thumbnails
- Badge count on Notes tab for unread notes (new notes since last admin view)
- Quick-add note from contractor job card action bar — opens minimal bottom sheet
- "Add Note" bottom sheet includes: text field, camera button, gallery button, PDF picker, drawing pad launcher

**Photo Capture & Storage**
- Camera + gallery + PDF document picker (image_picker + file_picker)
- Supported formats: JPG, PNG, PDF
- Up to 10 attachments per note entry
- Optional one-line caption per attachment
- Auto-compress photos: 2K resolution max, 90% JPEG quality (~500KB-1MB per photo)
- Auto-embed GPS coordinates in photo metadata when captured via camera
- Thumbnails generated locally for fast display
- Thumbnail + compressed view on tap (no original full-resolution retained)
- Backend storage: local filesystem via /files/ endpoint (not S3 for v1)
- Drawings saved as PNG, treated same as photos in storage

**GPS Address Capture**
- "Capture Location" button on job detail Details tab
- Available to both contractor and admin roles
- Tapping gets device GPS, reverse-geocodes to street address via backend ORS on sync
- Offline: store raw lat/lng immediately, display as coordinates, geocode to address when data syncs
- Store both geocoded address string AND raw coordinates
- Graceful fallback when GPS permission denied: message + link to settings, address field remains manually editable
- Confirm dialog before overwriting an existing address with GPS-captured location

**Drawing Pad**
- Freehand blank canvas (white background), full-screen overlay
- Supports landscape orientation only (rest of app is portrait-only per Phase 5)
- Tools: pen, eraser, text tool, shapes (line, rectangle, circle, arrow)
- 8 preset colors: black, red, blue, green, orange, purple, brown, white
- 3 pen thickness presets: thin (1px), medium (3px), thick (6px)
- Text tool with free-size slider
- 3 fixed layers: Background (grid), Drawing, Text & Shapes — toggle visibility per layer
- Optional grid overlay toggle (grid not included in saved PNG)
- Canvas resolution matches device screen (1:1 mapping)
- Saved as final PNG — no re-editing after save (immutable)
- Drawing attached to note entry (same as photos), not standalone
- Accessed from "Add Note" attachment options only

**Time Tracking**
- Dedicated timer screen with large elapsed time display, clock in/out button, and session history
- One job at a time — clocking in to new job auto-clocks out of current one
- No break tracking — clock out for breaks, back in as separate sessions
- Clock in on Scheduled job auto-transitions to In Progress (recorded in status_history)
- Clock out does NOT auto-complete — contractor may return tomorrow
- Multiple sessions per job — total time = sum of all sessions
- Admin can edit/adjust time entry start/end times (with audit trail)
- Billable vs non-billable deferred to Phase 8
- Cross-job daily time summary deferred to Phase 8

**Admin Time Visibility**
- Time tracked section added to existing Schedule tab on job detail
- Shows all clock sessions grouped by date with start/end times and durations
- Total time summary (per-day and overall total)
- Per-job time only in Phase 6

**Contractor Job Card Redesign**
- Action bar at bottom of each job card: [Add Note] [Camera] [Clock In/Out]
- Active (clocked-in) job card: highlighted border + pinned to top + elapsed timer display
- Drawing pad accessed from within "Add Note" flow only
- Status transitions via long-press on status badge (not in action bar)
- Complete job cards: dimmed, show total tracked time, no action bar
- Contextual buttons based on job status

**Sync Strategy for Attachments**
- Text-first sync: job status changes, note text, time entries, GPS coordinates sync before file uploads
- Photos/drawings/PDFs upload after all text data syncs
- Upload on any connection (WiFi or cellular)
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

### Deferred Ideas (OUT OF SCOPE)
- Photo annotation (draw on top of photos)
- Before/After photo tagging
- Voice recording attachment
- Full document management (arbitrary file types beyond images/PDFs)
- Aggregate time reporting across jobs (Phase 8)
- Billable vs non-billable time categorization (Phase 8)
- Auto-clock-in on GPS geofence proximity
- Cross-job client note timeline
</user_constraints>

---

<phase_requirements>
## Phase Requirements

| ID | Description | Research Support |
|----|-------------|-----------------|
| FIELD-01 | Job notes and photo capture (timestamped, offline-capable) | NoteDao + AttachmentDao + NoteSyncHandler + AttachmentSyncHandler + file upload endpoint patterns documented |
| FIELD-02 | GPS-based address capture for property locations | geolocator 14.0.2 usage pattern documented; ORS reverse geocode already in backend (ors_geocoder.py); GPS column additions to Jobs table |
| FIELD-03 | Drawing/handwriting pad for sketches and handwritten notes | flutter_drawing_board 1.0.1+2 with landscape lock documented; PNG export pattern; integration with note attachment flow |
| FIELD-04 | Time tracking (clock in/out per job) | TimeEntryDao + TimeEntrySyncHandler + timer UI patterns; active session state management; one-job-at-a-time enforcement |
</phase_requirements>

---

## Summary

Phase 6 builds on a mature offline-first foundation (Phase 2 SyncEngine, Phase 4 JobDao dual-write pattern) to add field capture capabilities. The architecture is well-understood: create new Drift tables (job_notes, time_entries, attachments), new DAOs following the BookingDao pattern, register new SyncHandlers, and extend the sync endpoint with new entity types.

The key complexity in this phase is the **two-tier sync strategy**: text data (notes, time entries, GPS) flows through the existing sync queue as JSON, while file attachments require a separate multipart upload path outside the normal sync queue. This requires a dedicated AttachmentUploadQueue table and upload-specific handler that operates after text sync completes.

GPS capture is straightforward — the `geolocator` package (v14.0.2, 6050+ likes) handles device location; the backend already has ORS reverse geocoding in `ors_geocoder.py`. The drawing pad uses `flutter_drawing_board` (v1.0.1+2, MIT, 160 pub points) which provides all required tools (pen, eraser, shapes, text) and PNG export — landscape lock via `SystemChrome.setPreferredOrientations` during the pad screen lifecycle.

**Primary recommendation:** Follow the BookingDao dual-write pattern exactly for NoteDao and TimeEntryDao. Add a dedicated AttachmentUploadQueue Drift table (separate from sync_queue) for file uploads with their own retry logic; this keeps the existing SyncEngine clean and lets file upload status be tracked independently.

---

## Standard Stack

### Core (all already in pubspec.yaml)
| Library | Version | Purpose | Why Standard |
|---------|---------|---------|--------------|
| drift | ^2.32.0 | NoteDao, TimeEntryDao, AttachmentDao local persistence | Established project pattern |
| image_picker | ^1.1.2 | Camera capture + gallery selection | Already added (Phase 4 gap closure) |
| flutter_riverpod | ^3.2.1 | AsyncNotifier for timer state, StreamProviders for notes | Established project state management |
| dio | ^5.9.2 | Multipart file upload to /files/ endpoint | Established network client |
| connectivity_plus | ^7.0.0 | Upload-on-any-connection gating | Already in use |

### New Dependencies Required
| Library | Version | Purpose | Why |
|---------|---------|---------|-----|
| flutter_drawing_board | ^1.0.1+2 | Drawing pad with pen, eraser, shapes, text, PNG export | 160 pub points, MIT license, verified publisher (fluttercandies.com), all required tools built-in |
| geolocator | ^14.0.2 | GPS coordinate capture, permission management | 6050+ likes, 1.26M downloads, standard for Flutter location |
| flutter_image_compress | ^2.4.0 | JPEG compression to 2K max / 90% quality before upload | 573k weekly downloads, supports keepExif for GPS metadata |
| file_picker | ^10.3.10 | PDF document picker | Supports `allowedExtensions: ['pdf']` on Android + iOS |

### Alternatives Considered
| Instead of | Could Use | Tradeoff |
|------------|-----------|----------|
| flutter_drawing_board | Custom CustomPainter canvas | Custom canvas would need to implement shapes, text tool, layers, and PNG export from scratch — 2+ days; flutter_drawing_board has all of these with palm rejection |
| flutter_image_compress | image package (pure Dart) | Pure Dart image package is ~10x slower on large photos; flutter_image_compress uses native APIs on Android/iOS for speed |
| geolocator | location package | geolocator has 4x more downloads and is the defacto standard; both work but geolocator has better permission flow helpers |

**Installation:**
```bash
# From mobile/ directory
flutter pub add flutter_drawing_board geolocator flutter_image_compress file_picker
```

**Android permissions to add to AndroidManifest.xml:**
```xml
<uses-permission android:name="android.permission.ACCESS_FINE_LOCATION"/>
<uses-permission android:name="android.permission.ACCESS_COARSE_LOCATION"/>
```

**iOS permissions to add to Info.plist:**
```xml
<key>NSLocationWhenInUseUsageDescription</key>
<string>ContractorHub uses your location to capture the job site address.</string>
```

**Backend: add python-multipart to pyproject.toml** (required for FastAPI UploadFile; verify it is already present — jobs router already uses multipart for photo upload on job requests).

---

## Architecture Patterns

### Drift Schema — New Tables (Migration v4 → v5)

**job_notes table:**
```dart
// lib/core/database/tables/job_notes.dart
class JobNotes extends Table {
  TextColumn get id => text().clientDefault(() => const Uuid().v4())();
  TextColumn get companyId => text()();       // tenant scope
  TextColumn get jobId => text()();           // FK to Jobs.id
  TextColumn get authorId => text()();        // FK to Users.id
  TextColumn get body => text()();            // max 2000 chars enforced in UI
  IntColumn get version => integer().withDefault(const Constant(1))();
  DateTimeColumn get createdAt => dateTime()();
  DateTimeColumn get updatedAt => dateTime()();
  DateTimeColumn get deletedAt => dateTime().nullable()();  // tombstone
  @override
  Set<Column> get primaryKey => {id};
}
```

**attachments table:**
```dart
// lib/core/database/tables/attachments.dart
class Attachments extends Table {
  TextColumn get id => text().clientDefault(() => const Uuid().v4())();
  TextColumn get companyId => text()();
  TextColumn get noteId => text()();          // FK to JobNotes.id
  // 'photo' | 'pdf' | 'drawing'
  TextColumn get attachmentType => text()();
  TextColumn get localPath => text()();       // absolute path to compressed file on device
  TextColumn get thumbnailPath => text().nullable()();
  TextColumn get caption => text().nullable()();
  // 'pending_upload' | 'uploading' | 'uploaded' | 'failed'
  TextColumn get uploadStatus => text().withDefault(const Constant('pending_upload'))();
  TextColumn get remoteUrl => text().nullable()();  // set after successful upload
  IntColumn get sortOrder => integer().withDefault(const Constant(0))();
  DateTimeColumn get createdAt => dateTime()();
  DateTimeColumn get updatedAt => dateTime()();
  DateTimeColumn get deletedAt => dateTime().nullable()();
  @override
  Set<Column> get primaryKey => {id};
}
```

**time_entries table:**
```dart
// lib/core/database/tables/time_entries.dart
class TimeEntries extends Table {
  TextColumn get id => text().clientDefault(() => const Uuid().v4())();
  TextColumn get companyId => text()();
  TextColumn get jobId => text()();           // FK to Jobs.id
  TextColumn get contractorId => text()();    // FK to Users.id
  DateTimeColumn get clockedInAt => dateTime()();
  DateTimeColumn get clockedOutAt => dateTime().nullable()();  // null = active session
  IntColumn get durationSeconds => integer().nullable()();     // null = active session
  // 'active' | 'completed' | 'adjusted'
  TextColumn get sessionStatus => text().withDefault(const Constant('active'))();
  // JSON: [{adjusted_at, adjusted_by, original_start, original_end, reason}]
  TextColumn get adjustmentLog => text().withDefault(const Constant('[]'))();
  IntColumn get version => integer().withDefault(const Constant(1))();
  DateTimeColumn get createdAt => dateTime()();
  DateTimeColumn get updatedAt => dateTime()();
  DateTimeColumn get deletedAt => dateTime().nullable()();
  @override
  Set<Column> get primaryKey => {id};
}
```

**Jobs table GPS columns (addColumn in migration v5):**
```dart
// Add to existing Jobs table:
RealColumn get gpsLatitude => real().nullable()();
RealColumn get gpsLongitude => real().nullable()();
TextColumn get gpsAddress => text().nullable()();   // null = geocode pending
```

### AppDatabase Migration v4 → v5

```dart
// In AppDatabase.migration onUpgrade:
if (from < 5) {
  await m.createTable(jobNotes);
  await m.createTable(attachments);
  await m.createTable(timeEntries);
  await m.addColumn(jobs, jobs.gpsLatitude);
  await m.addColumn(jobs, jobs.gpsLongitude);
  await m.addColumn(jobs, jobs.gpsAddress);
}
```

### Backend Database Migration 0009

New tables: `job_notes`, `attachments`, `time_entries`. GPS columns added to `jobs`.

```sql
-- job_notes
CREATE TABLE job_notes (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    company_id UUID NOT NULL REFERENCES companies(id),
    job_id UUID NOT NULL REFERENCES jobs(id),
    author_id UUID NOT NULL REFERENCES users(id),
    body TEXT NOT NULL,
    version INTEGER NOT NULL DEFAULT 1,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    deleted_at TIMESTAMPTZ
);
CREATE TRIGGER set_updated_at BEFORE UPDATE ON job_notes
    FOR EACH ROW EXECUTE FUNCTION set_updated_at();
ALTER TABLE job_notes ENABLE ROW LEVEL SECURITY;
-- RLS policy same pattern as jobs table (company_id = current_setting)

-- attachments
CREATE TABLE attachments (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    company_id UUID NOT NULL REFERENCES companies(id),
    note_id UUID NOT NULL REFERENCES job_notes(id),
    attachment_type TEXT NOT NULL CHECK (attachment_type IN ('photo','pdf','drawing')),
    remote_url TEXT,
    caption TEXT,
    sort_order INTEGER NOT NULL DEFAULT 0,
    version INTEGER NOT NULL DEFAULT 1,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    deleted_at TIMESTAMPTZ
);
ALTER TABLE attachments ENABLE ROW LEVEL SECURITY;

-- time_entries
CREATE TABLE time_entries (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    company_id UUID NOT NULL REFERENCES companies(id),
    job_id UUID NOT NULL REFERENCES jobs(id),
    contractor_id UUID NOT NULL REFERENCES users(id),
    clocked_in_at TIMESTAMPTZ NOT NULL,
    clocked_out_at TIMESTAMPTZ,
    duration_seconds INTEGER,
    session_status TEXT NOT NULL DEFAULT 'active'
        CHECK (session_status IN ('active','completed','adjusted')),
    adjustment_log JSONB NOT NULL DEFAULT '[]'::jsonb,
    version INTEGER NOT NULL DEFAULT 1,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    deleted_at TIMESTAMPTZ
);
ALTER TABLE time_entries ENABLE ROW LEVEL SECURITY;

-- GPS columns on jobs
ALTER TABLE jobs ADD COLUMN gps_latitude NUMERIC(9,6);
ALTER TABLE jobs ADD COLUMN gps_longitude NUMERIC(9,6);
ALTER TABLE jobs ADD COLUMN gps_address TEXT;
```

### Pattern 1: NoteDao — Dual-Write Outbox

Follows BookingDao exactly. Text note CREATE goes to sync_queue. Attachments go to a separate upload queue tracked via the attachments table `uploadStatus` column.

```dart
// Source: existing BookingDao pattern
Future<void> insertNote(JobNotesCompanion entry) async {
  await db.transaction(() async {
    await into(jobNotes).insert(entry);
    await into(syncQueue).insert(
      _buildQueueEntry(
        entityType: 'job_note',
        entityId: entry.id.value,
        operation: 'CREATE',
        payload: {
          'id': entry.id.value,
          'company_id': entry.companyId.value,
          'job_id': entry.jobId.value,
          'author_id': entry.authorId.value,
          'body': entry.body.value,
          'version': 1,
          'created_at': DateTime.now().toIso8601String(),
        },
      ),
    );
  });
}
```

### Pattern 2: Attachment Upload — Separate from Sync Queue

Attachments are NOT routed through sync_queue (JSON). They use Dio multipart upload directly. Upload is triggered by AttachmentUploadService after text sync completes.

```dart
// AttachmentUploadService.uploadPending()
// Called by SyncEngine after drainQueue() — text-first, then files
Future<void> uploadPending() async {
  final pending = await attachmentDao.getPendingUploads();
  for (final att in pending) {
    try {
      await attachmentDao.setUploadStatus(att.id, 'uploading');
      final formData = FormData.fromMap({
        'file': await MultipartFile.fromFile(
          att.localPath,
          filename: '${att.id}.${_ext(att.attachmentType)}',
        ),
        'note_id': att.noteId,
        'attachment_type': att.attachmentType,
        if (att.caption != null) 'caption': att.caption,
      });
      final response = await _dioClient.dio.post('/files/upload', data: formData);
      final remoteUrl = response.data['url'] as String;
      await attachmentDao.markUploaded(att.id, remoteUrl);
    } on DioException catch (e) {
      // 3 retries with 5s/15s/45s backoff — park after max
      await attachmentDao.incrementRetry(att.id);
    }
  }
}
```

### Pattern 3: GPS Capture Flow

```dart
// GPS capture in job detail Details tab
Future<void> captureGps(BuildContext context, JobEntity job, WidgetRef ref) async {
  // 1. Check permission
  LocationPermission permission = await Geolocator.checkPermission();
  if (permission == LocationPermission.denied) {
    permission = await Geolocator.requestPermission();
  }
  if (permission == LocationPermission.deniedForever) {
    // Show snackbar with settings link
    if (context.mounted) _showPermissionDeniedMessage(context);
    return;
  }

  // 2. Confirm overwrite if address exists
  if (job.address != null && context.mounted) {
    final confirmed = await _showOverwriteDialog(context);
    if (!confirmed) return;
  }

  // 3. Get position
  final position = await Geolocator.getCurrentPosition(
    locationSettings: const LocationSettings(accuracy: LocationAccuracy.high),
  );

  // 4. Store lat/lng immediately (offline-capable); address resolved on sync
  await jobDao.updateJobGps(
    jobId: job.id,
    latitude: position.latitude,
    longitude: position.longitude,
    address: null,  // pending geocode
  );

  // 5. Enqueue GPS update to sync_queue — backend will geocode and return address
}
```

Backend geocode-on-sync: When the sync handler receives a job UPDATE with `gps_latitude`/`gps_longitude` and `gps_address: null`, call `ORSGeocodingProvider.reverse_geocode()` and update the job record with the resolved address.

### Pattern 4: Drawing Pad — flutter_drawing_board Integration

```dart
// DrawingPadScreen wraps flutter_drawing_board
// Landscape lock: setPreferredOrientations during initState/dispose
@override
void initState() {
  super.initState();
  SystemChrome.setPreferredOrientations([
    DeviceOrientation.landscapeLeft,
    DeviceOrientation.landscapeRight,
  ]);
  _controller = DrawingController();
}

@override
void dispose() {
  SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
  _controller.dispose();
  super.dispose();
}

// Save PNG:
Future<Uint8List?> _saveDrawing() async {
  final imageData = await _controller.getImageData();
  if (imageData == null) return null;
  // Write to temp file → return path
  final tempDir = await getTemporaryDirectory();
  final file = File('${tempDir.path}/${const Uuid().v4()}.png');
  await file.writeAsBytes(imageData.buffer.asUint8List());
  return imageData.buffer.asUint8List();
}
```

The `flutter_drawing_board` DrawingController provides: `.getImageData()` (returns ByteData as PNG), undo/redo, and all drawing tools. The 3-layer requirement (Background grid, Drawing, Text & Shapes) maps to custom layer management — the grid overlay is rendered by a CustomPainter behind the DrawingBoard and excluded from PNG export by capturing only the DrawingController's canvas.

### Pattern 5: Timer State Management

Active timer state: an AsyncNotifier that tracks the currently-active time entry. The timer ticks every second via a Timer.periodic inside the notifier.

```dart
// TimerNotifier: AsyncNotifier<TimerState>
// TimerState: {activeEntry: TimeEntryEntity?, elapsedSeconds: int}
//
// clockIn(jobId):
//   1. If another job is active, clockOut that job first
//   2. Create TimeEntryEntity with clockedInAt = now, clockedOutAt = null
//   3. Write to Drift + sync_queue
//   4. If job was Scheduled, transition to In Progress via jobDao.updateJobStatus
//   5. Start Timer.periodic(1 second) → update elapsedSeconds
//
// clockOut():
//   1. Stop Timer.periodic
//   2. Compute durationSeconds = now - clockedInAt
//   3. Update TimeEntryEntity: clockedOutAt = now, durationSeconds, status = completed
//   4. Write to Drift + sync_queue (UPDATE operation)
```

The active time entry is persisted to Drift with `clockedOutAt = null` — on app restart, the timer screen reads the active entry from Drift and resumes the display (elapsedSeconds = now - clockedInAt).

### Pattern 6: Sync Handler Registration

Three new SyncHandlers registered in `SyncRegistry` (following existing handler pattern):

| Handler | entityType | Push | Pull |
|---------|------------|------|------|
| `NoteSyncHandler` | `job_note` | POST /api/v1/jobs/{job_id}/notes | upsert job_notes |
| `TimeEntrySyncHandler` | `time_entry` | POST /api/v1/jobs/{job_id}/time-entries (CREATE) / PATCH (UPDATE) | upsert time_entries |
| (GPS goes through existing JobSyncHandler as a job UPDATE) | — | PATCH /api/v1/jobs/{job_id} with gps fields | existing job upsert |

Attachments are NOT in SyncRegistry — they use the separate `AttachmentUploadService` path.

### Pattern 7: Sync Endpoint Extension

The backend `GET /api/v1/sync` response gets new fields (Phase 6 additions):

```python
# In sync/schemas.py SyncResponse — add with default=[] for backwards compatibility
job_notes: list[JobNoteResponse] = []
time_entries: list[TimeEntryResponse] = []
# Attachments: pull-down only via attachment metadata (remoteUrl returned)
attachments: list[AttachmentResponse] = []
```

### Backend File Storage Pattern (already established in jobs router)

The jobs router already saves uploaded files to `uploads/job_requests/{request_id}/` using `aiofiles`. Phase 6 follows the same pattern:

```python
# POST /api/v1/files/upload  (new endpoint in a new files router)
@router.post("/upload", status_code=201)
async def upload_attachment(
    file: UploadFile = File(...),
    note_id: str = Form(...),
    attachment_type: str = Form(...),
    caption: str | None = Form(default=None),
    _current_user: CurrentUser = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    upload_dir = Path("uploads") / "attachments" / note_id
    upload_dir.mkdir(parents=True, exist_ok=True)
    dest = upload_dir / f"{uuid4()}{Path(file.filename).suffix}"
    async with aiofiles.open(dest, "wb") as f:
        content = await file.read()
        await f.write(content)
    remote_url = f"/files/attachments/{note_id}/{dest.name}"
    # Insert attachment record in DB, return remote_url
    ...
```

Static file serving via `app.mount("/files", StaticFiles(directory="uploads"), name="files")` in `main.py`.

### Recommended Project Structure Extensions

```
mobile/lib/
├── core/database/tables/
│   ├── job_notes.dart           # new
│   ├── attachments.dart         # new
│   └── time_entries.dart        # new
├── core/sync/handlers/
│   ├── note_sync_handler.dart       # new
│   └── time_entry_sync_handler.dart # new
├── features/
│   └── jobs/
│       ├── data/
│       │   ├── note_dao.dart        # new
│       │   ├── attachment_dao.dart  # new
│       │   └── time_entry_dao.dart  # new
│       ├── domain/
│       │   ├── note_entity.dart     # new (Freezed)
│       │   ├── attachment_entity.dart # new (Freezed)
│       │   └── time_entry_entity.dart # new (Freezed)
│       ├── presentation/
│       │   ├── providers/
│       │   │   ├── note_providers.dart    # new
│       │   │   └── timer_providers.dart   # new
│       │   ├── screens/
│       │   │   ├── timer_screen.dart      # new — GoRoute, not bottom sheet
│       │   │   └── drawing_pad_screen.dart # new — GoRoute with landscape lock
│       │   └── widgets/
│       │       ├── notes_tab.dart          # new — 4th tab content
│       │       ├── add_note_bottom_sheet.dart # new
│       │       ├── attachment_thumbnail.dart  # new
│       │       └── time_tracked_section.dart  # new — for Schedule tab

backend/
├── migrations/versions/0009_field_workflow_tables.py  # new
├── app/features/
│   ├── jobs/
│   │   ├── models.py       # extend Job model: gps_latitude, gps_longitude, gps_address
│   │   ├── schemas.py      # add JobNoteCreate, JobNoteResponse, TimeEntryCreate, etc.
│   │   ├── router.py       # add note + time entry endpoints
│   │   └── service.py      # add note/time entry methods
│   └── files/
│       ├── __init__.py
│       └── router.py       # POST /files/upload, GET /files/* (StaticFiles mount)
```

### Anti-Patterns to Avoid

- **Using sync_queue for file uploads:** File uploads are binary; sync_queue is JSON text. Keep them separate — the AttachmentUploadService handles files independently.
- **Polling for active timer:** Use Timer.periodic inside the AsyncNotifier, not a StreamProvider polling Drift every second (wastes query cycles).
- **Direct `DateTime.now()` in timer without drift clock:** For testability, pass a clock parameter or use `package:clock` — but given existing codebase uses DateTime.now() directly in DAOs, maintain consistency.
- **Landscape lock without restore on dispose:** Always restore portrait-up in the DrawingPadScreen dispose() — failure to restore locks the whole app in landscape.
- **GPS without permission check every time:** Permissions can be revoked between sessions. Always call `checkPermission()` before `getCurrentPosition()`.
- **Showing spinner while getting GPS:** GPS can take 2-5 seconds. Show a loading indicator with "Getting location..." so the user knows to wait.

---

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| Drawing canvas with shapes + text + PNG export | Custom CustomPainter with all tools | `flutter_drawing_board` | Bezier interpolation, palm rejection, undo/redo, JSON serialization, and PNG export all built-in |
| GPS permission + location fetch | Manual platform channel + permission dialogs | `geolocator` | Permission flow helpers (requestPermission, openAppSettings), platform-specific accuracy handling |
| JPEG compression preserving GPS EXIF | dart:convert + raw JPEG manipulation | `flutter_image_compress` | Native API on Android/iOS — 10x faster than pure Dart; `keepExif: true` parameter |
| PDF document picking | File browse via platform channel | `file_picker` with `allowedExtensions: ['pdf']` | Handles Storage Access Framework (Android 13+) and iOS document picker |
| Multipart file upload | Raw HTTP client with form boundary | `Dio FormData.fromMap` + `MultipartFile.fromFile` | Handles chunking, Content-Type headers, stream vs. byte array automatically |

---

## Common Pitfalls

### Pitfall 1: Attachment Upload Ordering (Text-First)
**What goes wrong:** Attachment sync handler fires before note text is synced, so the backend receives an attachment for a note that doesn't exist yet (FK violation).
**Why it happens:** SyncEngine drains the queue in FIFO order; if an attachment is queued before the note's text sync is committed, the order breaks.
**How to avoid:** The attachment upload is NOT in sync_queue. The `AttachmentUploadService.uploadPending()` is called only AFTER `SyncEngine.drainQueue()` completes. The SyncEngine's `syncNow()` method calls these sequentially.
**Warning signs:** 422 errors from backend saying "note not found" on attachment upload.

### Pitfall 2: Active Timer Survives App Kill
**What goes wrong:** Timer state is only in memory; if the app is killed while clocked in, the elapsed time is lost.
**How to avoid:** Persist the active TimeEntryEntity to Drift with `clockedOutAt = null` immediately on clock-in. On app restart, `TimerNotifier.build()` reads Drift for any active session and resumes the elapsed time display as `DateTime.now() - clockedInAt`.
**Warning signs:** Timer shows 0:00 after app restart even though contractor is clocked in.

### Pitfall 3: Drawing Pad Landscape Lock Not Restored
**What goes wrong:** User closes drawing pad but app stays in landscape mode.
**Why it happens:** `SystemChrome.setPreferredOrientations` persists globally; calling it in `initState` without reversing in `dispose` permanently locks landscape.
**How to avoid:** Always call `SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp])` in DrawingPadScreen's `dispose()`.

### Pitfall 4: GPS Geocode Before Sync Completes
**What goes wrong:** Contractor taps "Capture Location" offline; expects to see the geocoded address immediately.
**How to avoid:** Store raw lat/lng immediately and display "Coordinates: 40.7128°N 74.0060°W (address pending sync)". Backend geocodes on sync and returns the resolved address in the next sync pull. UI updates reactively when the jobs stream emits the updated record.

### Pitfall 5: One-Job-at-a-Time Clock-In Enforcement
**What goes wrong:** Contractor clocks into a second job without clocking out of the first; creates two active sessions.
**How to avoid:** In `TimerNotifier.clockIn(jobId)`: first query Drift for any `time_entries` row where `contractorId = currentUser` AND `clockedOutAt IS NULL`. If found, clock out that session before creating the new one — in a single Drift transaction.
**Warning signs:** Multiple rows with `clocked_out_at = null` for same contractor.

### Pitfall 6: flutter_drawing_board PNG Export Includes Grid
**What goes wrong:** The grid overlay (grid toggle feature) appears in the saved PNG.
**Why it happens:** If the grid is rendered inside the DrawingController canvas, it gets included in `getImageData()`.
**How to avoid:** Render the grid as a separate `CustomPaint` widget BEHIND the `DrawingBoard` widget in the widget tree. `getImageData()` only captures the DrawingController's canvas, not the surrounding widget tree.

### Pitfall 7: file_picker on Android 13+
**What goes wrong:** `file_picker` returns a content URI, not a file path. `flutter_image_compress` (and most file libraries) expect a file path.
**How to avoid:** Use `file_picker` with `withData: true` OR copy the picked file to the app's temp directory first using `path_provider`. The `localPath` stored in the Attachments table should always be an absolute path in the app's support directory, not a content URI.

### Pitfall 8: Drift pump() vs pumpAndSettle() in Tests
**What goes wrong:** `pumpAndSettle()` hangs indefinitely in widget tests that have Drift Stream providers.
**How to avoid:** Use `pump()` with explicit durations for Drift stream-backed providers. This is already documented in project MEMORY.md: "NEVER use `pumpAndSettle()` — Drift streams never settle."

### Pitfall 9: Attachment thumbnails block UI thread
**What goes wrong:** Generating thumbnails from large images on the main isolate causes UI jank.
**How to avoid:** Use `compute()` (Flutter's isolate helper) for compression/thumbnail generation, or use `flutter_image_compress` which already uses native threads on Android/iOS.

---

## Code Examples

Verified patterns from official sources and existing codebase:

### GPS Permission + Location Fetch (geolocator 14.0.2)
```dart
// Source: https://pub.dev/packages/geolocator
Future<Position?> captureLocation(BuildContext context) async {
  bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
  if (!serviceEnabled) {
    // Show snackbar: "Enable location services in Settings"
    return null;
  }

  LocationPermission permission = await Geolocator.checkPermission();
  if (permission == LocationPermission.denied) {
    permission = await Geolocator.requestPermission();
    if (permission == LocationPermission.denied) return null;
  }
  if (permission == LocationPermission.deniedForever) {
    // Show action with openAppSettings()
    await Geolocator.openAppSettings();
    return null;
  }

  return await Geolocator.getCurrentPosition(
    locationSettings: const LocationSettings(
      accuracy: LocationAccuracy.high,
      timeLimit: Duration(seconds: 15),
    ),
  );
}
```

### Image Compression (flutter_image_compress 2.4.0)
```dart
// Source: https://pub.dev/packages/flutter_image_compress
// keepExif: true preserves GPS metadata embedded by the camera
Future<Uint8List?> compressPhoto(File file) async {
  return await FlutterImageCompress.compressWithFile(
    file.absolute.path,
    minWidth: 2048,     // 2K max width
    minHeight: 2048,    // 2K max height
    quality: 90,        // 90% JPEG quality
    format: CompressFormat.jpeg,
    keepExif: true,     // Preserve GPS metadata
  );
}
```

### Drawing Pad PNG Export (flutter_drawing_board 1.0.1+2)
```dart
// Source: https://pub.dev/packages/flutter_drawing_board
final DrawingController _controller = DrawingController();

// In DrawingPadScreen save action:
Future<String?> _saveToDisk() async {
  final data = await _controller.getImageData();
  if (data == null) return null;
  final bytes = data.buffer.asUint8List();
  final dir = await getApplicationSupportDirectory();
  final path = '${dir.path}/drawings/${const Uuid().v4()}.png';
  await Directory('${dir.path}/drawings').create(recursive: true);
  await File(path).writeAsBytes(bytes);
  return path;
}

// Widget usage:
DrawingBoard(
  controller: _controller,
  background: Container(color: Colors.white, width: 800, height: 600),
)
```

### Multipart File Upload with Dio
```dart
// Source: Dio docs + existing DioClient pattern in codebase
Future<String> uploadAttachment({
  required String localPath,
  required String noteId,
  required String attachmentType,
  String? caption,
}) async {
  final formData = FormData.fromMap({
    'file': await MultipartFile.fromFile(
      localPath,
      filename: '${const Uuid().v4()}${path.extension(localPath)}',
    ),
    'note_id': noteId,
    'attachment_type': attachmentType,
    if (caption != null) 'caption': caption,
  });
  final response = await _dioClient.dio.post(
    '/files/upload',
    data: formData,
    options: Options(contentType: 'multipart/form-data'),
  );
  return response.data['url'] as String;
}
```

### SyncEngine Extension for Attachment Upload
```dart
// In SyncEngine.syncNow() — text-first, then files
Future<void> syncNow() async {
  await pullDelta();
  await drainQueue();                    // text entities first
  await getIt<AttachmentUploadService>().uploadPending(); // files second
}
```

### Existing Backend Reverse Geocode (already in codebase)
```python
# Source: backend/app/features/scheduling/geocoding/ors_geocoder.py
# Already available — reverse_geocode(lat, lng) -> str | None
# Called in the job sync handler when gps_address is null and coordinates are present:
async def _geocode_if_needed(job: Job, geocoder: ORSGeocodingProvider) -> None:
    if job.gps_latitude and job.gps_longitude and not job.gps_address:
        address = await geocoder.reverse_geocode(
            float(job.gps_latitude), float(job.gps_longitude)
        )
        if address:
            job.gps_address = address
```

---

## State of the Art

| Old Approach | Current Approach | When Changed | Impact |
|--------------|------------------|--------------|--------|
| Custom canvas drawing (CustomPainter only) | `flutter_drawing_board` with built-in tools | 2023+ | 160 pub points, MIT, verified publisher, all required tools built-in |
| `location` package for GPS | `geolocator` 14.x | Standard since 2022 | 6050+ likes, cleaner permission API, `openAppSettings()` helper |
| S3 for file storage | Local filesystem + StaticFiles mount (v1 pattern) | Established pattern in existing jobs router | Simpler for v1; S3 migration is a config change |
| Storing full resolution photos | Compress to 2K/90% JPEG before storage | Current best practice | ~500KB-1MB per photo manageable on 4G sync |

**Deprecated/outdated:**
- `location` package: superseded by `geolocator` for standard use cases
- Storing raw `content://` URIs from file_picker: must copy to app directory for cross-session stability

---

## Validation Architecture

nyquist_validation is enabled (config.json `workflow.nyquist_validation: true`).

### Test Framework
| Property | Value |
|----------|-------|
| Framework | Flutter test + mocktail (existing) |
| Config file | none — flutter test is configured via pubspec.yaml |
| Quick run command | `flutter test test/unit/features/jobs/` |
| Full suite command | `flutter test` |
| Backend quick run | `uv run python -m pytest tests/test_jobs.py -x` |
| Backend full suite | `uv run python -m pytest` |

### Phase Requirements → Test Map

| Req ID | Behavior | Test Type | Automated Command | File Exists? |
|--------|----------|-----------|-------------------|-------------|
| FIELD-01 | NoteDao.insertNote writes to job_notes + sync_queue in transaction | unit (Drift in-memory) | `flutter test test/unit/features/jobs/note_dao_test.dart -x` | Wave 0 |
| FIELD-01 | AttachmentDao.markUploaded sets remoteUrl + uploadStatus=uploaded | unit (Drift in-memory) | `flutter test test/unit/features/jobs/attachment_dao_test.dart -x` | Wave 0 |
| FIELD-01 | AddNoteBottomSheet submits note with text + attachment | widget | `flutter test test/widget/features/jobs/add_note_bottom_sheet_test.dart -x` | Wave 0 |
| FIELD-01 | NotesTab renders note list newest-first | widget | `flutter test test/widget/features/jobs/notes_tab_test.dart -x` | Wave 0 |
| FIELD-01 | POST /jobs/{id}/notes creates note + syncs | backend integration | `uv run python -m pytest tests/test_field_workflow.py::test_create_note -x` | Wave 0 |
| FIELD-02 | GPS capture stores lat/lng immediately when offline | unit | `flutter test test/unit/features/jobs/gps_capture_test.dart -x` | Wave 0 |
| FIELD-02 | Permission denied shows snackbar + settings link | widget | `flutter test test/widget/features/jobs/gps_capture_widget_test.dart -x` | Wave 0 |
| FIELD-02 | Confirm dialog shown when overwriting existing address | widget | `flutter test test/widget/features/jobs/gps_overwrite_dialog_test.dart -x` | Wave 0 |
| FIELD-02 | Backend geocodes coordinates to address during job UPDATE sync | backend integration | `uv run python -m pytest tests/test_field_workflow.py::test_gps_geocode_on_sync -x` | Wave 0 |
| FIELD-03 | DrawingPadScreen sets landscape on init, restores portrait on dispose | widget | `flutter test test/widget/features/jobs/drawing_pad_screen_test.dart -x` | Wave 0 |
| FIELD-03 | Saved drawing PNG path stored as attachment with type=drawing | unit | `flutter test test/unit/features/jobs/drawing_save_test.dart -x` | Wave 0 |
| FIELD-04 | TimeEntryDao.clockIn writes to time_entries + sync_queue | unit (Drift in-memory) | `flutter test test/unit/features/jobs/time_entry_dao_test.dart -x` | Wave 0 |
| FIELD-04 | clockIn to new job auto-clocks out existing session | unit | `flutter test test/unit/features/jobs/time_entry_dao_test.dart::auto_clock_out -x` | Wave 0 |
| FIELD-04 | TimerScreen shows elapsed time + clock out button when active | widget | `flutter test test/widget/features/jobs/timer_screen_test.dart -x` | Wave 0 |
| FIELD-04 | TimerNotifier restores active session on rebuild (app restart simulation) | unit | `flutter test test/unit/features/jobs/timer_notifier_test.dart -x` | Wave 0 |
| FIELD-04 | POST /jobs/{id}/time-entries clock-in creates active session | backend integration | `uv run python -m pytest tests/test_field_workflow.py::test_time_entry_clock_in -x` | Wave 0 |

### Sampling Rate
- **Per task commit:** `flutter test test/unit/features/jobs/ && uv run python -m pytest tests/test_field_workflow.py -x`
- **Per wave merge:** `flutter test && uv run python -m pytest`
- **Phase gate:** Full suite green before `/gsd:verify-work`

### Wave 0 Gaps (all test files need creation)
- [ ] `mobile/test/unit/features/jobs/note_dao_test.dart` — REQ FIELD-01
- [ ] `mobile/test/unit/features/jobs/attachment_dao_test.dart` — REQ FIELD-01
- [ ] `mobile/test/unit/features/jobs/gps_capture_test.dart` — REQ FIELD-02
- [ ] `mobile/test/unit/features/jobs/drawing_save_test.dart` — REQ FIELD-03
- [ ] `mobile/test/unit/features/jobs/time_entry_dao_test.dart` — REQ FIELD-04
- [ ] `mobile/test/unit/features/jobs/timer_notifier_test.dart` — REQ FIELD-04
- [ ] `mobile/test/widget/features/jobs/add_note_bottom_sheet_test.dart` — REQ FIELD-01
- [ ] `mobile/test/widget/features/jobs/notes_tab_test.dart` — REQ FIELD-01
- [ ] `mobile/test/widget/features/jobs/gps_capture_widget_test.dart` — REQ FIELD-02
- [ ] `mobile/test/widget/features/jobs/gps_overwrite_dialog_test.dart` — REQ FIELD-02
- [ ] `mobile/test/widget/features/jobs/drawing_pad_screen_test.dart` — REQ FIELD-03
- [ ] `mobile/test/widget/features/jobs/timer_screen_test.dart` — REQ FIELD-04
- [ ] `backend/tests/test_field_workflow.py` — backend integration tests for all FIELD reqs
- [ ] New packages installed: `flutter pub add flutter_drawing_board geolocator flutter_image_compress file_picker`

---

## Open Questions

1. **Timer Screen Navigation: GoRoute vs Bottom Sheet**
   - What we know: timer needs elapsed time display that updates every second; go_router routes persist across tab switches; bottom sheets are dismissed on back
   - What's unclear: should the timer be accessible while viewing other parts of the job, or does pushing a new route work?
   - Recommendation: Use a GoRoute `/jobs/:id/timer` — consistent with `scheduleSettings` pattern; pushed from job card action bar; contractor can back-navigate to job list with timer still "running" in background (TimerNotifier is a singleton via GetIt or `keepAlive`)

2. **Attachment Table in sync_queue vs. Separate Upload Queue**
   - What we know: attachments need retry logic with 3 attempts + backoff; uploadStatus tracked in the `attachments` table itself
   - What's unclear: whether to reuse SyncEngine retry infrastructure or build a separate AttachmentUploadService
   - Recommendation: Separate AttachmentUploadService that reads from the `attachments` table directly. Reusing sync_queue would require binary data in a JSON column (impossible). The `uploadStatus` column on the attachments table IS the upload queue.

3. **Unread Badge Count for Notes Tab**
   - What we know: "badge count on Notes tab for unread notes (new notes since last admin view)"
   - What's unclear: where to store the "last viewed" timestamp per job per user — a new `note_read_receipts` table, or a column on job or user?
   - Recommendation: Add a `notesLastViewedAt` column to the local Jobs Drift table (client-side only — no sync needed). Badge count = count of notes with `createdAt > notesLastViewedAt`. Simple, no backend changes.

---

## Sources

### Primary (HIGH confidence)
- Existing codebase: `BookingDao`, `BookingSyncHandler`, `ORSGeocodingProvider`, `SyncRegistry` — patterns directly applicable
- https://pub.dev/packages/geolocator — version 14.0.2, usage patterns
- https://pub.dev/packages/flutter_drawing_board — version 1.0.1+2, features, PNG export
- https://pub.dev/packages/flutter_image_compress — version 2.4.0, keepExif parameter
- https://pub.dev/packages/file_picker — version 10.3.10, PDF support
- https://fastapi.tiangolo.com/tutorial/request-files/ — FastAPI UploadFile + aiofiles pattern

### Secondary (MEDIUM confidence)
- WebSearch: flutter_drawing_board vs custom CustomPainter tradeoffs — multiple sources confirm library approach for production apps
- WebSearch: GPS permission flow patterns for geolocator — confirmed by official pub.dev docs
- WebSearch: FastAPI local filesystem file serving via StaticFiles — confirmed by official FastAPI docs

### Tertiary (LOW confidence)
- WebSearch: flutter_image_compress vs image package performance comparison — single source, but platform-native vs pure Dart advantage is well-established

---

## Metadata

**Confidence breakdown:**
- Standard stack: HIGH — packages verified on pub.dev with version numbers and download counts
- Architecture: HIGH — all patterns derived from existing codebase (BookingDao, BookingSyncHandler, ORSGeocodingProvider) which are proven in production
- Pitfalls: HIGH — most derived from actual code inspection of existing patterns; drawing pad landscape pitfall confirmed by SystemChrome API docs

**Research date:** 2026-03-11
**Valid until:** 2026-04-11 (30 days; stable libraries, established patterns)
