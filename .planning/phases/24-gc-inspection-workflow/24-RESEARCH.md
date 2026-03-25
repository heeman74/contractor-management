# Phase 24: GC Inspection Workflow - Research

**Researched:** 2026-03-25
**Domain:** Mobile inspection workflow, task state machine extension, offline-first new entities, FCM push on rejection
**Confidence:** HIGH

---

<user_constraints>
## User Constraints (from CONTEXT.md)

### Locked Decisions

#### Inspection Flow
- **D-01:** Inline on existing task detail screen — add approve/reject buttons to the bottom bar when task status is "complete" and user is GC/admin. No separate inspection screen.
- **D-02:** Show existing content + time summary + inspection checklist — GC sees contractor's photos, notes, attachments, plus total hours logged and status transition timeline, plus a mini inspection checklist that must be completed before approve enables.
- **D-03:** Per-trade configurable inspection checklists — each trade scope can define its own default checklist items. Falls back to universal defaults (quality acceptable, materials correct, area clean, safety compliant) if none configured for the trade.

#### Rejection Experience
- **D-04:** New "rejected" task status — adds a distinct `rejected` state to the task lifecycle state machine.
- **D-05:** Structured reason + comment + annotated photo — GC picks from predefined rejection reasons, adds optional free-text comment, and can attach/annotate a photo showing the issue.
- **D-06:** FCM push on rejection — contractor receives immediate push notification with the GC's rejection reason within 30 seconds.

#### Punch List Design
- **D-07:** Separate `punch_list_items` entity — new table with its own schema (description, trade scope, photos, status, assigned contractor). Not a task with a flag.
- **D-08:** Mixed with regular tasks + "Punch" badge — punch items appear inline in the contractor's trade scope task view, sorted by priority, distinguished by a visible "Punch" badge.

#### Site Walk Flagging
- **D-09:** Camera-first with form fallback — tapping "Flag Issue" opens camera by default. "Skip photo" link goes straight to the description form.
- **D-10:** Project-scoped observations, auto-converts to punch item — flags start as project-level observations (new `site_walk_flags` entity). GC can later convert a flag to a punch list item by assigning a trade scope. Unconverted flags remain as documented observations.

### Claude's Discretion
- Inspection checklist storage schema (JSONB on trade_scopes table vs separate table)
- Predefined rejection reason list (exact wording and categorization)
- Universal default checklist items (exact wording)
- Site walk flag form fields beyond description and photo (severity, location, etc.)
- Punch list item status lifecycle (open → in_progress → resolved → verified)
- How converted flags link back to the original site_walk_flag record

### Deferred Ideas (OUT OF SCOPE)
None — discussion stayed within phase scope
</user_constraints>

---

<phase_requirements>
## Phase Requirements

| ID | Description | Research Support |
|----|-------------|-----------------|
| INSP-01 | GC can inspect completed tasks and approve or reject them with comments | Task status machine extension (add `rejected`), inspection bottom bar UI, backend approve/reject endpoint, TaskService inspection methods |
| INSP-02 | GC can flag issues discovered during site walks with photos and annotations | New `site_walk_flags` entity (backend + Drift), camera-first flag capture flow, PhotoAnnotationScreen reuse |
| INSP-03 | GC can create punch list items assigned to specific trades | New `punch_list_items` entity (backend + Drift), inline rendering in My Tasks / trade scope task views with "Punch" badge |
| INSP-04 | Rejected tasks trigger notification to the trade contractor with GC's feedback | NotificationService.send_task_rejection_notification() following existing fire-and-forget pattern; FCM data payload: task_id + rejection_reason |
</phase_requirements>

---

## Summary

Phase 24 extends three established infrastructure layers with new domain entities and one behavior change. The core pattern is well understood from prior phases: new Drift tables with sync queue dual-write (offline-first), new SQLAlchemy models with TenantScopedModel, and new FastAPI endpoints using the existing thin-router + service + repository OOP pattern.

The most critical change is the task status machine: `tasks` currently has a DB CHECK constraint `status IN ('not_started','in_progress','complete','blocked')`. Adding `rejected` requires a backend Alembic migration to alter that constraint, a new Drift schema version with `schemaVersion => 12`, and defensive handling in `watchTasksForContractor` (which currently excludes `complete` from the contractor's view — `rejected` should be treated similarly, remaining visible so contractors see the rejection reason).

FCM for rejection (INSP-04) is a direct parallel of `queue_task_completion_digest` in `NotificationService` — fire-and-forget, uses the existing `_fcm_executor` thread pool, looks up contractor device tokens, never blocks the primary operation.

**Primary recommendation:** Structure Phase 24 into 4 waves: (1) backend data model + migrations for all three new entities + task status extension, (2) backend endpoints for inspection/flag/punch, (3) mobile Drift schema + DAOs + providers, (4) UI extensions (task detail inspect bar, flag capture, punch rendering).

---

## Standard Stack

### Core (Established — Same Stack as Prior Phases)
| Layer | Library/Pattern | Version | Purpose |
|-------|----------------|---------|---------|
| Backend ORM | SQLAlchemy async | 2.x | New models inherit TenantScopedModel |
| Backend API | FastAPI | 0.115 | Thin routers, service layer |
| Backend DB | PostgreSQL 13 | 13 | RLS, JSONB for checklist data |
| Backend migrations | Alembic | current | Migration `0022_inspection_workflow.py` |
| Mobile DB | Drift + drift_flutter | current | `schemaVersion => 12`, new tables |
| Mobile state | Riverpod 3 | current | StreamProvider.autoDispose.family for new DAOs |
| Push | firebase_admin (backend) + firebase_messaging (mobile) | current | Rejection FCM, fire-and-forget |

### Key Discretion Decisions (Research Recommendations)

**Inspection checklist storage:** Use JSONB column `inspection_checklist` on `trade_scopes` table (not a separate table). The checklist is a simple ordered list of check items — a separate table adds joins without benefit. Universal defaults are baked in the service as a constant; per-trade overrides are stored in the JSONB column. The Drift `TradeScopes` table gets a nullable `inspectionChecklist` TEXT column.

**Rejection reason list (recommended set):**
1. `rework_needed` — "Rework needed"
2. `quality_issue` — "Quality does not meet standard"
3. `wrong_materials` — "Wrong materials used"
4. `incomplete` — "Work is incomplete"
5. `safety_concern` — "Safety concern identified"
6. `other` — "Other (see comment)"

**Universal default checklist items (recommended set):**
1. "Quality of work is acceptable"
2. "Correct materials were used"
3. "Work area is clean and safe"
4. "Safety requirements are met"

**Site walk flag additional fields (recommended):** `severity` (low/medium/high), `location_label` (optional free-text location description). Keep it minimal — photo + description + severity + location covers 95% of use cases.

**Punch list item status lifecycle:** `open → in_progress → resolved → verified`. Verified = GC has confirmed the punch item was addressed. Aligns with standard punch list workflow.

**Converted flag linkage:** Add nullable `source_flag_id` FK on `punch_list_items` pointing to `site_walk_flags`. Non-destructive: the original flag remains with its own status updated to `converted`. One-to-one: a flag can only be converted once.

---

## Architecture Patterns

### New Backend Entities

#### `TaskInspection` model (NEW — tied to a task)
```python
class TaskInspection(TenantScopedModel):
    __tablename__ = "task_inspections"
    task_id: UUID FK tasks.id CASCADE
    inspector_id: UUID soft FK (no hard FK — pattern from TaskNote)
    decision: Text  # 'approved' | 'rejected'
    checklist_results: JSONB  # [{item: str, checked: bool}]
    rejection_reason: Text nullable  # enum value
    rejection_comment: Text nullable
    rejection_photo_url: Text nullable  # URL of annotated rejection photo
    # TenantScopedModel provides: id, company_id, version, created_at, updated_at, deleted_at
```

**Rationale:** Storing inspection results separately from the task (not inline on Task) preserves the audit trail and supports future "re-inspection" flows where a task might be rejected, reworked, and re-inspected.

#### `SiteWalkFlag` model (NEW — project-scoped)
```python
class SiteWalkFlag(TenantScopedModel):
    __tablename__ = "site_walk_flags"
    project_id: UUID FK projects.id CASCADE
    flagged_by: UUID soft FK
    description: Text
    severity: Text  # 'low' | 'medium' | 'high'
    location_label: Text nullable
    photo_url: Text nullable
    annotation_data: JSONB nullable  # same JSON format as TaskAttachment.annotation_data
    status: Text  # 'open' | 'converted' | 'dismissed'
```

#### `PunchListItem` model (NEW — trade-scope-scoped)
```python
class PunchListItem(TenantScopedModel):
    __tablename__ = "punch_list_items"
    project_id: UUID FK projects.id CASCADE
    trade_scope_id: UUID FK trade_scopes.id CASCADE  # which trade is responsible
    created_by: UUID soft FK
    assigned_to: UUID soft FK nullable
    description: Text
    priority: Text  # 'low' | 'medium' | 'high' | 'urgent'
    status: Text  # 'open' | 'in_progress' | 'resolved' | 'verified'
    photo_url: Text nullable
    annotation_data: JSONB nullable
    source_flag_id: UUID nullable soft FK to site_walk_flags.id
    due_date: Date nullable
```

### Task Status Machine Extension

**Current constraint (tasks table):**
```sql
CHECK (status IN ('not_started','in_progress','complete','blocked'))
```

**New constraint (migration 0022):**
```sql
CHECK (status IN ('not_started','in_progress','complete','blocked','rejected'))
```

**State transitions:**
- `complete → rejected` (GC rejects) — creates TaskInspection record
- `complete → approved` (GC approves) — creates TaskInspection record, task stays `complete`
- `rejected → in_progress` (contractor re-opens for rework) — consistent with current `complete → in_progress` pattern

**Important:** `approved` is NOT a task status. Approval is recorded in `TaskInspection.decision = 'approved'`. The task stays `complete` — only rejection changes the task status. This avoids adding approved to the status machine, which would complicate the dependency engine.

### Recommended New Endpoints

```
POST /tasks/{task_id}/inspect          — approve or reject (GC/admin only)
POST /projects/{project_id}/flags      — create site walk flag
GET  /projects/{project_id}/flags      — list flags for a project
PATCH /flags/{flag_id}/convert         — convert flag to punch item
POST /projects/{project_id}/punch-items — create punch list item directly
GET  /trade-scopes/{scope_id}/punch-items — list punch items for a scope (contractor view)
PATCH /punch-items/{item_id}           — update status (contractor marks resolved)
```

### Backend Service Pattern (following existing OOP rules)

```python
class InspectionService(TenantScopedService[TaskInspection]):
    repository_class = TaskInspectionRepository

    async def inspect_task(
        self,
        task_id: uuid.UUID,
        decision: str,  # 'approved' | 'rejected'
        checklist_results: list[dict],
        rejection_reason: str | None,
        rejection_comment: str | None,
        rejection_photo_url: str | None,
        inspector_id: uuid.UUID,
    ) -> TaskInspection:
        # 1. Verify task exists and is 'complete'
        # 2. Create TaskInspection record
        # 3. If rejected: update task.status = 'rejected'; trigger FCM fire-and-forget
        # 4. flush() and return inspection record
        ...

class SiteWalkFlagService(TenantScopedService[SiteWalkFlag]):
    repository_class = SiteWalkFlagRepository

    async def convert_to_punch_item(self, flag_id, trade_scope_id, ...) -> PunchListItem:
        # 1. Load flag, verify it is 'open'
        # 2. Create PunchListItem with source_flag_id = flag_id
        # 3. Update flag.status = 'converted'
        # 4. flush() and return punch item
        ...

class PunchListService(TenantScopedService[PunchListItem]):
    repository_class = PunchListRepository
```

### FCM Rejection Notification (INSP-04)

Follows exact same pattern as `queue_task_completion_digest` in `NotificationService`:

```python
async def send_task_rejection_notification(
    self,
    task_id: uuid.UUID,
    task_title: str,
    rejection_reason: str,
    contractor_id: uuid.UUID,
) -> None:
    """Fire-and-forget FCM to contractor on task rejection.

    All failures logged but never raised — never blocks the inspect operation.
    Data payload: type='task_rejection', task_id=str, rejection_reason=str.
    """
    firebase_app = _get_firebase_app()
    if firebase_app is None:
        logger.debug("FCM not configured — skipping rejection notification")
        return
    # ... follow _send_to_token pattern
```

**FCM data payload:**
```python
{
    "type": "task_rejection",
    "task_id": str(task_id),
    "rejection_reason": rejection_reason,
}
```

Mobile deep-link: on tap, navigate to the task detail screen using `task_id`.

### Mobile Drift Schema (schemaVersion 12)

New tables to add:

```dart
// tables/task_inspections.dart
class TaskInspections extends Table {
  TextColumn get id => ...
  TextColumn get companyId => text().references(Companies, #id)();
  TextColumn get taskId => text().references(ProjectTasks, #id)();
  TextColumn get inspectorId => text()();  // soft FK
  TextColumn get decision => text()();     // 'approved' | 'rejected'
  TextColumn get checklistResults => text().withDefault(Constant('[]'))();  // JSON
  TextColumn get rejectionReason => text().nullable()();
  TextColumn get rejectionComment => text().nullable()();
  TextColumn get rejectionPhotoUrl => text().nullable()();
  ...timestamps, deletedAt
}

// tables/site_walk_flags.dart
class SiteWalkFlags extends Table {
  TextColumn get projectId => text().references(Projects, #id)();
  TextColumn get flaggedBy => text()();  // soft FK
  TextColumn get description => text()();
  TextColumn get severity => text().withDefault(Constant('medium'))();
  TextColumn get locationLabel => text().nullable()();
  TextColumn get photoLocalPath => text().nullable()();
  TextColumn get annotationData => text().nullable()();
  TextColumn get status => text().withDefault(Constant('open'))();
  ...timestamps, deletedAt
}

// tables/punch_list_items.dart
class PunchListItems extends Table {
  TextColumn get projectId => text().references(Projects, #id)();
  TextColumn get tradeScopeId => text().references(TradeScopes, #id)();
  TextColumn get createdBy => text()();  // soft FK
  TextColumn get assignedTo => text().nullable()();  // soft FK
  TextColumn get description => text()();
  TextColumn get priority => text().withDefault(Constant('medium'))();
  TextColumn get status => text().withDefault(Constant('open'))();
  TextColumn get photoLocalPath => text().nullable()();
  TextColumn get annotationData => text().nullable()();
  TextColumn get sourceFlagId => text().nullable()();  // soft FK to SiteWalkFlags
  DateTimeColumn get dueDate => dateTime().nullable()();
  ...timestamps, deletedAt
}
```

**Drift schemaVersion migration block (from < 12):**
```dart
if (from < 12) {
  // Phase 24: GC Inspection Workflow
  await m.createTable(taskInspections);
  await m.createTable(siteWalkFlags);
  await m.createTable(punchListItems);
  // Add inspection_checklist to trade_scopes (nullable JSON)
  await m.addColumn(tradeScopes, tradeScopes.inspectionChecklist);
}
```

### Mobile Provider Pattern

```dart
// New DAOs: TaskInspectionDao, SiteWalkFlagDao, PunchListItemDao
// All follow existing TaskDao / TaskNoteDao patterns:
// - StreamProvider.autoDispose.family for lists
// - Sync queue dual-write in Drift transactions

// For punch items appearing in contractor's task view:
// Option A: Separate provider that returns PunchListItem list per scope
// Option B: Union type query (complex in Drift)
// RECOMMENDATION: Option A — separate watchPunchItemsByScope stream, render punch
// items after regular tasks in TradeScopeDetailScreen with visual "Punch" badge.
// Avoids complex Drift union queries entirely.

final punchItemsProvider = StreamProvider.autoDispose
    .family<List<PunchListItem>, String>((ref, tradeScopeId) {
  final dao = ref.watch(punchListItemDaoProvider);
  return dao.watchByScopeId(tradeScopeId);
});
```

### TradeScope Drift Table Addition

```dart
// In tables/trade_scopes.dart — add:
TextColumn get inspectionChecklist => text().nullable()();
// JSON: [{"item": "Quality acceptable", "id": "q1"}, ...]
// Null = use universal defaults
```

### Inspection Checklist UX Pattern

Per D-02 and D-03, the inspection checklist renders as a list of toggleable checkboxes inside TaskDetailScreen (GC view only, shown when task is `complete`). The "Approve" button is disabled until all checklist items are checked. Rejection bypasses the checklist gate.

```dart
class _InspectionChecklist extends StatefulWidget {
  final List<Map<String, dynamic>> items;  // from scope or defaults
  final void Function(bool allChecked, List<Map<String, dynamic>> results) onChanged;
}
```

### Rejection Bottom Sheet Pattern

When GC taps "Reject", a `showModalBottomSheet` presents:
1. `DropdownButtonFormField` for rejection reason (required)
2. `TextField` for free-text comment (optional)
3. "Add Photo" button that pushes `PhotoAnnotationScreen` — same reuse pattern as task photo annotation
4. "Confirm Rejection" button

This follows the existing `showModalBottomSheet` pattern in `TaskDetailScreen._addPhoto`.

### TaskDetailScreen Bottom Bar Extension (D-01)

Current bottom bar has 2 buttons: "Add Photo" + "Mark Done"/"Mark Incomplete".

When `task.status == 'complete'` AND `isGcOrAdmin`:
- Hide "Add Photo" (irrelevant for inspection)
- Replace "Mark Done"/"Mark Incomplete" with:
  - "Reject" (OutlinedButton with error color)
  - "Approve" (ElevatedButton, disabled until all checklist items checked)

Role check pattern (already in auth state):
```dart
final isGcOrAdmin = authState is AuthAuthenticated &&
    (authState.roles.contains(UserRole.gc) ||
     authState.roles.contains(UserRole.admin));
```

---

## Don't Hand-Roll

| Problem | Don't Build | Use Instead |
|---------|-------------|-------------|
| Photo annotation for rejection evidence | Custom annotation UI | Reuse existing `PhotoAnnotationScreen` — push it, pop result as JSON string |
| FCM token lookup + send | Custom dispatch | Extend `NotificationService` with `send_task_rejection_notification` |
| Bottom sheet for rejection form | Custom overlay | `showModalBottomSheet` (established pattern in TaskDetailScreen) |
| Punch item badge rendering | Custom widget | Add `'punch'` case to existing `_StatusBadge._color()` method |
| Offline sync for new entities | Custom sync | Add new entity types to sync queue — same `_buildQueueEntry` pattern in TaskDao |

---

## Common Pitfalls

### Pitfall 1: Task Status CHECK Constraint Not Updated
**What goes wrong:** Inserting `status = 'rejected'` into `tasks` fails with a PostgreSQL CheckConstraint violation.
**Why it happens:** The Alembic migration must DROP and RE-ADD the constraint to include `'rejected'`. ALTER TABLE cannot simply modify a CHECK constraint.
**How to avoid:** Migration `0022` must:
```sql
ALTER TABLE tasks DROP CONSTRAINT tasks_status_check;
ALTER TABLE tasks ADD CONSTRAINT tasks_status_check
  CHECK (status IN ('not_started','in_progress','complete','blocked','rejected'));
```
**Warning signs:** 500 errors on inspect endpoint; `psycopg2.errors.CheckViolation` in logs.

### Pitfall 2: watchTasksForContractor Excludes `rejected` Tasks
**What goes wrong:** Contractor cannot see their rejected tasks because `TaskDao.watchTasksForContractor` filters `tbl.status.isNotIn(const ['complete'])`. The `rejected` status should also appear in the contractor view (they need to see what was rejected).
**Why it happens:** The original filter excludes `complete` because completed tasks are "done". But `rejected` tasks need contractor action — they SHOULD appear.
**How to avoid:** Change filter to `isNotIn(const ['complete'])` is correct — `rejected` is NOT in that list so it DOES appear. Verify this works as intended. The current query already handles this correctly. No change needed to `watchTasksForContractor`.
**Warning signs:** Contractor sees no rejected tasks; confused about what to rework.

### Pitfall 3: Drift schemaVersion Must Be Bumped
**What goes wrong:** New Drift tables are defined but not added to `AppDatabase.tables` + `onUpgrade`, causing `sqlite3.SqliteException: no such table` at runtime.
**Why it happens:** Drift requires explicit table registration AND migration step. Just adding table definitions doesn't auto-migrate existing installs.
**How to avoid:**
1. Add new tables to `@DriftDatabase(tables: [...])` list
2. Register new DAOs in `daos: [...]`
3. Add `if (from < 12)` migration block
4. Increment `schemaVersion => 12`
5. Run `dart run build_runner build --delete-conflicting-outputs` to regenerate `.g.dart`

### Pitfall 4: FCM fire-and-forget Must Not Block Inspect Response
**What goes wrong:** If FCM dispatch is awaited without proper try/catch, a Firebase error causes the inspect endpoint to fail, rolling back the TaskInspection record.
**Why it happens:** Async exceptions propagate unless caught.
**How to avoid:** Wrap the entire `send_task_rejection_notification` call in a fire-and-forget pattern — do NOT await it in the service layer, or wrap it in `asyncio.create_task()`. Follow the exact same outer `try/except Exception` pattern from `queue_task_completion_digest`.

### Pitfall 5: Punch Items vs Tasks in Drift — No Union Query Support
**What goes wrong:** Attempting to write a Drift JOIN or UNION query combining ProjectTasks and PunchListItems in a single stream hits Drift's limitation with complex unions.
**Why it happens:** Drift's type-safe query builder does not natively support UNION across different table types in a single stream.
**How to avoid:** Per recommendation above — use two separate providers (`tasksProvider` + `punchItemsProvider`) in the UI, render them as separate sections or concatenate the lists in the widget layer. No complex DAO queries needed.

### Pitfall 6: `rejected` Status and Dependency Engine Interaction
**What goes wrong:** When task status is set to `rejected`, `DependencyService._recompute_blocked_status` could interfere — it checks if a task is `complete` to unblock successors. A `rejected` task was previously `complete`, so its successors may have been unblocked. Rejecting it should re-block them.
**Why it happens:** The dependency engine runs when status changes TO `complete`. Changing FROM `complete` to `rejected` is not currently handled.
**How to avoid:** In `InspectionService.inspect_task` when decision is `rejected`, after updating task status to `rejected`, call `DependencyService._recompute_blocked_status(successor_id)` for each FS/SS/SE successor of the rejected task. This re-blocks any successors that were unblocked when the task was originally completed.

---

## Code Examples

### Backend — Approved inspection (no status change), rejected inspection (status change + FCM)

```python
# Source: pattern from TaskService.recompute_successor_statuses + NotificationService
async def inspect_task(self, task_id, decision, ...) -> TaskInspection:
    task = await self.db.get(Task, task_id)
    if task is None or task.deleted_at is not None:
        raise HTTPException(status_code=404, detail="Task not found")
    if task.status != "complete":
        raise HTTPException(status_code=422, detail="Task must be 'complete' to inspect")

    inspection = TaskInspection(
        company_id=self._require_tenant_id(),
        task_id=task_id,
        inspector_id=inspector_id,
        decision=decision,
        checklist_results=checklist_results,
        rejection_reason=rejection_reason,
        rejection_comment=rejection_comment,
        rejection_photo_url=rejection_photo_url,
    )
    self.db.add(inspection)

    if decision == "rejected":
        task.status = "rejected"
        await self.db.flush()
        # Re-block successors
        await self._reblock_successors(task_id)
        # Fire-and-forget FCM — NEVER await this in production code
        asyncio.create_task(
            notification_svc.send_task_rejection_notification(
                task_id=task_id,
                task_title=task.title,
                rejection_reason=rejection_reason or "Rejected",
                contractor_id=task.assigned_to,
            )
        )

    await self.db.flush()
    return inspection
```

### Mobile — Drift migration for schema 12

```dart
// Source: existing pattern in app_database.dart
if (from < 12) {
  // Phase 24: GC Inspection Workflow entities
  await m.createTable(taskInspections);
  await m.createTable(siteWalkFlags);
  await m.createTable(punchListItems);
  // Per-trade inspection checklist field on trade scopes
  await m.addColumn(tradeScopes, tradeScopes.inspectionChecklist);
}
```

### Mobile — TaskDetailScreen bottom bar role-conditional rendering

```dart
// Source: existing pattern in task_detail_screen.dart
final isGcOrAdmin = authState is AuthAuthenticated &&
    (authState.roles.contains(UserRole.gc) ||
     authState.roles.contains(UserRole.admin));
final showInspectBar = isCompleted && isGcOrAdmin;

// Bottom bar:
if (showInspectBar) ...[
  // Reject button (always enabled)
  Expanded(child: OutlinedButton(
    style: OutlinedButton.styleFrom(foregroundColor: colorScheme.error),
    onPressed: () => _showRejectionSheet(context),
    child: const Text('Reject'),
  )),
  const SizedBox(width: 12),
  // Approve button (disabled until checklist complete)
  Expanded(child: ElevatedButton(
    onPressed: _allChecklistItemsChecked ? () => _approve() : null,
    child: const Text('Approve'),
  )),
]
```

### Mobile — Sync queue entry for inspection

```dart
// Source: pattern from TaskDao._buildQueueEntry
await into(syncQueue).insert(
  SyncQueueCompanion.insert(
    id: Value(const Uuid().v4()),
    entityType: 'task_inspection',
    entityId: inspectionId,
    operation: 'CREATE',
    payload: jsonEncode({
      'taskId': taskId,
      'decision': decision,
      'checklistResults': checklistResults,
      'rejectionReason': rejectionReason,
      'rejectionComment': rejectionComment,
    }),
    status: const Value('pending'),
    attemptCount: const Value(0),
    createdAt: DateTime.now(),
  ),
);
```

---

## State of the Art

| Old Approach | Current Approach | Impact for Phase 24 |
|--------------|------------------|---------------------|
| Task status is `complete` only terminal | Task can be `rejected` after `complete` | Requires constraint migration + dependency engine update |
| Annotations only on TaskAttachments | Annotations reusable: task attachments, rejection photos, site walk flags, punch list items | Same PhotoAnnotationScreen + annotation JSON format across all new entities |
| FCM only for job updates + task completion digest | FCM also for task rejection | Direct extension of NotificationService pattern |

---

## Open Questions

1. **Rejection photo upload path**
   - What we know: Rejection photos follow the `PhotoAnnotationScreen → JSON annotation overlay` pattern already established.
   - What's unclear: Do rejection photos get uploaded via the same `POST /files/upload` endpoint as task attachment photos, or stored as part of the inspection record?
   - Recommendation: Store `rejection_photo_url` as a URL in `TaskInspection` — the planner should specify using the existing `POST /files/upload` endpoint for the binary upload, then passing the returned URL to the inspect endpoint. Keeps inspection creation as a single PATCH with a URL rather than a multipart form.

2. **Punch list items in My Tasks screen**
   - What we know: My Tasks screen (`watchTasksForContractor`) currently queries `project_tasks` only.
   - What's unclear: Should punch list items also appear in the cross-project "My Tasks" view, or only within the trade scope task list?
   - Recommendation: Based on D-08 ("appear inline in the contractor's trade scope task view"), punch items are scoped to a specific trade scope. Add them to the `TradeScopeDetailScreen` task list only — NOT to the cross-project My Tasks view. Simpler implementation; punch items always have a clear scope context.

3. **`inspectionChecklist` on trade scopes: Drift vs backend**
   - What we know: CONTEXT.md marks this as Claude's discretion (JSONB vs separate table).
   - Recommendation: JSONB on `trade_scopes` (both backend `inspection_checklist JSONB nullable` column and Drift `TextColumn inspectionChecklist` nullable). Simple to query, editable by GC in a later phase without schema changes. No separate table needed.

---

## Validation Architecture

### Test Framework
| Property | Value |
|----------|-------|
| Framework | pytest (backend) + flutter test (mobile) |
| Config file | `backend/pytest.ini` (or conftest.py), `mobile/test/` |
| Quick run command | `cd backend && uv run python -m pytest tests/test_phase_24_e2e.py -x` |
| Full suite command | `cd backend && uv run python -m pytest && cd ../mobile && flutter test` |

### Phase Requirements → Test Map
| Req ID | Behavior | Test Type | Automated Command | File Exists? |
|--------|----------|-----------|-------------------|-------------|
| INSP-01 | GC approves a complete task → TaskInspection created, task stays complete | Integration | `pytest tests/test_phase_24_e2e.py::test_gc_approves_task -x` | Wave 0 |
| INSP-01 | GC rejects a complete task → TaskInspection created, task status = rejected | Integration | `pytest tests/test_phase_24_e2e.py::test_gc_rejects_task -x` | Wave 0 |
| INSP-01 | Rejecting non-complete task returns 422 | Integration | `pytest tests/test_phase_24_e2e.py::test_reject_non_complete_task -x` | Wave 0 |
| INSP-01 | Approval checklist UI (all items checked enables Approve) | Widget | `flutter test test/e2e/phase_24_inspection_e2e_test.dart` | Wave 0 |
| INSP-02 | GC creates a site walk flag with photo + annotation | Integration | `pytest tests/test_phase_24_e2e.py::test_create_site_walk_flag -x` | Wave 0 |
| INSP-02 | Camera-first flag capture flow (skip photo → form fallback) | Widget | `flutter test test/e2e/phase_24_inspection_e2e_test.dart` | Wave 0 |
| INSP-03 | GC creates punch list item assigned to trade scope | Integration | `pytest tests/test_phase_24_e2e.py::test_create_punch_item -x` | Wave 0 |
| INSP-03 | Punch item appears in contractor trade scope view with "Punch" badge | Widget | `flutter test test/e2e/phase_24_inspection_e2e_test.dart` | Wave 0 |
| INSP-04 | FCM sent to contractor on rejection (token present) | Integration | `pytest tests/test_phase_24_e2e.py::test_rejection_fcm -x` | Wave 0 |
| INSP-04 | FCM gracefully skipped when GOOGLE_APPLICATION_CREDENTIALS not set | Integration | `pytest tests/test_phase_24_e2e.py::test_rejection_fcm_no_creds -x` | Wave 0 |

### Sampling Rate
- **Per task commit:** `cd backend && uv run python -m pytest tests/test_phase_24_e2e.py -x`
- **Per wave merge:** Full backend + mobile test suite
- **Phase gate:** Full suite green before `/gsd:verify-work`

### Wave 0 Gaps
- [ ] `backend/tests/test_phase_24_e2e.py` — covers INSP-01 through INSP-04 backend flows
- [ ] `mobile/test/e2e/phase_24_inspection_e2e_test.dart` — covers inspection UI, flag capture, punch badge
- [ ] `mobile/test/features/projects/inspection_checklist_test.dart` — unit tests for checklist logic
- [ ] New Drift tables regeneration: `cd mobile && dart run build_runner build --delete-conflicting-outputs`

---

## Sources

### Primary (HIGH confidence)
- Direct code inspection: `mobile/lib/features/projects/presentation/screens/task_detail_screen.dart` — bottom bar extension point
- Direct code inspection: `backend/app/features/projects/models.py` — task status constraint (line 238-245)
- Direct code inspection: `backend/app/features/notifications/service.py` — FCM fire-and-forget pattern
- Direct code inspection: `mobile/lib/features/projects/data/task_dao.dart` — sync queue dual-write
- Direct code inspection: `mobile/lib/core/database/app_database.dart` — schemaVersion 11, migration pattern
- Direct code inspection: `mobile/lib/features/projects/presentation/screens/photo_annotation_screen.dart` — annotation screen reuse interface
- Direct code inspection: `backend/migrations/versions/0021_performance_indexes.py` — latest migration is 0021; next is 0022

### Secondary (MEDIUM confidence)
- `.planning/phases/24-gc-inspection-workflow/24-CONTEXT.md` — all design decisions locked
- `.planning/phases/22-task-execution-and-photo-annotation/22-CONTEXT.md` — annotation JSON schema and photo pattern

---

## Metadata

**Confidence breakdown:**
- Standard stack: HIGH — same stack as prior 6 phases, all verified from code
- Architecture: HIGH — all patterns directly copied from existing, verified working code
- Pitfalls: HIGH — identified from code reading (constraint format, Drift limitations, FCM fire-and-forget requirements all verified in source)
- Open questions: LOW-MEDIUM — two discretion items are planner calls, not blocking

**Research date:** 2026-03-25
**Valid until:** 2026-04-25 (stable stack)
