# Phase 22: Task Execution and Photo Annotation - Research

**Researched:** 2026-03-24
**Domain:** Flutter mobile task execution, photo annotation (CustomPainter + JSON), web canvas annotation (HTML5 Canvas), FastAPI attachment endpoints, Drift DAO patterns
**Confidence:** HIGH

---

<user_constraints>
## User Constraints (from CONTEXT.md)

### Locked Decisions
- **D-01:** Checklist cards — card per task with checkbox, title, priority badge, time estimate, photo-required indicator. Grouped by trade scope with progress header.
- **D-02:** Tap checkbox to complete — status syncs to GC immediately via outbox pattern.
- **D-03:** Block completion until photo added — when `photo_required=true` and no photo attached, checkbox shows camera icon instead of checkmark.
- **D-04:** All scopes, grouped — single "My Tasks" screen shows all assigned tasks across all trade scopes, grouped by scope with collapsible headers.
- **D-05:** All incomplete tasks — show all incomplete tasks ordered by priority then due date. Overdue tasks highlighted at top. No date-based filtering.
- **D-06:** Overlay on photo — open photo in full-screen viewer, tap "Annotate" to enter draw mode with tools overlaying the photo. Pinch-to-zoom supported. Save stores original + annotation layer separately (non-destructive).
- **D-07:** Essential tools: Arrow, Circle/highlight, Text labels, Measurement ruler — all four required. Arrow and circle exist in DrawingPadScreen. Text rendering needs completion. Measurement ruler is new.
- **D-08:** JSON annotation layer — store annotations as JSON (tool type, coordinates, color, text, measurement value). Render on-the-fly over original photo. Non-destructive, toggleable, editable later.
- **D-09:** Web can annotate too — canvas-based annotation on web using same JSON format. Full tool set. Important for GC inspection flow in Phase 24.
- **D-10:** Scrollable detail page — full screen with Header, Details, Notes, Photos, Attachments sections. Bottom bar has "Add Photo" and "Mark Done" buttons.
- **D-11:** Inline text input for notes — TextField at top of Notes section, tap "+" to add. Timestamped, newest first, immutable after save.
- **D-12:** Grid gallery + FAB for photos — 3-column grid thumbnails. Annotated photos have pencil badge overlay. Tap thumbnail for full-screen viewer with "Annotate" button.
- **D-13:** 10 photos + 5 PDFs per task — attachment limits.
- **D-14:** Project detail with trade cards — trade color dot, name, X/Y task count, percentage progress bar, last activity timestamp + contractor name.
- **D-15:** Thumbnails in task list — small photo thumbnails (2-3 max) on each task card in GC's view.
- **D-16:** Batch digest notifications — group task completions into periodic digests. FCM infrastructure already exists.

### Claude's Discretion
- Photo compression settings for task attachments (existing pattern: 2K max, 90% quality)
- PDF viewer implementation (in-app webview vs native viewer vs intent)
- Measurement ruler UX (tap-two-points, drag-to-draw, unit selection)
- Offline behavior for attachment sync (outbox queue pattern already established)
- Annotation JSON schema structure (coordinate system, tool serialization format)
- Web annotation canvas library choice (HTML5 Canvas, fabric.js, or similar)
- Task note model (new table vs reuse existing Note pattern adapted for tasks)
- Progress bar animation and color thresholds

### Deferred Ideas (OUT OF SCOPE)
None — discussion stayed within phase scope
</user_constraints>

<phase_requirements>
## Phase Requirements

| ID | Description | Research Support |
|----|-------------|-----------------|
| TASK-01 | Contractor can view their daily AI-generated checklist on mobile | MyTasksScreen with cross-scope grouping, StreamProvider reading TaskDao.watchTasksForUser |
| TASK-02 | Contractor can check off checklist items as they complete tasks | Checkbox toggle → TaskDao.updateTask(status: complete) → sync queue → PATCH /tasks/{id} |
| TASK-03 | Contractor can add progress notes (text) to any task | New TaskNote Drift table (mirrors Note pattern); TaskNoteDao; PATCH or POST /tasks/{id}/notes |
| TASK-04 | Contractor can capture and attach photos to tasks | ImagePicker + compressPhoto() → TaskAttachmentDao; POST /tasks/{id}/attachments file upload |
| TASK-05 | Contractor can draw annotations on photos (arrows, circles, text, measurements) | Adapt DrawingPadScreen to photo-overlay mode; JSON annotation schema; annotation_data JSONB column on TaskAttachment |
| TASK-06 | Contractor can attach PDF documents to tasks | file_picker → copy to local → TaskAttachmentDao(type: document); same upload endpoint |
| TASK-07 | GC can view task progress across all trades from mobile | Enhanced ProjectDetailScreen with TradeScopeProgressCard using countTasksByScope |
</phase_requirements>

---

## Summary

Phase 22 builds on top of well-established infrastructure from Phases 19-21. The Task and TaskAttachment models already exist in the database (migration 0015), the Drift tables are defined, and the TaskDao provides reactive streams. What is missing is: (1) the contractor-facing "My Tasks" screen with cross-scope grouping, (2) the task detail page with notes/photos/attachments, (3) the photo annotation overlay (adapting DrawingPadScreen), (4) a new JSON annotation storage layer on TaskAttachment, (5) backend endpoints for task notes and task attachment uploads, (6) the GC progress monitoring view, and (7) web canvas annotation.

The existing `DrawingPadScreen` provides arrow, circle, line, rectangle, and pen tools in a CustomPainter architecture. Adapting it for photo-overlay annotation requires: loading the photo as a background image in the canvas, implementing proper text rendering (currently placeholder), adding a measurement ruler tool (draw a line + inline text label), and changing save behavior from PNG export to JSON serialization. The annotation JSON must be stored non-destructively alongside the original photo — a new `annotation_data` JSONB column on `task_attachments`.

The web annotation canvas (D-09) must use HTML5 Canvas directly (via `useRef<HTMLCanvasElement>`) since no canvas annotation library is in the current web `package.json` and adding fabric.js introduces significant bundle weight for a feature used infrequently. The same JSON annotation schema used on mobile can drive web rendering. No new npm packages are required.

**Primary recommendation:** Adapt existing DrawingPadScreen to photo-overlay mode, store annotations as JSONB on TaskAttachment, build web canvas annotation with plain HTML5 Canvas API, use the existing outbox sync pattern for all mutations.

---

## Standard Stack

### Core (already in project — no new installs needed)
| Library | Version | Purpose | Why Standard |
|---------|---------|---------|--------------|
| drift | ^2.32.0 | Reactive SQLite DAO for task notes, attachments | Established in project; TaskAttachments table exists |
| flutter_riverpod | ^3.2.1 | State management for task/attachment providers | All project screens use this pattern |
| image_picker | ^1.1.2 | Camera + gallery photo capture | Used in AddNoteBottomSheet |
| flutter_image_compress | ^2.4.0 | Photo compression (2K max, 90% quality) | `compressPhoto()` utility already written |
| file_picker | ^10.3.10 | PDF document picker | Used in AddNoteBottomSheet |
| go_router | ^17.1.0 | Navigation to new task screens and photo viewer | Established routing pattern |
| firebase_messaging | ^16.1.2 | FCM push notifications for task digest | Already initialized in project |

### Supporting (already in project)
| Library | Version | Purpose | When to Use |
|---------|---------|---------|-------------|
| path_provider | ^2.1.0 | Local file storage for attachments | Saving photos/PDFs offline |
| uuid | ^4.0.0 | Generating local IDs for offline records | All new entities need client-default IDs |
| dio | ^5.9.2 | HTTP client for backend sync | Used by all sync operations |

### New Packages Required
None. All required functionality is achievable with the existing package set. The web side uses only existing dependencies (React, TypeScript, Next.js, HTML5 Canvas API built into browsers).

**Version verification:** All packages above are from the verified `pubspec.yaml` and `package.json` in the project — no version drift.

---

## Architecture Patterns

### Recommended Project Structure

New files to create:

```
mobile/lib/features/projects/
  data/
    task_note_dao.dart           — New DAO for task notes
    task_attachment_dao.dart     — New DAO for task attachments
  domain/
    task_note_entity.dart        — Domain model mirroring Drift row
    task_attachment_entity.dart  — Domain model for task attachments
  presentation/
    screens/
      my_tasks_screen.dart       — Contractor cross-scope checklist (TASK-01)
      task_detail_screen.dart    — Full task detail with notes/photos (TASK-02,03,04,06)
      photo_annotation_screen.dart — Photo overlay annotator (TASK-05)
    widgets/
      task_checklist_card.dart   — Card with checkbox, priority badge, photo-gate
      task_scope_group_header.dart — Collapsible scope group header
      task_photo_grid.dart       — 3-column grid with annotation badges
      task_note_item.dart        — Timestamped note row
      trade_progress_card.dart   — GC progress card (TASK-07)
    providers/
      my_tasks_provider.dart     — Cross-scope task stream for contractor
      task_attachment_provider.dart — Attachment CRUD state notifier

mobile/lib/core/database/tables/
  task_notes.dart                — New Drift table (mirrors JobNotes pattern)

backend/app/features/projects/
  (extend existing router.py, service.py, schemas.py, models.py)

web/src/features/tasks/
  components/
    PhotoAnnotationCanvas.tsx    — HTML5 Canvas annotation component
    TradeProgressCard.tsx        — GC progress monitoring card
  hooks/
    usePhotoAnnotation.ts        — Canvas state management hook

backend/migrations/versions/
  0019_task_notes_and_annotation.py — Add task_notes table + annotation_data column
```

### Pattern 1: Photo Annotation JSON Schema

The annotation layer must be serializable to JSONB on the backend and parseable on both mobile and web.

**Schema (Claude's discretion — recommended):**
```typescript
// Shared annotation schema — same structure on mobile and web
interface AnnotationLayer {
  version: 1;                    // schema version for future migration
  canvasWidth: number;           // original photo width (normalize coordinates)
  canvasHeight: number;          // original photo height
  annotations: Annotation[];
}

interface Annotation {
  id: string;                    // uuid — for future delete/edit support
  tool: 'arrow' | 'circle' | 'text' | 'measurement';
  color: string;                 // hex color string e.g. "#FF0000"
  thickness: number;             // stroke width in logical pixels
  // For arrow and measurement: start + end points
  startX?: number;               // normalized 0-1 relative to canvasWidth
  startY?: number;
  endX?: number;
  endY?: number;
  // For circle: center + radius (or rect from DrawingPadScreen's Rect.fromPoints)
  x?: number;                    // top-left x, normalized
  y?: number;                    // top-left y, normalized
  width?: number;                // normalized
  height?: number;               // normalized
  // For text and measurement: label text
  label?: string;                // text content or measurement value e.g. "24 inches"
  fontSize?: number;             // logical pixels
}
```

**Why normalized coordinates:** The photo renders at different physical pixel sizes on mobile vs web. Normalizing 0-1 ensures annotations render correctly regardless of display size.

**Mobile Flutter serialization:**
```dart
// Source: project pattern — annotation stored in task_attachments.annotation_data
Map<String, dynamic> annotationLayerToJson(List<Annotation> annotations, Size canvasSize) {
  return {
    'version': 1,
    'canvasWidth': canvasSize.width,
    'canvasHeight': canvasSize.height,
    'annotations': annotations.map((a) => a.toJson()).toList(),
  };
}
```

### Pattern 2: Task Note Model (Claude's Discretion — Recommended)

Use a new `task_notes` Drift table that mirrors the `JobNotes` pattern exactly. Reusing `job_notes` would require adding a nullable `task_id` FK and conditional queries — too much coupling. A new table keeps lifecycles independent.

**Drift table structure:**
```dart
// Source: mirrors mobile/lib/core/database/tables/job_notes.dart pattern
class TaskNotes extends Table {
  TextColumn get id => text().clientDefault(() => const Uuid().v4())();
  TextColumn get companyId => text().references(Companies, #id)();
  TextColumn get taskId => text().references(ProjectTasks, #id)();
  TextColumn get authorId => text()();        // user UUID string (soft FK)
  TextColumn get body => text()();
  IntColumn get version => integer().withDefault(const Constant(1))();
  DateTimeColumn get createdAt => dateTime()();
  DateTimeColumn get updatedAt => dateTime()();
  DateTimeColumn get deletedAt => dateTime().nullable()();

  @override
  Set<Column> get primaryKey => {id};
}
```

**Backend model:** Add `TaskNote` SQLAlchemy model in `models.py` with `task_id` FK to tasks. Follow TenantScopedModel inheritance.

### Pattern 3: Task Attachment DAO (extends existing table)

The `TaskAttachments` Drift table already exists but has no DAO. The new `TaskAttachmentDao` extends `DatabaseAccessor<AppDatabase>` following `TaskDao` exactly.

```dart
// Source: pattern from mobile/lib/features/projects/data/task_dao.dart
@DriftAccessor(tables: [TaskAttachments, SyncQueue])
class TaskAttachmentDao extends DatabaseAccessor<AppDatabase>
    with _$TaskAttachmentDaoMixin {
  TaskAttachmentDao(super.db);

  Stream<List<TaskAttachment>> watchByTask(String taskId) {
    return (select(taskAttachments)
          ..where((t) => t.taskId.equals(taskId) & t.deletedAt.isNull())
          ..orderBy([(t) => OrderingTerm.asc(t.sortOrder)]))
        .watch();
  }

  Future<void> insertAttachment(TaskAttachmentsCompanion entry) async {
    await db.transaction(() async {
      await into(taskAttachments).insert(entry);
      await into(syncQueue).insert(_buildQueueEntry(/*...*/));
    });
  }
}
```

**Critical:** `TaskAttachments` table needs an `annotationData` TEXT nullable column added in Drift + migration 0019. This stores the JSON annotation layer for photos.

### Pattern 4: My Tasks Cross-Scope Provider

Contractor must see all tasks across all scopes they're assigned to, grouped by scope:

```dart
// Source: adapts project_providers.dart StreamProvider pattern
// New query needed in TaskDao: watchTasksForContractor(companyId, userId)
// Returns tasks where assigned_to = userId, status != 'complete', ordered by
// priority (urgent>high>medium>low) then due_date ASC nulls last

final myTasksProvider = StreamProvider.autoDispose
    .family<Map<String, List<ProjectTask>>, String>((ref, userId) {
  final dao = ref.watch(taskDaoProvider);
  // Group by tradeScopeId on the client side — Drift stream + groupBy
  return dao.watchTasksForContractor(userId).map((tasks) {
    final grouped = <String, List<ProjectTask>>{};
    for (final task in tasks) {
      grouped.putIfAbsent(task.tradeScopeId, () => []).add(task);
    }
    return grouped;
  });
});
```

**Note:** The `watchTasksForContractor` query in TaskDao must also join TradeScopes to get the scope name for grouping headers. Use Drift `join()` rather than a separate query per scope.

### Pattern 5: Backend Task Note Endpoints

Following existing `tasks_router` thin-router pattern:

```python
# Add to existing router.py — thin, delegate to TaskNoteService
task_notes_router = APIRouter(prefix="/tasks", tags=["task-notes"])

@task_notes_router.post("/{task_id}/notes", response_model=TaskNoteResponse, status_code=201)
async def add_task_note(task_id: uuid.UUID, data: TaskNoteCreate, ...) -> TaskNoteResponse:
    svc = TaskNoteService(db)
    note = await svc.create(task_id, data, author_id=current_user.user_id)
    return TaskNoteResponse.model_validate(note)

@task_notes_router.get("/{task_id}/notes", response_model=list[TaskNoteResponse])
async def list_task_notes(task_id: uuid.UUID, ...) -> list[TaskNoteResponse]:
    svc = TaskNoteService(db)
    return [TaskNoteResponse.model_validate(n) for n in await svc.list_by_task(task_id)]
```

### Pattern 6: Task Attachment Upload Endpoint

Adapt the existing `POST /files/upload` endpoint pattern for task attachments:

```python
# New endpoint in router.py — mirrors files/router.py POST /files/upload pattern
@tasks_router.post("/{task_id}/attachments", response_model=TaskAttachmentResponse, status_code=201)
async def upload_task_attachment(
    task_id: uuid.UUID,
    file: UploadFile,
    attachment_type: Annotated[str, Form()],   # 'photo' | 'document'
    caption: Annotated[str | None, Form()] = None,
    sort_order: Annotated[int, Form()] = 0,
    annotation_data: Annotated[str | None, Form()] = None,  # JSON string
    ...
):
    # Saves to uploads/task-attachments/{task_id}/{uuid}{ext}
    # Returns TaskAttachmentResponse with remote_url
```

**Storage path:** `uploads/task-attachments/{task_id}/{uuid}{ext}` — separate from job note attachments at `uploads/attachments/{note_id}/`.

### Pattern 7: Photo Annotation Screen (Mobile)

Adapt `DrawingPadScreen` to photo-overlay mode. Key differences:

1. **Takes photo path as constructor arg** (not a blank canvas)
2. **Photo renders as background** using `Image.file()` inside a Stack behind the CustomPainter
3. **Portrait-first orientation** (no landscape lock — photos are typically portrait)
4. **Pinch-to-zoom** via `InteractiveViewer` wrapping the Stack
5. **Save returns JSON** (not PNG path) — `Navigator.pop(context, jsonEncode(annotationLayer))`
6. **Text tool completes rendering** — use `TextPainter` in `_paintStroke` for text annotations
7. **Measurement tool** — draw a line + show label text centered on the line:

```dart
// Measurement tool rendering in _DrawingPainter._paintStroke
case _Tool.measurement:
  if (stroke.points.length >= 2) {
    final start = stroke.points.first;
    final end = stroke.points.last;
    canvas.drawLine(start, end, paint);
    // Draw tick marks at ends
    _drawMeasurementTicks(canvas, start, end, paint);
    // Draw label at midpoint
    if (stroke.measurementLabel != null) {
      final mid = Offset((start.dx + end.dx) / 2, (start.dy + end.dy) / 2);
      _drawTextLabel(canvas, stroke.measurementLabel!, mid, stroke.color, stroke.fontSize);
    }
  }
```

### Pattern 8: GC Progress Card

The existing `ProjectDetailScreen` shows `TradeScopeCard` with `completedTasks: 0, totalTasks: 0`. Phase 22 upgrades this to show real progress data:

```dart
// Replace TradeScopeCard with TradeProgressCard
// Data loaded via new tradeScopeProgressProvider(projectId)
// That provider streams countTasksByScope + countCompletedTasksByScope per scope
// Also loads last activity timestamp from task updatedAt

class TradeProgressCard extends StatelessWidget {
  final String tradeName;
  final Color tradeColor;
  final int completedTasks;
  final int totalTasks;
  final String? lastActivityText;   // "John D. - 2h ago"
  final List<String> thumbnailUrls; // 2-3 photo URLs
  final String status;
  final VoidCallback onTap;
  // ...
}
```

### Anti-Patterns to Avoid

- **PNG export for annotations:** Do NOT export annotations as PNG (flattened). Always store as JSON + original photo separate. The DrawingPadScreen's `_saveDrawing()` exports PNG — the new PhotoAnnotationScreen MUST NOT do this.
- **Eager loading all attachments on task list:** Do NOT load photo thumbnails for every visible task in the list. Load on demand using `StreamProvider.family` per task.
- **Drift pumpAndSettle in tests:** NEVER use `pumpAndSettle()` in widget tests involving Drift Stream providers. Use `pump()` with explicit counts (from project MEMORY.md).
- **Sync inside transaction for file upload:** File I/O (saving photos to disk) must happen OUTSIDE the Drift transaction. Do disk I/O first, then call `TaskAttachmentDao.insertAttachment()`.
- **Blocking task completion before server ack:** Task status change must write to Drift + sync queue atomically and update UI immediately (optimistic). Do not await HTTP response before showing completion.
- **Using landscape lock for photo annotation:** DrawingPadScreen locks landscape — PhotoAnnotationScreen must NOT lock orientation (photos are typically portrait).

---

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| Photo compression | Custom resize/compress logic | `compressPhoto()` utility in `add_note_bottom_sheet.dart` | Already handles 2K max, 90% quality, thumbnail generation, GPS EXIF preservation |
| Camera/gallery picker | Platform channel calls | `image_picker` (already in pubspec) | Handles permissions, temp file paths, source selection |
| PDF file picking | File open dialog | `file_picker` (already in pubspec) | Cross-platform, already in use |
| Sync outbox | Custom retry queue | `SyncQueue` Drift table + existing pattern in `TaskDao` | Transactions are atomic; retry/status already handled |
| Priority ordering | Custom sort algorithm | SQL `ORDER BY CASE WHEN priority='urgent' THEN 0 ...` in Drift | DB-level sort is correct and efficient |
| Text painting on Canvas | Custom glyph rendering | `TextPainter` Flutter built-in | Handles font metrics, text direction, multi-line |
| File storage on backend | Custom filesystem management | Existing `aiofiles` + `StaticFiles` pattern from `files/router.py` | Path structure, async writes, URL serving already established |
| FCM notification dispatch | Direct Firebase HTTP calls | `NotificationService` (already exists in `backend/app/features/notifications/`) | Lazy init, error handling, UnregisteredError cleanup already implemented |

**Key insight:** This phase is almost entirely adaptation and extension of existing patterns. The only genuinely new ground is: (1) the JSON annotation schema design, (2) the measurement ruler tool, and (3) the web canvas annotation component.

---

## Common Pitfalls

### Pitfall 1: Annotation Coordinate System Mismatch
**What goes wrong:** Annotations saved on mobile at one zoom level render incorrectly on web or at different screen sizes.
**Why it happens:** Using absolute pixel coordinates tied to the Flutter canvas physical size.
**How to avoid:** Store coordinates normalized 0.0–1.0 relative to original photo dimensions. Multiply by display dimensions at render time on both mobile and web.
**Warning signs:** Annotations appear shifted or scaled wrong between devices.

### Pitfall 2: InteractiveViewer + GestureDetector Conflict
**What goes wrong:** Pinch-to-zoom conflicts with drawing gestures on the annotation screen.
**Why it happens:** Both `InteractiveViewer` and `GestureDetector` compete for touch events.
**How to avoid:** Use a mode toggle (view mode = InteractiveViewer handles all gestures; draw mode = GestureDetector intercepts, InteractiveViewer disabled). The existing DrawingPadScreen does NOT have this problem because it has no zoom.
**Warning signs:** Drawing randomly triggers zoom, or zoom is impossible while drawing.
**Reference:** Phase 20 Gantt screen used `InteractiveViewer(constrained: false)` — the same `constrained: false` + `SizedBox` bounds wrapper pattern applies here.

### Pitfall 3: Drift Transaction + File I/O Ordering
**What goes wrong:** Photo file is not written to disk before the Drift transaction commits the attachment record, causing a record that points to a non-existent file.
**Why it happens:** Drift transactions are synchronous from the perspective of the DB; file I/O can fail after the transaction.
**How to avoid:** Always: (1) compress + write file to disk, (2) THEN call `TaskAttachmentDao.insertAttachment()`. If step 2 fails, the orphaned file is harmless. If step 1 fails, nothing is written.
**Warning signs:** Missing file errors when loading attachment images.

### Pitfall 4: Photo-Required Gate Race Condition
**What goes wrong:** User adds a photo and immediately taps "Mark Done" before the Drift insert completes.
**Why it happens:** Async gap between photo processing and DAO insert.
**How to avoid:** The "Mark Done" button checks `attachmentCount > 0` via a StreamProvider on `TaskAttachmentDao.watchByTask(taskId)`. The stream updates reactively — no polling needed.
**Warning signs:** Occasional "photo required" block despite photo being visually present.

### Pitfall 5: Web Canvas Annotation — React Re-render Clearing Canvas
**What goes wrong:** React state update re-renders component, wiping the canvas.
**Why it happens:** HTML5 Canvas element is imperative — its drawing state is not part of React's virtual DOM.
**How to avoid:** Store all annotations in a `useRef` list (not `useState`). On re-render, redraw the full annotation layer from the ref list. Use `useEffect` with canvas ref to redraw.
**Warning signs:** Annotations disappear when any React state changes.

### Pitfall 6: TaskNote Sync Without Backend Endpoint
**What goes wrong:** Task notes enqueued in SyncQueue fail because the backend endpoint doesn't exist yet.
**Why it happens:** Drift inserts can happen offline before backend is implemented.
**How to avoid:** Implement backend `POST /tasks/{task_id}/notes` in the same wave as the mobile TaskNoteDao. Never create a sync queue entry for an entity that has no backend endpoint.
**Warning signs:** Sync errors with 404 responses in the sync queue handler.

### Pitfall 7: Missing `annotation_data` Column in Existing TaskAttachments Drift Table
**What goes wrong:** `TaskAttachmentDao` tries to write `annotation_data` but Drift schema version is unchanged — migration required.
**Why it happens:** The `TaskAttachments` Drift table was generated from `task_attachments.dart` in Phase 19. The schema version must be bumped and a migration written.
**How to avoid:** Add `annotationData` column to `task_attachments.dart`, increment `schemaVersion` in `AppDatabase`, add migration step in `migration` callback.
**Warning signs:** Drift schema mismatch exception on startup.

---

## Code Examples

### Annotation Screen Navigation (Mobile)

```dart
// Source: adapts existing photo_viewer route pattern in route_names.dart
// New route: /tasks/:taskId/photos/:attachmentId/annotate
// Push from task_detail_screen.dart when "Annotate" button tapped

context.push(
  RouteNames.photoAnnotationPath(taskId, attachmentId),
  extra: {
    'localPath': attachment.localPath,
    'annotationData': attachment.annotationData, // nullable JSON string
  },
);
```

### Measurement Ruler UX (Claude's Discretion — Recommended)

Drag-to-draw: user drags from start to end point. On pan end, a dialog appears for entering the dimension text. This mirrors how Arrow works (drag to draw) and is less error-prone than tap-two-points.

```dart
// In PhotoAnnotationScreen — after _onPanEnd for measurement tool:
if (_activeTool == _Tool.measurement && _currentStroke != null) {
  final label = await _showMeasurementLabelDialog(context);
  if (label != null) {
    _currentStroke = _currentStroke!.copyWith(measurementLabel: label);
  }
  // Finalize stroke with label
}
```

### Task Completion with Photo Gate

```dart
// In TaskChecklistCard — checkbox tap handler
void _handleCheckboxTap(BuildContext context, WidgetRef ref, ProjectTask task) {
  if (task.photoRequired) {
    final hasPhoto = ref.read(taskAttachmentCountProvider(task.id)) > 0;
    if (!hasPhoto) {
      // Show camera picker instead of completing
      _openPhotoPicker(context, ref, task.id);
      return;
    }
  }
  // Toggle status: not_started/in_progress -> complete, complete -> in_progress
  final newStatus = task.status == 'complete' ? 'in_progress' : 'complete';
  ref.read(taskDaoProvider).updateTask(
    task.id,
    ProjectTasksCompanion(
      status: Value(newStatus),
      updatedAt: Value(DateTime.now()),
    ),
  );
}
```

### Backend Task Attachment Upload (extends files pattern)

```python
# Source: mirrors backend/app/features/files/router.py
# File saved to: uploads/task-attachments/{task_id}/{uuid}{ext}
# annotation_data stored as JSONB on task_attachments record
# attachment_type: 'photo' | 'document' (no 'video' in Phase 22 scope)

remote_url = f"/files/task-attachments/{task_id}/{unique_filename}"
attachment = TaskAttachment(
    company_id=current_user.company_id,
    task_id=task_id,
    attachment_type=attachment_type,
    remote_url=remote_url,
    caption=caption,
    sort_order=sort_order,
    annotation_data=json.loads(annotation_data) if annotation_data else None,
)
```

### Web Canvas Annotation (HTML5 Canvas — no new npm package)

```typescript
// Source: HTML5 Canvas API — browser built-in
// PhotoAnnotationCanvas.tsx — draws annotation layer over <img>

function usePhotoAnnotation(annotations: Annotation[]) {
  const canvasRef = useRef<HTMLCanvasElement>(null);

  useEffect(() => {
    const canvas = canvasRef.current;
    if (!canvas) return;
    const ctx = canvas.getContext('2d');
    if (!ctx) return;

    ctx.clearRect(0, 0, canvas.width, canvas.height);
    annotations.forEach((ann) => drawAnnotation(ctx, ann, canvas.width, canvas.height));
  }, [annotations]);  // Redraw whenever annotations change

  return canvasRef;
}

function drawAnnotation(ctx: CanvasRenderingContext2D, ann: Annotation, w: number, h: number) {
  // Denormalize coordinates: ann.startX * w, ann.startY * h
  ctx.strokeStyle = ann.color;
  ctx.lineWidth = ann.thickness;
  switch (ann.tool) {
    case 'arrow':
      drawArrow(ctx, ann.startX! * w, ann.startY! * h, ann.endX! * w, ann.endY! * h);
      break;
    case 'circle':
      ctx.beginPath();
      ctx.ellipse(
        (ann.x! + ann.width! / 2) * w, (ann.y! + ann.height! / 2) * h,
        (ann.width! / 2) * w, (ann.height! / 2) * h, 0, 0, 2 * Math.PI
      );
      ctx.stroke();
      break;
    // text, measurement...
  }
}
```

---

## State of the Art

| Old Approach | Current Approach | When Changed | Impact |
|--------------|------------------|--------------|--------|
| DrawingPadScreen saves PNG (destructive) | PhotoAnnotationScreen saves JSON (non-destructive) | Phase 22 new | Annotations can be edited, toggled, and rendered on web |
| TradeScopeCard shows 0/0 tasks | TradeProgressCard shows real progress + thumbnails | Phase 22 new | GC has at-a-glance project health |
| Task detail stub in TradeScopeDetailScreen | Full TaskDetailScreen with notes/photos/attachments | Phase 22 new | Core contractor execution flow |
| No cross-scope task view | MyTasksScreen with all scopes grouped | Phase 22 new | Contractor sees full day's work in one place |
| TaskAttachments table with no DAO | TaskAttachmentDao with full CRUD + sync | Phase 22 new | Offline-first attachment management |

**Deprecated/outdated:**
- `_showTaskDetailStub()` in `TradeScopeDetailScreen`: replaced by full `TaskDetailScreen` push navigation. The stub method should be removed.
- `completedTasks: 0, totalTasks: 0` in `ProjectDetailScreen`'s TradeScopeCard instantiation: replaced by live data from `tradeScopeProgressProvider`.

---

## Open Questions

1. **PDF Viewer Implementation** (Claude's Discretion)
   - What we know: `file_picker` already handles PDF selection. The project has no existing PDF viewer package.
   - What's unclear: Whether to use `url_launcher` (opens system PDF viewer), `flutter_pdfview` (in-app), or a WebView.
   - Recommendation: Use `url_launcher` to open PDFs in the system viewer via `launchUrl(Uri.file(localPath))` — zero new dependencies, familiar UX, works offline. Add `url_launcher` to pubspec (it's not currently there).

2. **Batch Digest Notification Timing**
   - What we know: FCM infrastructure exists, `NotificationService` has dispatch logic, batch digest is D-16.
   - What's unclear: Whether to trigger digest via a scheduled job (celery/APScheduler) or on a per-completion basis with a cooldown. No task scheduler currently exists in the backend.
   - Recommendation: Trigger digest from the `PATCH /tasks/{id}` endpoint when `status=complete`: collect all completions in the last hour, send digest if threshold (e.g., 3+ completions) is met, otherwise send single notification. This avoids a scheduler dependency.

3. **Drift Schema Version for `annotation_data` Column**
   - What we know: `task_attachments.dart` has no `annotationData` column. Schema version must be bumped.
   - What's unclear: Current Drift schema version number (not checked in codebase — needs verification in `AppDatabase`).
   - Recommendation: Read `mobile/lib/core/database/app_database.dart` at planning time to confirm current `schemaVersion` and add `schemaVersion + 1` migration.

4. **MyTasksScreen: Cross-Scope Ordering**
   - What we know: D-05 says "ordered by priority then due date" with "overdue tasks highlighted at top."
   - What's unclear: Whether the priority+due-date ordering applies WITHIN each scope group, or across all scopes. D-04 says "grouped by scope."
   - Recommendation: Within each scope group, order by: (1) overdue first, (2) priority (urgent > high > medium > low), (3) due_date ASC. Across scopes, the scope groups themselves are ordered by scope sort_order from TradeScopes.

---

## Validation Architecture

### Test Framework
| Property | Value |
|----------|-------|
| Framework (Flutter) | flutter_test (SDK) + mocktail ^1.0.4 |
| Framework (Backend) | pytest + ASGI client (conftest.py) |
| Config file | `mobile/flutter_test_default_tags.yaml` (none — uses flutter test directly) |
| Quick run command (mobile) | `cd mobile && flutter test test/features/projects/` |
| Quick run command (backend) | `cd backend && uv run python -m pytest tests/integration/test_phase_22_e2e.py -x` |
| Full suite command (mobile) | `cd mobile && flutter test` |
| Full suite command (backend) | `cd backend && uv run python -m pytest` |

### Phase Requirements → Test Map

| Req ID | Behavior | Test Type | Automated Command | File Exists? |
|--------|----------|-----------|-------------------|-------------|
| TASK-01 | Contractor sees tasks grouped by scope | Widget (E2E) | `flutter test test/e2e/phase_22_task_execution_e2e_test.dart` | ❌ Wave 0 |
| TASK-02 | Tapping checkbox changes status to complete | Widget (E2E) | `flutter test test/e2e/phase_22_task_execution_e2e_test.dart` | ❌ Wave 0 |
| TASK-03 | Adding a note saves with timestamp | Widget (E2E) | `flutter test test/e2e/phase_22_task_execution_e2e_test.dart` | ❌ Wave 0 |
| TASK-04 | Photo capture attaches to task | Widget (E2E) | `flutter test test/e2e/phase_22_task_execution_e2e_test.dart` | ❌ Wave 0 |
| TASK-05 | Annotation JSON round-trip (draw → JSON → render) | Unit | `flutter test test/features/projects/photo_annotation_test.dart` | ❌ Wave 0 |
| TASK-06 | PDF picker attaches document | Widget (E2E) | `flutter test test/e2e/phase_22_task_execution_e2e_test.dart` | ❌ Wave 0 |
| TASK-07 | GC sees trade progress bars with real counts | Widget (E2E) | `flutter test test/e2e/phase_22_task_execution_e2e_test.dart` | ❌ Wave 0 |
| TASK-04 (backend) | POST /tasks/{id}/attachments saves file + DB record | Integration | `uv run python -m pytest tests/integration/test_phase_22_e2e.py::test_task_attachment_upload -x` | ❌ Wave 0 |
| TASK-03 (backend) | POST /tasks/{id}/notes creates task note | Integration | `uv run python -m pytest tests/integration/test_phase_22_e2e.py::test_task_note_create -x` | ❌ Wave 0 |
| TASK-02 (backend) | PATCH /tasks/{id} status=complete triggers dependency unblock | Integration (existing) | `uv run python -m pytest tests/ -k "task" -x` | Partial (Phase 20) |

### Sampling Rate
- **Per task commit:** `cd mobile && flutter test test/features/projects/ && cd ../backend && uv run python -m pytest tests/integration/test_phase_22_e2e.py -x`
- **Per wave merge:** `cd mobile && flutter test && cd ../backend && uv run python -m pytest`
- **Phase gate:** Full suite green before `/gsd:verify-work`

### Wave 0 Gaps
- [ ] `mobile/test/e2e/phase_22_task_execution_e2e_test.dart` — covers TASK-01 through TASK-07 full flow
- [ ] `mobile/test/features/projects/photo_annotation_test.dart` — unit tests for annotation JSON schema serialization/deserialization
- [ ] `mobile/test/features/projects/task_note_dao_test.dart` — Drift in-memory DAO tests for TaskNoteDao
- [ ] `mobile/test/features/projects/task_attachment_dao_test.dart` — Drift in-memory DAO tests for TaskAttachmentDao
- [ ] `backend/tests/integration/test_phase_22_e2e.py` — backend integration tests for task notes + attachment upload endpoints

---

## Sources

### Primary (HIGH confidence)
- `backend/app/features/projects/models.py` — Verified: Task, TaskAttachment SQLAlchemy models; existing field set; lazy="raise" pattern
- `backend/app/features/projects/schemas.py` — Verified: TaskResponse, TaskAttachmentResponse, existing endpoint patterns
- `backend/app/features/projects/router.py` — Verified: existing PATCH /tasks/{id} with dependency recompute; no task note or attachment upload endpoints yet
- `mobile/lib/features/jobs/presentation/screens/drawing_pad_screen.dart` — Verified: full CustomPainter tool set (arrow, circle, line, rect, pen, text); PNG export; undo/redo; text tool exists but rendering uses freehand path (placeholder)
- `mobile/lib/core/database/tables/task_attachments.dart` — Verified: table defined, no annotationData column, no DAO
- `mobile/lib/features/projects/data/task_dao.dart` — Verified: sync-aware mutations, watchTasksByScope; no cross-scope query
- `mobile/lib/features/jobs/presentation/widgets/add_note_bottom_sheet.dart` — Verified: `compressPhoto()` utility, camera/gallery/PDF picker patterns
- `backend/app/features/files/router.py` — Verified: file upload pattern with aiofiles, StaticFiles, remote_url construction
- `backend/app/features/notifications/service.py` — Verified: FCM service exists, fire-and-forget pattern, lazily initialized
- `mobile/pubspec.yaml` — Verified: all required packages present; no PDF viewer package; url_launcher not present
- `web/package.json` — Verified: Next.js 16, React 19, no canvas annotation library; HTML5 Canvas API available natively
- `mobile/lib/core/routing/route_names.dart` — Verified: existing routes; task detail, photo annotation, my tasks routes need to be added

### Secondary (MEDIUM confidence)
- STATE.md accumulated decisions: "Annotation storage is non-destructive (base photo immutable; annotation JSON in separate JSONB column)" — confirms D-08 was a project-level decision, not just phase-level
- STATE.md: "v3.0: Online-first architecture (AI requires connectivity), offline cache for daily task execution" — confirms offline support for task checklist is required
- REQUIREMENTS.md: TASK-01 through TASK-07 all Phase 22 pending — confirms full scope

### Tertiary (LOW confidence)
- fabric.js considered and rejected for web annotation — no official benchmarks, decision based on bundle weight analysis and project's pattern of avoiding new npm packages unless necessary

---

## Metadata

**Confidence breakdown:**
- Standard stack: HIGH — all packages verified from pubspec.yaml and package.json
- Architecture: HIGH — all patterns derived from reading existing source files
- Backend endpoints: HIGH — confirmed existing pattern in files/router.py, no task note endpoint exists
- Annotation JSON schema: MEDIUM — design is sound but normalized-coordinates approach needs validation during planning
- Web canvas annotation: HIGH — HTML5 Canvas is stable browser API; approach confirmed feasible
- Pitfalls: HIGH — all pitfalls derived from actual code patterns and existing STATE.md decisions

**Research date:** 2026-03-24
**Valid until:** 2026-04-24 (stable — no fast-moving dependencies)
