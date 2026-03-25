# Phase 24: GC Inspection Workflow - Context

**Gathered:** 2026-03-25
**Status:** Ready for planning

<domain>
## Phase Boundary

GCs can formally inspect completed tasks from mobile, approve or reject them with annotated photo evidence and structured reasons, create punch list items as a separate entity, flag issues during site walks (camera-first), and contractors receive FCM notifications on rejections immediately.

</domain>

<decisions>
## Implementation Decisions

### Inspection Flow
- **D-01:** Inline on existing task detail screen — add approve/reject buttons to the bottom bar when task status is "complete" and user is GC/admin. No separate inspection screen.
- **D-02:** Show existing content + time summary + inspection checklist — GC sees contractor's photos, notes, attachments, plus total hours logged and status transition timeline, plus a mini inspection checklist that must be completed before approve enables.
- **D-03:** Per-trade configurable inspection checklists — each trade scope can define its own default checklist items (e.g., electrical: "grounding verified, circuits labeled"). Falls back to universal defaults (quality acceptable, materials correct, area clean, safety compliant) if none configured for the trade.

### Rejection Experience
- **D-04:** New "rejected" task status — adds a distinct `rejected` state to the task lifecycle state machine. Contractor sees it clearly differentiated from reopened tasks.
- **D-05:** Structured reason + comment + annotated photo — GC picks from predefined rejection reasons (rework needed, quality issue, wrong materials, incomplete, safety concern), adds optional free-text comment, and can attach/annotate a photo showing the issue. Full evidence trail.
- **D-06:** FCM push on rejection — contractor receives immediate push notification with the GC's rejection reason within 30 seconds (per INSP-04 success criteria).

### Punch List Design
- **D-07:** Separate `punch_list_items` entity — new table with its own schema (description, trade scope, photos, status, assigned contractor). Not a task with a flag. Clean domain boundary from project tasks.
- **D-08:** Mixed with regular tasks + "Punch" badge — punch items appear inline in the contractor's trade scope task view, sorted by priority, distinguished by a visible "Punch" badge on the card. No separate section or tab.

### Site Walk Flagging
- **D-09:** Camera-first with form fallback — tapping "Flag Issue" opens camera by default. "Skip photo" link goes straight to the description form. Covers both visual and non-visual issues.
- **D-10:** Project-scoped observations, auto-converts to punch item — flags start as project-level observations (new `site_walk_flags` entity). GC can later convert a flag to a punch list item by assigning a trade scope. Unconverted flags remain as documented observations.

### Claude's Discretion
- Inspection checklist storage schema (JSONB on trade_scopes table vs separate table)
- Predefined rejection reason list (exact wording and categorization)
- Universal default checklist items (exact wording)
- Site walk flag form fields beyond description and photo (severity, location, etc.)
- Punch list item status lifecycle (open → in_progress → resolved → verified)
- How converted flags link back to the original site_walk_flag record

</decisions>

<canonical_refs>
## Canonical References

**Downstream agents MUST read these before planning or implementing.**

### Phase Dependencies
- `.planning/phases/22-task-execution-and-photo-annotation/22-CONTEXT.md` — Task detail screen design (D-10), photo annotation JSON format (D-08), annotation tools (D-07), photo gate pattern (D-03), GC progress monitoring (D-14/D-15)
- `.planning/phases/22-task-execution-and-photo-annotation/22-RESEARCH.md` — Photo annotation implementation research

### Requirements
- `.planning/REQUIREMENTS.md` §INSP-01 through INSP-04 — Inspection workflow requirements

### Existing Code (Mobile)
- `mobile/lib/features/projects/presentation/screens/task_detail_screen.dart` — Task detail screen to extend with inspection UI
- `mobile/lib/features/projects/presentation/screens/photo_annotation_screen.dart` — Annotation screen to reuse for rejection evidence
- `mobile/lib/features/projects/presentation/providers/project_providers.dart` — Task/scope providers to extend
- `mobile/lib/features/projects/data/task_dao.dart` — Task DAO for status transitions
- `mobile/lib/core/notifications/fcm_service.dart` — FCM infrastructure for rejection notifications

### Existing Code (Backend)
- `backend/app/features/projects/router.py` — Project/task endpoints to extend
- `backend/app/features/projects/service.py` — Task service for inspection logic
- `backend/app/features/notifications/service.py` — FCM dispatch for rejection notifications

</canonical_refs>

<code_context>
## Existing Code Insights

### Reusable Assets
- **PhotoAnnotationScreen**: Full annotation overlay with arrow, circle, text, measurement tools. Reuse for rejection photo evidence.
- **TaskDetailScreen**: CustomScrollView with header, details, notes, photos, attachments sections. Extend bottom bar with inspect/approve/reject buttons for GC role.
- **NotificationService**: FCM push with fire-and-forget pattern, device token management, UnregisteredError cleanup. Reuse for rejection notifications.
- **ProjectStatusBadge**: Chip-style badge supporting multiple status strings. Add "rejected" and "punch" status colors.
- **TaskDao**: Full CRUD with sync queue dual-write pattern. Extend for rejected status transitions.

### Established Patterns
- **Task status machine**: not_started → in_progress → complete → (new: rejected → in_progress). Service layer validates transitions.
- **Offline-first dual-write**: All mutations write to entity table + sync_queue atomically in a Drift transaction.
- **Photo annotation JSON**: Non-destructive JSON overlay stored in `annotationData` field. Same format for mobile and web.
- **FCM fire-and-forget**: Notification failures never block the primary operation. Errors logged but not raised.
- **Role-based UI**: GC/admin vs contractor determined by auth state. Bottom bar buttons conditionally rendered.

### Integration Points
- **Task detail bottom bar**: Currently has "Add Photo" + "Mark Done" buttons. Add "Approve"/"Reject" for GC when task is "complete".
- **My Tasks screen**: Currently shows tasks grouped by scope. Punch list items will appear inline with badge.
- **Project detail screen**: TradeProgressCards already exist. Site walk flags could surface as a separate list or badge count.
- **Backend task transition endpoint**: `PATCH /jobs/{job_id}/transition` pattern — extend project task service similarly.
- **Alembic migrations**: New tables (punch_list_items, site_walk_flags) + inspection_checklists field on trade_scopes + rejected status support on tasks.

</code_context>

<specifics>
## Specific Ideas

- Inspection checklist must be configurable per trade scope (electrical has different checks than plumbing)
- Rejection requires full evidence trail: structured reason + comment + annotated photo
- Site walk flags are first-class project observations that can be promoted to punch items — not throwaway notes
- Punch list items are a distinct entity, not tasks with a tag — keeps the domain clean

</specifics>

<deferred>
## Deferred Ideas

None — discussion stayed within phase scope

</deferred>

---

*Phase: 24-gc-inspection-workflow*
*Context gathered: 2026-03-25*
