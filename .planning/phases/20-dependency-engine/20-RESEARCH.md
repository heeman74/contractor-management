# Phase 20: Dependency Engine - Research

**Researched:** 2026-03-21
**Domain:** Graph algorithms (DAG cycle detection, topological sort), Gantt chart UI (web + mobile), dependency data modeling, conflict detection
**Confidence:** HIGH

---

<user_constraints>
## User Constraints (from CONTEXT.md)

### Locked Decisions
- **All four dependency types** supported: Finish-to-Start (FS), Start-to-Start (SS), Finish-to-Finish (FF), Start-to-End (SE)
- **Task-to-task granularity** for cross-trade dependencies (not scope-to-scope)
- **Unified edge table** — migrate intra-scope `depends_on` JSONB into a single `TaskDependency` edge table. Remove `depends_on` JSONB from Task model. Single source of truth for all dependencies (intra-scope and cross-scope)
- **Lag/lead time supported** — each dependency link has an optional lag field (positive = delay in days, negative = overlap/lead)
- **Hard block enforcement** — tasks with unmet dependencies cannot be started. Status stays 'blocked', start button disabled. No override mechanism
- **Sync to Drift** — TaskDependency edges sync to mobile like other entities. Contractors see blocked status offline
- **Both platforms** — full interactive Gantt on web AND mobile
- **Full interactive** — drag bars to reschedule, drag-connect to create dependencies, click to edit task details, zoom in/out (MS Project-like on web)
- **Swim lanes by trade** — each trade scope gets its own horizontal lane colored by trade
- **Progress visualization** — filled progress bars showing completion %, status colors (green = on track, yellow = at risk/behind schedule, red = blocked), today line as vertical marker
- **Dependency creation via drag-connect** on the Gantt chart (visual arrow drawing)
- **Location + date overlap** defines a conflict — two tasks from different trades scheduled on the same date AND assigned to the same project zone/area
- **Project-level zone list** — GC defines zones (Kitchen, Master Bath, Garage, etc.). Tasks pick from this list
- **Warning with details** — "Electrical and Plumbing overlap in Kitchen on Mar 25". Not a hard block
- **Surfaced everywhere** — conflict indicators on Gantt chart, conflict badge on task detail page, conflict count on project overview card
- **Detection at creation time** — validate every new dependency link before saving. Reject immediately if cycle
- **Visual cycle path on Gantt** — highlight the cycle path with red arrows
- **Mobile cycle errors** — text dialog showing the cycle as a readable chain: "Framing -> Electrical -> Plumbing -> Framing"

### Claude's Discretion
- Gantt chart library selection (web and mobile)
- Topological sort algorithm choice
- Cycle detection algorithm choice (DFS, Kahn's, etc.)
- TaskDependency edge table schema details (indexes, constraints)
- Zone list UI design (modal vs inline)
- Gantt chart zoom levels and time scale options
- Mobile Gantt interaction patterns (pinch-to-zoom, horizontal scroll)

### Deferred Ideas (OUT OF SCOPE)
- AI-generated zone lists from project description — Phase 21 (AI Intake)
- AI conflict resolution suggestions — Phase 21+ (AI features)
- Critical path highlighting on Gantt — possible future enhancement
- Milestone diamonds on Gantt — possible future enhancement
</user_constraints>

---

<phase_requirements>
## Phase Requirements

| ID | Description | Research Support |
|----|-------------|-----------------|
| PROJ-04 | System enforces cross-trade task dependencies (Task A must finish before Task B starts) | TaskDependency edge table, cycle detection service, blocked status auto-compute, DFS algorithm section |
| PROJ-05 | GC can view project timeline with all trades on a Gantt-style chart showing dependencies | SVAR React Gantt (web), custom Flutter Gantt (mobile), swim lanes, dependency arrows sections |
| AI-06 | AI detects cross-trade conflicts (two trades needing same space on same day) | ProjectZone model, conflict detection SQL, warning surfacing section |
</phase_requirements>

---

## Summary

Phase 20 introduces a dependency engine on top of the Phase 19 project data model. The three pillars are: (1) a relational `task_dependencies` edge table replacing the current JSONB `depends_on` field on Task, (2) server-side cycle detection using DFS with path tracking that runs synchronously before any dependency edge is persisted, and (3) interactive Gantt chart views on both web and mobile.

The web Gantt uses **@svar-ui/react-gantt** (version 2.5.2, MIT license) — the only fully open-source React Gantt library with all four dependency types, drag-connect, and Next.js 14+ compatibility. The mobile Gantt requires a **custom Flutter implementation using CustomPainter** because no pub.dev package combines swim lanes, cross-lane dependency arrows, and drag-to-connect at production quality. The mobile Gantt is the largest single piece of new work in this phase.

Conflict detection (AI-06) is implemented without AI in this phase: a SQL query finds tasks from different trade scopes that share the same `zone_id` and overlap date ranges. The AI label in the requirement refers to the detection being automated (not requiring manual review), not an LLM-based analysis.

**Primary recommendation:** Use DFS with recursion-stack path tracking for cycle detection (returns the cycle chain for display). Use SVAR Gantt on web. Build the mobile Gantt as a custom `CustomPainter` widget with `InteractiveViewer` for zoom/pan.

---

## Standard Stack

### Core
| Library | Version | Purpose | Why Standard |
|---------|---------|---------|--------------|
| @svar-ui/react-gantt | 2.5.2 | Interactive Gantt chart for web | Only MIT-licensed React Gantt with FS/SS/FF/SE deps, drag-connect, Next.js SSR support |
| SQLAlchemy async | 2.0.38 | ORM for TaskDependency, ProjectZone models | Already used throughout; async session, lazy="raise" pattern required |
| Alembic | (existing) | Migration 0016: add task_dependencies, project_zones, alter tasks | Already used for all migrations |
| Drift | 2.32.0 | TaskDependencies, ProjectZones Drift tables for mobile | Already used; schema version 7 → 8 upgrade |
| Flutter CustomPainter | SDK | Mobile Gantt chart rendering | No viable pub.dev alternative; full control over swim lanes + arrows |
| InteractiveViewer | SDK | Pinch-to-zoom and pan on mobile Gantt | Built-in Flutter widget; wraps CustomPainter canvas |

### Supporting
| Library | Version | Purpose | When to Use |
|---------|---------|---------|-------------|
| recharts | 3.8.0 | Already installed — NOT used for Gantt | Do not use for Gantt; lacks dependency arrows |
| date-fns | 4.1.0 | Date arithmetic for lag/lead computation | Already installed; use for computing effective start/end dates |
| lucide-react | 0.577.0 | Warning/conflict icons | Already installed |
| @tanstack/react-query | 5.90.21 | Data fetching for Gantt and dependency API | Already used throughout web |

### Alternatives Considered
| Instead of | Could Use | Tradeoff |
|------------|-----------|----------|
| @svar-ui/react-gantt | DHTMLX Gantt | DHTMLX costs $699+; has swim lanes but commercial; SVAR is MIT and sufficient |
| @svar-ui/react-gantt | Bryntum Gantt | Bryntum costs $940+; best MS Project feel but commercial; out of budget |
| @svar-ui/react-gantt | gantt-task-react 0.3.9 | Abandoned; drag-connect dependency arrows not implemented (open GitHub issue #44) |
| CustomPainter (mobile) | interactive_gantt_chart | 88 downloads/week, no swim lanes, no cross-lane dependency arrows, low adoption |
| DFS cycle detection | Kahn's algorithm | Kahn's detects cycles but does NOT return the cycle path needed for display. DFS with recursion stack returns the exact node chain |

**Installation (web only — new dependency):**
```bash
cd web && npm install @svar-ui/react-gantt
```

**Version verification (confirmed 2026-03-21):**
- `@svar-ui/react-gantt`: `npm view @svar-ui/react-gantt version` → 2.5.2
- `gantt-task-react`: `npm view gantt-task-react version` → 0.3.9 (last publish 2022 — do NOT use)

---

## Architecture Patterns

### Recommended Project Structure

New files created in this phase:

```
backend/
├── migrations/versions/
│   └── 0016_dependency_engine.py    # task_dependencies + project_zones + drop depends_on
├── app/features/projects/
│   ├── models.py                    # + TaskDependency, ProjectZone (append to existing)
│   ├── schemas.py                   # + TaskDependencyCreate/Response, ProjectZoneCreate/Response
│   ├── repository.py                # + TaskDependencyRepository, ProjectZoneRepository
│   ├── service.py                   # + DependencyService (cycle detection), ConflictService
│   └── router.py                    # + /dependencies endpoints, /zones endpoints

mobile/lib/
├── core/database/
│   ├── tables/
│   │   ├── task_dependencies.dart   # NEW Drift table
│   │   └── project_zones.dart       # NEW Drift table
│   └── app_database.dart            # add tables, daos; schemaVersion → 8
├── features/projects/
│   ├── data/
│   │   ├── task_dependency_dao.dart  # NEW
│   │   └── project_zone_dao.dart     # NEW
│   └── presentation/
│       ├── screens/
│       │   └── gantt_screen.dart     # NEW — full Gantt page
│       └── widgets/
│           ├── gantt_chart_widget.dart       # CustomPainter-based Gantt
│           ├── gantt_painter.dart            # CustomPainter implementation
│           └── dependency_arrow_painter.dart  # SVG-style arrow overlay

web/src/
├── app/(dashboard)/projects/
│   └── [id]/
│       └── gantt/
│           └── page.tsx             # NEW — Gantt page route
├── components/gantt/
│   ├── GanttView.tsx               # SVAR Gantt wrapper + swim lane config
│   ├── ConflictBadge.tsx           # Conflict warning display
│   └── CycleErrorDialog.tsx        # Cycle detection error UI
└── types/
    └── dependencies.ts             # NEW TypeScript interfaces
```

### Pattern 1: TaskDependency Edge Table Schema

**What:** Single table stores all task-to-task dependency edges for both intra-scope and cross-scope dependencies. Replaces the JSONB `depends_on` column on Task.

**When to use:** All dependency creation, validation, and graph traversal use this table exclusively.

**Backend model:**
```python
# Source: established TenantScopedModel pattern from backend/app/core/base_models.py
class TaskDependency(TenantScopedModel):
    """Edge table for all task-to-task dependency links.

    dependency_type: FS | SS | FF | SE (Finish-to-Start, Start-to-Start,
                     Finish-to-Finish, Start-to-End)
    lag_days: positive = delay (lag), negative = overlap (lead). Days unit.

    UNIQUE(predecessor_task_id, successor_task_id): prevents duplicate edges.
    company_id: for RLS tenant isolation (inherited from TenantScopedModel).
    """
    __tablename__ = "task_dependencies"

    predecessor_task_id: Mapped[uuid.UUID] = mapped_column(
        UUID(as_uuid=True), ForeignKey("tasks.id", ondelete="CASCADE"), nullable=False
    )
    successor_task_id: Mapped[uuid.UUID] = mapped_column(
        UUID(as_uuid=True), ForeignKey("tasks.id", ondelete="CASCADE"), nullable=False
    )
    dependency_type: Mapped[str] = mapped_column(
        Text, nullable=False, server_default="'FS'"
    )
    lag_days: Mapped[int] = mapped_column(Integer, nullable=False, server_default="0")

    __table_args__ = (
        UniqueConstraint("predecessor_task_id", "successor_task_id",
                         name="uq_task_dependency_edge"),
        CheckConstraint(
            "dependency_type IN ('FS','SS','FF','SE')",
            name="task_dependencies_type_check"
        ),
        CheckConstraint(
            "predecessor_task_id != successor_task_id",
            name="task_dependencies_no_self_loop"
        ),
    )

    predecessor: Mapped[Task] = relationship(
        "Task", foreign_keys=[predecessor_task_id], lazy="raise"
    )
    successor: Mapped[Task] = relationship(
        "Task", foreign_keys=[successor_task_id], lazy="raise"
    )
```

**Drift table (mobile):**
```dart
class TaskDependencies extends Table {
  TextColumn get id => text().clientDefault(() => const Uuid().v4())();
  TextColumn get companyId => text().references(Companies, #id)();
  TextColumn get predecessorTaskId => text().references(ProjectTasks, #id)();
  TextColumn get successorTaskId => text().references(ProjectTasks, #id)();
  // FS | SS | FF | SE
  TextColumn get dependencyType => text().withDefault(const Constant('FS'))();
  // positive = lag days, negative = lead days
  IntColumn get lagDays => integer().withDefault(const Constant(0))();
  IntColumn get version => integer().withDefault(const Constant(1))();
  DateTimeColumn get createdAt => dateTime()();
  DateTimeColumn get updatedAt => dateTime()();
  DateTimeColumn get deletedAt => dateTime().nullable()();

  @override
  Set<Column> get primaryKey => {id};
}
```

### Pattern 2: ProjectZone Model

**What:** Simple list of named zones within a project. Tasks get a nullable `zone_id` FK.

**Schema:**
```python
class ProjectZone(TenantScopedModel):
    """A named spatial zone within a project (Kitchen, Master Bath, Garage).

    Used for conflict detection: two tasks with the same zone_id and
    overlapping date ranges from different trade scopes = conflict.
    """
    __tablename__ = "project_zones"

    project_id: Mapped[uuid.UUID] = mapped_column(
        UUID(as_uuid=True), ForeignKey("projects.id", ondelete="CASCADE"), nullable=False
    )
    name: Mapped[str] = mapped_column(Text, nullable=False)

    __table_args__ = (
        UniqueConstraint("project_id", "name", name="uq_project_zone_name"),
    )

    project: Mapped[Project] = relationship("Project", lazy="raise")
    tasks: Mapped[list[Task]] = relationship("Task", back_populates="zone", lazy="raise")
```

Task model gets a new column added via migration 0016:
```python
zone_id: Mapped[uuid.UUID | None] = mapped_column(
    UUID(as_uuid=True), ForeignKey("project_zones.id", ondelete="SET NULL"), nullable=True
)
```

### Pattern 3: DFS Cycle Detection with Path Return

**What:** Before persisting any new TaskDependency edge, run cycle detection across the full task dependency graph for the affected project. DFS with recursion-stack tracking returns the exact cycle path.

**Why DFS over Kahn's:** Kahn's algorithm detects whether a cycle exists but does NOT return the specific nodes forming the cycle. The UX requires displaying "Framing -> Electrical -> Plumbing -> Framing". DFS with a `path` list returns this chain directly.

**Algorithm (Python, in DependencyService):**
```python
# Source: well-established CS algorithm; verified against GeeksforGeeks and Medium 2024
def _find_cycle(
    self,
    graph: dict[str, list[str]],  # successor_id -> [predecessor_ids]
    all_nodes: set[str],
) -> list[str] | None:
    """DFS cycle detection returning the cycle path, or None if no cycle.

    Uses white/gray/black coloring:
      white (0): unvisited
      gray (1): in current DFS path (recursion stack)
      black (2): fully processed

    Returns: ordered list of task IDs forming the cycle, or None.
    """
    color = {node: 0 for node in all_nodes}
    path: list[str] = []

    def dfs(node: str) -> list[str] | None:
        color[node] = 1  # gray: on current path
        path.append(node)
        for neighbor in graph.get(node, []):
            if color[neighbor] == 1:
                # Cycle found — extract the cycle segment from path
                cycle_start = path.index(neighbor)
                return path[cycle_start:] + [neighbor]
            if color[neighbor] == 0:
                result = dfs(neighbor)
                if result:
                    return result
        color[node] = 2  # black: fully processed
        path.pop()
        return None

    for node in all_nodes:
        if color[node] == 0:
            result = dfs(node)
            if result:
                return result
    return None
```

**Service integration:**
```python
class DependencyService(TenantScopedService[TaskDependency]):
    """Manages task dependency edges with cycle detection.

    create_dependency() loads ALL edges for the project into a graph,
    speculatively adds the new edge, runs cycle detection, and raises
    HTTP 422 if a cycle is detected before persisting.
    """

    async def create_dependency(
        self, data: TaskDependencyCreate, project_id: uuid.UUID
    ) -> TaskDependency:
        # 1. Load all existing edges for this project
        # 2. Build adjacency graph (dict[task_id, list[task_id]])
        # 3. Add proposed edge speculatively
        # 4. Run _find_cycle
        # 5. If cycle: raise HTTPException 422 with cycle path in detail
        # 6. Else: persist and return
        ...
```

### Pattern 4: Blocked Status Auto-Compute

**What:** When a dependency edge is created, modified, or a task status changes, recompute `blocked` status for affected tasks. A task is `blocked` if any of its predecessor tasks have status != 'complete', respecting dependency type:
- FS: blocked if predecessor status != 'complete'
- SS: blocked if predecessor status == 'not_started'
- FF: relevant only at completion time
- SE: blocked if predecessor status == 'not_started'

**Implementation approach:** Call `_recompute_blocked_status(successor_task_id)` after any dependency write and after any task status update. This is a single query checking all predecessor edges for a given task.

**Query:**
```python
# Source: standard SQLAlchemy pattern with selectinload
async def recompute_blocked_status(self, task_id: uuid.UUID) -> None:
    """Set task.status = 'blocked' if any FS/SS/SE predecessor is not complete."""
    result = await self.db.execute(
        select(TaskDependency)
        .where(TaskDependency.successor_task_id == task_id)
        .where(TaskDependency.deleted_at.is_(None))
    )
    edges = result.scalars().all()

    is_blocked = False
    for edge in edges:
        predecessor = await self.db.get(Task, edge.predecessor_task_id)
        if predecessor and predecessor.status != 'complete':
            if edge.dependency_type in ('FS', 'SS', 'SE'):
                is_blocked = True
                break

    task = await self.db.get(Task, task_id)
    if task:
        new_status = 'blocked' if is_blocked else task.status
        if new_status != task.status and task.status != 'complete':
            task.status = new_status
            await self.db.flush()
```

### Pattern 5: Conflict Detection SQL Query

**What:** Cross-trade conflicts are two tasks from different trade scopes that share the same `zone_id` AND have overlapping date ranges (both have non-null `due_date` and their dates overlap by at least one day).

**Query (async SQLAlchemy):**
```python
# Source: standard self-join pattern
async def detect_conflicts(self, project_id: uuid.UUID) -> list[ConflictRecord]:
    """Return all zone/date conflicts for a project.

    A conflict = two tasks in different trade scopes with:
    - same zone_id (non-null)
    - overlapping date ranges (treated as single-day: due_date)
    """
    t1 = aliased(Task, name="t1")
    t2 = aliased(Task, name="t2")
    s1 = aliased(TradeScope, name="s1")
    s2 = aliased(TradeScope, name="s2")

    stmt = (
        select(t1, t2, s1.trade_name, s2.trade_name)
        .join(s1, t1.trade_scope_id == s1.id)
        .join(s2, t2.trade_scope_id == s2.id)
        .where(t1.zone_id.is_not(None))
        .where(t1.zone_id == t2.zone_id)
        .where(t1.due_date == t2.due_date)   # same day = conflict
        .where(s1.project_id == project_id)
        .where(t1.trade_scope_id != t2.trade_scope_id)
        .where(t1.id < t2.id)                 # avoid duplicate pairs
        .where(t1.deleted_at.is_(None))
        .where(t2.deleted_at.is_(None))
    )
    ...
```

### Pattern 6: SVAR Gantt Web Integration

**What:** SVAR React Gantt (`@svar-ui/react-gantt`) renders swim lanes via its task hierarchy: TradeScopes become summary tasks (group rows), individual Tasks become child task bars. Dependency arrows render natively from the `links` prop.

**Key integration:**
```typescript
// Source: SVAR Gantt official docs at docs.svar.dev/react/gantt
"use client";
import { Gantt } from "@svar-ui/react-gantt";

// Transform API data into SVAR Gantt format
const tasks = scopes.flatMap(scope => [
  // Summary row = swim lane header
  { id: scope.id, text: scope.trade_name, type: "summary",
    color: scope.trade_color },
  // Child tasks = bars within the swim lane
  ...scope.tasks.map(t => ({
    id: t.id, parent: scope.id,
    text: t.title,
    start: new Date(t.due_date || t.created_at),
    end: new Date(t.due_date || t.created_at),
    progress: t.status === 'complete' ? 100 : t.status === 'in_progress' ? 50 : 0,
  }))
]);

const links = dependencies.map(dep => ({
  id: dep.id,
  source: dep.predecessor_task_id,
  target: dep.successor_task_id,
  type: dep.dependency_type,  // "FS" | "SS" | "FF" | "SE"
}));
```

**Conflict/cycle highlighting:** SVAR supports custom task styling via `taskStyle` callback — use to apply red border/background for tasks with conflicts or cycle involvement.

### Pattern 7: Flutter Mobile Gantt (CustomPainter)

**What:** Build a custom Gantt widget using `CustomPainter` for rendering and `InteractiveViewer` for zoom/pan. No pub.dev library meets the requirements (swim lanes + cross-lane dependency arrows + drag-to-connect).

**Widget structure:**
```dart
// Source: Flutter CustomPaint documentation + established pattern
class GanttChartWidget extends StatefulWidget {
  final List<TradeScope> scopes;
  final List<ProjectTask> tasks;
  final List<TaskDependency> dependencies;
  final void Function(String predId, String succId) onDependencyCreated;
  // ...
}

class _GanttChartWidgetState extends State<GanttChartWidget> {
  @override
  Widget build(BuildContext context) {
    return InteractiveViewer(
      // Pinch-to-zoom and pan
      minScale: 0.5,
      maxScale: 3.0,
      child: CustomPaint(
        painter: GanttPainter(
          scopes: widget.scopes,
          tasks: widget.tasks,
          dependencies: widget.dependencies,
          // ... day width, lane height, date range
        ),
      ),
    );
  }
}
```

**GanttPainter responsibilities:**
- Horizontal axis: time scale (days/weeks), today line as vertical marker
- Swim lanes: one row per TradeScope, colored header strip using `trade_color`
- Task bars: horizontal rectangles within their lane row, filled by progress %
- Status colors: green (complete/on-track), amber (in_progress/at-risk), red (blocked)
- Dependency arrows: draw bezier curves between task bars. Arrow color: red if cycle-involved

**Drag-to-connect interaction:** Use `GestureDetector` with `onLongPressStart`/`onLongPressMoveUpdate`/`onLongPressEnd` to detect drag-from-task-bar gestures. Track drag origin task and draw a "ghost arrow" during drag via `setState`.

### Anti-Patterns to Avoid

- **JSONB depends_on after migration:** Never write to `Task.depends_on` after migration 0016. The column is dropped. All dependency operations go through `task_dependencies` table.
- **Cycle check after persist:** Never save a TaskDependency edge before running cycle detection. Detection must be synchronous within the same transaction — use `db.flush()` only after the check passes.
- **Lazy-loading dependencies in loops:** Never load TaskDependency edges row by row. Load the full graph for a project in a single query before running DFS.
- **Conflict detection as hard block:** The UX decision is warning-only for conflicts. Never block save on conflict — only on cycle.
- **Kahn's for cycle path display:** Kahn's tells you IF a cycle exists but not WHICH nodes. Use DFS for the cycle chain displayed in the UI.
- **InteractiveViewer clipping issues:** CustomPainter content must not exceed `constraints.biggest` without explicit size. Use `LayoutBuilder` to determine available space.

---

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| Web Gantt chart rendering | Custom SVG/Canvas React chart | @svar-ui/react-gantt | 2.5k+ stars, MIT, handles all four dep types, zoom, today line, task editing |
| Date arithmetic for lag/lead | Custom day-counting code | date-fns (addDays, differenceInDays) | DST, leap years, calendar edge cases — already installed |
| Task dependency types | Custom FS/SS/FF/SE enum logic | DB CHECK constraint + service enum | Validated at DB layer, not just app layer |
| Topological sort | Re-inventing the algorithm | Standard DFS (20 lines, pure Python) | Well-understood O(V+E), no external dependency needed |
| Mobile zoom/pan | Custom GestureDetector math | InteractiveViewer | Handles pinch scale, bounds, inertia automatically |

**Key insight:** Graph algorithms (DFS, topological sort) are standard CS algorithms that should be implemented directly in Python — no library needed. The complexity is O(V+E) and the implementation is ~30 lines. The complexity is in the data layer and the UI, not the algorithm itself.

---

## Common Pitfalls

### Pitfall 1: SVAR Gantt SSR Hydration Error
**What goes wrong:** Next.js throws hydration error because Gantt renders with browser-only APIs.
**Why it happens:** SVAR Gantt uses `window` object on import.
**How to avoid:** Add `"use client"` at the top of any file importing SVAR Gantt. Wrap the component in `dynamic(() => import('...'), { ssr: false })` as a fallback if hydration errors persist.
**Warning signs:** `ReferenceError: window is not defined` during `next build`.

### Pitfall 2: Recursive Drift DAG Query Performance
**What goes wrong:** Loading all task dependencies for a project with many tasks causes slow queries on mobile.
**Why it happens:** Naive N+1 query pattern — loading each task's predecessors separately.
**How to avoid:** Load all `TaskDependency` rows for the project in a single `SELECT` query using `selectOnly` with a WHERE clause on `companyId` + `projectId` join (via task.tradeScopeId -> tradeScope.projectId). Cache in provider state.
**Warning signs:** Gantt screen taking >500ms to render for projects with 20+ tasks.

### Pitfall 3: Circular Reference in DFS Stack Overflow
**What goes wrong:** Python DFS uses recursion, which can stack-overflow for deep dependency chains.
**Why it happens:** Python default recursion limit is 1000.
**How to avoid:** Construction projects typically have <200 tasks, so stack overflow is unlikely. Still, add a guard: if `len(all_nodes) > 500`, switch to iterative DFS with an explicit stack. Document this limit.
**Warning signs:** `RecursionError` in production logs.

### Pitfall 4: Migration 0016 Data Migration Order
**What goes wrong:** Dropping `depends_on` JSONB before migrating data into `task_dependencies` table causes data loss.
**Why it happens:** Wrong column drop order in migration.
**How to avoid:** Migration 0016 must: (1) CREATE `task_dependencies` table, (2) INSERT rows from existing `depends_on` JSONB data, (3) ALTER TABLE tasks DROP COLUMN `depends_on`. Verify with a SELECT COUNT before and after step 2.
**Warning signs:** task_dependencies table is empty immediately after migration.

### Pitfall 5: Mobile Schema Version Mismatch
**What goes wrong:** Drift app on device has schema version 7, new code expects version 8. Migration not applied, app crashes.
**Why it happens:** `onUpgrade` guard missing for `from < 8` block.
**How to avoid:** In `app_database.dart`, increment `schemaVersion` to 8 and add `if (from < 8)` block creating `taskDependencies` and `projectZones` tables and adding `zoneId` column to `projectTasks`.
**Warning signs:** `InvalidMigrationException` in Flutter debug output on upgrade.

### Pitfall 6: Conflict Detection Zone Name Drift
**What goes wrong:** Two tasks assigned to "Kitchen" and "kitchen" (different case) aren't detected as a conflict.
**Why it happens:** Zone name stored as free text, case mismatch.
**How to avoid:** `ProjectZone.name` is constrained to the zone list — tasks pick from the FK list, not free text. No free-text zone naming on tasks — only `zone_id` FK.
**Warning signs:** GC complains that conflicts visible on Gantt are not detected by the API.

---

## Code Examples

### Cycle Detection Service Method

```python
# Source: established CS algorithm; matches project DependencyService pattern
async def _load_project_graph(
    self, project_id: uuid.UUID
) -> tuple[dict[str, list[str]], set[str]]:
    """Load all task dependency edges for a project into an adjacency list.

    Returns: (graph, all_node_ids)
    graph: {predecessor_id -> [successor_id, ...]}
    """
    from sqlalchemy import select
    from app.features.projects.models import TaskDependency, Task, TradeScope

    stmt = (
        select(TaskDependency)
        .join(Task, TaskDependency.predecessor_task_id == Task.id)
        .join(TradeScope, Task.trade_scope_id == TradeScope.id)
        .where(TradeScope.project_id == project_id)
        .where(TaskDependency.deleted_at.is_(None))
    )
    result = await self.db.execute(stmt)
    edges = result.scalars().all()

    graph: dict[str, list[str]] = {}
    all_nodes: set[str] = set()
    for edge in edges:
        pred = str(edge.predecessor_task_id)
        succ = str(edge.successor_task_id)
        graph.setdefault(pred, []).append(succ)
        all_nodes.update([pred, succ])
    return graph, all_nodes
```

### TaskDependency API Endpoint Pattern

```python
# Source: follows existing router pattern in backend/app/features/projects/router.py
@router.post("/tasks/{task_id}/dependencies", response_model=TaskDependencyResponse,
             status_code=201)
async def create_dependency(
    task_id: uuid.UUID,
    data: TaskDependencyCreate,
    db: AsyncSession = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    """Create a dependency edge. Returns 422 if the edge creates a cycle."""
    svc = DependencyService(db)
    # data.successor_task_id is task_id (the task being blocked by data.predecessor_task_id)
    return await svc.create_dependency(data)
```

### SVAR Gantt Conflict Highlight

```typescript
// Source: SVAR Gantt docs (docs.svar.dev/react/gantt) - taskStyle callback
const taskStyle = (task: GanttTask) => {
  const hasConflict = conflictTaskIds.has(task.id);
  const isCycled = cycleTaskIds.has(task.id);
  if (isCycled) return { border: "2px solid #ef4444", background: "#fee2e2" };
  if (hasConflict) return { border: "2px solid #f59e0b", background: "#fef3c7" };
  return {};
};

<Gantt
  tasks={tasks}
  links={links}
  taskStyle={taskStyle}
  onLinkAdd={(link) => handleDependencyCreate(link.source, link.target, link.type)}
  onTaskUpdate={(task) => handleTaskReschedule(task.id, task.start, task.end)}
/>
```

### Drift TaskDependency Sync Handler

```dart
// Source: follows SyncHandler abstract pattern in mobile/lib/core/sync/sync_handler.dart
class TaskDependencySyncHandler extends SyncHandler {
  final Dio _dio;
  final TaskDependencyDao _dao;

  TaskDependencySyncHandler(this._dio, this._dao);

  @override
  String get entityType => 'task_dependency';

  @override
  Future<void> push(SyncQueueData item) async {
    final payload = jsonDecode(item.payload) as Map<String, dynamic>;
    switch (item.operation) {
      case 'CREATE':
        await _dio.post('/tasks/${payload['successorTaskId']}/dependencies',
            data: payload,
            options: Options(headers: {'Idempotency-Key': item.id}));
      case 'DELETE':
        await _dio.delete('/dependencies/${payload['id']}');
    }
  }

  @override
  Future<void> applyPulled(Map<String, dynamic> data) async {
    await _dao.upsertDependency(/* ... */);
  }
}
```

---

## State of the Art

| Old Approach | Current Approach | When Changed | Impact |
|--------------|------------------|--------------|--------|
| JSONB `depends_on` array on Task | Relational `task_dependencies` edge table | Phase 20 migration 0016 | Enables cross-trade deps, FK integrity, graph queries, RLS isolation |
| No dependency type | FS/SS/FF/SE with lag_days | Phase 20 | Matches PM industry standard (MS Project model) |
| No conflict detection | Zone-based date overlap SQL query | Phase 20 | Automated conflict flagging without AI inference |
| No Gantt view | SVAR Gantt (web) + custom Flutter Gantt | Phase 20 | Visual project timeline management |

**Deprecated in this phase:**
- `Task.depends_on` JSONB column: dropped in migration 0016. All existing JSONB data migrated to `task_dependencies` rows.
- `TaskCreate.depends_on` / `TaskUpdate.depends_on` schema fields: removed. Dependency management now uses the `/tasks/{id}/dependencies` endpoint.
- `ProjectTask.dependsOn` TEXT column in Drift: removed in schema version 8. Replace with `TaskDependencies` table.

---

## Open Questions

1. **SVAR Gantt swim lane configuration**
   - What we know: SVAR Gantt supports summary tasks with child tasks. Parent rows collapse/expand.
   - What's unclear: Whether summary rows show a true "lane" (colored background strip) or just a tree row. The free tier may not include resource/lane view.
   - Recommendation: Prototype SVAR Gantt with summary tasks in Wave 0 before committing. If swim lane coloring is insufficient, use DHTMLX trial edition as fallback or custom CSS overrides.

2. **Effective date computation for non-FS dependency types**
   - What we know: SS means successor cannot start before predecessor starts. FF means successor cannot finish before predecessor finishes. SE means successor cannot end before predecessor starts.
   - What's unclear: The data model has `due_date` only (single date). Multi-date tracking (start_date + end_date) is not in the current Task model.
   - Recommendation: Treat `due_date` as the "end date" for all tasks. For Gantt rendering, derive `start_date = due_date - estimated_hours / 8` (business days). Add a `start_date` column to Tasks in migration 0016 for explicit control. This is a Task model enhancement that serves the Gantt.

3. **Mobile Gantt performance with large projects**
   - What we know: Flutter CustomPainter re-paints on every frame during interaction.
   - What's unclear: Performance with 50+ tasks across 10+ trade scopes.
   - Recommendation: Use `RepaintBoundary` around the Gantt canvas. Only re-paint when task data changes (Riverpod watch). Limit initial visible date range to 30 days; scroll/zoom to navigate.

---

## Validation Architecture

### Test Framework
| Property | Value |
|----------|-------|
| Backend Framework | pytest + ASGI client (existing conftest.py) |
| Backend Config | backend/tests/conftest.py |
| Backend Quick Run | `cd backend && uv run python -m pytest tests/test_phase_20_e2e.py -x` |
| Backend Full Suite | `cd backend && uv run python -m pytest -x` |
| Flutter Framework | flutter_test + mocktail + Drift in-memory |
| Flutter Config | mobile/test/ |
| Flutter Quick Run | `cd mobile && flutter test test/e2e/phase_20_dependency_engine_e2e_test.dart` |
| Flutter Full Suite | `cd mobile && flutter test` |

### Phase Requirements → Test Map

| Req ID | Behavior | Test Type | Automated Command | File Exists? |
|--------|----------|-----------|-------------------|-------------|
| PROJ-04 | Create FS dependency between two tasks | integration | `pytest tests/test_phase_20_e2e.py::test_create_dependency -x` | ❌ Wave 0 |
| PROJ-04 | Reject dependency that creates a cycle | integration | `pytest tests/test_phase_20_e2e.py::test_cycle_rejected_422 -x` | ❌ Wave 0 |
| PROJ-04 | Task with unmet FS predecessor has status=blocked | integration | `pytest tests/test_phase_20_e2e.py::test_task_blocked_by_dependency -x` | ❌ Wave 0 |
| PROJ-04 | Task unblocked when predecessor completed | integration | `pytest tests/test_phase_20_e2e.py::test_task_unblocked_on_completion -x` | ❌ Wave 0 |
| PROJ-04 | depends_on JSONB migrated to edge table | integration | `pytest tests/test_phase_20_e2e.py::test_migration_data_integrity -x` | ❌ Wave 0 |
| PROJ-05 | Gantt page loads with trade swim lanes | E2E Playwright | `cd web && npx playwright test tests/phase_20_gantt.spec.ts` | ❌ Wave 0 |
| PROJ-05 | Dependency arrows visible on Gantt | E2E Playwright | `cd web && npx playwright test tests/phase_20_gantt.spec.ts::dependency-arrows` | ❌ Wave 0 |
| PROJ-05 | Mobile Gantt renders trade lanes | Flutter widget | `flutter test test/e2e/phase_20_dependency_engine_e2e_test.dart::gantt_renders` | ❌ Wave 0 |
| AI-06 | Two tasks in same zone on same day flagged | integration | `pytest tests/test_phase_20_e2e.py::test_conflict_detected -x` | ❌ Wave 0 |
| AI-06 | Conflict warning visible on Gantt | E2E Playwright | `cd web && npx playwright test tests/phase_20_gantt.spec.ts::conflict-badge` | ❌ Wave 0 |
| AI-06 | Tasks in different zones NOT flagged | integration | `pytest tests/test_phase_20_e2e.py::test_no_conflict_different_zones -x` | ❌ Wave 0 |

### Sampling Rate
- **Per task commit:** `uv run python -m pytest tests/test_phase_20_e2e.py -x` (backend) + `flutter test test/e2e/phase_20_dependency_engine_e2e_test.dart` (mobile)
- **Per wave merge:** Full suites: `uv run python -m pytest -x` + `flutter test`
- **Phase gate:** Full suite green before `/gsd:verify-work`

### Wave 0 Gaps
- [ ] `backend/tests/test_phase_20_e2e.py` — covers PROJ-04, AI-06
- [ ] `web/tests/phase_20_gantt.spec.ts` — covers PROJ-05 web
- [ ] `mobile/test/e2e/phase_20_dependency_engine_e2e_test.dart` — covers PROJ-04 + PROJ-05 mobile

---

## Sources

### Primary (HIGH confidence)
- Project codebase: `backend/app/features/projects/models.py` — Task model with `depends_on` JSONB confirmed
- Project codebase: `backend/app/core/base_models.py` — TenantScopedModel pattern
- Project codebase: `mobile/lib/core/database/app_database.dart` — Drift schemaVersion=7 confirmed
- npm registry: `npm view @svar-ui/react-gantt version` → 2.5.2 (verified 2026-03-21)
- npm registry: `npm view gantt-task-react version` → 0.3.9 (last publish 2022 — abandoned)
- Python standard algorithms: DFS cycle detection with white/gray/black coloring — well-documented in CS literature

### Secondary (MEDIUM confidence)
- [SVAR React Gantt official site](https://svar.dev/react/gantt/) — MIT license, FS/SS/FF/SE dependency types, Next.js 14+ compatibility confirmed
- [Top React Gantt comparison](https://svar.dev/blog/top-react-gantt-charts/) — SVAR is only MIT library; DHTMLX/Bryntum commercial
- [PostgreSQL cycle detection](https://vb-consulting.github.io/blog/recursion-postgresql/part3-cycle-detection/) — recursive CTE cycle clause (PostgreSQL 14+)
- [Kahn's cycle detection](https://gaultier.github.io/blog/kahns_algorithm.html) — confirmed Kahn's does NOT return cycle path

### Tertiary (LOW confidence)
- Flutter `interactive_gantt_chart` package (pub.dev) — low adoption (88 downloads/week); not recommended

---

## Metadata

**Confidence breakdown:**
- Standard stack: HIGH — npm versions verified live; existing libraries confirmed from codebase
- Architecture: HIGH — data model extension follows exact existing TenantScopedModel pattern; algorithms are standard CS
- Gantt library (web): MEDIUM — SVAR Gantt features confirmed from official site; swim lane rendering needs Wave 0 prototype to verify
- Gantt library (mobile): HIGH — recommendation to use CustomPainter is based on absence of viable alternatives (verified via pub.dev search)
- Pitfalls: HIGH — migration ordering, schema version, cycle detection algorithm choice all verified against project patterns
- Conflict detection: HIGH — SQL self-join pattern is standard; zone model is simple FK list

**Research date:** 2026-03-21
**Valid until:** 2026-04-21 (stable domain; SVAR Gantt versioning may change)
