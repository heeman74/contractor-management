# Phase 22: Task Execution and Photo Annotation - Context

**Gathered:** 2026-03-24
**Status:** Ready for planning

<domain>
## Phase Boundary

Contractors execute their AI-generated tasks on mobile: view a prioritized checklist, mark tasks complete (with photo gates), add progress notes and photo/PDF attachments, and annotate photos with construction-specific tools (arrows, circles, text, measurements). Annotations are non-destructive (JSON layer over original photo), renderable on both mobile and web. GC monitors progress across all trades from a project detail view with trade scope cards, progress bars, and photo thumbnails. Web also supports photo annotation for GC review.

</domain>

<decisions>
## Implementation Decisions

### Daily Task View
- **D-01:** Checklist cards — card per task with checkbox, title, priority badge, time estimate, photo-required indicator. Grouped by trade scope with progress header (scope name, X/Y tasks, percentage bar)
- **D-02:** Tap checkbox to complete — tap checkbox toggles complete. Status syncs to GC immediately via outbox pattern
- **D-03:** Block completion until photo added — when `photo_required=true` and no photo attached, checkbox shows camera icon instead of checkmark. Tapping opens camera/gallery picker. After photo attached, checkbox becomes available
- **D-04:** All scopes, grouped — single "My Tasks" screen shows all assigned tasks across all trade scopes, grouped by scope with collapsible headers
- **D-05:** All incomplete tasks — show all incomplete tasks ordered by priority then due date. Overdue tasks highlighted at top. No date-based filtering (tasks don't have precise daily scheduling yet)

### Photo Annotation Flow
- **D-06:** Overlay on photo — open photo in full-screen viewer, tap "Annotate" to enter draw mode with tools overlaying the photo. Pinch-to-zoom supported. Save stores original + annotation layer separately (non-destructive)
- **D-07:** Essential tools: Arrow, Circle/highlight, Text labels, Measurement ruler — all four are required. Arrow, circle exist in DrawingPadScreen. Text rendering needs completion (tool exists but rendering is placeholder). Measurement ruler is new (draw a line with dimension text like "24 inches")
- **D-08:** JSON annotation layer — store annotations as JSON (tool type, coordinates, color, text, measurement value). Render on-the-fly over original photo. Non-destructive, toggleable, editable later. Both mobile and web can render from same JSON
- **D-09:** Web can annotate too — canvas-based annotation on web using same JSON format. Full tool set (arrow, circle, text, measurement). Important for GC inspection flow in Phase 24

### Task Detail & Attachments
- **D-10:** Scrollable detail page — full screen with sections: Header (title, status, priority), Details (description, estimate, materials), Notes (timestamped text entries), Photos (3-column grid gallery with annotation badges), Attachments (PDF list). Bottom bar has "Add Photo" and "Mark Done" buttons
- **D-11:** Inline text input for notes — TextField at top of Notes section, tap "+" to add. Notes are timestamped, shown newest first. Immutable after save (same pattern as existing job notes)
- **D-12:** Grid gallery + FAB for photos — photos shown as 3-column grid thumbnails. Annotated photos have pencil badge overlay. Tap thumbnail for full-screen viewer with "Annotate" button. Floating "Add Photo" button offers camera or gallery
- **D-13:** 10 photos + 5 PDFs per task — practical attachment limits. Prevents storage abuse while allowing thorough documentation

### GC Progress Monitoring
- **D-14:** Project detail with trade cards — project detail screen shows trade scope cards with: trade color dot, name, X/Y task count, percentage progress bar, last activity timestamp + contractor name. Tap into scope to see tasks (read-only for GC)
- **D-15:** Thumbnails in task list — small photo thumbnails (2-3 max) visible on each task card in GC's view. Quick visual progress check without opening every task
- **D-16:** Batch digest notifications — group task completions into periodic digests: "Plumbing: 3 tasks completed today". Avoids notification spam. FCM infrastructure already exists from v1.0

### Claude's Discretion
- Photo compression settings for task attachments (existing pattern: 2K max, 90% quality)
- PDF viewer implementation (in-app webview vs native viewer vs intent)
- Measurement ruler UX (tap-two-points, drag-to-draw, unit selection)
- Offline behavior for attachment sync (outbox queue pattern already established)
- Annotation JSON schema structure (coordinate system, tool serialization format)
- Web annotation canvas library choice (HTML5 Canvas, fabric.js, or similar)
- Task note model (new table vs reuse existing Note pattern adapted for tasks)
- Progress bar animation and color thresholds

</decisions>

<canonical_refs>
## Canonical References

**Downstream agents MUST read these before planning or implementing.**

### Task Data Model (Phase 19)
- `backend/app/features/projects/models.py` — Task, TaskAttachment SQLAlchemy models with all fields (status, priority, photo_required, materials_needed, assigned_to)
- `backend/app/features/projects/schemas.py` — TaskCreate, TaskUpdate, TaskResponse, TaskAttachmentCreate, TaskAttachmentResponse Pydantic schemas
- `backend/app/features/projects/service.py` — TaskService (create, update, soft-delete, status transitions, blocked auto-detection)
- `backend/app/features/projects/router.py` — Task CRUD endpoints (POST, GET, PATCH, DELETE at /api/v1/tasks)

### Mobile Task Infrastructure
- `mobile/lib/core/database/tables/tasks.dart` — Drift ProjectTasks table definition
- `mobile/lib/core/database/tables/task_attachments.dart` — Drift TaskAttachments table (exists but no DAO)
- `mobile/lib/features/projects/data/task_dao.dart` — TaskDao with watchTasksByScope, countTasksByScope, sync-aware mutations
- `mobile/lib/features/projects/presentation/providers/project_providers.dart` — taskDaoProvider, tasksProvider (StreamProvider.autoDispose.family)
- `mobile/lib/features/projects/presentation/screens/trade_scope_detail_screen.dart` — Existing task list with priority borders and task row widget

### Drawing & Annotation (Existing)
- `mobile/lib/features/jobs/presentation/screens/drawing_pad_screen.dart` — Full CustomPainter implementation with pen/eraser/text/line/rect/circle/arrow tools, undo/redo, PNG export, landscape orientation lock

### Photo & Attachment Patterns
- `mobile/lib/features/jobs/presentation/widgets/add_note_bottom_sheet.dart` — Photo capture pattern: ImagePicker + FlutterImageCompress (2K max, 90%), gallery, PDF picker, drawing integration
- `mobile/lib/features/jobs/domain/attachment_entity.dart` — AttachmentEntity pattern (type, localPath, thumbnailPath, uploadStatus, remoteUrl)
- `backend/app/features/files/router.py` — File upload endpoint pattern (POST /files/upload, aiofiles, StaticFiles mount)

### Sync Infrastructure
- `mobile/lib/core/database/tables/sync_queue.dart` — SyncQueue table for outbox pattern (CREATE/UPDATE/DELETE operations)

</canonical_refs>

<code_context>
## Existing Code Insights

### Reusable Assets
- **DrawingPadScreen**: Full drawing tool set (pen, eraser, text, line, rect, circle, arrow) with CustomPainter, undo/redo, PNG export. Needs adaptation for photo overlay mode + measurement tool
- **AddNoteBottomSheet**: Photo capture + compression + gallery + PDF picker + drawing integration. Can reuse capture logic for task attachments
- **TaskDao**: Stream-based task queries with sync queue integration. Extend with attachment queries
- **File upload endpoint**: Backend pattern for saving files to disk with DB records. Adapt for task attachments

### Established Patterns
- **Drift StreamProvider.autoDispose.family**: All list screens use this for reactive updates. Task list and detail should follow same pattern
- **Outbox sync**: Mutations create sync queue items in same transaction. Task completions and attachment uploads follow this
- **Soft-delete**: All entities use deletedAt column. TaskAttachments should follow
- **Priority color coding**: 4px left border (red=urgent, orange=high, blue=medium, grey=low) on task cards

### Integration Points
- **Project detail → Trade scope → Task list**: Existing navigation hierarchy. Need to add "My Tasks" cross-scope screen for contractors
- **Task status change → Dependency engine**: Phase 20's dependency system auto-blocks/unblocks downstream tasks on status changes. Task completion here triggers that
- **FCM push**: Infrastructure exists. Add batch digest trigger for task completions
- **Web project detail**: Needs trade progress cards matching mobile design

</code_context>

<specifics>
## Specific Ideas

- Photo annotation overlay: same approach as professional construction apps (PlanGrid/Fieldwire) — draw directly on the photo, not a separate canvas
- Measurement ruler: contractor draws a line and types the dimension (e.g., "24 inches") — displayed as a labeled line on the annotation layer
- Annotated photo badge: small pencil icon overlay on thumbnails so GC can instantly see which photos have markup
- Trade scope progress cards: trade color dot + name + progress bar + last activity creates at-a-glance project health view

</specifics>

<deferred>
## Deferred Ideas

None — discussion stayed within phase scope

</deferred>

---

*Phase: 22-task-execution-and-photo-annotation*
*Context gathered: 2026-03-24*
